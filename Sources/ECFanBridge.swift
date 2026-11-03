//
//  ECFanBridge.swift
//  VelaX —— 直接读写 EC 风扇曲线的用户态通道
//
//  为什么需要它：
//    上游的曲线通道是 SMCAsusFan.kext 暴露的 SMC 键（AFMf / AFW1–4 / AFWg）。
//    本机没装那个 kext，于是 FanController 判定「kext 未加载」，曲线整块不可用。
//    实际本机装的是自写的 AsusECTool.kext：它把 EC 的三个 256 字节内存窗口
//    映射给用户态，并提供了「按 WMI 设备号读写 16 字节」的通用入口 ——
//    这正是 DSDT 里 DEFC 走的那条路，不需要再额外写内核代码。
//
//  链路（与 DSDT 的 DEFC 逐条对应）：
//    WMNB(0x00110024, 16 字节) → DEFC → FANM=4 / M6CB=4 / FANC / MC5C..MC68 / WCMR
//    EC 把载荷收下（占空比逐字节 −1 落到 MC00 0x64..0x6B），但不回显预设槽位，
//    所以「是否生效」只能看转速，不能靠回读判断。
//
//  实机验证（2026-11-02，G815LM / 枪神9 Plus）：
//    写占空 100%  → CPU 风扇 4320 → 5640 RPM（24 秒内单调上升）
//    写占空 10–17% → 回落到 4500 一带
//    还原原曲线   → 4320 → 4140
//    窗口差分另证：MC00 0x64..0x6B 精确跟随写入值（−1），说明载荷确实进了 EC。
//

import Foundation
import IOKit

/// AsusECTool.kext 的用户态客户端。
///
/// 只做「读转速 / 读曲线 / 写曲线 / 读写散热模式与充电上限」这四件事，
/// 不做任何物理地址访问（那需要 ACPI SystemMemory 读取，越界会直接内核 panic）。
final class ECFanBridge {

    static let shared = ECFanBridge()

    /// kext 的 IOClass 名（Info.plist 里 IOKitPersonalities 的键）
    private static let serviceName = "AsusECTool"

    // 三个 EC 内存窗口（基址来自 DSDT 的 OperationRegion，已多次实测）
    static let winB: UInt64 = 0xFE700B00   // MB00：充电上限 MBF3(0xF3)、FANM(0xF9)
    static let winC: UInt64 = 0xFE700C00   // MC00：风扇曲线信箱
    static let winT: UInt64 = 0xFE700600   // IT55：三路转速 tach、散热模式 CMMV(0xCE)

    // 转速 tach 偏移（低字节 / 高字节）
    private enum Tach {
        static let cpuL: UInt64 = 0x02, cpuH: UInt64 = 0x03   // FA1
        static let centerL: UInt64 = 0x22, centerH: UInt64 = 0x23 // FA3
        static let gpuL: UInt64 = 0x24, gpuH: UInt64 = 0x25   // FA2
    }

    private enum Off {
        static let chargeLimit: UInt64 = 0xF3   // MBF3，0 = 不限充
        static let thermalMode: UInt64 = 0xCE   // CMMV：0 平衡 / 1 增强 / 2 静音
    }

    /// kext 派发表序号（见 AsusECTool.cpp 的 sMethods）
    private enum Selector: UInt32 {
        case readFanRPM = 0
        case deviceSet = 6
        case deviceGet = 7
        case memRead = 10
        case memWrite = 11
    }

