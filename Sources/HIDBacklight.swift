//
//  HIDBacklight.swift
//  通过 ASUS Aura HID 输出报告控制键盘背光（2021+ 机型的主通道）
//
//  协议（与 G-Helper USB/AsusHid.cs 一致）：
//    握手：  output report 0x5A  ← "ASUS Tech.Inc."
//    亮度：  output report 0x5A  ← BA C5 C4 <0..3>
//
//  为什么走这条：新版 ROG 的背光由键盘内置控制器（USB HID 0x0B05:0x19B6 之类）负责，
//  固件的 ATK 设备没有 SKBV 方法，所以 AsusSMC 的 LKSB → SKBV 通道是断的。
//
//  注意：macOS 把键盘类 HID 设备锁了，只有拿到「输入监控」权限的进程才能 open，
//  否则 IOHIDDeviceOpen 返回 kIOReturnNotPermitted (0xE00002E2)。
//

import Foundation
import AppKit
import IOKit
import IOKit.hid

final class HIDBacklight {

    static let shared = HIDBacklight()

    static let asusVendorID = 0x0B05
    /// ASUS 的 INPUT_ID。亮度命令 0xBA 0xC5 0xC4 <level> 走这个 feature report。
    /// 注意：Aura 灯效才用 0x5D（AURA_ID），别混。
    static let inputReportID: CFIndex = 0x5A
    /// Aura 灯效/唤醒通道
    static let auraReportID2: CFIndex = 0x5D
    static let maxLevel = 3     // 关 / 低 / 中 / 高

    /// G-Helper 里登记过的 Aura 主控 PID
    static let auraPIDs: [Int] = [
        0x1a30, 0x1854, 0x1869, 0x1866, 0x19b6, 0x1822, 0x1837, 0x184a, 0x183d,
        0x8502, 0x1807, 0x17e0, 0x1abe, 0x1b4c, 0x1b6e, 0x1b2c, 0x8854,
        0x1ce7, 0x1ce6, 0x1bf2, 0x1bf3, 0x1cd7, 0x1cd8, 0x4b42
    ]

    private var device: IOHIDDevice?
    private var opened: [IOHIDDevice] = []
    private var devicePID: Int = 0
    private(set) var lastError: String?
    private(set) var permissionDenied = false
    private(set) var lastOpenResult: kern_return_t = kIOReturnSuccess
    private(set) var deviceFound = false
    /// 最近一次成功的写入方式（诊断用）
    private(set) var lastWriteVariant: String?
    private(set) var lastWriteResult: kern_return_t = kIOReturnSuccess
    /// 失败时每种写法的返回码，拼进错误信息便于定位
    private(set) var lastAttempts: [(String, kern_return_t)] = []
    private let lock = NSRecursiveLock()

    // MARK: - 输入监控权限

    enum Permission: String {
        case granted, denied, unknown
    }

    /// 比 Permission 更细：区分「系统里已授权但本进程还没生效」
    enum PermissionState: Equatable {
        case granted          // 授权到位，设备能打开
        case needsRestart     // 系统设置里已勾选，但本进程仍被拒 → 需要重启 App
        case denied           // 明确拒绝
        case notDetermined    // 还没申请过
        case busy             // 权限有，但设备被别的进程占着
        case noDevice         // 找不到 Aura 控制器（和权限无关）

        var canControl: Bool { self == .granted }
    }

    static var listenPermission: Permission {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    @discardableResult
    static func requestPermission() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static var privacySettingsURL: URL? {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    /// 重置本应用在「输入监控」里的记录（不需要 root）。
    /// 用于「勾选了但系统说没授权」这种 TCC 记录与当前二进制对不上的情况：
    /// 每次重新编译都会换 cdhash（ad-hoc 签名），旧授权就失效了。
    @discardableResult
    static func resetPermission() -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        let bundleID = Bundle.main.bundleIdentifier ?? "dev.vela.mac"
        p.arguments = ["reset", "ListenEvent", bundleID]
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus
        } catch {
            return -1
        }
    }

    /// 重新启动本应用（TCC 授权只在进程启动时读取一次）
    static func relaunch() {
        let url = Bundle.main.bundleURL
        guard url.pathExtension == "app" else {
            // 命令行/符号链接场景没法自重启，交给调用方提示
            NSApp.terminate(nil)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - 设备发现（同步遍历 IORegistry，不依赖 run loop）

    private func candidateDevices() -> [IOHIDDevice] {
        var result: [IOHIDDevice] = []
        var seen = Set<String>()
        for cls in ["IOHIDDevice", "AppleUserHIDDevice"] {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { continue }
            var service = IOIteratorNext(iter)
            while service != 0 {
                if let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
                    // VendorID / ProductID 由 IOHIDDevice 从 HID 描述符合成，必须通过 GetProperty 读
                    let vid = intProp(dev, kIOHIDVendorIDKey)
                    let pid = intProp(dev, kIOHIDProductIDKey)
                    if vid == Self.asusVendorID, Self.auraPIDs.contains(pid) {
                        let key = "\(cls)-\(pid)-\(intProp(dev, kIOHIDLocationIDKey))"
                        if !seen.contains(key) {
                            seen.insert(key)
                            result.append(dev)
                        }
                    }
                }
                IOObjectRelease(service)
                service = IOIteratorNext(iter)
            }
            IOObjectRelease(iter)
        }
        return result
    }

    private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? -1
    }

