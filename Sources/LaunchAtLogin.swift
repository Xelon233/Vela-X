//
//  LaunchAtLogin.swift
//  开机自启
//
//  为什么不用 SMAppService.mainApp（macOS 13 起官方推荐）：
//  那套 API 要求应用被正式签名（Developer ID / 公证）并且由 LaunchServices 正常注册，
//  本项目是本地自签证书 + 直接拷进 /Applications，register() 会返回
//  “Operation not permitted”（Error Code=1），而且不给任何可操作的原因。
//
//  LaunchAgent 不挑签名，也不需要在「系统设置 → 登录项」里额外批准，行为可预期：
//    · 打开：写 ~/Library/LaunchAgents/dev.asuscontrol.mac.autostart.plist
//    · 关闭：删掉它，并顺手 bootout（这次登录已经 load 过的情形）
//  本次不 bootstrap —— RunAtLoad 会让 launchd 立刻再拉起一份实例，
//  变成开两个 App。写到磁盘、下次登录生效才是想要的行为。
//

import Foundation

enum LaunchAtLogin {
    static let label = "dev.vela.mac.autostart"
    /// 更名前的 label（AsusControl / ROG X 时期）。启动时迁移一次，否则旧 agent
    /// 会一直指向一个已经不存在的 app 包，登录时静默失败。
    private static let legacyLabel = "dev.asuscontrol.mac.autostart"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    private static var legacyPlistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(legacyLabel).plist")
    }

    /// 开关状态以 plist 是否存在为准（勾上就写、取消就删）
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 本次启动是否由开机自启拉起 —— 用来决定不弹主窗口
    static var isAutostartLaunch: Bool {
        CommandLine.arguments.contains("--autostart")
    }

    /// 返回 nil 表示成功，否则是给用户看的错误说明
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        enabled ? enable() : disable()
    }

    /// App 改名 / 挪位置之后，旧 plist 里的 `-a <路径>` 会指向一个不存在的包，
    /// 开机时就静默失效。启动时对一遍：开关是开的但路径不对，就按当前位置重写。
    static func repairIfMoved() {
        guard isEnabled,
              let raw = try? String(contentsOf: plistURL, encoding: .utf8) else { return }
        let current = Bundle.main.bundlePath
        // 用最小代价判断：当前 bundle 路径已经写进 plist 就不用动
        guard !raw.contains(xmlEscape(current)) else { return }
        _ = enable()
    }

    /// 更名时换过 label：把旧 plist 迁到新 label 下（保留用户的「开着」状态），
    /// 再 bootout 旧的 agent，避免它还挂在 launchd 里每次登录去开一个空路径。
    static func migrateLegacyLabel() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyPlistURL.path) else { return }
        let wasEnabled = true
        try? fm.removeItem(at: legacyPlistURL)
        if wasEnabled { _ = enable() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(legacyLabel)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private static func enable() -> String? {
        let fm = FileManager.default
        let bundle = Bundle.main.bundlePath
        // 走 open 而不是直接指可执行文件：LaunchServices 负责激活与单实例，
        // -g 表示不要在登录时抢焦点
        guard fm.fileExists(atPath: bundle) else {
            return "找不到应用包，无法设置开机自启"
        }

        let dir = plistURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return "无法创建 LaunchAgents 目录：\(error.localizedDescription)"
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-g</string>
                <string>-a</string>
                <string>\(xmlEscape(bundle))</string>
                <string>--args</string>
                <string>--autostart</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>LimitLoadToSessionType</key>
            <string>Aqua</string>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "写入启动项失败：\(error.localizedDescription)"
        }
    }

    private static func disable() -> String? {
        try? FileManager.default.removeItem(at: plistURL)
        // 这次登录若已经 load 过，顺手卸掉；失败也无所谓 —— plist 没了，下次登录就不会再启动
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return nil
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