    /// 曲线用的 WMI 设备号（与 ACPI 里 DEFC 的 Arg0 一致）
    enum Channel: UInt32, CaseIterable {
        case cpu = 0x00110024
        case gpu = 0x00110025
        case center = 0x00110032

        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .gpu: return "GPU"
            case .center: return "中置"
            }
        }
    }

    private var conn: io_connect_t = 0
    private let lock = NSLock()

    /// 可用性缓存：kext 开机注入，正常不会中途消失；缓存 5 秒，驱动更新后能自愈
    private var lastProbe = Date.distantPast
    private var probeResult = false

    private init() {}

    // MARK: - 连接

    private func connectLocked() -> io_connect_t {
        if conn != 0 { return conn }
        guard let matching = IOServiceMatching(ECFanBridge.serviceName) else { return 0 }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return 0 }
        defer { IOObjectRelease(svc) }

        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == KERN_SUCCESS else { return 0 }
        conn = c
        return c
    }

    private func dropLocked() {
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
    }

    // MARK: - 底层内存窗口访问

    private func memReadLocked(_ base: UInt64, _ off: UInt64) -> UInt8? {
        let c = connectLocked()
        guard c != 0 else { return nil }
        let input: [UInt64] = [base, off]
        var out: UInt64 = 0
        var outCnt: UInt32 = 1
        let kr = input.withUnsafeBufferPointer {
            IOConnectCallScalarMethod(c, Selector.memRead.rawValue, $0.baseAddress, 2, &out, &outCnt)
        }
        guard kr == KERN_SUCCESS else { dropLocked(); return nil }
        return UInt8(truncatingIfNeeded: out)
    }

    @discardableResult
    private func memWriteLocked(_ base: UInt64, _ off: UInt64, _ value: UInt8) -> Bool {
        let c = connectLocked()
        guard c != 0 else { return false }
        let input: [UInt64] = [base, off, UInt64(value)]
        let kr = input.withUnsafeBufferPointer {
            IOConnectCallScalarMethod(c, Selector.memWrite.rawValue, $0.baseAddress, 3, nil, nil)
        }
        guard kr == KERN_SUCCESS else { dropLocked(); return false }
        return memReadLocked(base, off) == value
    }

    private func word(_ lo: UInt64, _ hi: UInt64) -> Int? {
        guard let l = memReadLocked(ECFanBridge.winT, lo),
              let h = memReadLocked(ECFanBridge.winT, hi) else { return nil }
        let v = Int(h) << 8 | Int(l)
        return v == 0xFFFF ? nil : v       // 0xFFFF = EC 未就绪
    }

    // MARK: - 可用性

    /// kext 是否可用（5 秒缓存）。判据是 selector 0 能成功返回。
    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        if Date().timeIntervalSince(lastProbe) < 5 { return probeResult }

        let c = connectLocked()
        var ok = false
        if c != 0 {
            var out: UInt64 = 0
            var cnt: UInt32 = 1
            ok = IOConnectCallScalarMethod(c, Selector.readFanRPM.rawValue, nil, 0, &out, &cnt) == KERN_SUCCESS
            if !ok { dropLocked() }
        }
        lastProbe = Date()
        probeResult = ok
        return ok
    }

    /// kext 的构建标识（Info.plist 的 AsusECBuild 属性）
    var buildTag: String? {
        guard let matching = IOServiceMatching(ECFanBridge.serviceName) else { return nil }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        guard let cf = IORegistryEntryCreateCFProperty(
                svc, "AsusECBuild" as CFString, kCFAllocatorDefault, 0) else { return nil }
        return cf.takeRetainedValue() as? String
    }

    // MARK: - 转速

    func rpm(_ ch: Channel) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() != 0 else { return nil }
        switch ch {
        case .cpu:    return word(Tach.cpuL, Tach.cpuH)
        case .gpu:    return word(Tach.gpuL, Tach.gpuH)
        case .center: return word(Tach.centerL, Tach.centerH)
        }
    }

    // MARK: - 曲线

    /// 读一组曲线。返回的是 EC 当前的预设槽位，不是我们上次写入的内容（EC 不回显）。
    func readCurve(_ ch: Channel) -> FanCurve? {
        lock.lock(); defer { lock.unlock() }
        let c = connectLocked()
        guard c != 0 else { return nil }

        let input: [UInt64] = [UInt64(ch.rawValue)]
        var outScalar: UInt64 = 0
        var outCnt: UInt32 = 1
        var buf = [UInt8](repeating: 0, count: 16)
        var bufSize = buf.count

        let kr = input.withUnsafeBufferPointer { inp in
            buf.withUnsafeMutableBytes { raw in
                IOConnectCallMethod(c, Selector.deviceGet.rawValue,
                                    inp.baseAddress, 1, nil, 0,
                                    &outScalar, &outCnt,
                                    raw.baseAddress, &bufSize)
            }
        }
        guard kr == KERN_SUCCESS, bufSize >= 16 else { dropLocked(); return nil }

        let bytes = Array(buf.prefix(16))
        return FanCurve(temp: bytes[0..<8].map(Int.init),
                        duty: bytes[8..<16].map(Int.init))
    }

    /// 写一组曲线。返回 true 仅代表 ACPI 侧返回成功 —— EC 不回显，是否真的生效要看转速。
    @discardableResult
    func writeCurve(_ curve: FanCurve, to ch: Channel) -> Bool {
        guard curve.temp.count == 8, curve.duty.count == 8 else { return false }

        lock.lock(); defer { lock.unlock() }
        let c = connectLocked()
        guard c != 0 else { return false }

        var buf = [UInt8]()
        buf.append(contentsOf: curve.temp.map { UInt8(clamping: $0) })
        buf.append(contentsOf: curve.duty.map { UInt8(clamping: $0) })

        let input: [UInt64] = [UInt64(ch.rawValue)]
        var outScalar: UInt64 = 0
        var outCnt: UInt32 = 1

        let kr = input.withUnsafeBufferPointer { inp in
            buf.withUnsafeBytes { raw in
                IOConnectCallMethod(c, Selector.deviceSet.rawValue,
                                    inp.baseAddress, 1,
                                    raw.baseAddress, buf.count,
                                    &outScalar, &outCnt,
                                    nil, nil)
            }
        }
        guard kr == KERN_SUCCESS else { dropLocked(); return false }
        return outScalar == 1        // WMNB 返回 0x1 = 成功
    }

    // MARK: - 散热模式 / 充电上限（与曲线上层共用同一通道）

    /// 写散热模式：0 平衡 / 1 增强 / 2 静音 —— 这是本机唯一真正改变风扇策略的寄存器
    @discardableResult
    func setThermalMode(_ mode: Int) -> Bool {
        guard (0...2).contains(mode) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() != 0 else { return false }
        return memWriteLocked(ECFanBridge.winT, Off.thermalMode, UInt8(mode))
    }

    func thermalMode() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() != 0 else { return nil }
        return memReadLocked(ECFanBridge.winT, Off.thermalMode).map(Int.init)
    }

    /// 充电上限：0 = 不限充，其余为百分比（实测 60 / 80 / 100 可落盘）
    @discardableResult
    func setChargeLimit(_ pct: Int) -> Bool {
        guard (0...100).contains(pct) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() != 0 else { return false }
        return memWriteLocked(ECFanBridge.winB, Off.chargeLimit, UInt8(clamping: pct))
    }

    func chargeLimit() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard connectLocked() != 0 else { return nil }
        return memReadLocked(ECFanBridge.winB, Off.chargeLimit).map(Int.init)
    }
}
