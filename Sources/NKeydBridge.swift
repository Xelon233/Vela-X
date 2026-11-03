//
//  NKeydBridge.swift
//  经 nkeyd 的本地控制口下发 Aura 报文（设备被 daemon 独占时唯一可行的一条路）
//
//  背景
//  ────
//  内置键盘 0x0B05:0x19B6 由 nkeyd 用 IOUSBHostDevice 的 device-capture 独占，
//  目的是拿到原始按键报告来消除 macOS 下的丢键。代价是：设备被 capture 之后，
//  系统里不再有它的 IOHIDDevice 服务，别的进程既枚举不到、也 open 不了。
//  所以 HIDBacklight / AuraEffects 那套 IOHIDDevice 直连方式在本机会一直返回
//  “没有找到 ASUS Aura HID 控制器”，Aura 能力被判成不可用。
//
//  nkeyd 因此开了一个本地控制口，把报文转成 USB 控制传输下发：
//
//    请求  [cmd][type][reportID][len] + payload
//          cmd  1 = SET_REPORT，2 = GET_REPORT
//          type 2 = Output，3 = Feature（USB 的 report type，不是 IOHIDReportType）
//          payload 第 0 字节是 reportID，后面是报文内容
//    应答  [status][len] + payload           status 0 = 成功
//
//  nkeyd 内部会自己把设备切成 report 协议、发完再切回 boot，所以这里不用管协议。
//

import Foundation

final class NKeydBridge {

    static let shared = NKeydBridge()

    static let socketPath = "/var/run/nkeyd-aura.sock"
    /// nkeyd 维护的亮度档位（0–3），重启后自行恢复
    static let levelPath = "/Users/Shared/.nkeyd-backlight"
    /// 最近一次下发的灯效（与 rgbctl 共用，格式：zone mode r g b speed）
    static let rgbStatePath = "/Users/Shared/.nkeyd-rgb"
    /// LED 接口初始化标记（内容 = 本次开机时间，换一次开机就重做一次初始化）
    static let initFlagPath = "/Users/Shared/.nkeyd-rgb-inited"

    static let maxLevel = 3

    /// USB SET/GET_REPORT 的 report type
    enum ReportType: UInt8 {
        case output = 2
        case feature = 3
    }

    /// 一个完整的灯效参数
    struct RGBState {
        var zone: Int = 0
        var mode: Int = 0
        var r: Int = 255
        var g: Int = 255
        var b: Int = 255
        var speed: Int = 1
        /// 方向 / 标记 / 第二颜色（只有需要的模式才带）
        var direction: Int = 0
        var flag: Int = 0
        var r2: Int = 0
        var g2: Int = 0
        var b2: Int = 0

        var needsExtended: Bool {
            direction != 0 || flag != 0 || r2 != 0 || g2 != 0 || b2 != 0
        }
    }

    private let lock = NSRecursiveLock()
    private var availableCache = false
    private var availableAt = Date.distantPast
    private static let availableTTL: TimeInterval = 2.0

    // MARK: - 连接

    /// 一条请求一连接：nkeyd 的 accept 循环一次只服务一个客户端，
    /// 长期挂着会把它堵死（rgbctl / 桥接库就都进不来了），所以用完就关。
    private func openSocket() -> Int32 {
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return -1 }