    private func strProp(_ dev: IOHIDDevice, _ key: String) -> String {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? String) ?? ""
    }

    private func outReportSize(_ dev: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(dev, kIOHIDMaxOutputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 0
    }

    private func featureReportSize(_ dev: IOHIDDevice) -> Int {
        (IOHIDDeviceGetProperty(dev, "MaxFeatureReportSize" as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// 已打开的设备（没有就尝试打开）
    private func openDevice() -> IOHIDDevice? {
        lock.lock(); defer { lock.unlock() }
        if let device { return device }

        let all = candidateDevices()
        // 不按「是否有 feature report」过滤：实测有些机型（如 0x19B6 N-KEY）主通道只走
        // output report，按 feature 优先会错失真正能控灯的接口。
        // 优先挑产品名含 "N-KEY" 的设备（已验证可点亮的那条通道）。
        let candidates = all.sorted {
            strProp($1, kIOHIDProductKey).contains("N-KEY")
                && !strProp($0, kIOHIDProductKey).contains("N-KEY")
        }
        deviceFound = !candidates.isEmpty
        guard !candidates.isEmpty else {
            lastError = "没有找到 ASUS Aura HID 控制器"
            return nil
        }

        permissionDenied = false
        opened.removeAll()
        for dev in candidates {
            let rc = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            lastOpenResult = rc
            if rc == kIOReturnSuccess {
                opened.append(dev)
                if device == nil {
                    device = dev
                    devicePID = (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
                }
                continue
            }
            if rc == kIOReturnNotPermitted {
                permissionDenied = true
                lastError = "macOS 拒绝了键盘类 HID 设备的访问：需要「输入监控」权限"
            } else {
                lastError = "打开 HID 设备失败 (kern_return 0x\(String(UInt32(bitPattern: rc), radix: 16)))"
            }
        }
        guard !opened.isEmpty else { return nil }
        sendAuraPrimers()
        sendInit()
        lastError = nil
        return opened.first
    }

    // MARK: - 状态

    var isAvailable: Bool {
        lock.lock(); defer { lock.unlock() }
        return openDevice() != nil
    }

    /// 一次探测拿到全部状态（避免连续调用 isAvailable / needsPermission / activeProductID 各枚举一遍）
    func probeState() -> (available: Bool, pid: Int, blocked: Bool) {
        lock.lock(); defer { lock.unlock() }
        if openDevice() != nil {
            return (true, devicePID, false)
        }
        return (false, 0, permissionDenied)
    }

    /// 综合「TCC 查询结果 + 实际能否打开设备」判断当前真实状态
    var permissionState: PermissionState {
        lock.lock(); defer { lock.unlock() }
        if openDevice() != nil { return .granted }
        guard deviceFound else { return .noDevice }
        if lastOpenResult == kIOReturnExclusiveAccess { return .busy }
        switch Self.listenPermission {
        case .granted:
            // 系统里已经勾选，但本进程 open 仍被拒：
            // TCC 的判定在进程启动时缓存，必须重启 App 才生效
            return lastOpenResult == kIOReturnNotPermitted ? .needsRestart : .denied
        case .denied:
            return .denied
        case .unknown:
            return .notDetermined
        }
    }

    /// 设备存在但被系统拦下（缺输入监控权限）
    var needsPermission: Bool {
        lock.lock(); defer { lock.unlock() }
        if openDevice() != nil { return false }
        return permissionDenied
    }

    var activeProductID: Int {
        lock.lock(); defer { lock.unlock() }
        return devicePID
    }

    /// 探测：返回找到的 Aura 控制器 PID 列表
    func probe() -> [Int] {
        candidateDevices().compactMap {
            (IOHIDDeviceGetProperty($0, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        }.sorted()
    }

    // MARK: - 下发

    /// 一帧完整的写入方案
    struct Frame {
        let name: String
        let type: IOHIDReportType
        let reportID: CFIndex
        let data: [UInt8]
    }

    private var maxFeatureLen: Int {
        let n = opened.first.map { featureReportSize($0) } ?? 0
        return n >= 8 ? n : 64
    }

    /// 所有候选写法。已对齐「KbdBacklight」实测可用的发送方式：
    ///   缓冲区首字节就是报告 ID（0x5A / 0x5D），后面跟 BA C5 C4 <level>，整体补零到 64 字节；
    ///   报告 ID 参数同时传相同的值。顺序：feature 0x5A → feature 0x5D → output 0x5D。
    ///   （之前的实现漏了首字节的报告 ID，导致设备收不到命令、灯不亮。）
    func frames(level: UInt8) -> [Frame] {
        let body: [UInt8] = [0xBA, 0xC5, 0xC4, level]
        /// 首字节放报告 ID，再补零到 64 字节
        func withID(_ id: UInt8) -> [UInt8] {
            var b = [id] + body
            b += [UInt8](repeating: 0, count: max(0, 64 - b.count))
            return b
        }
        return [
            Frame(name: "feature · 0x5A + BA C5 C4 \(level)", type: kIOHIDReportTypeFeature,
                  reportID: Self.inputReportID, data: withID(0x5A)),
            Frame(name: "feature · 0x5D + BA C5 C4 \(level)", type: kIOHIDReportTypeFeature,
                  reportID: Self.auraReportID2, data: withID(0x5D)),
            Frame(name: "output · 0x5D + BA C5 C4 \(level)", type: kIOHIDReportTypeOutput,
                  reportID: Self.auraReportID2, data: withID(0x5D))
        ]
    }

    private func write(_ frame: Frame, to dev: IOHIDDevice) -> kern_return_t {
        frame.data.withUnsafeBufferPointer { buf -> kern_return_t in
            guard let base = buf.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(dev, frame.type, frame.reportID, base, buf.count)
        }
    }

    /// 把一帧广播给所有已打开接口，返回最好的一次结果
    @discardableResult
    private func send(_ frame: Frame) -> kern_return_t {
        lock.lock(); defer { lock.unlock() }
        var best = kIOReturnError
        for dev in opened {
            let rc = write(frame, to: dev)
            if rc == kIOReturnSuccess { return rc }
            best = rc
        }
        return best
    }

    /// 握手：0x5A + "ASUS Tech.Inc."
    private func sendInit() {
        let body = Array("ASUS Tech.Inc.".utf8)
        let frame = Frame(name: "init", type: kIOHIDReportTypeFeature,
                          reportID: Self.inputReportID,
                          data: body + [UInt8](repeating: 0, count: max(0, maxFeatureLen - 1 - body.count)))
        _ = send(frame)
    }

    /// G-Helper 启动时会先给 Aura 通道发一串唤醒/探测报文（output report 0x5D）
    private func sendAuraPrimers() {
        guard !opened.isEmpty else { return }
        let payloads: [[UInt8]] = [
            [0xB9],
            Array("ASUS Tech.Inc.".utf8),
            [0x05, 0x20, 0x31, 0x00, 0x20]
        ]
        for payload in payloads {
            let frame = Frame(name: "primer", type: kIOHIDReportTypeOutput,
                              reportID: Self.auraReportID2, data: payload)
            _ = send(frame)
        }
    }

    /// 设置背光，level 取值 0...3。返回 nil 表示至少有一种写法被接受
    func setLevel(_ level: Int) -> String? {
        lock.lock()
        let ready = !opened.isEmpty || openDevice() != nil
        lock.unlock()
        guard ready else { return lastError ?? "未找到 ASUS Aura HID 设备" }

        let clamped = UInt8(max(0, min(Self.maxLevel, level)))
        var succeeded: [String] = []
        var attempts: [(String, kern_return_t)] = []

        for frame in frames(level: clamped) {
            let rc = send(frame)
            if rc == kIOReturnSuccess {
                succeeded.append(frame.name)
            } else {
                attempts.append((frame.name, rc))
            }
        }

        lastWriteVariant = succeeded.isEmpty ? nil : succeeded.joined(separator: " + ")
        lastAttempts = attempts
        if !succeeded.isEmpty { return nil }

        let detail = attempts
            .map { "\($0.0)=0x\(String(format: "%08X", UInt32(bitPattern: $0.1)))" }
            .joined(separator: " · ")
        return "写入 HID 报告失败（全部写法都被拒绝）\(detail.isEmpty ? "" : "｜" + detail)"
    }

    /// 调试面板：单独发第 index 种写法
    @discardableResult
    func debugWrite(index: Int, level: Int) -> kern_return_t {
        lock.lock()
        let ready = !opened.isEmpty || openDevice() != nil
        lock.unlock()
        guard ready else { return lastOpenResult }

        let clamped = UInt8(max(0, min(Self.maxLevel, level)))
        let all = frames(level: clamped)
        guard index >= 0, index < all.count else { return kIOReturnBadArgument }
        let rc = send(all[index])
        if rc == kIOReturnSuccess {
            lastWriteVariant = all[index].name
        }
        return rc
    }

    /// 调试面板用的写法名
    var frameNames: [String] { frames(level: 2).map(\.name) }

    /// 当前设备接受的写入方式，写进诊断报告
    var writeMethodText: String {
        lastWriteVariant ?? "尚未写入"
    }
}
