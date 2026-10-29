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
//    · CPU 频率    不可用 —— hw.cpufrequency 的 min/max 相等，是固件写死的标称值；
//                  真实频率要 ring0 读 MSR，macOS 用户态没有这条路
//    · 显卡占用率  不可用 —— NVAccel 的 PerformanceStatistics 里没有任何 utilization 键，
//                  macOS 下也没有 NVML 的等价接口
//    · 实时功耗    不可用 —— powermetrics 必须 root；SMC 也没有 PSTR/PCPC 这类功耗键
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
    /// 能否拿到「实时」频率。macOS 用户态基本拿不到，这里绝大多数情况是 false
    var live = false
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

        // min 和 max 相等 → 这是固件/伪装写死的标称值，不会随负载变化
        let isStatic = gotLo && gotHi && lo == hi
        return CPUFrequencyInfo(nominalHz: hz, live: !isStatic)
    }
}

// MARK: - 显卡占用率

enum GPUProbe {
    /// 在 IORegistry 里找加速器驱动报的利用率。
    /// Apple 的 AGXAccelerator、AMD 的 AMDRadeonX* 会在 PerformanceStatistics 里给
    /// 「Device Utilization %」这类键；NVIDIA（NullMoth / NVAccel）实测没有，返回 nil。
    static func usage() -> Double? {
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
               let dict = raw as? [String: Any] {
                if let stats = dict["PerformanceStatistics"] as? [String: Any],
                   let v = utilization(in: stats) {
                    IOObjectRelease(entry)
                    return v
                }
                // 少数驱动把统计平铺在顶层
                if let v = utilization(in: dict) {
                    IOObjectRelease(entry)
                    return v
                }
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        return nil
    }

    private static func utilization(in dict: [String: Any]) -> Double? {
        for (key, value) in dict {
            let lk = key.lowercased()
            guard lk.contains("utilization") || lk.contains("utilisation") else { continue }
            let v: Double?
            if let d = value as? Double { v = d }
            else if let i = value as? Int { v = Double(i) }
            else if let n = value as? NSNumber { v = n.doubleValue }
            else { continue }
            guard let v else { continue }
            // 0...1 的是比率，>1 的按百分比处理
            return v <= 1.0 ? v * 100 : v
        }
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

// MARK: - 功耗

enum PowerProbe {
    /// SMC 上可能的功耗键。Apple Silicon 才有（PSTR 系统总功耗、PCPC CPU 功耗），
    /// Hackintosh 的 VirtualSMC 一般不提供，返回 nil。
    private static let keys = ["PSTR", "PCPC", "PCPT", "PDTR", "PWRS"]

    static func watts() -> Double? {
        for key in keys {
            if let r = SMC.read(key), let n = r.number, n > 0 { return n }
        }
        return nil
    }
}

// MARK: - 一次性的可用性探测

final class MetricProbe {
    static let shared = MetricProbe()

    private(set) var cpuFreq = CPUFrequencyInfo()
    private(set) var gpuUsage: Double?
    private(set) var powerWatts: Double?
    private(set) var probed = false

    private let lock = NSLock()

    func probeIfNeeded() {
        lock.lock()
        let done = probed
        lock.unlock()
        guard !done else { return }

        let freq = CPUFrequency.probe()
        let gpu = GPUProbe.usage()
        let power = PowerProbe.watts()

        lock.lock()
        cpuFreq = freq
        gpuUsage = gpu
        powerWatts = power
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
        case .power:    return "实时功耗"
        }
    }

    var icon: String {
        switch self {
        case .cpuTemp:  return "thermometer.medium"
        case .cpuLoad:  return "chart.bar.fill"
        case .cpuFreq:  return "speedometer"
        case .memUsage: return "memorychip"
        case .netSpeed: return "arrow.down.arrow.up"
        case .gpuLoad:  return "display"
        case .power:    return "bolt.fill"
        }
    }

    /// 菜单栏空间很窄：网速仍用方向文字表达上下行，这里用单个网络图标，
    /// 避免和数值前的 ↓ / ↑ 重复。
    var menuBarIcon: String {
        switch self {
        case .netSpeed: return "network"
        default:        return icon
        }
    }

    /// 采集通道说明，设置页里给用户看
    var backend: String {
        switch self {
        case .cpuTemp:  return "AppleSMC → SMCAMDProcessor → MSR"
        case .cpuLoad:  return "Mach host_processor_info"
        case .cpuFreq:  return "sysctl hw.cpufrequency"
        case .memUsage: return "Mach host_statistics64"
        case .netSpeed: return "getifaddrs 接口字节计数"
        case .gpuLoad:  return "IORegistry IOAccelerator PerformanceStatistics"
        case .power:    return "AppleSMC 功耗键（PSTR / PCPC）"
        }
    }
}

/// 菜单栏标题中的一个「图标 + 紧凑数值」分段。
struct MenuBarSegment: Identifiable {
    let metric: MenuMetric
    let text: String

    var id: MenuMetric { metric }
}

/// 某一项当前的值（无法采集时给出原因）
struct MenuMetricValue {
    var text: String
    var available: Bool
    var reason: String?
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

    /// 默认开这四项：都能拿到数据，且是大多数人会想看的。
    /// 用户可以随时在「菜单栏」页增删，改动存在 Prefs 里。
    static let defaultMetrics: [MenuMetric] = [.cpuTemp, .cpuLoad, .memUsage, .netSpeed]

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
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = self
        var idx = 0
        while value >= 1024, idx < units.count - 1 {
            value /= 1024
            idx += 1
        }
        let fmt = idx == 0 ? "%.0f %@" : "%.1f %@"
        return String(format: fmt, value, units[idx])
    }
}
