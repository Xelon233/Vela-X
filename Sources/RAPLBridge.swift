//
//  RAPLBridge.swift
//  VelaX —— Intel 封装功耗墙（RAPL MSR 0x610）
//
//  为什么需要它：
//    EC 那边只有 CMMV 三档，没有「瓦数」。Intel 机器的 PL1 / PL2 在 CPU 的
//    RAPL 寄存器里（MSR 0x610 MSR_PACKAGE_POWER_LIMIT），写它才能真的按瓦数限。
//    ASUS 自家的 Armoury Crate 在 Windows 侧也是由驱动（AsIO3 的 WriteMsr）去写。
//
//  通道：
//    AsusECTool.kext v1.4.0 起新增了两个 selector（12 读 / 13 写），
//    kext 内部对 MSR 号做了白名单：读只放 0x606 / 0x610 / 0x611 / 0x639，
//    写只放 0x610，且不允许改动位 63（lock）。
//    所以这里不是「任意 MSR 后门」，是一根窄管。
//
//  字段布局（Intel SDM，与 turbostat 的 rapl_probe 一致）：
//    0x610  14:0  PL1（单位 = 0x606 的功率刻度）
//           15    PL1 使能
//           16    PL1 clamp
//           23:17 PL1 时间窗
//           46:32 PL2
//           47    PL2 使能
//           48    PL2 clamp
//           55:49 PL2 时间窗
//           63    lock —— 锁定后写入被硬件忽略，只能进 BIOS 改
//
//  注意：PL1 是「长期墙」，PL2 是「短时爆发墙」。只压 PL1 的话，
//  跑分类负载仍会在 TAU 窗口内冲到 PL2，所以限功耗时两个一起写。
//

import Foundation
import IOKit

final class RAPLBridge {

    static let shared = RAPLBridge()

    /// MSR 通道的宿主 kext，按优先级排列：
    ///   AsusECMSR  —— 独立小 kext（selector 0/1），可随时加载卸载，用于验证
    ///   AsusECTool —— 开机注入的那个，v1.4.0 起把 MSR 挂在 selector 12/13
    private static let serviceNames = ["AsusECMSR", "AsusECTool"]

    /// 与 kext 派发表序号相关，连接成功后按宿主 kext 决定
    private enum Selector: UInt32 {
        case standaloneRead = 0
        case standaloneWrite = 1
        case toolRead = 12
        case toolWrite = 13
    }

    private enum MSR {
        static let powerUnit: UInt32 = 0x606
        static let pkgLimit: UInt32 = 0x610
        static let energy: UInt32 = 0x611
    }

    /// PL1 字段宽度 15 位
    private static let fieldMask: UInt64 = 0x7FFF
    /// 位 63：锁定
    private static let lockBit: UInt64 = 1 << 63

    // MARK: - 解码结果

    struct Reading {
        /// MSR 0x610 原始值
        let raw: UInt64
        /// 功率刻度：1 LSB = 多少瓦。来自 0x606 位 3:0，正常是 1/8 W。
        let wattPerLSB: Double
        /// 刻度是否为实测值（false = 0x606 读不出来，按常见值 1/8 W 假设）
        let unitMeasured: Bool

        var pl1Raw: UInt64 { raw & RAPLBridge.fieldMask }
        var pl2Raw: UInt64 { (raw >> 32) & RAPLBridge.fieldMask }
        var pl1Enabled: Bool { (raw >> 15) & 1 == 1 }
        var pl2Enabled: Bool { (raw >> 47) & 1 == 1 }
        var pl1Clamped: Bool { (raw >> 16) & 1 == 1 }
        /// 位 63：锁定后写入会被硬件静默忽略
        var locked: Bool { (raw >> 63) & 1 == 1 }

        var pl1W: Double { Double(pl1Raw) * wattPerLSB }
        var pl2W: Double { Double(pl2Raw) * wattPerLSB }

        /// 数值是否像人话（用来兜住刻度解错的平台）
        var plausible: Bool { pl1W >= 3 && pl1W <= 400 && pl2W >= 3 && pl2W <= 600 }
    }

    enum ApplyError: Error, CustomStringConvertible {
        case noKext
        case notSupported
        case locked
        case implausible
        case writeRejected

