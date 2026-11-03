//
//  PowerWallPersist.swift
//  VelaX —— 「重启 / 登录后自动恢复功耗墙」
//
//  为什么需要单独一个 LaunchAgent：
//    RAPL 写的是 CPU 寄存器 0x610，重启后固件会重新编程回标称值（本机 175W），
//    上次设的 30W / 35W 就没了。SMC 那条通道早有 powlimit.sh install 兜底，
//    RAPL 这条没有 —— 但 RAPL **不需要 root**，所以用用户级 LaunchAgent 就够：
//
//      Label            dev.vela.mac.powerwall
//      ProgramArguments AsusControl power replay      ← 瓦数从 Prefs 读，改档不用重写 plist
//      RunAtLoad        true                          ← 登录即执行
//
//    CLI 里的 `power replay` 会重试若干次：登录早期 kext 的 user client 可能还没就绪，
//    一次失败就放弃的话这个功能等于没有。
//
//  和 App 内逻辑的关系：
//    每次成功下发都 noteApplied(瓦数)，恢复默认则 clearTarget()；
//    启动 / 唤醒时 App 自己也会 replay 一次（不依赖 agent 是否装了）。
//

import Foundation

enum PowerWallPersist {

    static let label = "dev.vela.mac.powerwall"

    /// 上次成功下发的瓦数（0 / 缺省 = 没设过，agent 到点直接跳过）
    private static let keyTarget = "power.persistTarget"
    private static let logPath = "/tmp/vela-powerwall.log"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    // MARK: - 目标瓦数

    static var target: Int? {
        let v = Prefs.int(keyTarget, default: 0)
        return v > 0 ? v : nil
    }

    static func noteApplied(_ watts: Int) {
        Prefs.set(watts, for: keyTarget)
    }

    static func clearTarget() {
        Prefs.set(0, for: keyTarget)
    }

    // MARK: - LaunchAgent 开关

    /// 状态以 plist 是否存在为准（与开机自启那套一致）
    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// 返回 nil = 成功，否则是给用户看的错误说明
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        enabled ? install() : remove()
    }

    /// App 改名 / 换位置后，plist 里写死的可执行文件路径会失效 —— 启动时对一遍
    static func repairIfMoved() {
        guard isEnabled,
              let raw = try? String(contentsOf: plistURL, encoding: .utf8) else { return }
        guard !raw.contains(xmlEscape(currentExe)) else { return }
        _ = install()
    }

    private static var currentExe: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    private static func install() -> String? {
        let fm = FileManager.default
        let exe = currentExe
        guard fm.fileExists(atPath: exe) else { return "找不到可执行文件，无法设置登录自动下发" }

        do {
            try fm.createDirectory(at: plistURL.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
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
                <string>\(xmlEscape(exe))</string>
                <string>power</string>
                <string>replay</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
        do {
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "写入登录项失败：\(error.localizedDescription)"
        }
    }

    private static func remove() -> String? {
        try? FileManager.default.removeItem(at: plistURL)
        // 本次登录若已经 load 过就卸掉；失败无妨，plist 已删，下次登录不会再跑
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["bootout", "gui/\(getuid())/\(label)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return nil
    }

    // MARK: - 重放

    /// 把上次下发的瓦数重新写进 MSR 0x610。
    /// - retries: 登录早期 kext 可能还没就绪，多试几次；App 内调用给 1 次即可
    /// - Returns: 实际生效的瓦数；nil = 没下发（没设过 / 通道不符 / 已被硬件锁）
    @discardableResult
    static func replay(retries: Int = 1, gap: TimeInterval = 2.0) -> Int? {
        guard PowerWallProbe.backend == .rapl else { return nil }
        guard let watts = target else { return nil }

        for attempt in 0..<max(1, retries) {
            if let r = RAPLBridge.shared.reading() {
                // 已经在位（比如 App 重启但没重启机器）就不必再写一遍
                if r.pl1Enabled, Int(r.pl1W.rounded()) == watts { return watts }
                if r.locked { return nil }
                switch RAPLBridge.shared.setLimits(pl1: watts, pl2: watts) {
                case .success(let actual):
                    return actual
                case .failure:
                    // 通道暂时读不到就等等再试，其它错误重试也白搭
                    break
                }
            }
            if attempt < retries - 1 { Thread.sleep(forTimeInterval: gap) }
        }
        return nil
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
