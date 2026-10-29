//
//  SystemInfo.swift
//  硬件 / 电池 / 内核扩展探测
//

import Foundation
import IOKit

// MARK: - 数据结构

struct HardwareInfo {
    var modelCode: String = ""
    var modelName: String = ""

    /// 标题栏用的短 CPU 名（"AMD Ryzen 9 6900HX with Radeon Graphics" → "AMD Ryzen 9 6900HX"）
    var cpuShort: String {
        if let r = cpu.range(of: " with ") { return String(cpu[..<r.lowerBound]) }
        return cpu
    }
    /// 零售商品名（如 "ROG 魔霸6"），可能来自型号库或手动设置
    var productName: String = ""
    /// 海外名（如 "ROG Strix G15"）
    var globalName: String = ""
    /// 名称来源：手动设置 / 型号库匹配 / 未收录
    var nameSource: String = ""
    var vendor: String = "ASUSTeK"
    var cpu: String = ""
    var cores: Int = 0
    var ramGB: Double = 0
    var osVersion: String = ""
    var gpus: [GPUInfo] = []
    var smcVersion: String = ""
}

struct GPUInfo: Identifiable {
    let id = UUID()
    let name: String
    let vendor: String
    /// 已绑定驱动的完整描述，例如 "NullMoth 2.6.2（加速已启用）"
    let driver: String
    /// 徽标用的短标签，例如 "NullMoth 2.6.2"
    let shortDriver: String
    /// 是否真正绑定到带加速的 framebuffer / 加速器（不是只有 PCI 节点）
    let accelerated: Bool
    /// PCI 设备路径，调试用
    let pciPath: String
}

/// 显卡驱动状态（从 IORegistry 里实际绑定的 CFBundleIdentifier 推断）
enum GPUDriverKind {
    case nullMoth(String)       // com.nullmoth.* —— Turing/Ampere 第三方驱动
    case webDriver(String)      // com.nvidia.web.* —— 官方 Web Driver（Kepler/Maxwell）
    case appleAMD               // com.apple.AMDRadeonX*
    case appleIntel             // com.apple.driver.AppleIntel*FB
    case appleSilicon           // AGX*
    case framebufferOnly        // 只挂了 framebuffer，没有加速器
    case none

    var accelerated: Bool {
        switch self {
        case .nullMoth, .webDriver, .appleAMD, .appleIntel, .appleSilicon: return true
        case .framebufferOnly, .none: return false
        }
    }

    var shortLabel: String {
        switch self {
        case .nullMoth(let v): return v.isEmpty ? "NullMoth" : "NullMoth \(v)"
        case .webDriver(let v): return v.isEmpty ? "Web Driver" : "Web Driver \(v)"
        case .appleAMD: return "AMD 内置驱动"
        case .appleIntel: return "Intel 内置驱动"
        case .appleSilicon: return "Apple GPU"
        case .framebufferOnly: return "仅 framebuffer"
        case .none: return "无驱动"
        }
    }

    var detail: String {
        switch self {
        case .nullMoth(let v):
            return v.isEmpty ? "NullMoth 驱动（加速已启用）" : "NullMoth \(v) 驱动（加速已启用）"
        case .webDriver(let v):
            return "NVIDIA Web Driver \(v)（加速已启用）"
        case .appleAMD:
            return "macOS 内置 AMD 驱动（加速已启用）"
        case .appleIntel:
            return "macOS 内置 Intel 驱动（加速已启用）"
        case .appleSilicon:
            return "Apple Silicon 内置 GPU"
        case .framebufferOnly:
            return "仅 framebuffer，无加速器"
        case .none:
            return "未绑定驱动（仅 PCI 节点可见）"
        }
    }
}

struct BatteryInfo {
    var present = false
    var charge: Int = 0
    var maxCapacity: Int = 0
    var designCapacity: Int = 0
    var cycleCount: Int = 0
    var temperature: Double = 0
    var externalPower = false
    var charging = false

    var healthPercent: Double {
        guard designCapacity > 0, maxCapacity > 0, maxCapacity <= designCapacity else { return 0 }
        return Double(maxCapacity) / Double(designCapacity) * 100
    }

    var maxWh: Double { Double(maxCapacity) * 15.4 / 1000.0 }
}

struct KextState {
    var asusSMC = false
    var virtualSMC = false
    var smcAMDProcessor = false
    var amdRyzenCPU = false
    var lilu = false
    /// NullMoth 驱动版本（未安装为 nil）
    var nullMoth: String?

    var summary: String {
        var parts: [String] = []
        if asusSMC { parts.append("AsusSMC") }
        if virtualSMC { parts.append("VirtualSMC") }
        if smcAMDProcessor { parts.append("SMCAMDProcessor") }
        if lilu { parts.append("Lilu") }
        if let nullMoth { parts.append("NullMoth \(nullMoth)") }
        return parts.isEmpty ? "未检测到" : parts.joined(separator: "、")
    }
}

// MARK: - 探测

enum SystemProbe {