        var description: String {
            switch self {
            case .noKext:
                return "连不上 AsusECTool.kext"
            case .notSupported:
                return "kext 版本过旧：没有 MSR 通道（需要 v1.4.0 及以上）"
            case .locked:
                return "MSR 0x610 的 lock 位已置位，硬件会忽略写入；要在 BIOS 里解锁功耗墙后才能改"
            case .implausible:
                return "读到的功耗墙数值不像人话（刻度可能解错），为避免写坏，已中止"
            case .writeRejected:
                return "写入被拒绝"
            }
        }
    }

    private var conn: io_connect_t = 0
    private let lock = NSLock()
    private var lastProbe = Date.distantPast
    private var probeResult = false
    /// 连上的是哪个 kext（决定 selector 号）
    private var host: String?

    private init() {}

    // MARK: - 连接

    private func connectLocked() -> io_connect_t {
        if conn != 0 { return conn }
        for name in RAPLBridge.serviceNames {
            guard let matching = IOServiceMatching(name) else { continue }
            let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
            guard svc != 0 else { continue }
            var c: io_connect_t = 0
            let kr = IOServiceOpen(svc, mach_task_self_, 0, &c)
            IOObjectRelease(svc)
            guard kr == KERN_SUCCESS else { continue }
            conn = c
            host = name
            return c
        }
        return 0
    }

    private var readSelector: UInt32 {
        host == "AsusECMSR" ? Selector.standaloneRead.rawValue : Selector.toolRead.rawValue
    }

    private var writeSelector: UInt32 {
        host == "AsusECMSR" ? Selector.standaloneWrite.rawValue : Selector.toolWrite.rawValue
    }

