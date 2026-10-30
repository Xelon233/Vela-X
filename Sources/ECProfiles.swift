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
    /// 选中代码与判定出的机型完全一致
    case matched
    /// 选中的不是判定出的机型（用户手动覆盖，或家族近似但不同代码）
    case mismatched
    /// 证据不足，没能认出机型 —— 不拦用户，但要求手动确认机型后再下发曲线
    case undetected
}

// MARK: - 硬件指纹

/// 一台机型「应该长什么样」——判定用的硬件指纹。
///
/// 为什么是这几个维度（踩过坑才定下来的）：
///   · OpenCore 把 SMBIOS 整组换成 Mac（`hw.model` 恒为 MacBookPro16,4），读不到真实 DMI 型号；
///   · 电池上报的 `DeviceName` 是**电池部件号**（魔霸6 / 魔霸7 Plus 都报 `GA50358`），也不能当结论；
///   · G-Helper 在 Windows 读 `Win32_ComputerSystem.Model` 拿到真实型号（如 "G513RM"）再选配置，
///     黑苹果下这串读不到，只能**推断**——而推断维度就用 G-Helper 选配置真正依赖的：
///     **独显档位 + CPU 世代**；
///   · 关键：枪神（G533）和魔霸（G513）**共用同一颗 CPU**（都是 6900HX），差别只在独显档位
///     （魔霸6 = RTX 3060，枪神6 = RTX 3070 Ti / 3080）。所以**独显型号是主判据（闸门）**，
///     CPU 只降到「世代」级别做佐证，绝不能再拿 CPU 后缀当唯一/主判定（否则把枪神认成魔霸）。
public struct ModelFingerprint: Hashable {
    /// 独显名称里应包含的片段（子串包含即可，如 "RTX 3060"）。
    /// **这是判定闸门**：独显不匹配整条 0 分，宁可识别不出也不误判。
    /// 只收本家族「独有」的档位——魔霸6 仅收 RTX 3060（枪神6 没有 3060，
    /// 于是枪神6 不会被误认成魔霸6，而是落到「未识别」这个安全状态）。
    public let gpuHints: [String]
    /// CPU 世代代号前缀（**前缀匹配**而非精确相等）：如 ["6900","6800"] = 6000 系 Rembrandt，
    /// ["7945","7845","7745"] = 7000 系 Dragon Range。只用来佐证世代，不区分 H/HX/HS 后缀。
    public let cpuFamilyCodes: [String]
    /// 出厂电池容量（Wh）区间；只作佐证（主要用来排除幻15 的 76Wh）。nil = 不作数。
    public let batteryWh: ClosedRange<Double>?

    public init(gpuHints: [String],
                cpuFamilyCodes: [String],
                batteryWh: ClosedRange<Double>? = nil) {
        self.gpuHints = gpuHints
        self.cpuFamilyCodes = cpuFamilyCodes
        self.batteryWh = batteryWh
    }
}

/// 某条机型配置对当前硬件的得分
struct ModelScore {
    let profile: ECProfile
    let points: Int
    /// 每条命中项的人话说明（UI / CLI 展示判定依据用）
    let reasons: [String]
}

/// 判定的可信程度
public enum DetectionConfidence: String {
    case high, medium, low, none

    public var label: String {
        switch self {
        case .high: return "高置信度"
        case .medium: return "中等置信度"
        case .low: return "低置信度"
        case .none: return "未能识别"
        }
    }

    /// 可信到「可以拿它质疑用户手动选的机型」吗？
    /// 只有中/高置信度才会触发「机型不匹配」的硬件损坏警告；
    /// 低或无法识别时不拦 —— 没有证据，就不该拿免责声明吓人。
    public var isTrustworthy: Bool { self == .high || self == .medium }
}

/// 一次机型判定的完整结果（含证据，方便用户核对）
public struct ModelDetection {
    let fingerprint: HardwareFingerprint
    /// 命中的候选，按得分降序；空数组 = 一条都没命中
    let scores: [ModelScore]

    var best: ModelScore? { scores.first }

    var confidence: DetectionConfidence {
        guard let p = best?.points else { return .none }
        switch p {
        case 70...: return .high
        case 45..<70: return .medium
        default: return .low
        }
    }

    /// 判定出的机型代码；认不出来时给 "UNKNOWN"
    var code: String { best?.profile.modelCodes.first ?? "UNKNOWN" }
    var name: String {
        ModelCatalog.lookup(code)?.china ?? best?.profile.familyName ?? "未识别机型"
    }
    var source: String { "硬件指纹推断（独显型号 + CPU 世代 + 电池容量）" }

