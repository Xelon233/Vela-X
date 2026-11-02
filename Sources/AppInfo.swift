//
//  AppInfo.swift
//  版本 / 作者 / 致谢 —— 关于页与诊断报告共用
//

import Foundation

enum AppInfo {
    static let name = "Vela X"
    static let author = "Xelon Jangs"
    static let githubURL = "https://github.com/Xelon233"
    static let githubDisplay = "github.com/Xelon233"
    static let tagline = "macOS 上的华硕笔记本控制中心"

    /// G-Helper（本项目的灵感来源与功能参照）
    static let helperURL = "https://github.com/seerge/g-helper"
    static let helperName = "G-Helper"
    static let helperAuthor = "seerge"

    static let uiInspiration = "ASUS 奥创中心（Armoury Crate）"

    /// 驱动页 / 关于页引用的项目主页
    static let repoURL = "https://github.com/nullmoth/nvidia-macos-driver"

    // 同样是「每次访问都查一遍」的老写法，改成缓存（版本号运行期不会变）
    static let version: String = plistValue("CFBundleShortVersionString") ?? fallbackVersion

    static let build: String = plistValue("CFBundleVersion") ?? fallbackBuild

    /// CLI 通过符号链接调用时 Bundle.main 拿不到 Info.plist，用编译期常量兜底
    static let fallbackVersion = "2.4.9"
    static let fallbackBuild = "87"

    /// 先问 Bundle，再沿可执行文件路径找 Info.plist（build/asuscontrol 符号链接场景）
    static func plistValue(_ key: String) -> String? {
        if let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, !v.isEmpty {
            return v
        }
        guard let exe = Bundle.main.executablePath ?? CommandLine.arguments.first else { return nil }
        let dir = URL(fileURLWithPath: exe).deletingLastPathComponent()
        let candidates = ["Info.plist", "../Info.plist", "../../Info.plist",
                          "../Resources/Info.plist", "../../Resources/Info.plist"]
        for name in candidates {
            let url = dir.appendingPathComponent(name).standardizedFileURL
            guard let dict = NSDictionary(contentsOf: url) else { continue }
            if let v = dict[key] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    static var displayVersion: String {
        let v = version
        return v.hasPrefix("v") ? v : "v" + v
    }

    /// 可执行文件的修改时间——比手写日期可靠。**只算一次**（读文件属性是 I/O）
    static let buildDate: Date? = {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first
        guard let path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }()

    static let buildDateText: String = {
        guard let date = buildDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }()

    /// 系统版本，例如 "macOS 15.8.1 (24G90)"
    ///
    /// ⚠️ **绝不能 spawn 子进程**（这里曾经 `fork` 一个 `/usr/bin/sw_vers`）。
    /// 两个连环坑：
    /// 1. 写成 `static var` 时，视图每次重算都 spawn 一次（十几毫秒），
    ///    慢到触发下一轮布局 → `AttributeGraph: cycle detected` 依赖环；
    /// 2. 改成 `static let` 后更糟：`Process.waitUntilExit()` 会在主线程**跑 runloop**，
    ///    于是求值过程中又进了一次 SwiftUI 显示周期 → 再次读 `osVersion` →
    ///    `dispatch_once` 递归加锁 → `BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively`
    ///    → `EXC_BAD_INSTRUCTION`（打开「关于」页直接崩）。
    ///
    /// 现在用 `sysctlbyname("kern.osversion")`：它**就是** `sw_vers -buildVersion` 的值，
    /// 只是一次内核查询 —— 零进程、不进 runloop、可安全地在 `body` 里求值。
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { text += ".\(v.patchVersion)" }
        if let build = SystemProbe.sysctlString("kern.osversion"), !build.isEmpty {
            text += " (\(build))"
        }
        return text
    }()

    /// 复制到剪贴板 / 诊断报告用的一行
    static var oneLine: String {
        "\(name) \(displayVersion) (build \(build)) · \(osVersion) · by \(author)"
    }
}