    static func hardware() -> HardwareInfo {
        var info = HardwareInfo()
        info.cpu = sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
        info.cores = ProcessInfo.processInfo.activeProcessorCount
        info.ramGB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
        let v = ProcessInfo.processInfo.operatingSystemVersion
        info.osVersion = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"

        // 型号线索来自 EC / 电池设备（OpenCore 的 SMBIOS 覆盖会隐藏真实 DMI）
        if let name = ioregString("AppleSmartBattery", "DeviceName"), !name.isEmpty {
            info.modelCode = name
        } else {
            info.modelCode = sysctlString("hw.model") ?? "ASUS"
        }
        info.modelName = friendlyModel(info.modelCode)
        applyProductName(to: &info)

        // 厂商信息（OpenCore 通常保留 ASUSTeK）
        if let mfg = ioregString("IOPlatformExpertDevice", "manufacturer"), !mfg.isEmpty {
            info.vendor = mfg
        }

        info.gpus = listGPUs()
        return info
    }

    /// 零售名解析：手动设置 > 型号库匹配 > 原始代码
    static func applyProductName(to info: inout HardwareInfo) {
        let override = (Prefs.string(ModelCatalog.overrideKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = ModelCatalog.lookup(info.modelCode)

        if !override.isEmpty {
            info.productName = override
            if let saved = Prefs.string(ModelCatalog.overrideGlobalKey), !saved.isEmpty {
                info.globalName = saved
            } else if entry?.china == override {
                info.globalName = entry?.global ?? ""
            } else {
                info.globalName = ""
            }
            info.nameSource = "手动设置"
        } else if let entry {
            info.productName = entry.china
            info.globalName = entry.global
            info.nameSource = "型号库匹配"
        } else {
            info.productName = "ASUS \(info.modelCode)"
            info.globalName = ""
            info.nameSource = "型号未收录"
        }
    }

    static func friendlyModel(_ code: String) -> String {
        let prefix = String(code.prefix(5)).uppercased()
        let table: [String: String] = [
            "GA503": "ROG Zephyrus G15",
            "GA502": "ROG Zephyrus G15 (2020)",
            "GA401": "ROG Zephyrus G14",
            "GA402": "ROG Zephyrus G14 (2022)",
            "G513": "ROG Strix G15",
            "G533": "ROG Strix G17",
            "G713": "ROG Strix G17 (2022)",
            "G733": "ROG Strix G17",
            "GU603": "ROG Zephyrus M16",
            "GV301": "ROG Flow X13",
            "GV601": "ROG Flow X16",
            "FA506": "TUF Gaming A15",
            "FA507": "TUF Gaming A15 (2022)",
            "FX506": "TUF Gaming F15",
            "FX507": "TUF Gaming F15 (2022)",
            "FA617": "TUF Gaming A16",
            "UX": "ZenBook",
            "UM": "ZenBook",
            "X": "VivoBook"
        ]
        if let hit = table[prefix] { return "\(hit) · \(code)" }
        return "ASUS \(code)"
    }

    static func battery() -> BatteryInfo {
        var b = BatteryInfo()
        guard let props = ioregProperties("AppleSmartBattery") else { return b }
        b.present = (props["BatteryInstalled"] as? Bool) ?? false
        b.maxCapacity = (props["MaxCapacity"] as? Int) ?? 0
        b.designCapacity = (props["DesignCapacity"] as? Int) ?? 0
        b.cycleCount = (props["CycleCount"] as? Int) ?? 0
        b.externalPower = (props["ExternalConnected"] as? Bool) ?? false
        b.charging = (props["IsCharging"] as? Bool) ?? false
        if let t = props["Temperature"] as? Int, t > 0 {
            b.temperature = Double(t) / 10.0 - 273.15
        }
        if let data = props["BatteryData"] as? [String: Any] {
            b.charge = (data["StateOfCharge"] as? Int) ?? 0
            if b.designCapacity == 0, let d = data["DesignCapacity"] as? Int { b.designCapacity = d }
        }
        if b.charge == 0, let cur = props["CurrentCapacity"] as? Int, b.maxCapacity > 0 {
            b.charge = Int(Double(cur) / Double(b.maxCapacity) * 100)
        }
        return b
    }

    /// kmutil showloaded 输出（缓存，一次启动只跑一次）
    private static var cachedKextList: String?

    static var kextList: String {
        if let cachedKextList { return cachedKextList }
        let out = run("/usr/bin/kmutil", ["showloaded"])
        cachedKextList = out
        return out
    }

    static func kexts() -> KextState {
        var k = KextState()
        let out = kextList
        k.asusSMC = out.contains("com.hieplpvip.AsusSMC")
        k.virtualSMC = out.contains("as.vit9696.VirtualSMC")
        k.smcAMDProcessor = out.contains("SMCAMDProcessor")
        k.amdRyzenCPU = out.contains("AMDRyzenCPUPowerManagement")
        k.lilu = out.contains("as.vit9696.Lilu")
        // NullMoth：优先取 NVRM 的版本号
        k.nullMoth = kextVersion(in: out, identifier: "com.nullmoth.NVRM")
            ?? kextVersion(in: out, identifier: "com.nullmoth.NVAccel")
        return k
    }

    /// 从 kmutil showloaded 输出里取 `com.foo.Bar (1.2.3)` 的版本号
    static func kextVersion(in output: String, identifier: String) -> String? {
        for line in output.components(separatedBy: "\n") where line.contains(identifier) {
            guard let open = line.range(of: identifier + " (") else { continue }
            let rest = line[open.upperBound...]
            guard let close = rest.firstIndex(of: ")") else { continue }
            let v = String(rest[rest.startIndex..<close]).trimmingCharacters(in: .whitespaces)
            if !v.isEmpty { return v }
        }
        return nil
    }

    // MARK: - 底层工具

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }

    static func ioregProperties(_ service: String) -> [String: Any]? {
        let s = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(service))
        guard s != 0 else { return nil }
        defer { IOObjectRelease(s) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(s, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let dict = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func ioregString(_ service: String, _ key: String) -> String? {
        guard let props = ioregProperties(service) else { return nil }
        if let s = props[key] as? String, !s.isEmpty { return s }
        if let d = props[key] as? Data { return String(data: d, encoding: .utf8) }
        return nil
    }

    static func listGPUs() -> [GPUInfo] {
        var result: [GPUInfo] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOPCIDevice"),
                                           &iterator) == kIOReturnSuccess else { return [] }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var unmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let props = unmanaged?.takeRetainedValue() as? [String: Any] else { continue }

            let classCode = (props["class-code"] as? Data) ?? Data()
            let isDisplay = classCode.count >= 3 && classCode[2] == 0x03
            guard isDisplay else { continue }

            var name = ""
            if let d = props["model"] as? Data { name = String(data: d, encoding: .utf8) ?? "" }
            // 没有 model 属性的 PCI 显示设备通常是桥接/兼容控制器，忽略
            guard !name.isEmpty else { continue }

            // 关键：往下递归看这个 GPU 实际绑定了哪个驱动
            let kind = driverKind(for: service, deviceName: name)
            let vendor: String
            if name.localizedCaseInsensitiveContains("nvidia") {
                vendor = "NVIDIA"
            } else if name.localizedCaseInsensitiveContains("radeon") || name.localizedCaseInsensitiveContains("amd") {
                vendor = "AMD"
            } else {
                vendor = "其他"
            }

            let path = registryPath(service)
            result.append(GPUInfo(name: name,
                                  vendor: vendor,
                                  driver: kind.detail,
                                  shortDriver: kind.shortLabel,
                                  accelerated: kind.accelerated,
                                  pciPath: path))
        }
        return result
    }

    /// 读取某个 IORegistry 节点及其所有后代的 CFBundleIdentifier，判断实际生效的驱动
    static func driverKind(for entry: io_registry_entry_t, deviceName: String) -> GPUDriverKind {
        var bundles: [String] = []
        var iterator: io_iterator_t = 0
        if IORegistryEntryCreateIterator(entry, kIOServicePlane,
                                         IOOptionBits(kIORegistryIterateRecursively),
                                         &iterator) == kIOReturnSuccess {
            var child = IOIteratorNext(iterator)
            while child != 0 {
                var unmanaged: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(child, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                   let props = unmanaged?.takeRetainedValue() as? [String: Any],
                   let bid = props["CFBundleIdentifier"] as? String {
                    bundles.append(bid)
                }
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }

        let lower = bundles.map { $0.lowercased() }
        func has(_ needle: String) -> Bool { lower.contains { $0.contains(needle) } }

        if has("com.nullmoth.") {
            let v = SystemProbe.nullMothVersion()
            return .nullMoth(v)
        }
        if has("com.nvidia.web.") {
            let v = SystemProbe.nvidiaWebDriverVersion()
            return .webDriver(v)
        }
        if has("amdraedonx") || has("amdraedon3") || has("amdraedon7") || has("amdraedon8") || has("amdraedon9") {
            return .appleAMD
        }
        if has("applegpu") || has("agxg") || has("agx") {
            return .appleSilicon
        }
        if has("appleintel") {
            return .appleIntel
        }
        if !bundles.isEmpty {
            return .framebufferOnly
        }
        return .none
    }

    static func nullMothVersion() -> String {
        let out = kextList
        return kextVersion(in: out, identifier: "com.nullmoth.NVRM")
            ?? kextVersion(in: out, identifier: "com.nullmoth.NVAccel")
            ?? ""
    }

    static func nvidiaWebDriverVersion() -> String {
        kextVersion(in: kextList, identifier: "com.nvidia.web.NVDAGPUWrangler") ?? ""
    }

    static func registryPath(_ entry: io_registry_entry_t) -> String {
        var path = [CChar](repeating: 0, count: 4096)
        if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == kIOReturnSuccess {
            return String(cString: path)
        }
        return ""
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
