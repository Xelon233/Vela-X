//
//  ECProfiles.swift
//  VelaX —— 机型识别 + 每机型的 EC 配置
//
//  为什么需要它：
//    不同华硕机型的 EC（嵌入式控制器）配置不一样 —— 风扇曲线的点数/温区、
//    邮箱寄存器、MMIO 地址、曲线格式都随机型而变。同一套曲线套到错误机型上，
//    可能让风扇停转或狂转，造成过热甚至硬件损坏。所以程序必须：
//      1) 识别出真实机型（OpenCore 会覆盖 SMBIOS，得走 EC/电池上报的代码）
//      2) 让用户能手动选择机型（按型号名），但强制先确认「机型不匹配」的风险
//      3) 按所选机型加载对应的 EC 配置（曲线文件 + 校验边界）
//
//  新增机型：在 ECProfiles.catalog 里加一条，曲线放到
//  Resources/fan_presets-<MODEL>.json 即可，无需改其它代码。
//

import Foundation

/// 匹配级别：检测到的机型 vs 选中的机型
public enum ModelMatch: String {
    /// 选中代码与检测到的硬件代码完全一致
    case matched
    /// 选中的不是检测到的硬件（用户手动覆盖，或家族近似但不同代码）
    case mismatched
}

/// 一台机型的 EC 配置（逆向产物）。风扇曲线、邮箱寄存器、MMIO 地址、曲线格式都随机型不同。
public struct ECProfile: Identifiable, Hashable {
    public var id: String { familyName }

    /// 覆盖的机型代码（EC/电池 DeviceName 上报的形式，如 "G513RM"、"GA50358"）
    public let modelCodes: [String]
    /// 家族前缀（用于「兼容」匹配，如 "G513"、"GA503"）
    public let familyPrefixes: [String]
    /// 显示用型号族名
    public let familyName: String
    public let ecChip: String
    public let ecFirmware: String
    /// 每条曲线的温度/占空比断点数量
    public let curvePoints: Int
    public let tempMin, tempMax: Int
    public let dutyMin, dutyMax: Int
    public let mmio: [String: String]
    public let note: String
    public let source: String

    public func matches(_ code: String) -> MatchLevel {
        let c = code.uppercased()
        if modelCodes.contains(where: { $0.uppercased() == c }) { return .verified }
        if familyPrefixes.contains(where: { c.hasPrefix($0.uppercased()) || $0.uppercased().hasPrefix(c) }) {
            return .compatible
        }
        return .unknown
    }
}

/// 已知 EC 配置与检测到的机型的匹配程度
public enum MatchLevel: String {
    /// 精确命中某条已收录机型
    case verified
    /// 落在同一 EC 家族（曲线大概率适用，但未经本机验证）
    case compatible
    /// 不在目录里，没有对应的 EC 配置
    case unknown
}

/// 当前检测到的机型 + 用户可覆盖的选择。
public struct MachineModel {
    /// 从 EC/电池 DeviceName 读到的真实型号代码
    /// （OpenCore 的 SMBIOS 覆盖会隐藏真实 DMI，所以这条最可靠）
    public let detectedCode: String
    /// 检测来源说明
    public let source: String

    public static func detect() -> MachineModel {
        if let name = SystemProbe.ioregString("AppleSmartBattery", "DeviceName"), !name.isEmpty {
            return MachineModel(detectedCode: name, source: "EC/电池 DeviceName")
        }
        return MachineModel(detectedCode: SystemProbe.sysctlString("hw.model") ?? "ASUS",
                            source: "sysctl hw.model（SMBIOS，可能被 OpenCore 覆盖）")
    }

    public var detectedName: String {
        ModelCatalog.lookup(detectedCode)?.china ?? detectedCode
    }
}

/// 已知机型 → EC 配置表。新增机型时在这里加一条即可。
public enum ECProfiles {

    public static let catalog: [ECProfile] = [
        ECProfile(
            modelCodes: ["G513RM", "G513", "GA50358", "GA503Q", "GA503"],
            familyPrefixes: ["G513", "GA503"],
            familyName: "ROG Strix G15 / Zephyrus G15 (2022)",
            ecChip: "ITE IT5571",
            ecFirmware: "TI5825_G513_1027",
            curvePoints: 8, tempMin: 20, tempMax: 110, dutyMin: 0, dutyMax: 100,
            mmio: ["it55": "0xFE700600", "mb00": "0xFE700B00", "mc00": "0xFE700C00"],
            note: "SMCAsusFan v9-curvewrite 逆向，8 点曲线",
            source: "内置（SMCAsusFan 交付包 v14）"
        )
    ]

    /// 按机型代码匹配已知 EC 配置
    public static func match(_ code: String) -> (profile: ECProfile?, level: MatchLevel) {
        for p in catalog {
            let l = p.matches(code)
            if l != .unknown { return (p, l) }
        }
        return (nil, .unknown)
    }
}

/// 机型不匹配的免责声明（GUI 弹窗与 CLI 共用同一段文案）
public enum ModelDisclaimer {
    public static let title = "⚠️ 机型不匹配：硬件损坏风险"

    /// 生成完整声明文本（selected / detected 由调用方填入）
    public static func body(selected: String, detected: String) -> String {
        """
        你选择的机型「\(selected)」与检测到的硬件「\(detected)」不一致。

        风扇曲线和 EC 配置是针对特定机型逆向得到的。如果机型不对，写入的曲线可能让风扇停转或全速狂转，\
        导致过热、降频，甚至永久性硬件损坏（EC 不会回显写入结果，出错时无法自动恢复）。

        继续即表示你确认所选机型与电脑完全一致，并自愿承担由此产生的所有风险。
        """
    }

    /// 一句话版（给状态行/CLI 用）
    public static func short(selected: String, detected: String) -> String {
        "机型「\(selected)」≠ 检测到的「\(detected)」：EC 配置可能不适用，写入有误会损坏硬件。"
    }
}
