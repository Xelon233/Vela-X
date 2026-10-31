//
//  MenuMetrics.swift
//  菜单栏可选项的数据源与偏好
//
//  设计前提：这些指标在 macOS 上的可获取性差得很远，不能想当然。
//  每项都先探测一次能不能拿到，拿不到的在设置页明说原因并禁止勾选，
//  而不是显示一个永远是 0 或者恒定的假数字。
//
//  本机（Ryzen 6900HX + RTX 3060 / NullMoth，macOS 26）实测结论：
//    · CPU 温度    可用（SMC TC0P）
//    · CPU 占用率  可用（host_processor_info）
//    · 内存占用率  可用（host_statistics64）
//    · 实时网速    可用（sysctl net.link.generic.ifdata 的 64 位网卡计数做差）
//    · CPU 频率    可用 —— 由 AMDRyzenCPUPowerManagement.kext 用户客户端读每核有效频率
//                  （selector 4，APERF/MPERF 增量），不需要 root；
//                  sysctl hw.cpufrequency 的 min/max 相等只是固件标称值，仅作兜底显示
//    · 显卡占用率  可用 —— NullMoth 新驱动（NVAccel / NVMTLDriver）在 PerformanceStatistics
//                  里上报「Device Utilization %」「GPU Core Utilization %」等键
//    · 显卡温度    可用 —— 同上，「Temperature(C)」键
//    · 显卡功耗    可用 —— 由 SMCNvidiaGPU-PowerVRAM（zzzyy678/SMCNvidiaGPU 的二改驱动）
//                  读 GSP 的 RUSD 共享内存并挂成 sysctl kern.nvgpupower，不需要 root
//    · 显存占用    可用 —— 同上，sysctl kern.nvgvramused / kern.nvgvramtotal
//    · 实时功耗    可用 —— 同上，AMDRyzenCPUPowerManagement.kext selector 4 的整包功耗（Watt）
//                  （powermetrics 必须 root、SMC 也没有 PSTR/PCPC 这类键，那条路在黑苹果上走不通）
//

import Foundation
import IOKit

// MARK: - 网速与流量

struct NetSpeedSnapshot {
    var down: Double = 0        // B/s
    var up: Double = 0          // B/s
    var sampled = false         // 至少要两次采样才能算出速率
    var interfaceName = ""
    /// 自系统启动以来所有网卡收 / 发的累计字节数（内核 64 位计数器）
    var totalDown: UInt64 = 0
    var totalUp: UInt64 = 0
    /// 内核记录的开机时刻（Unix 秒）。计数器每次开机归零，用它判断「系统是不是重启过」
    var bootTime: TimeInterval = 0
}

/// `sysctl net.link.generic.ifdata.<n>.general` 返回的结构，系统头文件里叫 `struct ifmibdata`，
/// Swift 没有直接导入，这里按同样的字段顺序自己摆一份。
///
/// 为什么不用 getifaddrs：它的 `ifa_data` 落到的是 `struct if_data`（实测 96 字节），
/// 字节计数是 **32 位**，累计超过 4 GiB 就回绕 —— 拿它做「自开机累计」这种长期统计，
/// 下载一部电影就能让总量倒退。ifmib 这份是 `if_data64`，计数为 64 位，不会回绕。
private struct IFMIBData {
    var name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
               CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar)
    var pcount: UInt32
    var flags: UInt32
    var sndLen: UInt32
    var sndMaxLen: UInt32
    var sndDrops: UInt32
    var filler: (UInt32, UInt32, UInt32, UInt32)
    var data: if_data64
}

enum NetSpeed {

    private static var lastDown: UInt64 = 0
    private static var lastUp: UInt64 = 0
    private static var lastAt: TimeInterval = 0
    private static var seeded = false

    /// 开机时刻（Unix 秒）。开机后不变，但要拿它判断计数器是否被系统重启清零，所以每次现读。
    static var bootTime: TimeInterval {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000
    }

    static func sample() -> NetSpeedSnapshot {
        var snap = NetSpeedSnapshot()
        snap.bootTime = bootTime

        var count: Int32 = 0
        var csize = MemoryLayout<Int32>.size
        guard sysctlbyname("net.link.generic.system.ifcount", &count, &csize, nil, 0) == 0,
              count > 0 else { return snap }

        let size = MemoryLayout<IFMIBData>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        raw.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        defer { raw.deallocate() }
        let buf = raw.bindMemory(to: IFMIBData.self, capacity: 1)
        var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, 0, IFDATA_GENERAL]

