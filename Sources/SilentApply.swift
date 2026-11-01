//
//  SilentApply.swift
//  开机 / 唤醒静默下发功耗墙 + 风扇配置
//
//  背景：写 SMC 键必须 root，而唯一的提权通道 `Admin.runSelfAsAdmin`
//  （osascript with administrator privileges）是交互式的，每次弹密码框 —— 开机时人不在场，
//  没法静默。本模块用「一次性授权后的常驻 root 能力」解决：
//
//    · 首次在「设置」里打开「开机自动应用配置」时，用一次管理员密码把本 App 的 CLI
//      写进 /etc/sudoers.d（NOPASSWD），之后这台机器上该 CLI 即可免密以 root 运行；
//    · 启动时与睡眠唤醒后，自动读持久化的功耗墙 / 风扇档位，用 `Admin.runSilent`
//      （sudo -n，不弹框）默默下发；未授权 / 不支持时静默跳过。
//
//  ⚠️ sudoers 的坑（1.8.9 修）：命令路径带空格时 **不能用双引号包**，
//  sudo 会报 `expected a fully-qualified path name` 并把整份 drop-in 判为非法 ——
//  不只是本规则失效，这台机器上所有 sudo 都会打印这行错误。必须用反斜杠转义空格
//  （`/Applications/Vela\ X.app/...`）。落盘前一律先用 `visudo -c -f` 校验，
//  校验不过就绝不写入，避免再把用户的 sudo 弄坏。
//

import Foundation
import AppKit

enum SilentApply {
    /// 用户开关（设置页「开机自动应用配置」）
    static let enabledKey = "silent.applyEnabled"
    /// 是否已成功安装 sudoers 免密规则
    static let authorizedKey = "silent.applyAuthorized"
    /// 已安装规则时用的可执行文件路径（App 移动后与之不符 → 需要重装）
    private static let exeKey = "silent.applyExe"
    /// 规则格式版本：转义写法变了就 +1，老规则会在下次启动自动重写
    private static let versionKey = "silent.applyRuleVersion"
    /// 上次自动下发的结果（设置页直接显示，省得「失败但看不出来」）
    private static let lastResultKey = "silent.applyLastResult"
    private static let lastAtKey = "silent.applyLastAt"
    /// sudoers drop-in 规则文件
    static let rulePath = "/etc/sudoers.d/vela-silent"

    /// 规则格式版本。1 = 双引号包路径（非法，已废）；2 = 反斜杠转义
    static let ruleVersion = 2

    // MARK: 状态

    static var isEnabled: Bool { Prefs.bool(enabledKey) }

    private static var currentExe: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    /// 已授权 = 开关标记为已装 + 规则文件在 + 规则是当前格式 + 路径与当前 App 一致
    /// （被删 / App 移动 / 格式过老都算未授权，需要重装一次）
    static var isAuthorized: Bool {
        guard Prefs.bool(authorizedKey) else { return false }
        guard FileManager.default.fileExists(atPath: rulePath) else { return false }
        guard let stored = Prefs.string(exeKey), stored == currentExe else { return false }
        // 规则版本只作提示，不再当门槛：真正的判据是 probe() 能不能跑通。
        // （2.0.1 之前把版本存成字符串、这里按 Int 读，恒为 0 → 永远「未授权」，
        //   于是开机静默下发一次都没真正执行过。）
        return true
    }

    // MARK: 一键授权（需一次管理员密码）