    // 兼容旧的调用点命名
    var detectedCode: String { code }
    var detectedName: String { name }

    /// 一行证据摘要，如 "CPU 6900HX · RTX 3060 · 电池 87Wh"
    var evidenceLine: String {
        var parts: [String] = []
        if !fingerprint.cpuCode.isEmpty { parts.append("CPU \(fingerprint.cpuCode)") }
        if let g = fingerprint.gpus.first { parts.append(ModelDetection.shortGPU(g)) }
        if fingerprint.batteryWh > 0 { parts.append("电池 \(Int(fingerprint.batteryWh.rounded()))Wh") }
        if let s = fingerprint.screen { parts.append("屏 \(s)") }
        return parts.joined(separator: " · ")
    }

    /// "NVIDIA GeForce RTX 3060 Laptop GPU" → "RTX 3060"
    static func shortGPU(_ name: String) -> String {
        let pattern = "(RTX|GTX)\\s*\\d{4}(\\s*(TI|SUPER))?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let r = Range(m.range, in: name) else { return name }
        return String(name[r])
    }
}

/// 机型判定器：采集硬件指纹 → 给每条已知机型配置打分 → 排序取最优
enum ModelDetector {

    /// 权重。独显型号是主判据（闸门，+55）；CPU 世代佐证（+30）；电池容量佐证（+15）。
    /// 顺序很重要：枪神/魔霸同 CPU，差别只在独显，所以独显不过关就整条 0 分。
    static let gpuPoints = 55
    static let cpuPoints = 30
    static let batteryPoints = 15

    static func detect() -> ModelDetection {
        let fp = SystemProbe.fingerprint()
        let scores = ECProfiles.catalog
            .map { score(profile: $0, fingerprint: fp) }
            .filter { $0.points > 0 }
            .sorted { $0.points > $1.points }
        return ModelDetection(fingerprint: fp, scores: scores)
    }

    static func score(profile p: ECProfile, fingerprint fp: HardwareFingerprint) -> ModelScore {
        // 独显型号是「闸门」：枪神/魔霸同 CPU，只有独显档位不同，
        // 所以独显不匹配直接 0 分（宁可不识别，也不把枪神认成魔霸）。
        guard let gpu = fp.gpus.first(where: { name in
            p.fingerprint.gpuHints.contains { name.localizedCaseInsensitiveContains($0) }
        }) else {
            return ModelScore(profile: p, points: 0, reasons: [])
        }

        var points = gpuPoints
        var reasons = ["显卡 \(ModelDetection.shortGPU(gpu)) 命中（+\(gpuPoints)）"]

        // 独显过关后，CPU 世代只做佐证（前缀匹配，不区分 H/HX/HS 后缀）
        let cpu = fp.cpuCode.uppercased()
        if !cpu.isEmpty, p.fingerprint.cpuFamilyCodes.contains(where: { cpu.hasPrefix($0.uppercased()) }) {
            points += cpuPoints
            reasons.append("CPU \(cpu) 属 \(p.fingerprint.cpuFamilyCodes.joined(separator: "/")) 世代（+\(cpuPoints)）")
        }

        // 电池容量只作佐证（主要用来排除幻15 的 76Wh）：独显已匹配，
        // 容量对不上只少加分，不会因此翻成别的机型。
        if let range = p.fingerprint.batteryWh, fp.batteryWh > 0, range.contains(fp.batteryWh) {
            points += batteryPoints
            reasons.append("电池 \(Int(fp.batteryWh.rounded()))Wh 在 \(Int(range.lowerBound))–\(Int(range.upperBound))Wh（+\(batteryPoints)）")
        }

        return ModelScore(profile: p, points: points, reasons: reasons)
    }
}

/// 这套 EC 配置的可信程度。
///
/// 区分它是必要的：「机型代码能对上」和「曲线在这台机器上真的跑过」是两回事。
/// 前者只说明 EC 布局一致，后者才说明写进去的曲线确实让风扇转起来了。
public enum CurveVerification: String {
    /// 已在本机型实机下发过，转速/温度响应符合预期
    case verifiedOnDevice
    /// 逆向得到的布局 + 沿用同族机型的曲线，但**没在这台机器上实机跑过**
    case reverseEngineered

