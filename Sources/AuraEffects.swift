//
//  AuraEffects.swift
//  ASUS ROG 键盘 RGB 灯效控制（2021+ N-KEY 机型，USB HID 0x0B05:0x19B6）
//
//  协议权威来源（两者完全一致，互为印证）：
//    • asusctl   rog-aura/src/builtin_modes.rs  From<&AuraEffect> for [u8; 17]
//    • G-Helper  app/USB/Aura.cs                AuraMessage()
//
//  报文格式（全部 17 字节）
//    效果  5D B3 <Zone> <Mode> <R> <G> <B> <Speed> <Dir> <Flag> <R2> <G2> <B2>
//    提交  5D B5 00 00 00 ...
//    应用  5D B4 00 ...
//    亮度  5A BA C5 C4 <level>          ← 走 INPUT_ID 通道（不是 0x5D！）
//
//  关键点（踩过的坑）：
//    1. 0x5A 是 INPUT_ID（亮度/握手），0x5D 是 AURA_ID（灯效），别混。
//    2. 效果/提交/应用 走 **Output** 报告，17 字节原样长度、不补零；
//       亮度与握手走 **Feature** 报告，要补零到 MaxFeatureReportSize。
//    3. 第 9 字节是 Flag：0x00 普通 / 0x01 呼吸 / 0xFF 全黑（随机色）。
//    4. 生效需要「效果 → 提交(B5) → 应用(B4)」三步，缺一不生效。
//
//  注意：macOS 把键盘类 HID 锁了，IOHIDDeviceOpen 会返回 kIOReturnNotPermitted，
//  需要「系统设置 → 隐私与安全性 → 输入监控」授权，且授权后要重启进程。
//

import Foundation
import AppKit
import IOKit
import IOKit.hid

/// ASUS Aura 灯效模式（与 G-Helper AuraMode / asusctl AuraModeNum 一致）
enum AuraMode: Int, CaseIterable {
    case static_   = 0   // 静态
    case breathe   = 1   // 呼吸
    case colorCycle = 2   // 色彩循环
    case rainbow   = 3   // 彩虹
    case star      = 4   // 星光
    case rain      = 5   // 雨滴
    case highlight = 6   // 高亮
    case laser     = 7   // 激光
    case ripple    = 8   // 涟漪
    case strobe    = 10  // 频闪
    case pulse     = 11  // 脉冲
    case comet     = 12  // 彗星 / 闪光

    var title: String {
        switch self {
        case .static_:   return "静态"
        case .breathe:   return "呼吸"
        case .colorCycle: return "色彩循环"
        case .rainbow:   return "彩虹"
        case .star:      return "星光"
        case .rain:      return "雨滴"
        case .highlight: return "高亮"
        case .laser:     return "激光"
        case .ripple:    return "涟漪"
        case .strobe:    return "频闪"
        case .pulse:     return "脉冲"
        case .comet:     return "彗星"
        }
    }

    /// G-Helper 里 AuraBreathe 用 Flag=0x01，其余用 0x00
    var flag: UInt8 { self == .breathe ? 0x01 : 0x00 }

    /// 该模式是否需要第二颜色
    var needsSecondColor: Bool {
        switch self {
        case .breathe, .star, .ripple, .pulse, .comet: return true
        default: return false
        }
    }
}

/// 速度（asusctl Speed 枚举）
enum AuraSpeed: Int, CaseIterable {
    case low = 0xE1, med = 0xEB, high = 0xF5

    var title: String {
        switch self {
        case .low:  return "慢"
        case .med:  return "中"
        case .high: return "快"
        }
    }
}

/// 方向（asusctl Direction 枚举，主要彩虹模式用）
enum AuraDirection: Int, CaseIterable {
    case right = 0, left = 1, up = 2, down = 3

    var title: String {
        switch self {
        case .right: return "向右"
        case .left:  return "向左"
        case .up:    return "向上"
        case .down:  return "向下"
        }
    }
}

/// 一个完整的灯效配置
struct AuraEffect {
    var mode: AuraMode = .rainbow
    var zone: Int = 0            // 0 = 无分区；1...4 = 分区
    var color1: (r: Int, g: Int, b: Int) = (255, 0, 0)
    var color2: (r: Int, g: Int, b: Int) = (0, 0, 0)
    var speed: AuraSpeed = .med
    var direction: AuraDirection = .right