        var tv = timeval(tv_sec: 1, tv_usec: 500_000)
        let tvLen = socklen_t(MemoryLayout<timeval>.size)
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, tvLen)
        setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, tvLen)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cap = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
                _ = strlcpy(dst, Self.socketPath, cap)
            }
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if rc < 0 {
            close(s)
            return -1
        }
        return s
    }

    private func writeAll(_ s: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        while off < bytes.count {
            let n = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return write(s, base.advanced(by: off), bytes.count - off)
            }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    private func readAll(_ s: Int32, _ buf: inout [UInt8], _ len: Int) -> Bool {
        var off = 0
        while off < len {
            let n = buf.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return read(s, base.advanced(by: off), len - off)
            }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    /// 一次完整往返。payload 的第 0 字节是 reportID。
    private func transact(cmd: UInt8, type: ReportType, rid: UInt8,
                          payload: [UInt8]) -> (ok: Bool, data: [UInt8], sent: Bool) {
        lock.lock(); defer { lock.unlock() }

        let s = openSocket()
        guard s >= 0 else { return (false, [], false) }
        defer { close(s) }

        let body = payload.count > 64 ? Array(payload.prefix(64)) : payload
        var packet: [UInt8] = [cmd, type.rawValue, rid, UInt8(body.count)]
        packet.append(contentsOf: body)
        guard writeAll(s, packet) else { return (false, [], false) }

        var head = [UInt8](repeating: 0, count: 2)
        guard readAll(s, &head, 2) else { return (false, [], true) }

        var data: [UInt8] = []
        let outLen = Int(head[1])
        if outLen > 0 {
            var buf = [UInt8](repeating: 0, count: outLen)
            guard readAll(s, &buf, outLen) else { return (head[0] == 0, [], true) }
            data = buf
        }
        return (head[0] == 0, data, true)
    }

    /// 把一个完整序列放进**同一个连接**里连续发。
    ///
    /// 为什么必须同连接：nkeyd 支持「保持 report 协议」模式（cmd 4 = 进入并保持，
    /// 3 = 不切协议直接发，5 = 切回 boot）。灯效的 B3(设模式) → B5(保存) →
    /// B4(应用) 必须在同一个 report 协议会话内连续到达，否则设备内部的灯效状态机
    /// 会被协议切换打断 —— 表现就是报文全部返回成功、GET 回读也一致，但灯不动。
    private func batch(_ steps: [(cmd: UInt8, type: ReportType, rid: UInt8, payload: [UInt8])]) -> Bool {
        lock.lock(); defer { lock.unlock() }

        let s = openSocket()
        guard s >= 0 else { return false }
        defer { close(s) }

        var allOK = true
        for step in steps {
            let body = step.payload.count > 64 ? Array(step.payload.prefix(64)) : step.payload
            var packet: [UInt8] = [step.cmd, step.type.rawValue, step.rid, UInt8(body.count)]
            packet.append(contentsOf: body)

            guard writeAll(s, packet) else { allOK = false; break }

            var head = [UInt8](repeating: 0, count: 2)
            guard readAll(s, &head, 2) else { allOK = false; break }
            if head[1] > 0 {
                var buf = [UInt8](repeating: 0, count: Int(head[1]))
                _ = readAll(s, &buf, Int(head[1]))
            }
            if head[0] != 0 { allOK = false }
        }
        return allOK
    }

    // MARK: - 可用性

    /// nkeyd 是否在跑（socket 能连上）
    var isAvailable: Bool {
        lock.lock()
        if Date().timeIntervalSince(availableAt) < Self.availableTTL {
            let v = availableCache
            lock.unlock()
            return v
        }
        lock.unlock()

        let s = openSocket()
        let ok = s >= 0
        if ok { close(s) }

        lock.lock()
        availableCache = ok
        availableAt = Date()
        lock.unlock()
        return ok
    }

    /// socket 文件是否存在（区分“daemon 没跑”和“根本没有这功能”）
    var socketPresent: Bool {
        FileManager.default.fileExists(atPath: Self.socketPath)
    }

    func invalidateAvailability() {
        lock.lock()
        availableAt = .distantPast
        lock.unlock()
    }

    // MARK: - 原始报文

    /// 发一条报文；`bytes[0]` 默认为 reportID
    @discardableResult
    func setReport(_ bytes: [UInt8], type: ReportType = .feature, rid: UInt8? = nil) -> Bool {
        guard let first = bytes.first else { return false }
        let r = rid ?? first
        let res = transact(cmd: 1, type: type, rid: r, payload: bytes)
        if !res.sent { invalidateAvailability() }
        return res.ok
    }

    /// 回读一条 feature 报告
    func getReport(rid: UInt8, type: ReportType = .feature) -> [UInt8]? {
        let res = transact(cmd: 2, type: type, rid: rid, payload: [])
        return res.ok ? res.data : nil
    }

    // MARK: - 背光亮度（0x5A）

    /// 设置亮度 0–3，带回读校验（设备在 report 协议下会回 5A BA C5 C4 <level>）
    @discardableResult
    func setLevel(_ level: Int) -> Bool {
        let v = UInt8(max(0, min(Self.maxLevel, level)))
        let packet: [UInt8] = [0x5A, 0xBA, 0xC5, 0xC4, v]
        guard setReport(packet, type: .feature) else { return false }

        if let rb = getReport(rid: 0x5A), rb.count >= 5,
           rb[1] == 0xBA, rb[2] == 0xC5, rb[3] == 0xC4, rb[4] != v {
            // 校验不一致时补发一次（刚开机时偶发）
            _ = setReport(packet, type: .feature)
        }
        Self.persistLevel(level)
        return true
    }

    /// nkeyd 记录的当前档位
    static var storedLevel: Int {
        guard let s = try? String(contentsOfFile: levelPath, encoding: .utf8),
              let v = Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return 0 }
        return max(0, min(maxLevel, v))
    }

    static func persistLevel(_ level: Int) {
        let v = max(0, min(maxLevel, level))
        try? "\(v)\n".write(toFile: levelPath, atomically: true, encoding: .utf8)
    }

    // MARK: - RGB 灯效（0x5D）

    /// 本次开机的时间戳：灯效初始化每个开机周期只需做一次
    private static var bootSeconds: Int {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 { return Int(tv.tv_sec) }
        return 0
    }

    private static var initDoneThisBoot: Bool {
        guard let s = try? String(contentsOfFile: initFlagPath, encoding: .utf8) else { return false }
        return s.trimmingCharacters(in: .whitespacesAndNewlines) == "\(bootSeconds)"
    }

    private static func markInitDone() {
        try? "\(bootSeconds)\n".write(toFile: initFlagPath, atomically: true, encoding: .utf8)
    }

    /// LED 接口初始化（hid-asus 的 rog_nkey_led_init 序列）
    ///
    /// 不发这一段，后面所有 5D B3/B4/B5 都会被固件静默忽略 —— 表现就是“灯效设了没反应”。
    /// 0x5D 与 0x5E 两条通道都要喂一遍。
    @discardableResult
    func ensureLEDInit(force: Bool = false) -> Bool {
        if !force, Self.initDoneThisBoot { return true }
        guard isAvailable else { return false }

        let sequence: [[UInt8]] = [
            [0x5D, 0xB9],
            [0x5D] + Array("ASUS Tech.Inc.".utf8) + [0x00],
            [0x5D, 0x05, 0x20, 0x31, 0x00, 0x08],
            [0x5E] + Array("ASUS Tech.Inc.".utf8) + [0x00],
            [0x5E, 0x05, 0x20, 0x31, 0x00, 0x08]
        ]
        var ok = true
        for packet in sequence {
            if !setReport(packet, type: .feature) { ok = false }
            usleep(80_000)
        }
        if ok { Self.markInitDone() }
        return ok
    }

    /// 下发灯效：握手 → 设模式(5D B3) → 保存(5D B5) → 应用(5D B4)
    ///
    /// 整段在**同一个连接**里完成，并且全程保持在 report 协议下（见 batch 的说明）。
    /// 默认只发 8 字节核心报文；需要第二颜色 / 非默认方向时，才补上
    /// dir / flag / r2 g2 b2 三个字段，凑成 G-Helper 的 17 字节布局。
    @discardableResult
    func applyRGB(_ st: RGBState) -> Bool {
        var effect: [UInt8] = [
            0x5D, 0xB3,
            UInt8(st.zone & 0xFF),
            UInt8(st.mode & 0xFF),
            UInt8(st.r & 0xFF), UInt8(st.g & 0xFF), UInt8(st.b & 0xFF),
            UInt8(st.speed & 0xFF)
        ]
        if st.needsExtended {
            effect.append(contentsOf: [
                UInt8(st.direction & 0xFF),
                UInt8(st.flag & 0xFF),
                UInt8(st.r2 & 0xFF), UInt8(st.g2 & 0xFF), UInt8(st.b2 & 0xFF)
            ])
        }

        // Linux hid-asus: asus_report_id_init[] = { 0x5a, 0x5d, 0x5e }
        let magic = Array("ASUS Tech.Inc.".utf8) + [0x00]

        let steps: [(cmd: UInt8, type: ReportType, rid: UInt8, payload: [UInt8])] = [
            (4, .feature, 0x5D, []),                                // 进入 report 协议并保持
            (3, .feature, 0x5A, [0x5A] + magic),                    // 握手 0x5A
            (3, .feature, 0x5D, [0x5D] + magic),                    // 握手 0x5D
            (3, .feature, 0x5E, [0x5E] + magic),                    // 握手 0x5E
            (3, .feature, 0x5D, effect),                            // B3 设模式
            (3, .feature, 0x5D, [0x5D, 0xB5, 0x00]),                // B5 保存
            (3, .feature, 0x5D, [0x5D, 0xB4, 0x00]),                // B4 应用
            (5, .feature, 0x5D, []),                                // 切回 boot（打字用）
        ]

        let ok = batch(steps)
        if !ok { invalidateAvailability() }
        if ok { Self.persistRGBState(st) }
        return ok
    }

    // MARK: - 灯效状态记录

    static func persistRGBState(_ st: RGBState) {
        let line = "\(st.zone) \(st.mode) \(st.r) \(st.g) \(st.b) \(st.speed)\n"
        try? line.write(toFile: rgbStatePath, atomically: true, encoding: .utf8)
    }

    static var storedRGBState: RGBState? {
        guard let s = try? String(contentsOfFile: rgbStatePath, encoding: .utf8) else { return nil }
        let parts = s.split(separator: " ").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count >= 6 else { return nil }
        return RGBState(zone: parts[0], mode: parts[1],
                        r: parts[2], g: parts[3], b: parts[4], speed: parts[5])
    }

    /// 诊断用的一行摘要
    var statusText: String {
        if isAvailable {
            return "nkeyd 控制口在线（\(Self.socketPath)），亮度 \(Self.storedLevel)/\(Self.maxLevel)"
        }
        if socketPresent {
            return "nkeyd 控制口存在但连不上（daemon 未响应）"
        }
        return "nkeyd 未运行（\(Self.socketPath) 不存在）"
    }
}
