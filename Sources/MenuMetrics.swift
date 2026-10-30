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
//    · 实时网速    可用（getifaddrs 字节计数做差）
//    · CPU 频率    可用 —— 由 AMDRyzenCPUPowerManagement.kext 用户客户端读每核有效频率
//                  （selector 4，APERF/MPERF 增量），不需要 root；
//                  sysctl hw.cpufrequency 的 min/max 相等只是固件标称值，仅作兜底显示
//    · 显卡占用率  可用 —— NullMoth 新驱动（NVAccel / NVMTLDriver）在 PerformanceStatistics
//                  里上报「Device Utilization %」「GPU Core Utilization %」等键
//    · 显卡温度    可用 —— 同上，「Temperature(C)」键
//    · 显卡功耗    不可用 —— PerformanceStatistics 里没有功耗键，macOS 下也没有 NVML 的等价接口
//    · 实时功耗    可用 —— 同上，AMDRyzenCPUPowerManagement.kext selector 4 的整包功耗（Watt）
//                  （powermetrics 必须 root、SMC 也没有 PSTR/PCPC 这类键，那条路在黑苹果上走不通）
//

import Foundation
import IOKit

// MARK: - 网速

struct NetSpeedSnapshot {
    var down: Double = 0        // B/s
    var up: Double = 0          // B/s
    var sampled = false         // 至少要两次采样才能算出速率
    var interfaceName = ""
}

enum NetSpeed {

    private static var lastDown: UInt64 = 0
    private static var lastUp: UInt64 = 0
    private static var lastAt: TimeInterval = 0
    private static var seeded = false

    static func sample() -> NetSpeedSnapshot {
        var snap = NetSpeedSnapshot()

        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return snap }
        defer { freeifaddrs(addrs) }

        var down: UInt64 = 0
        var up: UInt64 = 0
        var bestName = ""
        var bestBytes: UInt64 = 0

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            let flags = Int32(p.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback, let data = p.pointee.ifa_data {
                let net = data.assumingMemoryBound(to: if_data.self)
                let ib = UInt64(net.pointee.ifi_ibytes)
                let ob = UInt64(net.pointee.ifi_obytes)
                down += ib
                up += ob
                if ib + ob > bestBytes {
                    bestBytes = ib + ob
                    bestName = String(cString: p.pointee.ifa_name)
                }
            }
            cursor = p.pointee.ifa_next
        }

        snap.interfaceName = bestName
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
        let dDown = delta(prev: lastDown, now: down)
        let dUp = delta(prev: lastUp, now: up)
        lastDown = down
        lastUp = up
        lastAt = now

        // 接口计数字段是 UInt32，累计超过 4 GiB 会回绕；
        // 遇到回绕就丢掉这一帧重新起基准，不要拿一个错得离谱的速率去显示
        guard dt > 0.2, let dDown, let dUp else { return snap }

        snap.down = dDown / dt
        snap.up = dUp / dt
        snap.sampled = true
        return snap
    }

    private static func delta(prev: UInt64, now: UInt64) -> Double? {
        guard now >= prev else { return nil }
        return Double(now - prev)
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
    case cpuTemp
    case cpuLoad
    case cpuFreq
    case memUsage
    case netSpeed
    case gpuLoad
    case gpuTemp
    case power

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuTemp:  return "CPU 温度"
        case .cpuLoad:  return "CPU 占用率"
        case .cpuFreq:  return "CPU 频率"
        case .memUsage: return "内存占用率"
        case .netSpeed: return "实时网速"
        case .gpuLoad:  return "显卡占用率"
        case .gpuTemp:  return "显卡温度"
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
        case .gpuLoad:  return "display"
        case .gpuTemp:  return "thermometer.sun"
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
        case .netSpeed: return "getifaddrs 接口字节计数"
        case .gpuLoad:  return "IORegistry IOAccelerator PerformanceStatistics（Device Utilization %）"
        case .gpuTemp:  return "IORegistry IOAccelerator PerformanceStatistics（Temperature(C)）"
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