        var down: UInt64 = 0
        var up: UInt64 = 0
        var bestName = ""
        var bestBytes: UInt64 = 0

        for i in 0..<Int(count) {
            mib[4] = Int32(i)
            var outSize = size
            // 索引不连续时会返回 ENOENT，跳过即可（比如已经拔掉的接口）
            guard sysctl(&mib, 6, buf, &outSize, nil, 0) == 0 else { continue }
            let d = buf.pointee
            let flags = Int32(bitPattern: d.flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            let ib = d.data.ifi_ibytes
            let ob = d.data.ifi_obytes
            down += ib
            up += ob
            if ib + ob > bestBytes {
                bestBytes = ib + ob
                bestName = Self.name(of: d)
            }
        }

        snap.interfaceName = bestName
        snap.totalDown = down
        snap.totalUp = up
        let now = Date().timeIntervalSince1970

        guard seeded else {
            // 第一次只有累计值，没有速率
            seeded = true
            lastDown = down
            lastUp = up
            lastAt = now
            return snap
        }

        let dt = now - lastAt
        // 必须先拿旧基准算出增量，再更新基准，否则增量恒为 0
        let dDown = down >= lastDown ? down - lastDown : 0
        let dUp = up >= lastUp ? up - lastUp : 0
        lastDown = down
        lastUp = up
        lastAt = now

        guard dt > 0.2 else { return snap }

        snap.down = Double(dDown) / dt
        snap.up = Double(dUp) / dt
        snap.sampled = true
        return snap
    }

    private static func name(of d: IFMIBData) -> String {
        var chars: [CChar] = []
        withUnsafeBytes(of: d.name) { raw in
            for b in raw {
                if b == 0 { break }
                chars.append(CChar(bitPattern: b))
            }
        }
        chars.append(0)
        return String(cString: chars)
    }
}

// MARK: - CPU 频率

struct CPUFrequencyInfo {
    var nominalHz: UInt64 = 0
    /// 实时频率（GHz），来自 AMDRyzenCPUPowerManagement 用户客户端；拿不到就 nil
    var liveGHz: Double?
    /// 能否拿到「实时」频率：有 kext 且采到有效频率时为 true
    var live: Bool { liveGHz != nil }
}

enum CPUFrequency {
    static func probe() -> CPUFrequencyInfo {
        var hz: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.cpufrequency", &hz, &size, nil, 0) == 0, hz > 0 else {
            return CPUFrequencyInfo()
        }

        var lo: UInt64 = 0
        var hi: UInt64 = 0
        var s = MemoryLayout<UInt64>.size
        let gotLo = sysctlbyname("hw.cpufrequency_min", &lo, &s, nil, 0) == 0
        s = MemoryLayout<UInt64>.size
        let gotHi = sysctlbyname("hw.cpufrequency_max", &hi, &s, nil, 0) == 0

        // min 和 max 相等 → 这是固件/伪装写死的标称值，不会随负载变化。
        // 这里只给标称值；实时频率（liveGHz）由 AMDRyzenProbe 每帧填充。
        return CPUFrequencyInfo(nominalHz: hz)
    }
}

// MARK: - 显卡占用率 / 温度

/// 显卡实时统计。NullMoth 新驱动（NVAccel / NVMTLDriver）会在 PerformanceStatistics
/// 里上报「Device Utilization %」「GPU Core Utilization %」「Temperature(C)」等键；
/// Apple/AMD 加速器驱动用「Device Utilization %」。macOS 下没有 NVML，
/// 显卡**功耗**没有公开接口（PerformanceStatistics 里也没有），所以功耗拿不到。
struct GPUStats {
    /// 占用率 %（0...100），读不到为 nil
    var usage: Double?
    /// 温度 °C，读不到为 nil
    var temperature: Double?
}

enum GPUProbe {
    /// 一次遍历同时取占用率与温度，避免每帧重复枚举 IORegistry
    static func stats() -> GPUStats {
        guard let dict = performanceStatistics() else { return GPUStats() }
        return GPUStats(usage: utilization(in: dict),
                        temperature: number(dict["Temperature(C)"])
                                     ?? number(dict["GPU Temperature(C)"]))
    }

    static func usage() -> Double? { stats().usage }
    static func temperature() -> Double? { stats().temperature }

