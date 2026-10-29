//
//  ModelCatalog.swift
//  型号代码 → 零售商品名
//
//  背景：黑苹果用 OpenCore 覆盖了 SMBIOS，macOS 里读不到真实的 DMI 机型。
//  唯一还能拿到的型号线索是 EC/电池上报的 DeviceName（例如 "GA50358"），
//  它并不总是等于零售名，所以这里做两层：
//    1) 按代码前缀匹配下面这张表
//    2) 允许用户手动改名（写进 UserDefaults，优先级最高）
//
//  命名依据：ROG 中国官网 / ASUS 全球站的系列页，2026-10 核对。
//

import Foundation

struct ASUSModel: Identifiable, Hashable {
    var id: String { code }
    let code: String       // 型号代码前缀
    let china: String      // 国内零售名
    let global: String     // 海外名
    let note: String       // 年份 / 定位

    var display: String {
        note.isEmpty ? china : "\(china)（\(note)）"
    }
}

enum ModelCatalog {

    static let all: [ASUSModel] = [
        // ROG 魔霸 / 枪神（Strix 系列）
        ASUSModel(code: "G513", china: "ROG 魔霸6", global: "ROG Strix G15", note: "2022"),
        ASUSModel(code: "G713", china: "ROG 魔霸6 Plus", global: "ROG Strix G17", note: "2022"),
        ASUSModel(code: "G533", china: "ROG 枪神6", global: "ROG Strix SCAR 15", note: "2022"),
        ASUSModel(code: "G733", china: "ROG 枪神6 Plus", global: "ROG Strix SCAR 17", note: "2022"),
        ASUSModel(code: "G614", china: "ROG 枪神8", global: "ROG Strix G16", note: "2024"),
        ASUSModel(code: "G634", china: "ROG 枪神8 Plus", global: "ROG Strix G18", note: "2024"),

        // ROG 幻（Zephyrus 系列）
        ASUSModel(code: "GA503", china: "ROG 幻15", global: "ROG Zephyrus G15", note: "2022"),
        ASUSModel(code: "GA502", china: "ROG 幻15", global: "ROG Zephyrus G15", note: "2020"),
        ASUSModel(code: "GA402", china: "ROG 幻14", global: "ROG Zephyrus G14", note: "2022"),
        ASUSModel(code: "GA401", china: "ROG 幻14", global: "ROG Zephyrus G14", note: "2020/2021"),
        ASUSModel(code: "GU603", china: "ROG 幻16", global: "ROG Zephyrus M16", note: "2022"),
        ASUSModel(code: "GV301", china: "ROG 幻13", global: "ROG Flow X13", note: ""),
        ASUSModel(code: "GV601", china: "ROG 幻16 翻转版", global: "ROG Flow X16", note: ""),
        ASUSModel(code: "GX650", china: "ROG 冰刃6 双屏", global: "ROG Zephyrus Duo 16", note: "2022"),
        ASUSModel(code: "GX703", china: "ROG 冰刃5 双屏", global: "ROG Zephyrus Duo 15", note: "2021"),

        // 天选（TUF）
        ASUSModel(code: "FA507", china: "天选3", global: "TUF Gaming A15", note: "2022"),
        ASUSModel(code: "FX507", china: "天选3", global: "TUF Gaming F15", note: "2022"),
        ASUSModel(code: "FA617", china: "天选4R", global: "TUF Gaming A16", note: "2023"),
        ASUSModel(code: "FA506", china: "天选", global: "TUF Gaming A15", note: "2020/2021"),
        ASUSModel(code: "FX506", china: "天选", global: "TUF Gaming F15", note: "2020/2021"),

        // 轻薄本
        ASUSModel(code: "UX", china: "灵耀 ZenBook", global: "ZenBook", note: ""),
        ASUSModel(code: "UM", china: "灵耀 ZenBook", global: "ZenBook", note: ""),
        ASUSModel(code: "X", china: "无畏 VivoBook", global: "VivoBook", note: "")
    ]

    /// 最长前缀匹配（避免 "G" 这类过短前缀误命中）
    static func lookup(_ code: String) -> ASUSModel? {
        let upper = code.uppercased()
        guard upper.count >= 3 else { return nil }
        return all
            .filter { upper.hasPrefix($0.code.uppercased()) }
            .max { $0.code.count < $1.code.count }
    }

    /// 手动改名用的存储键
    static let overrideKey = "model.overrideName"
    static let overrideGlobalKey = "model.overrideGlobal"
}
