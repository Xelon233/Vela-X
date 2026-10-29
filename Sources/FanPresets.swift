//
//  FanPresets.swift
//  VelaX —— 风扇预设的模型、加载与下发
//
//  数据来源：fan_presets.json / fan_presets.plist（同一份内容的两种格式）
//  搜索顺序：App 内资源 → ~/Library/Application Support/SMCAsusFan → /Library/...
//
//  用法：
//      let presets = try FanPresets.load()
//      let ctrl = FanController()
//      try ctrl.apply(preset: presets.preset("silent")!, fan: .cpu)   // 需要 root
//      print(ctrl.rpms())                                             // 普通权限即可
//

import Foundation
import IOKit

// MARK: - 数据模型

public struct FanCurve: Codable, Equatable {
    public let temp: [Int]      // 8 个温度点，°C，单调不减
    public let duty: [Int]      // 8 个占空比，%，单调不减

    /// 简单校验，避免把非法曲线写进 EC
    public var isValid: Bool {
        guard temp.count == 8, duty.count == 8 else { return false }
        guard zip(temp, temp.dropFirst()).allSatisfy({ $0 <= $1 }) else { return false }
        guard zip(duty, duty.dropFirst()).allSatisfy({ $0 <= $1 }) else { return false }
        guard let t0 = temp.first, let t1 = temp.last,
              let dMax = duty.max() else { return false }
        return t0 >= 20 && t1 <= 110 && dMax <= 100
    }
}

public struct FanPreset: Codable, Equatable {
    public let label: String?
    public let desc: String?
    public let cpu: FanCurve
    public let gpu: FanCurve

    public func curve(for fan: FanController.Fan) -> FanCurve {
        fan == .cpu ? cpu : gpu
    }
}

public struct FanPresets: Codable {
    public let schema: String
    public let presets: [String: FanPreset]
    /// 实际读取的文件路径（不参与解码）
    public private(set) var sourceURL: URL? = nil

    private enum CodingKeys: String, CodingKey {
        case schema, presets
    }

    public func preset(_ name: String) -> FanPreset? { presets[name] }
    public var names: [String] { presets.keys.sorted() }

    // MARK: 加载

    public static func searchPaths() -> [URL] {
        var list: [URL] = []
        if let url = Bundle.main.url(forResource: "fan_presets", withExtension: "json") {
            list.append(url)
        }
        // CLI 通过 build/vela 符号链接调用时，Bundle.main 解析不到 App 里的资源，
        // 这里按可执行文件位置回溯一层 Contents/Resources 再找一个。
        if let exe = Bundle.main.executablePath ?? CommandLine.arguments.first {
            let dir = URL(fileURLWithPath: exe).deletingLastPathComponent()
            list.append(dir.appendingPathComponent("../Resources/fan_presets.json").standardizedFileURL)
            list.append(dir.appendingPathComponent("fan_presets.json"))
        }
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            list.append(appSupport.appendingPathComponent("SMCAsusFan/fan_presets.json"))
        }
        list.append(URL(fileURLWithPath: "/Library/Application Support/SMCAsusFan/fan_presets.json"))
        return list
    }

    public static func load() throws -> FanPresets {
        for url in searchPaths() where FileManager.default.fileExists(atPath: url.path) {
            return try load(from: url)
        }
        throw NSError(domain: "VelaX", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "找不到 fan_presets.json（已查找：\(searchPaths().map(\.path).joined(separator: ", "))）"
        ])
    }

    public static func load(from url: URL) throws -> FanPresets {
        let data = try Data(contentsOf: url)
        var result = try JSONDecoder().decode(FanPresets.self, from: data)
        result.sourceURL = url
        return result
    }
}

// MARK: - 下发（写 EC 曲线）

public final class FanController {

    public enum Fan: UInt8 {
        case cpu = 0
        case gpu = 1
    }

    private let smc = SMCClient.shared

    public init() {}

    /// 把 8 个温度 + 8 个占空打包成 EC 邮箱要求的四个 u32（小端字节序）
    public static func pack(_ curve: FanCurve) -> [UInt32] {
        func group(_ s: ArraySlice<Int>) -> UInt32 {
            let a = Array(s)
            return UInt32(a[0]) | (UInt32(a[1]) << 8) | (UInt32(a[2]) << 16) | (UInt32(a[3]) << 24)
        }
        return [group(curve.temp[0..<4]), group(curve.temp[4..<8]),
                group(curve.duty[0..<4]), group(curve.duty[4..<8])]
    }

    /// 当前进程是否有写 SMC 的权限（写键需要 root）
    public static var isPrivileged: Bool { geteuid() == 0 }

    /// 下发一条曲线。**需要 root**，否则抛 SMCError.notWritable / ioFailed。
    ///
    /// 流程与 DSDT 的 DEFC 一致：选风扇 → 填 4 个参数 → 触发。
    /// 注意：写入后 EC 的预设槽位不会变，别用回读值判断是否生效，
    ///      唯一可靠的证据是转速（`rpms()`）发生变化。
    public func apply(_ curve: FanCurve, fan: Fan) throws {
        guard curve.isValid else {
            throw NSError(domain: "VelaX", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "曲线非法：需要 8 点、单调不减、温度 20..110、占空 <=100"
            ])
        }

        try smc.writeUInt8("AFMf", fan.rawValue)
        let args = Self.pack(curve)
        for (i, value) in args.enumerated() {
            try smc.writeUInt32("AFW\(i + 1)", value)
        }
        try smc.writeUInt8("AFWg", 1)
    }

    /// 双风扇转速（fpe2 换算成 RPM）。普通权限即可。
    public func rpms() -> (cpu: Int, gpu: Int) {
        let cpu = (try? smc.readRPM("F0Ac")) ?? 0
        let gpu = (try? smc.readRPM("F1Ac")) ?? 0
        return (cpu, gpu)
    }

    /// kext 是否已加载 —— 用 SMC 键 AFMd 是否存在来判断（最可靠）
    public var isKextLoaded: Bool {
        (try? smc.keyInfo("AFMd")) != nil
    }

    /// 在注册表里找出带 AFBuild 属性的节点（我们的 kext 没有 registerService，
    /// 所以用类名匹配是找不到的，只能遍历 IOService 平面按属性筛）
    private static func findDriverEntry() -> io_registry_entry_t? {
        var iter: io_iterator_t = 0
        guard IORegistryCreateIterator(kIOMainPortDefault, kIOServicePlane,
                                       IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let cf = IORegistryEntryCreateCFProperty(
                    entry, "AFBuild" as CFString, kCFAllocatorDefault, 0) {
                cf.release()
                return entry          // 调用方负责 IOObjectRelease
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return nil
    }

    /// kext 版本标识（ioreg 属性 AFBuild）
    public var kextBuild: String? {
        guard let service = Self.findDriverEntry() else { return nil }
        defer { IOObjectRelease(service) }
        guard let cf = IORegistryEntryCreateCFProperty(
                service, "AFBuild" as CFString, kCFAllocatorDefault, 0) else { return nil }
        return cf.takeRetainedValue() as? String
    }

    /// 读取 EC 的三个预设槽位（开机时 kext 已扫描好放在 ioreg 里；这里读 SMC 键 AFMd 只拿到 FANM 镜像）
    public var modeMirror: UInt8? {
        try? smc.readUInt8("AFMd")
    }
}