    /// 生成 17 字节效果报文（与 G-Helper AuraMessage 逐字节一致）
    var message: [UInt8] {
        var msg = [UInt8](repeating: 0, count: 17)
        msg[0] = 0x5D
        msg[1] = 0xB3
        msg[2] = UInt8(zone & 0xFF)
        msg[3] = UInt8(mode.rawValue)
        msg[4] = UInt8(color1.r & 0xFF)
        msg[5] = UInt8(color1.g & 0xFF)
        msg[6] = UInt8(color1.b & 0xFF)
        msg[7] = UInt8(speed.rawValue)
        msg[8] = UInt8(direction.rawValue)
        msg[9] = mode.flag
        msg[10] = UInt8(color2.r & 0xFF)
        msg[11] = UInt8(color2.g & 0xFF)
        msg[12] = UInt8(color2.b & 0xFF)
        return msg
    }
}

/// 灯效控制入口
final class AuraEffects {

    static let shared = AuraEffects()

    /// G-Helper MAIN_AURA_PIDS —— 含 0x19B6（2021+ N-KEY 机型）
    static let auraPIDs: [Int] = [
        0x1a30, 0x1854, 0x1869, 0x1866, 0x19b6, 0x1822, 0x1837, 0x184a, 0x183d,
        0x8502, 0x1807, 0x17e0, 0x1abe, 0x1b4c, 0x1b6e, 0x1b2c, 0x8854,
        0x1ce7, 0x1ce6, 0x1bf2, 0x1bf3, 0x1cd7, 0x1cd8, 0x4b42
    ]

    private var opened: [IOHIDDevice] = []
    private let lock = NSRecursiveLock()
    private(set) var lastError: String?
    private(set) var permissionDenied = false

    private static let auraID: CFIndex = 0x5D
    private static let inputID: CFIndex = 0x5A

    // MARK: - 设备