    private static func performanceStatistics() -> [String: Any]? {
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault,
                                              IOServiceMatching("IOAccelerator"), &iter)
        guard kr == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            let ok = IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0)
            if ok == KERN_SUCCESS, let raw = props?.takeRetainedValue(),
               let dict = raw as? [String: Any],
               let stats = dict["PerformanceStatistics"] as? [String: Any], !stats.isEmpty {
                IOObjectRelease(entry)
                return stats
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return nil
    }

    /// 优先整卡占用率，其次核心占用率，最后兜底任何含 utilization 的键。
    /// 新驱动会同时给 5 个 utilization 键，若不固定优先级会误取到
    /// 「Video Engine Utilization %=0」而不是整卡占用率。
    private static func utilization(in stats: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Core Utilization %"] {
            if let v = number(stats[key]) { return normalized(v) }
        }
        for (key, value) in stats {
            let lk = key.lowercased()
            guard lk.contains("utilization") || lk.contains("utilisation") else { continue }
            if let v = number(value) { return normalized(v) }
        }
        return nil
    }

    private static func normalized(_ v: Double) -> Double {
        // 0...1 的是比率，>1 的按百分比处理
        v <= 1.0 ? v * 100 : v
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        return nil
    }

    static var displayName: String {
        var iter: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault,
                                              IOServiceMatching("IOAccelerator"), &iter)
        guard kr == KERN_SUCCESS else { return "GPU" }
        defer { IOObjectRelease(iter) }
        let entry = IOIteratorNext(iter)
        guard entry != 0 else { return "GPU" }
        defer { IOObjectRelease(entry) }
        if let name = IORegistryEntryCreateCFProperty(entry, "IOName" as CFString,
                                                      kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String, !name.isEmpty {
            return name
        }
        return "GPU"
    }
}

// MARK: - 一次性的可用性探测

final class MetricProbe {
    static let shared = MetricProbe()

    private(set) var cpuFreq = CPUFrequencyInfo()
    private(set) var gpuUsage: Double?
    private(set) var gpuTemp: Double?
    private(set) var amdAvailable = false
    private(set) var probed = false

    private let lock = NSLock()

    func probeIfNeeded() {
        lock.lock()
        let done = probed
        lock.unlock()
        guard !done else { return }

        let freq = CPUFrequency.probe()
        let gpu = GPUProbe.stats()
        let amd = AMDRyzenProbe.shared.available

        lock.lock()
        cpuFreq = freq
        gpuUsage = gpu.usage
        gpuTemp = gpu.temperature
        amdAvailable = amd
        probed = true
        lock.unlock()
    }
}

// MARK: - 指标定义

enum MenuMetric: String, CaseIterable, Identifiable, Hashable {
    // 顺序即「菜单栏」设置页里的排列顺序（allCases 跟随声明顺序）：
    // CPU 组 → GPU 组 → 内存 → 网络，同类指标挨在一起，找起来不用上下乱扫。
    case cpuTemp
    case cpuLoad
    case cpuFreq
    case power
    case gpuTemp
    case gpuLoad
    case gpuPower
    case gpuVRAM
    case memUsage
    case netSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuTemp:  return "CPU 温度"
        case .cpuLoad:  return "CPU 占用率"
        case .cpuFreq:  return "CPU 频率"
        case .memUsage: return "内存占用率"
        case .netSpeed: return "实时网速"
        case .gpuLoad:  return "GPU 占用率"
        case .gpuTemp:  return "GPU 温度"
        case .gpuPower: return "GPU 功耗"
        case .gpuVRAM:  return "显存占用"
        case .power:    return "CPU 功耗"
        }
    }

    var icon: String {
        switch self {
        case .cpuTemp:  return "thermometer.medium"
        case .cpuLoad:  return "cpu.fill"
        case .cpuFreq:  return "cpu"
        case .memUsage: return "memorychip"
        case .netSpeed: return "arrow.up.arrow.down"
        // 显卡用「板卡 + 芯片方块」的信用卡形（SF Symbols 没有真正的显卡符号，
        // 这个长条卡+方块的轮廓在 12pt 下最接近一块小显卡，且与 cpu.fill 一眼可分）
        case .gpuLoad:  return "creditcard"
        case .gpuTemp:  return "thermometer.sun"
        // CPU 功耗是裸闪电；GPU 功耗用「方框里的闪电」——形状差别大，12pt 也能分开
        case .gpuPower: return "bolt.square.fill"
        case .gpuVRAM:  return "memorychip.fill"
        case .power:    return "bolt.fill"
        }
    }

    /// 菜单栏标题里数值旁的短标签（缩小字），用来区分同类指标
    var shortLabel: String {
        switch self {
        case .cpuTemp:  return "CPU"
        case .cpuLoad:  return "CPU"
        case .cpuFreq:  return "CPU"
        case .memUsage: return "内存"
        case .netSpeed: return "网速"
        case .gpuLoad:  return "GPU"
        case .gpuTemp:  return "GPU"
        case .gpuPower: return "GPU"
        case .gpuVRAM:  return "显存"
        case .power:    return "功耗"
        }
    }

    /// 采集通道说明，设置页里给用户看
    var backend: String {
        switch self {
        case .cpuTemp:  return "AppleSMC → SMCAMDProcessor → MSR"
        case .cpuLoad:  return "Mach host_processor_info"
        case .cpuFreq:  return "AMDRyzenCPUPowerManagement.kext → 用户客户端 selector 4（APERF/MPERF）"
        case .memUsage: return "Mach host_statistics64"
        case .netSpeed: return "sysctl net.link.generic.ifdata（内核 64 位网卡字节计数）"
        case .gpuLoad:  return "IORegistry IOAccelerator PerformanceStatistics（Device Utilization %）"
        case .gpuTemp:  return "IORegistry IOAccelerator PerformanceStatistics（Temperature(C)）"
        case .gpuPower: return "SMCNvidiaGPU-PowerVRAM.kext → sysctl kern.nvgpupower（GSP RUSD 共享内存）"
        case .gpuVRAM:  return "SMCNvidiaGPU-PowerVRAM.kext → sysctl kern.nvgvramused / kern.nvgvramtotal"
        case .power:    return "AMDRyzenCPUPowerManagement.kext → 用户客户端 selector 4（整包功耗）"
        }
    }
}