    private func dropLocked() {
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
            host = nil
        }
    }

    // MARK: - 原始 MSR

    private func readMSRLocked(_ msr: UInt32) -> UInt64? {
        let c = connectLocked()
        guard c != 0 else { return nil }
        var out = [UInt64](repeating: 0, count: 2)
        var outCnt: UInt32 = 2
        let kr = IOConnectCallScalarMethod(c, readSelector,
                                           [UInt64(msr)], 1, &out, &outCnt)
        guard kr == KERN_SUCCESS, outCnt >= 2 else { return nil }
        return (out[1] << 32) | (out[0] & 0xFFFF_FFFF)
    }

    private func writeMSRLocked(_ msr: UInt32, _ value: UInt64) -> Bool {
        let c = connectLocked()
        guard c != 0 else { return false }
        let input: [UInt64] = [UInt64(msr), value & 0xFFFF_FFFF, value >> 32]
        let kr = IOConnectCallScalarMethod(c, writeSelector,
                                           input, 3, nil, nil)
        if kr != KERN_SUCCESS { dropLocked() }
        return kr == KERN_SUCCESS
    }

    // MARK: - 对外

    /// kext 是否提供 MSR 通道（5 秒缓存）。判据是 0x606 能读出来。
    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(lastProbe) < 5 { return probeResult }
        let v = readMSRLocked(MSR.powerUnit)
        lastProbe = Date()
        probeResult = (v != nil)
        return probeResult
    }

    /// 读当前功耗墙。0x606 读不到时按 1/8 W 假设，并用 plausible 标记不确定。
    func reading() -> Reading? {
        lock.lock(); defer { lock.unlock() }
        guard let limit = readMSRLocked(MSR.pkgLimit) else { return nil }

        var wattPerLSB = 0.125
        var measured = false
        if let unit = readMSRLocked(MSR.powerUnit) {
            // 位 3:0 = n，1 LSB = 2^-n 瓦（绝大多数机器 n = 3 → 0.125 W）
            let n = Int(unit & 0xF)
            if n >= 0 && n <= 10 {
                wattPerLSB = 1.0 / Double(1 << n)
                measured = true
            }
        }
        return Reading(raw: limit, wattPerLSB: wattPerLSB, unitMeasured: measured)
    }

    /// 有没有可用通道（不判断 lock）
    var hasChannel: Bool { reading() != nil }

    /// 把 PL1 / PL2 一起设成给定瓦数。
    /// 只改 PL1、不动 PL2 的话，负载一冲高就会被 PL2 放过去，等于没限。
    func setLimits(pl1: Int, pl2: Int? = nil) -> Result<Int, ApplyError> {
        guard let r = reading() else {
            return .failure(isAvailable ? .notSupported : .noKext)
        }
        guard r.plausible else { return .failure(.implausible) }
        guard !r.locked else { return .failure(.locked) }

        let p1 = UInt64(max(1, min(pl1, Int(RAPLBridge.fieldMask))))
        let p2 = UInt64(max(1, min(pl2 ?? pl1, Int(RAPLBridge.fieldMask))))
        let f1 = UInt64((Double(p1) / r.wattPerLSB).rounded())
        let f2 = UInt64((Double(p2) / r.wattPerLSB).rounded())
        guard f1 > 0, f2 > 0 else { return .failure(.writeRejected) }

        // 保留时间窗、clamp、lock 等其它位，只换两个功率字段并打开使能
        var v = r.raw
        v &= ~(RAPLBridge.fieldMask | (RAPLBridge.fieldMask << 32))
        v |= (f1 & RAPLBridge.fieldMask)
        v |= ((f2 & RAPLBridge.fieldMask) << 32)
        v |= (1 << 15)      // PL1 使能
        v |= (1 << 47)      // PL2 使能
        // lock 位保持原样（kext 也会强制保持，双保险）
        v = (v & ~RAPLBridge.lockBit) | (r.raw & RAPLBridge.lockBit)

        lock.lock()
        // 第一次写之前把原始值存下来，「恢复默认」才有得恢复
        if Prefs.string(RAPLBridge.keyOriginal) == nil {
            Prefs.set(String(r.raw), for: RAPLBridge.keyOriginal)
        }
        let ok = writeMSRLocked(MSR.pkgLimit, v)
        let after = ok ? readMSRLocked(MSR.pkgLimit) : nil
        lock.unlock()

        guard ok else { return .failure(.writeRejected) }
        // 回读校验：字段没变说明硬件忽略了写入（最常见就是 lock）
        guard let a = after, (a & RAPLBridge.fieldMask) == (f1 & RAPLBridge.fieldMask) else {
            return .failure(.locked)
        }
        return .success(Int((Double(a & RAPLBridge.fieldMask) * r.wattPerLSB).rounded()))
    }

    /// 恢复出厂功耗墙（写回第一次读到的原始值）
    func restoreOriginal() -> Result<Int, ApplyError> {
        guard let rawText = Prefs.string(RAPLBridge.keyOriginal), let original = UInt64(rawText) else {
            return .failure(.writeRejected)
        }
        guard let r = reading() else { return .failure(.noKext) }
        guard !r.locked else { return .failure(.locked) }

        lock.lock()
        let ok = writeMSRLocked(MSR.pkgLimit, original)
        let after = ok ? readMSRLocked(MSR.pkgLimit) : nil
        lock.unlock()

        guard ok, let a = after else { return .failure(.writeRejected) }
        guard (a & RAPLBridge.fieldMask) == (original & RAPLBridge.fieldMask) else {
            return .failure(.locked)
        }
        Prefs.set(nil, for: RAPLBridge.keyOriginal)
        return .success(Int((Double(a & RAPLBridge.fieldMask) * r.wattPerLSB).rounded()))
    }

    /// 有没有存过「原始功耗墙」（决定「恢复默认」按钮是否有意义）
    var hasOriginal: Bool { Prefs.string(RAPLBridge.keyOriginal) != nil }

    /// 瞬时封装功耗（用 0x611 两次差值算，不需要 root、不需要 powermetrics）
    /// 只做诊断用：GUI 的功耗显示仍走 powermetrics，那里还有 CPU 频率。
    func packageWatts(window: TimeInterval = 0.2) -> Double? {
        lock.lock()
        guard let e0 = readMSRLocked(MSR.energy),
              let unitRaw = readMSRLocked(MSR.powerUnit) else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        // 0x606 位 12:8 = 能量刻度 n，1 LSB = 2^-n 焦耳
        let n = Int((unitRaw >> 8) & 0x1F)
        let joulePerLSB = 1.0 / Double(1 << max(0, min(n, 20)))

        Thread.sleep(forTimeInterval: window)

        lock.lock()
        let e1 = readMSRLocked(MSR.energy)
        lock.unlock()

        guard let e1 else { return nil }
        let delta = e1 & 0xFFFF_FFFF
        let base = e0 & 0xFFFF_FFFF
        // 32 位计数器会回绕
        let ticks = delta >= base ? delta - base : (0x1_0000_0000 - base + delta)
        return Double(ticks) * joulePerLSB / window
    }

    private static let keyOriginal = "power.raplOriginal"
}
