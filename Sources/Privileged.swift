//
//  Privileged.swift
//  背光控制层：优先走 ASUS Aura HID（用户态、免 root），其次走 VirtualSMC 的 LKSB（需 root）
//  以及需要 root 时的提权通道。
//

import Foundation

enum Admin {
    static var isRoot: Bool { geteuid() == 0 }

    /// 以管理员身份运行当前可执行文件的 CLI 模式
    static func runSelfAsAdmin(_ args: [String]) -> (ok: Bool, output: String) {
        if isRoot {
            return SelfExec.runCLI(args)
        }
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let safePath = exe.replacingOccurrences(of: "\\", with: "\\\\")
                           .replacingOccurrences(of: "\"", with: "\\\"")
        let argString = args.joined(separator: " ")
        let script = "do shell script (quoted form of \"\(safePath)\") & \" \(argString)\" with administrator privileges"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }

    /// 静默以 root 执行本程序 CLI（不弹密码框）。
    /// 走 `sudo -n`：`-n` 表示非交互，一旦需要密码立即失败（不卡住、不弹框）。
    /// 调用方应把它当「能发就发，发不了就跳过」——典型用途是开机 / 唤醒的自动下发，
    /// 那时人不在场，弹密码框没有意义。手动点「应用」仍走 `runSelfAsAdmin`（弹框一次）。
    static func runSilent(_ args: [String]) -> (ok: Bool, output: String) {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        p.arguments = ["-n", exe] + args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

/// 直接在本进程内执行 CLI 逻辑（已是 root 时走这里）
enum SelfExec {
    static func runCLI(_ args: [String]) -> (ok: Bool, output: String) {
        let status = CLI.run(args, printOutput: false)
        return (status == 0, CLI.lastMessage)
    }
}

// MARK: - 风扇探测

enum FanProbe {
    /// VirtualSMC / AsusSMC 上报的风扇数量（可能是不靠谱的占位值，例如 8）。
    /// 本机 FNum=0（VirtualSMC 没接管风扇），此时退回 AsusECTool 实际存在几颗 tach。
    static var count: Int {
        let n = Int(SMC.read("FNum")?.number ?? 0)
        if n > 0 { return n }
        let ec = ECFanBridge.shared
        guard ec.isAvailable else { return 0 }
        return [ECFanBridge.Channel.cpu, .gpu, .center].reduce(0) { acc, ch in
            acc + ((ec.rpm(ch) ?? 0) > 0 ? 1 : 0)
        }
    }

    /// 只在数值合理时才认为可用：200–8000 RPM。
    /// 本机实测 F0Ac 恒为 0x9c40（10000 RPM）且不随负载变化，属于占位值，
    /// 所以 SMC 读不到合理值时要退回 EC 的 tach（IT55 + 0x02）。
    static var rpm: Double? {
        if let v = SMC.read("F0Ac")?.number, v >= 200, v <= 8000 { return v }
        if let ec = ECFanBridge.shared.rpm(.cpu), ec >= 200, ec <= 8000 {
            return Double(ec)
        }
        return nil
    }

    /// GPU 风扇转速（F1Ac / EC tach FA2）。待机可能为 0（风扇停转），属正常，下限取 0。
    static var gpuRPM: Double? {
        if let v = SMC.read("F1Ac")?.number, v >= 0, v <= 8000, v > 0 { return v }
        if let ec = ECFanBridge.shared.rpm(.gpu), ec <= 8000 { return Double(ec) }
        return nil
    }

    /// 第三颗（中置）风扇 —— 18 寸机型才有，只能走 EC
    static var centerRPM: Double? {
        guard let ec = ECFanBridge.shared.rpm(.center), ec > 0, ec <= 8000 else { return nil }
        return Double(ec)
    }

    /// 转速读数是否可用：SMC 值合理，或 EC tach 有值
    static var isAvailable: Bool {
        guard rpm != nil else { return false }
        return count > 0 || ECFanBridge.shared.isAvailable
    }

    /// 当前转速读数来自哪条通道
    static var backendLabel: String {
        if let v = SMC.read("F0Ac")?.number, v >= 200, v <= 8000 { return "AppleSMC → F0Ac" }
        if ECFanBridge.shared.isAvailable { return "AsusECTool.kext → EC tach（IT55）" }
        return "不可用"
    }
}

// MARK: - 控制层

enum BacklightMode {
    case nkeyd              // 交给 nkeyd 的控制口代发（键盘被 daemon 独占时唯一可行）
    case hid(pid: Int)      // Aura HID 输出报告，免 root
    case smc                // VirtualSMC LKSB → AsusSMC → ATK.SKBV，需要 root
    case none

    var maxLevel: Int {
        switch self {
        case .nkeyd: return NKeydBridge.maxLevel  // 0...3
        case .hid: return HIDBacklight.maxLevel   // 0...3
        case .smc: return 16                      // 0...16
        case .none: return 0
        }
    }

    var label: String {
        switch self {
        case .nkeyd: return "nkeyd 转发 (0x0B05:0x19B6)"
        case .hid(let pid): return String(format: "Aura HID (0x%04X)", pid)
        case .smc: return "SMC · LKSB"
        case .none: return "不可用"
        }
    }

    /// 走 Aura 报文（0x5A / 0x5D）的通道，只有 4 档
    var isAura: Bool {
        switch self {
        case .nkeyd, .hid: return true
        case .smc, .none: return false
        }
    }

    var isNKeyd: Bool {
        if case .nkeyd = self { return true }
        return false
    }

    var detail: String {
        switch self {
        case .nkeyd:
            return "键盘已被 nkeyd 独占，背光与灯效报文经它的控制口转发（report 0x5A / 0x5D），无需 root，也不影响打字"
        case .hid:
            return "通过键盘控制器的 Aura HID 输出报告（report 0x5A）直接下发，无需 root"
        case .smc:
            return "写入 AppleSMC 的 LKSB，由 AsusSMC 转发给 ACPI 的 SKBV 方法"
        case .none:
            return "既没有 nkeyd 控制口与 Aura HID 控制器，AsusSMC 也没拿到 SKBV 方法"
        }
    }
}

enum Control {
    static let keyboardBacklightKey = "LKSB"

    /// AsusSMC 是否成功在 ATK 设备上找到了 SKBV 方法
    static var asusSMCBacklightSupported: Bool {
        guard let props = SystemProbe.ioregProperties("AsusSMC") else { return false }
        if let b = props["IsKeyboardBacklightSupported"] as? Bool { return b }
        if let n = props["IsKeyboardBacklightSupported"] as? NSNumber { return n.boolValue }
        return false
    }

    // MARK: 通道缓存
    //
    // 探测一次要枚举全部 IOHID 设备并逐个尝试 open（实测 13 ms，峰值 21 ms），
    // 而背光通道在运行期间几乎不会变，所以这里缓存结果，只在需要时刷新。

    private static var cachedMode: BacklightMode?
    private static var cachedBlocked = false
    private static var cachedPermission: HIDBacklight.PermissionState = .notDetermined
    private static var cachedAt = Date.distantPast
    private static let cacheTTL: TimeInterval = 60
    private static let cacheLock = NSLock()

    static var mode: BacklightMode {
        // nkeyd 的探测只是一次本地 socket 连接（几十微秒），不参与 60 秒缓存：
        // daemon 重启或退出后界面能立刻反映真实状态。
        if NKeydBridge.shared.isAvailable { return .nkeyd }
        cacheLock.lock()
        if let cachedMode, Date().timeIntervalSince(cachedAt) < cacheTTL {
            cacheLock.unlock()
            return cachedMode
        }
        cacheLock.unlock()
        return refreshMode()
    }

    /// 重新探测通道（授权变化、插拔键盘、切换机型后调用）
    @discardableResult
    static func refreshMode() -> BacklightMode {
        if NKeydBridge.shared.isAvailable {
            cacheLock.lock()
            cachedMode = .nkeyd
            cachedPermission = .granted
            cachedBlocked = false
            cachedAt = Date()
            cacheLock.unlock()
            return .nkeyd
        }
        // 一次探测同时拿到「能不能用 / 哪个 PID / 卡在哪种权限状态」，避免重复枚举
        let permission = HIDBacklight.shared.permissionState
        let pid = HIDBacklight.shared.activeProductID
        let mode: BacklightMode
        if permission == .granted {
            mode = .hid(pid: pid)
        } else if SMC.exists(keyboardBacklightKey), asusSMCBacklightSupported {
            mode = .smc
        } else {
            mode = .none
        }
        cacheLock.lock()
        cachedMode = mode
        cachedPermission = permission
        cachedBlocked = (permission == .denied || permission == .needsRestart)
        cachedAt = Date()
        cacheLock.unlock()
        return mode
    }

    /// 当前输入监控权限的真实状态（走缓存，不会每次都枚举设备）
    static var permissionState: HIDBacklight.PermissionState {
        _ = mode
        cacheLock.lock()
        let value = cachedPermission
        cacheLock.unlock()
        return value
    }

    static func invalidateMode() {
        cacheLock.lock()
        cachedMode = nil
        cachedAt = .distantPast
        cacheLock.unlock()
    }

    static var maxLevel: Int { mode.maxLevel }

    /// Aura HID 设备存在但被系统拦下（缺「输入监控」权限）
    static var hidBlocked: Bool {
        _ = mode          // 触发缓存刷新
        return cachedBlocked
    }
    static var hidPermission: HIDBacklight.Permission { HIDBacklight.listenPermission }

    // MARK: 读

    private static let lastLevelKey = "kbd.lastLevel"

    /// HID 通道没有回读能力，用上次成功下发的值
    static var lastHIDLevel: Int {
        get { Prefs.int(lastLevelKey) }
        set { Prefs.set(newValue, for: lastLevelKey) }
    }

    /// 当前档位（尽力而为：SMC 直接读，HID 用程序记录值）
    static func currentLevel() -> Int {
        switch mode {
        case .nkeyd:
            return min(max(lastHIDLevel, 0), NKeydBridge.maxLevel)
        case .hid:
            return min(max(lastHIDLevel, 0), HIDBacklight.maxLevel)
        case .smc:
            guard let r = SMC.read(keyboardBacklightKey), let raw = r.number else { return 0 }
            // 驱动内部把 16 位值 /256 得到 SKBV，所以正向是 level*256
            let v = Int(raw)
            return v > 16 ? v / 256 : v
        case .none:
            return 0
        }
    }

    // MARK: 写

    /// 设置背光（0...maxLevel）。返回 nil 表示成功，否则是错误描述
    static func setBacklight(_ level: Int) -> String? {
        switch mode {
        case .nkeyd:
            let clamped = max(0, min(NKeydBridge.maxLevel, level))
            if NKeydBridge.shared.setLevel(clamped) {
                lastHIDLevel = clamped
                return nil
            }
            NKeydBridge.shared.invalidateAvailability()
            return "nkeyd 通道：背光报文下发失败（连接 \(NKeydBridge.socketPath) 出错）"

        case .hid:
            let clamped = max(0, min(HIDBacklight.maxLevel, level))
            if let err = HIDBacklight.shared.setLevel(clamped) { return err }
            lastHIDLevel = clamped
            return nil

        case .smc:
            let clamped = max(0, min(16, level))
            // 驱动公式：tval = (val1 << 4) | (val2 >> 4)，随后 /16 交给 SKBV
            // 因此 16 位原始值应为 level * 256
            let raw = UInt16(clamped * 256)
            let bytes: [UInt8] = [UInt8(raw >> 8 & 0xFF), UInt8(raw & 0xFF)]
            if Admin.isRoot {
                let rc = SMC.write(keyboardBacklightKey, bytes: bytes)
                if rc == 0 { invalidateMode(); return nil }
                if rc == 1 { return "权限不足：写入 \(keyboardBacklightKey) 需要 root" }
                return "SMC 写入失败（kern_return \(smc_last_kern_return())）"
            }
            // 提权：以 root 重跑自身 CLI，参数用 12 位原始值
            let result = Admin.runSelfAsAdmin(["smc", "write", keyboardBacklightKey,
                                               String(format: "%04x", raw)])
            if result.ok { invalidateMode(); return nil }
            if result.output.localizedCaseInsensitiveContains("cancel") || result.output.contains("-128") {
                return "已取消授权"
            }
            return result.output.isEmpty ? "授权失败" : result.output

        case .none:
            switch permissionState {
            case .needsRestart:
                return "已获得「输入监控」授权，但当前进程还没生效：请退出并重新打开本程序"
            case .denied:
                return "「输入监控」权限被拒绝：系统设置 → 隐私与安全性 → 输入监控，勾选本程序后重启"
            case .notDetermined:
                return "尚未获得「输入监控」授权：点「申请权限」，勾选后重启本程序"
            case .busy:
                return "背光设备被其他进程占用：关掉多余的 Vela X 实例后再试"
            case .noDevice:
                return "没有找到 ASUS Aura HID 控制器（0x0B05），键盘背光不可控"
            case .granted:
                break
            }
            if !asusSMCBacklightSupported {
                return "当前机型不可控：ATK 设备没有 SKBV 方法（AsusSMC 报 IsKeyboardBacklightSupported=No），也没有找到 Aura HID 控制器"
            }
            return "当前机型不可控"
        }
    }
}