    private func intProp(_ dev: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(dev, key as CFString) as? NSNumber)?.intValue ?? -1
    }

    private func candidateDevices() -> [IOHIDDevice] {
        var result: [IOHIDDevice] = []
        var seen = Set<String>()
        for cls in ["IOHIDDevice", "AppleUserHIDDevice"] {
            var iter: io_iterator_t = 0
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(cls), &iter) == KERN_SUCCESS else { continue }
            var service = IOIteratorNext(iter)
            while service != 0 {
                if let dev = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
                    let vid = intProp(dev, kIOHIDVendorIDKey)
                    let pid = intProp(dev, kIOHIDProductIDKey)
                    if vid == 0x0B05, Self.auraPIDs.contains(pid) {
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

    /// 打开所有 Aura 接口；返回成功打开的数量
    @discardableResult
    private func openAll() -> Int {
        lock.lock(); defer { lock.unlock() }
        if !opened.isEmpty { return opened.count }

        let all = candidateDevices()
        guard !all.isEmpty else {
            lastError = "没有找到 ASUS Aura HID 控制器"
            return 0
        }
        permissionDenied = false
        for dev in all {
            let rc = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
            if rc == kIOReturnSuccess {
                opened.append(dev)
            } else if rc == kIOReturnNotPermitted {
                permissionDenied = true
                lastError = "macOS 拒绝访问键盘类 HID 设备：需要「输入监控」权限"
            } else {
                lastError = "打开 HID 设备失败 (kern_return 0x\(String(UInt32(bitPattern: rc), radix: 16)))"
            }
        }
        if !opened.isEmpty {
            lastError = nil
            primeAuraChannel()
        }
        return opened.count
    }

    // MARK: - 写入

    /// Output 报告：原样长度，不补零（G-Helper 的 stream.Write）
    @discardableResult
    private func writeOutput(_ msg: [UInt8]) -> kern_return_t {
        var best = kIOReturnError
        for dev in opened {
            let rc = msg.withUnsafeBufferPointer { buf -> kern_return_t in
                guard let base = buf.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, Self.auraID, base, buf.count)
            }
            if rc == kIOReturnSuccess { return rc }
            best = rc
        }
        return best
    }

    /// Feature 报告：补零到 MaxFeatureReportSize
    @discardableResult
    private func writeFeature(_ msg: [UInt8], reportID: CFIndex) -> kern_return_t {
        var best = kIOReturnError
        for dev in opened {
            let featureLen = intProp(dev, kIOHIDMaxFeatureReportSizeKey)
            let total = max(featureLen, msg.count)
            var payload = [UInt8](repeating: 0, count: total)
            payload.replaceSubrange(0..<msg.count, with: msg)
            let rc = payload.withUnsafeBufferPointer { buf -> kern_return_t in
                guard let base = buf.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(dev, kIOHIDReportTypeFeature, reportID, base, buf.count)
            }
            if rc == kIOReturnSuccess { return rc }
            best = rc
        }
        return best
    }

    /// Aura 通道握手（G-Helper 的 primer 序列）
    private func primeAuraChannel() {
        // 5D B9
        writeOutput([0x5D, 0xB9])
        // 5D "ASUS Tech.Inc."
        var sig: [UInt8] = [0x5D]
        sig.append(contentsOf: Array("ASUS Tech.Inc.".utf8))
        writeOutput(sig)
        // 5D 05 20 31 00 20
        writeOutput([0x5D, 0x05, 0x20, 0x31, 0x00, 0x20])
        // INPUT_ID 握手：5A "ASUS Tech.Inc."
        var isig: [UInt8] = [0x5A]
        isig.append(contentsOf: Array("ASUS Tech.Inc.".utf8))
        writeFeature(isig, reportID: Self.inputID)
        // ProArt 风格 init
        writeFeature([0x5A, 0x05, 0x20, 0x31, 0x00, 0x08], reportID: Self.inputID)
        writeFeature([0x5A, 0xBA, 0xC5, 0xC4], reportID: Self.inputID)
    }

    // MARK: - 对外接口

    /// 是否可用（能打开设备）
    var isAvailable: Bool { openAll() > 0 }

    var needsPermission: Bool {
        lock.lock(); defer { lock.unlock() }
        if !opened.isEmpty { return false }
        _ = openAll()
        return permissionDenied
    }

    /// 应用一个灯效。返回 nil 表示成功，否则是错误描述
    func apply(_ effect: AuraEffect) -> String? {
        lock.lock()
        let ready = !opened.isEmpty || openAll() > 0
        lock.unlock()
        guard ready else { return lastError ?? "未找到 ASUS Aura HID 设备" }

        let msg = effect.message
        let rc = writeOutput(msg)
        guard rc == kIOReturnSuccess else {
            return "写入灯效报文失败 (kern_return 0x\(String(UInt32(bitPattern: rc), radix: 16)))"
        }
        // 提交
        writeOutput([0x5D, 0xB5, 0x00, 0x00, 0x00])
        // 应用
        writeOutput([0x5D, 0xB4])
        return nil
    }

    /// 原始发送（调试用）
    @discardableResult
    func raw(_ msg: [UInt8], useOutput: Bool = true) -> kern_return_t {
        lock.lock()
        let ready = !opened.isEmpty || openAll() > 0
        lock.unlock()
        guard ready else { return kIOReturnNotPermitted }
        return useOutput ? writeOutput(msg) : writeFeature(msg, reportID: Self.auraID)
    }

    /// 探测到的 Aura 接口 PID 列表
    func probe() -> [Int] {
        candidateDevices().map { intProp($0, kIOHIDProductIDKey) }.sorted()
    }

    // MARK: - 机型诊断（适配其他机型用）

    /// G-Helper AuraProbe 的解析结果（报文见 Aura.cs DetectBacklightType）
    struct AuraProbeInfo {
        let raw: [UInt8]
        /// response[9]: 背光类型
        let typeByte: UInt8
        /// response[10]: 上市年份(BCD)
        let year: UInt8
        /// response[12]: 键盘布局
        let layout: UInt8
        /// response[13]: 区域特性位（logo/灯带/尾部灯…）
        let feat1: UInt8
        /// response[14]: 功能特性位（默认色/RGB滚轮/单区红/逐键…）
        let feat2: UInt8
        /// response[17]: 产品族（2023+ 固件才有）
        let family: UInt8

        var backlightTypeText: String {
            switch typeByte {
            case 0x02: return "MultiZone 多区"
            case 0x03: return "PerKey 逐键 RGB"
            case 0x04: return "SingleZone 单区"
            case 0x00: return "SingleZone 单区（旧固件隐式）"
            default:   return "Unknown 0x\(String(typeByte, radix: 16))"
            }
        }

        var familyText: String {
            switch family {
            case 0x01: return "Strix"
            case 0x02: return "Flow"
            case 0x04: return "Zephyrus"
            case 0x08: return "TUF"
            case 0x10: return "NR2301"
            case 0x20: return "Desktop"
            case 0x00: return "(2023 前机型无此字段)"
            default:   return "unknown 0x\(String(family, radix: 16))"
            }
        }

        /// feat1 区域位（G-Helper FEAT1_*）
        var feat1Text: String {
            var parts: [String] = []
            if feat1 & 0x01 != 0 { parts.append("Logo灯") }
            if feat1 & 0x02 != 0 { parts.append("灯带Lightbar") }
            if feat1 & 0x10 != 0 { parts.append("Vcut") }
            if feat1 & 0x20 != 0 { parts.append("Aero") }
            if feat1 & 0x40 != 0 { parts.append("Bump") }
            if feat1 & 0x80 != 0 { parts.append("尾部Rearglow") }
            return parts.isEmpty ? "无" : parts.joined(separator: " / ")
        }

        /// feat2 功能位（G-Helper FEAT2_*）
        var feat2Text: String {
            var parts: [String] = []
            if feat2 & 0x04 != 0 { parts.append("默认色") }
            if feat2 & 0x08 != 0 { parts.append("RGB滚轮") }
            if feat2 & 0x10 != 0 { parts.append("单区红(isWhite)") }
            if feat2 & 0x40 != 0 { parts.append("逐键KeyMap") }
            return parts.isEmpty ? "无" : parts.joined(separator: " / ")
        }
    }

    /// 回读 Feature 报告（取第一个成功打开的接口）
    private func readFeature(reportID: CFIndex, length: Int) -> [UInt8]? {
        for dev in opened {
            var buf = [UInt8](repeating: 0, count: max(length, 64))
            var n = buf.count
            let r = buf.withUnsafeMutableBufferPointer { b -> kern_return_t in
                guard let base = b.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceGetReport(dev, kIOHIDReportTypeFeature, reportID, base, &n)
            }
            if r == kIOReturnSuccess { return Array(buf.prefix(max(n, 1))) }
        }
        return nil
    }

    /// 发送 Aura Probe 并解析响应（G-Helper AsusHid.AuraProbe + Aura.DetectBacklightType）
    func auraProbe() -> AuraProbeInfo? {
        lock.lock()
        let ready = !opened.isEmpty || openAll() > 0
        lock.unlock()
        guard ready else { return nil }

        // 探测序列（Output）
        raw([0x5D, 0xB9])
        var sig: [UInt8] = [0x5D]
        sig.append(contentsOf: Array("ASUS Tech.Inc.".utf8))
        raw(sig)
        raw([0x5D, 0x05, 0x20, 0x31, 0x00, 0x20])

        // 回读 Feature 0x5D
        guard let resp = readFeature(reportID: Self.auraID, length: 64), resp.count >= 15 else { return nil }
        // 校验前 4 字节与查询一致（G-Helper 同款校验）
        let query: [UInt8] = [0x5D, 0x05, 0x20, 0x31]
        guard resp.prefix(4) == query[...] else { return nil }

        let year = resp.count > 10 ? resp[10] : 0
        return AuraProbeInfo(
            raw: resp,
            typeByte: resp[9],
            year: year,
            layout: resp.count > 12 ? resp[12] : 0,
            feat1: resp.count > 13 ? resp[13] : 0,
            feat2: resp.count > 14 ? resp[14] : 0,
            family: (resp.count > 17 && year >= 0x23) ? resp[17] : 0
        )
    }

    /// 从 HID 报告描述符提取全部 Report ID
    private func reportIDs(of dev: IOHIDDevice) -> [UInt8] {
        guard let data = IOHIDDeviceGetProperty(dev, kIOHIDReportDescriptorKey as CFString) as? Data else { return [] }
        let b = [UInt8](data)
        var ids: [UInt8] = []
        var i = 0
        while i < b.count {
            if b[i] == 0x85, i + 1 < b.count { ids.append(b[i + 1]) }
            // 粗略跳过长项（0xFE 前缀）；短项 item size 由低 2 位决定
            if b[i] == 0xFE { i += 2 + Int(b[i + 1]) + Int(b.count > i + 2 ? b[i + 2] : 0) }
            i += 1
        }
        return ids
    }

    /// 一键诊断报告：适配其他机型时让用户跑这个，把输出回传即可
    func diagnosticReport() -> String {
        var lines: [String] = []

        let devs = candidateDevices()
        guard !devs.isEmpty else {
            return "ERR 未找到 ASUS Aura HID 控制器（VID 0x0B05）。\n" +
                   "    这台机器可能：① 没有内置 RGB 键盘 ② 走 LampArray/其他协议 ③ 需要安装虚拟驱动才有 IOHIDDevice 节点。"
        }

        lines.append("=== ASUS Aura 机型诊断 ===")
        lines.append("系统: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")
        lines.append("-- 设备接口 --")
        for dev in devs {
            let pid = intProp(dev, kIOHIDProductIDKey)
            let name = (IOHIDDeviceGetProperty(dev, kIOHIDProductKey as CFString) as? String) ?? "?"
            let fl = intProp(dev, kIOHIDMaxFeatureReportSizeKey)
            let ol = intProp(dev, kIOHIDMaxOutputReportSizeKey)
            let page = intProp(dev, kIOHIDPrimaryUsagePageKey)
            let ids = reportIDs(of: dev).map { String(format: "0x%02X", $0) }.joined(separator: " ")
            lines.append(String(format: "  PID=0x%04X '%@' usagePage=0x%04X featLen=%d outLen=%d", pid, name, page, fl, ol))
            lines.append("    ReportIDs: \(ids)")
        }

        lines.append("")
        lines.append("-- 权限/打开 --")
        let count = openAll()
        if count > 0 {
            lines.append("  打开成功: \(count) 个接口 ✓")
        } else {
            lines.append("  打开失败: \(lastError ?? "?")")
            lines.append("  → 系统设置 → 隐私与安全性 → 输入监控 授权本 App 并重启后重试")
            return lines.joined(separator: "\n")
        }

        lines.append("")
        lines.append("-- Aura Probe（G-Helper 同款探测）--")
        if let p = auraProbe() {
            let hex = p.raw.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
            lines.append("  原始响应: \(hex)")
            lines.append("  背光类型: \(p.backlightTypeText)")
            lines.append("  上市年份: 0x\(String(p.year, radix: 16))")
            lines.append("  键盘布局: 0x\(String(p.layout, radix: 16))")
            lines.append("  区域特性: 0x\(String(p.feat1, radix: 16)) → \(p.feat1Text)")
            lines.append("  功能特性: 0x\(String(p.feat2, radix: 16)) → \(p.feat2Text)")
            lines.append("  产品族  : 0x\(String(p.family, radix: 16)) → \(p.familyText)")
        } else {
            lines.append("  探测无响应（旧固件机型可能不支持 Probe，属正常）")
        }

        lines.append("")
        lines.append("-- 亮度通道回读 --")
        if let cur = readFeature(reportID: Self.inputID, length: 64) {
            let hex = cur.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
            let level = (cur.count > 4 && cur[1] == 0xBA && cur[2] == 0xC5 && cur[3] == 0xC4) ? "\(cur[4])/3" : "格式不匹配"
            lines.append("  0x5A 回读: \(hex)  亮度: \(level)")
        } else {
            lines.append("  0x5A 回读失败")
        }

        lines.append("")
        lines.append("-- 适配结论（自动判断）--")
        if let p = auraProbe() {
            switch p.typeByte {
            case 0x02, 0x03, 0x04:
                lines.append("  ✓ 本机属于 5D B3 协议族，可直接使用本工具（含亮度/12 种灯效）")
                if p.typeByte == 0x03 {
                    lines.append("  · 逐键机型：整体灯效可用；逐键控制需额外 key-map，见 asusctl per_key_rgb.rs")
                }
                if p.feat2 & 0x10 != 0 {
                    lines.append("  · 单区红机型（isWhite）：颜色会被固件强制按红/暗处理，属正常")
                }
            default:
                lines.append("  ? 探测到未知类型 0x\(String(p.typeByte, radix: 16))，请把本报告整体回传")
            }
        } else {
            lines.append("  ? 无 Probe 响应：请把本报告整体回传，另行判断协议族")
        }

        lines.append("")
        lines.append("把以上全部内容截图/复制发回来即可完成机型适配信息收集。")
        return lines.joined(separator: "\n")
    }

    /// 关闭并释放设备
    func closeAll() {
        lock.lock(); defer { lock.unlock() }
        for dev in opened { IOHIDDeviceClose(dev, 0) }
        opened.removeAll()
    }
}