    /// sudoers 里命令名的转义：空格、逗号、冒号、等号和通配符都要前置反斜杠。
    static func escapeSudoersPath(_ path: String) -> String {
        let specials = Set<Character>(" \t,:=*?[]\"'\\#~()")
        var out = ""
        out.reserveCapacity(path.count + 4)
        for ch in path {
            if specials.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// 生成规则文本（暴露出来便于自测 / 诊断页展示）
    static func ruleText(exe: String, user: String = NSUserName()) -> String {
        "\(user) ALL=(root) NOPASSWD: \(escapeSudoersPath(exe))\n"
    }

    /// 把本 App 的 CLI 加入 sudoers（NOPASSWD）。
    /// 返回 nil 表示成功；否则是错误描述（用户取消授权返回「已取消授权」）。
    @discardableResult
    static func installAuthorization() -> String? {
        let exe = currentExe
        let rule = ruleText(exe: exe)
        let pid = ProcessInfo.processInfo.processIdentifier
        let src = "/tmp/vela-sudoers-\(pid).rule"
        let scriptPath = "/tmp/vela-sudoers-\(pid).sh"
        do {
            try rule.write(to: URL(fileURLWithPath: src), atomically: true, encoding: .utf8)
        } catch {
            return "写临时规则失败：\(error.localizedDescription)"
        }
        // 落盘前先用 visudo 校验语法：校验不过宁可不装，也不能写坏 /etc/sudoers
        if let bad = visudoCheck(src) {
            try? FileManager.default.removeItem(atPath: src)
            return "规则语法校验未通过（未写入，以免影响其他 sudo）：\(bad)"
        }
        // 用脚本落地，避开 AppleScript 字符串里层层转义的坑。
        // 先写成 .tmp（含「.」的文件 sudo 会忽略），再 mv 到正式名 —— 原子替换，
        // 中间态不会让 sudo 读到半份规则。
        let sh = """
        #!/bin/sh
        set -e
        tmp=/etc/sudoers.d/vela-silent.tmp
        cp '\(src)' "$tmp"
        chown root:wheel "$tmp"
        chmod 0440 "$tmp"
        mv -f "$tmp" /etc/sudoers.d/vela-silent
        rm -f '\(src)'
        """
        do {
            try sh.write(to: URL(fileURLWithPath: scriptPath), atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(atPath: src)
            return "写安装脚本失败：\(error.localizedDescription)"
        }
        let rc = runOsascript("do shell script \"/bin/sh '\(scriptPath)'\" with administrator privileges")
        try? FileManager.default.removeItem(atPath: scriptPath)
        guard rc.ok else {
            try? FileManager.default.removeItem(atPath: src)
            if rc.output.localizedCaseInsensitiveContains("cancel") || rc.output.contains("-128") {
                return "已取消授权"
            }
            return rc.output.isEmpty ? "授权失败" : rc.output
        }
        // 真的用免密通道跑一次，确认规则对「这个路径 + 这个参数」真的放行
        Prefs.set(true, for: authorizedKey)
        Prefs.set(exe, for: exeKey)
        Prefs.set(ruleVersion, for: versionKey)     // 存 Int，别存 String
        if let why = probe() {
            clearAuthorization(keepEnabled: true)
            return why
        }
        return nil
    }

    /// 撤销授权标记（规则文件本身保留，删它需要 root；保留也无害，因为调用方不再走 sudo）
    static func clearAuthorization(keepEnabled: Bool = false) {
        Prefs.set(false, for: authorizedKey)
        Prefs.set(nil, for: exeKey)
        Prefs.set(nil, for: versionKey)
        if !keepEnabled { Prefs.set(false, for: enabledKey) }
    }

    /// 实测免密通道是否真的可用：用 sudo -n 跑一次只读的 `status`。
    /// 返回 nil = 通；否则是失败原因。
    static func probe() -> String? {
        let r = Admin.runSilent(["status"])
        if r.ok { return nil }
        let detail = r.output.isEmpty ? "sudo 返回非零" : r.output
        // sudo 把语法错误直接打到 stderr，原样透出便于定位
        return "免密规则未生效：\(detail)"
    }

    // MARK: 自动下发

    /// 已知预设档位（与 FanControl.order 同源；这里本地存一份，避免触碰 @MainActor 控制器）。
    private static let knownPresets = ["silent", "balanced", "performance"]

    /// 应用当前持久化的功耗墙 + 风扇配置（静默，无密码框）。
    /// 返回 true = 全部成功（或没有需要下发的项）；false = 至少一项失败，可稍后重试。
    ///
    /// 注意并发：本函数跑在后台线程。读状态只读 Prefs / SMCClient（二者都不是 @MainActor），
    /// 不下发时绝不碰控制器；下发成功后才用 `DispatchQueue.main.async { @MainActor in ... }`
    /// 在主线程更新控制器 UI —— 这样 sudo 这种会阻塞 ~1.5s 的动作不卡 UI。
    @discardableResult
    static func applyCurrentConfig() -> Bool {
        guard isEnabled else {
            recordResult(problems: ["未开启「开机自动应用配置」"], applied: 0)
            return false
        }
        guard isAuthorized else {
            recordResult(problems: ["免密规则未生效（设置里关掉再打开可重新授权）"], applied: 0)
            return false
        }

        // 功耗墙：kext 不支持（AFsw 不存在）则跳过；档位与自定义值都从持久化偏好读
        var powerArgs: [String]?
        if (try? SMCClient.shared.keyInfo(PowerLimitSpec.keyWatts)) != nil {
            let profileRaw = Prefs.string(PowerLimitSpec.prefsProfile) ?? "balanced"
            if let profile = PowerProfile(rawValue: profileRaw) {
                if profile == .custom {
                    // 自定义档仍受高级功能解锁门约束（与手动下发一致）
                    if Prefs.bool(PowerLimitSpec.prefsUnlocked),
                       let cw = Int(Prefs.string(PowerLimitSpec.prefsCustom) ?? "") {
                        let w = min(max(cw, PowerLimitSpec.minW), PowerLimitSpec.maxW)
                        powerArgs = ["fan", "power-limit", String(w)]
                    }
                } else if let watts = profile.watts {
                    powerArgs = ["fan", "power-limit", String(watts)]
                }
            }
        }

        // 风扇：上次应用的档位持久化在 "fan.preset"；custom 用 fan.customCurve
        var fanArgs: [String]?
        var fanIsCustom = false
        let last = Prefs.string("fan.preset") ?? "balanced"
        if last == "custom" {
            if let json = Prefs.string("fan.customCurve"),
               let data = json.data(using: .utf8) {
                let path = "/tmp/vela_custom_curve.json"
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
                fanArgs = ["fan", "apply-custom", path]
                fanIsCustom = true
            }
        } else if knownPresets.contains(last) {
            fanArgs = ["fan", "set", last]
        }

        var problems: [String] = []
        var applied = 0

        if let args = powerArgs {
            let r = Admin.runSilent(args)
            if r.ok {
                applied += 1
                DispatchQueue.main.async { @MainActor in
                    PowerLimitController.shared.refreshApplied()
                }
            } else {
                problems.append("功耗墙 \(args.last ?? "") W：\(shortError(r))")
            }
        }
        if let args = fanArgs {
            let r = Admin.runSilent(args)
            if r.ok {
                applied += 1
                DispatchQueue.main.async { @MainActor in
                    if fanIsCustom { FanControl.shared.noteCustomApplied() }
                    else { FanControl.shared.notePresetApplied(last) }
                }
            } else {
                problems.append("风扇 \(last)：\(shortError(r))")
            }
        }

        recordResult(problems: problems, applied: applied)
        return problems.isEmpty
    }

    private static func shortError(_ r: (ok: Bool, output: String)) -> String {
        let t = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "sudo 免密执行失败" }
        // 只留第一行，避免把整段 usage 塞进设置页
        return t.split(separator: "\n").first.map(String.init) ?? t
    }

    private static func recordResult(problems: [String], applied: Int) {
        let text: String
        if !problems.isEmpty {
            text = "失败 · " + problems.joined(separator: "；")
        } else if applied == 0 {
            text = "跳过 · 无可下发项（kext 未就绪或未选档位）"
        } else {
            text = applied >= 2 ? "成功（功耗墙 + 风扇）" : "成功（1 项）"
        }
        Prefs.set(text, for: lastResultKey)
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        Prefs.set(f.string(from: Date()), for: lastAtKey)
    }

    /// 设置页用：显示上次自动下发的结果
    static var lastResultText: String? {
        guard let text = Prefs.string(lastResultKey) else { return nil }
        if let at = Prefs.string(lastAtKey) { return "\(at)  \(text)" }
        return text
    }

    /// 启动时调用：**只在真的需要时**才重装规则（路径变了 / 规则丢了 / 格式过老）。
    /// 修掉了 1.8.5 的毛病 —— 那时只要「已授权」就无条件重装，于是每次登录都弹一次密码框。
    /// 重装成功后立刻补发一次配置，免得这次登录白等。
    static func repairIfNeeded() {
        guard isEnabled else { return }

        // ① 真判据只有一条：`sudo -n` 到底通不通。通就把标记补齐（App 被移动过也能自愈），
        //    不弹任何框；不通再谈重装 —— 老版本吃过「标志位不符就每次登录弹一次」的亏。
        if probe() == nil {
            if !isAuthorized {
                Prefs.set(true, for: authorizedKey)
                Prefs.set(currentExe, for: exeKey)
                Prefs.set(ruleVersion, for: versionKey)
            }
            return
        }

        // ② 通道不通。若当前跑的不是 /Applications 里的正式版本（比如开发时直接跑 build/xxxx），
        //    **绝不重装** —— 否则会把 sudoers 改指到 build 路径，正式 App 反而失去免密
        //    （2.0.1 期间就是这么把自己的授权搞坏的）。只标记失败原因，等用户装正式版再修。
        guard runsFromApplications else {
            recordResult(problems: ["当前不是 /Applications 里的正式版本，未改动免密规则"], applied: 0)
            return
        }

        // ③ 正式版且通道不通 → 重装一次（这一步需要管理员密码）
        _ = installAuthorization()
    }

    /// 当前是否从 /Applications 下的正式安装位置运行
    private static var runsFromApplications: Bool {
        currentExe.hasPrefix("/Applications/")
    }

    /// 兼容旧调用名
    static func repairIfMoved() { repairIfNeeded() }

    // MARK: - 工具

    /// 用 visudo 校验规则文件语法。返回 nil = 通过，否则是错误摘要。
    private static func visudoCheck(_ path: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/visudo")
        p.arguments = ["-c", "-f", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else {
                let out = String(data: data, encoding: .utf8) ?? ""
                return out.split(separator: "\n").first.map(String.init) ?? "visudo 校验失败"
            }
            return nil
        } catch {
            // visudo 不在预期路径（极少见）：宁可放行，也别把功能卡死
            return nil
        }
    }

    private static func runOsascript(_ script: String) -> (ok: Bool, output: String) {
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
}