    /// 状态行短标签
    public var label: String {
        switch self {
        case .verifiedOnDevice: return "实机已验证"
        case .reverseEngineered: return "逆向未实机验证"
        }
    }

    /// 首次使用时的额外提醒（未验证的机型才会返回非 nil）
    public var caveat: String? {
        switch self {
        case .verifiedOnDevice:
            return nil
        case .reverseEngineered:
            return """
                这套曲线来自逆向分析，尚未在本机型实机验证过。\
                首次上机请先做只读验证：确认能读到转速、且转速随负载变化，\
                再下发曲线并观察转速是否真的响应、温度是否真的下降。\
                EC 不回显写入结果，判断是否生效只能看转速。
                """
        }
    }
}

/// 一台机型的 EC 配置（逆向产物）。风扇曲线、邮箱寄存器、MMIO 地址、曲线格式都随机型不同。
public struct ECProfile: Identifiable, Hashable {
    public var id: String { familyName }

    /// 覆盖的机型代码。第一个是**判定用的规范代码**（如 "G513RM"、"G713PV"）。
    ///
    /// 这里不再收录 GA50358 之类的电池部件号：它来自电池固件，
    /// 同一块电池装在多款机器上，实测魔霸6 与魔霸7 Plus 都报它，拿它当机型会认错。
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
    /// 这套配置的可信程度：实机验证过，还是仅逆向得到
    public let verification: CurveVerification
    /// 这台机器「应该长什么样」——判定机型时用它给硬件指纹打分
    public let fingerprint: ModelFingerprint

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

/// 当前判定出的机型 + 用户可覆盖的选择。
public struct MachineModel {
    public let detectedCode: String
    /// 判定依据说明
    public let source: String

    /// 判定机型（黑苹果下为「推断」，非读取 DMI）：以硬件指纹为准 ——
    /// 独显型号为主判据（闸门），CPU 世代与电池容量佐证。
    /// 不再拿电池 DeviceName 当结论：它是电池部件号，多机型共用，
    /// 实测魔霸6（G513RM）和魔霸7 Plus（G713PV）都报 GA50358。
    public static func detect() -> MachineModel {
        let d = ModelDetector.detect()
        return MachineModel(detectedCode: d.detectedCode, source: d.source)
    }

    public var detectedName: String {
        ModelCatalog.lookup(detectedCode)?.china ?? detectedCode
    }

    /// 旧版本把电池 DeviceName（GA50358 之类）当成机型代码写进过偏好。
    /// 判断某个代码是否就是这种「伪机型」，用于启动时把它清掉，
    /// 免得升级后平白弹出「机型不匹配」的红色警告。
    public static func isLegacyBatteryCode(_ code: String) -> Bool {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !c.isEmpty else { return false }
        guard let name = SystemProbe.ioregString("AppleSmartBattery", "DeviceName") else { return false }
        return name.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == c.uppercased()
    }
}

/// 已知机型 → EC 配置表。新增机型时在这里加一条即可。
public enum ECProfiles {

