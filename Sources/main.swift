//
//  main.swift
//  入口：带非选项参数 → CLI 模式；否则启动图形界面
//

import Foundation

let cliArgs = Array(CommandLine.arguments.dropFirst())

// 界面离屏渲染（自检 / 文档配图），必须在主线程执行
if cliArgs.first == "snapshot" {
    guard cliArgs.count >= 2 else {
        print("ERR 用法: snapshot <输出路径> [宽 高]")
        exit(2)
    }
    var size = CGSize(width: 1000, height: 730)
    if cliArgs.count >= 4, let w = Double(cliArgs[2]), let h = Double(cliArgs[3]) {
        size = CGSize(width: w, height: h)
    }
    var page = Page.overview
    if cliArgs.count >= 5, let p = Page(rawValue: cliArgs[4]) { page = p }
    var ok = false
    if #available(macOS 14.0, *) {
        ok = MainActor.assumeIsolated { Snapshot.render(to: cliArgs[1], size: size, page: page) }
    }
    print(ok ? "OK 已渲染到 \(cliArgs[1])" : "ERR 渲染失败")
    exit(ok ? 0 : 6)
}

if let first = cliArgs.first, !first.hasPrefix("-") {
    exit(CLI.run(cliArgs))
}

// 命令文件模式：`open` 启动时 macOS 不会传 --args（已知限制），
// 所以改用文件传递命令：把命令写进 ~/.asuscontrol-cmd，App 启动后读取、执行并退出。
// 输出写到 ~/.asuscontrol-cli.log
if let cmdFile = CLI.pendingCommandFile, FileManager.default.fileExists(atPath: cmdFile) {
    let raw = (try? String(contentsOfFile: cmdFile, encoding: .utf8)) ?? ""
    try? FileManager.default.removeItem(atPath: cmdFile)
    let args = raw.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        .map(String.init)
    if !args.isEmpty {
        exit(CLI.run(args))
    }
}

AsusControlApp.main()
