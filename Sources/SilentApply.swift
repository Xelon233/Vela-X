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
//  安全权衡：sudoers 规则把整个 CLI 二进制授权为免密 root。本机是自签证书（SMJobBless
//  走不通），这是最轻量且可行的静默方案；规则限定到 Bundle 内当前可执行文件路径，
//  且文件权限锁成 0440 + root:wheel（sudoers 要求，否则整份失效）。App 被移动后路径失效，
//  repairIfMoved() 会重写规则。
//

import Foundation
import AppKit

enum SilentApply {
    /// 用户开关（设置页「开机自动应用配置」）
    static let enabledKey = "silent.applyEnabled"
    /// 是否已成功安装 sudoers 免密规则
    static let authorizedKey = "silent.applyAuthorized"
    /// sudoers drop-in 规则文件
    static let rulePath = "/etc/sudoers.d/vela-silent"

    // MARK: 状态

    static var isEnabled: Bool { Prefs.bool(enabledKey) }

    /// 已授权 = 开关标记为已装，且规则文件确实还在（被删 / App 移动后路径失效都算未授权）
    static var isAuthorized: Bool {
        Prefs.bool(authorizedKey) && FileManager.default.fileExists(atPath: rulePath)
    }

    // MARK: 一键授权（需一次管理员密码）

    /// 把本 App 的 CLI 加入 sudoers（NOPASSWD）。
    /// 返回 nil 表示成功；否则是错误描述（用户取消授权返回「已取消授权」）。
    @discardableResult
    static func installAuthorization() -> String? {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let user = NSUserName()
        // 路径带空格时 sudoers 要求引号；命令限定到本可执行文件（不开放任意参数）
        let rule = "\(user) ALL=(root) NOPASSWD: \"\(exe)\"\n"
        let tmp = "/tmp/vela-sudoers-\(ProcessInfo.processInfo.processIdentifier).tmp"
        do {
            try rule.write(to: URL(fileURLWithPath: tmp), atomically: true, encoding: .utf8)
        } catch {
            return "写临时规则失败：\(error.localizedDescription)"
        }
        // 以 root 落规则并锁权限（sudoers 要求 0440 + root:wheel，否则整份被忽略 → 全部 sudo 失效）
        let script = "do shell script \"mkdir -p /etc/sudoers.d && cp '\(tmp)' '\(rulePath)' && chown root:wheel '\(rulePath)' && chmod 0440 '\(rulePath)' && rm -f '\(tmp)'\" with administrator privileges"
        let rc = runOsascript(script)
        if rc.ok {
            Prefs.set(true, for: authorizedKey)
            return nil
        }
        if rc.output.localizedCaseInsensitiveContains("cancel") || rc.output.contains("-128") {
            return "已取消授权"
        }
        return rc.output.isEmpty ? "授权失败" : rc.output
    }

    // MARK: 自动下发

    /// 应用当前持久化的功耗墙 + 风扇配置（静默，无密码框）。
    /// 在启动和唤醒时调用；未启用 / 未授权 / kext 不支持时直接跳过，不报错、不弹框。
    static func applyCurrentConfig() {
        guard isEnabled, isAuthorized else { return }
        applyPower()
        applyFan()
    }

    private static func applyPower() {
        // 功耗墙通道：AFsw 键存在才算 kext 支持
        guard (try? SMCClient.shared.keyInfo(PowerLimitSpec.keyWatts)) != nil else { return }
        let profileRaw = Prefs.string(PowerLimitSpec.prefsProfile) ?? "balanced"
        guard let profile = PowerProfile(rawValue: profileRaw) else { return }
        let w: Int
        if profile == .custom {
            // 自定义档仍受高级功能解锁门约束（与手动下发一致）
            guard Prefs.bool(PowerLimitSpec.prefsUnlocked) else { return }
            let cw = Int(Prefs.string(PowerLimitSpec.prefsCustom) ?? "") ?? 30
            w = min(max(cw, PowerLimitSpec.minW), PowerLimitSpec.maxW)
        } else {
            w = profile.watts ?? 30
        }
        let r = Admin.runSilent(["fan", "power-limit", String(w)])
        if r.ok {
            // 回读 SMC 更新 UI 上的「已限 NW」（打开功耗墙页时也会再刷一次）
            DispatchQueue.main.async { PowerLimitController.shared.refreshApplied() }
        }
    }

    private static func applyFan() {
        let last = Prefs.string(FanControl.shared.presetKeyName) ?? "balanced"
        if last == "custom" {
            guard let json = Prefs.string("fan.customCurve"),
                  let data = json.data(using: .utf8) else { return }
            let path = "/tmp/vela_custom_curve.json"
            do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) } catch { return }
            let r = Admin.runSilent(["fan", "apply-custom", path])
            if r.ok { DispatchQueue.main.async { FanControl.shared.noteCustomApplied() } }
        } else {
            // 自定义解锁门只约束「自定义」档；预设档随时可用，但必须是已知档位
            guard FanControl.order.contains(last) else { return }
            let r = Admin.runSilent(["fan", "set", last])
            if r.ok { DispatchQueue.main.async { FanControl.shared.notePresetApplied(last) } }
        }
    }

    /// App 移动 / 改名后 sudoers 路径失效：已授权则重写规则（需一次管理员密码）。
    static func repairIfMoved() {
        guard isAuthorized else { return }
        _ = installAuthorization()
    }

    // MARK: - 工具

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
