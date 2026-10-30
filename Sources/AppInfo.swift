//
//  AppInfo.swift
//  版本 / 作者 / 致谢 —— 关于页与诊断报告共用
//

import Foundation

enum AppInfo {
    static let name = "Vela X"
    static let author = "XelonJangs"
    static let tagline = "macOS 上的华硕笔记本控制中心"

    /// G-Helper（本项目的灵感来源与功能参照）
    static let helperURL = "https://github.com/seerge/g-helper"
    static let helperName = "G-Helper"
    static let helperAuthor = "seerge"

    static let uiInspiration = "ASUS 奥创中心（Armoury Crate）"

    /// 驱动页 / 关于页引用的项目主页
    static let repoURL = "https://github.com/nullmoth/nvidia-macos-driver"

    static var version: String {
        plistValue("CFBundleShortVersionString") ?? fallbackVersion
    }

    static var build: String {
        plistValue("CFBundleVersion") ?? fallbackBuild
    }

    /// CLI 通过符号链接调用时 Bundle.main 拿不到 Info.plist，用编译期常量兜底
    static let fallbackVersion = "1.7.0"
    static let fallbackBuild = "33"

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

    /// 可执行文件的修改时间——比手写日期可靠
    static var buildDate: Date? {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first
        guard let path else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    static var buildDateText: String {
        guard let date = buildDate else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    /// 系统版本，例如 "macOS 15.8.1 (24G90)"
    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var text = "macOS \(v.majorVersion).\(v.minorVersion)"
        if v.patchVersion > 0 { text += ".\(v.patchVersion)" }
        let build = SystemProbe.run("/usr/bin/sw_vers", ["-buildVersion"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !build.isEmpty { text += " (\(build))" }
        return text
    }

    /// 复制到剪贴板 / 诊断报告用的一行
    static var oneLine: String {
        "\(name) \(displayVersion) (build \(build)) · \(osVersion) · by \(author)"
    }
}