    public static let catalog: [ECProfile] = [
        ECProfile(
            // 只收 G513（魔霸6 / 枪神6 2022）本体：
            // 电池部件号 GA50358 之类不再当机型代码用，理由见 modelCodes 的注释。
            modelCodes: ["G513RM", "G513RS", "G513RW", "G513"],
            familyPrefixes: ["G513"],
            familyName: "ROG Strix G15 / 魔霸6 (2022)",
            ecChip: "ITE IT5571",
            ecFirmware: "TI5825_G513_1027",
            curvePoints: 8, tempMin: 20, tempMax: 110, dutyMin: 0, dutyMax: 100,
            mmio: ["it55": "0xFE700600", "mb00": "0xFE700B00", "mc00": "0xFE700C00"],
            note: "SMCAsusFan v9-curvewrite 逆向，8 点曲线",
            source: "内置（SMCAsusFan 交付包 v14）",
            verification: .verifiedOnDevice,
            fingerprint: ModelFingerprint(
                // 独显闸门：魔霸6 基础款是 RTX 3060，只收它 ——
                // 枪神6 用 RTX 3070 Ti / 3080，没有 3060，于是枪神6 不会误认成魔霸6。
                //（同族的 G513RW/RX 用 3070 Ti / 3080，本目录没收它们的 EC 配置，
                //  会落到「未识别」而非被当成 3060 款放行。）
                gpuHints: ["RTX 3060"],
                // CPU 世代佐证（前缀匹配）：2022 Rembrandt 6000 系
                cpuFamilyCodes: ["6900", "6800"],
                batteryWh: 80...96
            )
        ),
        ECProfile(
            // 注意 familyPrefixes 收窄成 "G713P" 而不是 "G713"：
            // 写 "G713" 会把魔霸6 Plus（G713RW / G713RS，2022）也吸进这套配置，
            // 但那批机器的曲线没验证过。收窄后 6 Plus 会落到 MatchLevel.unknown
            // （没有 EC 配置），而不是被当成「兼容」放行 —— 宁可不给，也不给错的。
            modelCodes: ["G713PV", "G713PI", "G713PY", "G713P"],
            familyPrefixes: ["G713P"],
            familyName: "ROG Strix G17 / 魔霸7 Plus (2023)",
            ecChip: "ITE IT5571",
            ecFirmware: "ITE EC-V14.6",
            curvePoints: 8, tempMin: 20, tempMax: 110, dutyMin: 0, dutyMax: 100,
            mmio: ["it55": "0xFE700600", "mb00": "0xFE700B00", "mc00": "0xFE700C00"],
            note: """
                G713PV 逆向（ACPI 46 表反编译 + BIOS 剥离 EC 双重核对）：
                tach CPU=IT55+0x02(FA1L) / GPU=IT55+0x24(FA2L)；FANM=MB00+0xF9；
                曲线邮箱=MC00 0x58(选风扇)/0x5C/0x60/0x64/0x68/0x6C/0x7C/0x7D；
                WMI devid：曲线 0x00110024(CPU)/0x00110025(GPU)、
                转速 0x00110013/14、限速 0x00110026/27。
                布局与 G513RM 逐项一致。
                三档曲线沿用 G513RM 实测值，尚未在魔霸7 Plus 实机验证 ——
                首次使用请先做只读验证（能读转速且随负载变化）再下发。
                """,
            source: "内置（G713PV 逆向包 v10-ecprobe）",
            verification: .reverseEngineered,
            fingerprint: ModelFingerprint(
                // 独显闸门：魔霸7 Plus 是 RTX 4060 / 4070（40 系），与魔霸6 的 30 系一眼可分
                gpuHints: ["RTX 4060", "RTX 4070"],
                // CPU 世代佐证（前缀匹配）：2023 Dragon Range 7000 系
                cpuFamilyCodes: ["7945", "7845", "7745"],
                batteryWh: 80...96
            )
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
    public static let titleUndetected = "⚠️ 机型未经自动识别确认"

    /// 生成完整声明文本（selected / detected 由调用方填入）
    public static func body(selected: String, detected: String) -> String {
        """
        你选择的机型「\(selected)」与本机判定出的机型「\(detected)」不一致。

        判定依据是硬件指纹（独显型号 + CPU 世代 + 电池容量），不是 SMBIOS —— \
        黑苹果下 SMBIOS 已被 OpenCore 换成 Mac，读不到真实机型（Windows 上 G-Helper 读 \
        Win32_ComputerSystem.Model 能拿到真实型号，这里读不到，只能按硬件推断）。

        风扇曲线和 EC 配置是针对特定机型逆向得到的。如果机型不对，写入的曲线可能让风扇停转或全速狂转，\
        导致过热、降频，甚至永久性硬件损坏（EC 不会回显写入结果，出错时无法自动恢复）。

        继续即表示你确认所选机型与电脑完全一致，并自愿承担由此产生的所有风险。
        """
    }

    /// 没能自动认出机型时的声明文本
    public static func bodyUndetected(selected: String) -> String {
        """
        本机硬件指纹没能匹配到任何已收录机型，所以无法自动核对你的选择「\(selected)」。

        风扇曲线和 EC 配置是针对特定机型逆向得到的。机型不对，写入的曲线可能让风扇停转或全速狂转，\
        导致过热、降频，甚至永久性硬件损坏（EC 不会回显写入结果，出错时无法自动恢复）。

        请确认所选机型代码与机身底部 / 包装箱上的型号完全一致，再继续。
        """
    }

    /// 一句话版（给状态行/CLI 用）
    public static func short(selected: String, detected: String) -> String {
        "机型「\(selected)」≠ 判定出的「\(detected)」：EC 配置可能不适用，写入有误会损坏硬件。"
    }

    public static func shortUndetected(selected: String) -> String {
        "未能自动识别机型，「\(selected)」无法核对：EC 配置可能不适用，写入有误会损坏硬件。"
    }
}