/// 某一项当前的值（无法采集时给出原因）
struct MenuMetricValue {
    var text: String
    var available: Bool
    var reason: String?
}

/// 菜单栏状态项用的紧凑显示项：图标 + 短标签 + 数值由渲染层（App.swift）拼接
struct MenuBarItem {
    let metric: MenuMetric
    let value: String
}

// MARK: - 网速显示模式

enum NetSpeedDisplay: String, CaseIterable, Identifiable {
    case down, up, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .down: return "仅下行"
        case .up:   return "仅上行"
        case .both: return "上下行"
        }
    }
}

// MARK: - 偏好

enum MenuBarPrefs {
    private static let metricsKey = "menubar.metrics"
    private static let netModeKey = "menubar.netmode"

    /// 默认开这六项：温度 / 负载 / 频率 / 内存 / 网速 / 功耗。
    /// 频率与功耗来自 AMDRyzenCPUPowerManagement.kext，没装时这两项自动降级为「不可用」、
    /// 菜单栏标题里不会出现（shortText 返回 nil），不会显示假数字。
    /// 用户可以随时在「菜单栏」页增删，改动存在 Prefs 里。
    static let defaultMetrics: [MenuMetric] = [.cpuTemp, .cpuLoad, .cpuFreq, .memUsage, .netSpeed, .power]

    static var enabled: [MenuMetric] {
        guard let raw = Prefs.string(metricsKey), !raw.isEmpty else { return defaultMetrics }
        let list = raw.split(separator: ",").compactMap { MenuMetric(rawValue: String($0)) }
        return list.isEmpty ? defaultMetrics : list
    }

    static func setEnabled(_ list: [MenuMetric]) {
        Prefs.set(list.map(\.rawValue).joined(separator: ","), for: metricsKey)
    }

    static func isEnabled(_ metric: MenuMetric) -> Bool {
        enabled.contains(metric)
    }

    static func set(_ metric: MenuMetric, enabled: Bool) {
        var list = self.enabled
        if enabled {
            if !list.contains(metric) { list.append(metric) }
        } else {
            list.removeAll { $0 == metric }
        }
        setEnabled(list)
    }

    static var netMode: NetSpeedDisplay {
        NetSpeedDisplay(rawValue: Prefs.string(netModeKey) ?? "") ?? .both
    }

    static func setNetMode(_ mode: NetSpeedDisplay) {
        Prefs.set(mode.rawValue, for: netModeKey)
    }
}

// MARK: - 格式化

extension Double {
    /// 字节速率 → 人类可读
    var asRate: String {
        // 最小单位固定为 KB/s：低于 1 KB/s 也显示 0.x KB/s，不再出现 B/s
        let units = ["KB/s", "MB/s", "GB/s"]
        var value = max(self, 0) / 1024
        var idx = 0
        while value >= 1024, idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        return String(format: "%.1f %@", value, units[idx])
    }
}
