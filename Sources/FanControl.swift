//
//  FanControl.swift
//  风扇档位 / 曲线的状态中枢
//
//  数据来源：SMCAsusFan.kext 暴露的 SMC 键（AFMd 版本号、AFMf 选风扇、AFW1..4 曲线参数、AFWg 提交），
//  以及 F0Ac / F1Ac 两个转速键。
//
//  机型识别：
//    不同机型的 EC 配置不同，所以先用硬件指纹（CPU 代号 + 独显 + 电池 + 屏幕）判定机型
//    （ModelDetector.detect，见 ECProfiles.swift），再按机主选择的机型加载对应曲线。
//    机主可以手动选机型（按型号名），但所选机型与判定结果不一致、或压根没认出机型时，
//    写曲线前必须先确认「硬件损坏风险」免责声明。
//
//  权限边界：
//    · 读转速、判断 kext 是否在跑 —— 普通用户即可（本页每 2 秒刷一次）
//    · 下发曲线要写 SMC 键 —— 必须 root，走 Admin 提权执行本程序自己的 CLI：
//        vela fan set <silent|balanced|performance>
//      这样提权只发生在用户点「应用」的那一下，而不是整个 App 常驻 root。
//
//  注意：EC 不会回显我们写进去的曲线（预设槽位保持不变），
//  所以「是否生效」只能看转速变化，不能靠回读判断。
//

import Foundation
import Combine

@MainActor
final class FanControl: ObservableObject {
    static let shared = FanControl()

    /// 界面上的固定顺序（json 里是字典，顺序不可靠）
    static let order = ["silent", "balanced", "performance"]

    // MARK: 机型

    /// 判定出的机型（硬件指纹：CPU 代号 + 独显 + 电池 + 屏幕），含证据与置信度。
    ///
    /// 早先这里读的是电池 DeviceName，结果魔霸6 和魔霸7 Plus 都被认成 GA50358
    /// —— 那是电池部件号，多机型共用，不能当机型用。
    let detection = ModelDetector.detect()

    /// 机主选择的机型代码（默认 = 判定的；可手动覆盖）
    @Published private(set) var selectedCode: String
    /// 匹配状态
    var status: ModelMatch {
        // 证据不足（没认出机型）时，没有依据去质疑机主手动选的机型
        guard detection.confidence.isTrustworthy else { return .undetected }
        return selectedCode.trimmingCharacters(in: .whitespaces).uppercased()
            == detection.code.trimmingCharacters(in: .whitespaces).uppercased()
            ? .matched : .mismatched
    }
    /// 所选机型对应的已知 EC 配置（可能为空 = 未收录）
    var ecProfile: ECProfile? { ECProfiles.match(selectedCode).profile }
    var ecLevel: MatchLevel { ECProfiles.match(selectedCode).level }

    /// 机主是否已确认「机型不匹配」的硬件损坏风险
    @Published private(set) var acknowledgedMismatch: Bool

    private let modelOverrideKey = "fan.modelOverride"
    private let mismatchAckKey = "fan.mismatchAck"

    // MARK: 风扇状态

    @Published private(set) var kextLoaded = false
    @Published private(set) var kextBuild: String?
    @Published private(set) var rpmCPU = 0
    @Published private(set) var rpmGPU = 0
    @Published private(set) var fanmMirror: UInt8?
    @Published private(set) var presets: FanPresets?
    @Published private(set) var loadError: String?
    @Published private(set) var applying: String?
    @Published private(set) var message: String?
    /// 我们自己记下的档位（kext 不回显，只能自助记忆）
    @Published private(set) var lastApplied: String?

    private let presetKey = "fan.preset"
    private var refreshing = false

    /// 交付包里的命令行工具把档位记录在 /tmp/fanmode.state（它们不回读 EC），
    /// 这里读一份做兜底，免得 GUI 和 CLI 各记各的、显示不一致。
    private static var toolStatePreset: String? {
        let url = URL(fileURLWithPath: "/tmp/fanmode.state")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = obj["mode"] as? String else { return nil }
        return mode
    }

    private init() {
        // 迁移：旧版本把电池部件号（GA50358 之类）当机型存进过偏好。
        // 现在判定改用硬件指纹，那个值会平白造成「机型不匹配」，清掉它。
        if let saved = Prefs.string(modelOverrideKey), MachineModel.isLegacyBatteryCode(saved) {
            Prefs.set(nil as String?, for: modelOverrideKey)
            Prefs.set(false, for: mismatchAckKey)
        }
        selectedCode = (Prefs.string(modelOverrideKey) ?? detection.code)
            .trimmingCharacters(in: .whitespaces)
        acknowledgedMismatch = Prefs.bool(mismatchAckKey)
        lastApplied = Prefs.string(presetKey) ?? FanControl.toolStatePreset
        reloadPresets()
        refresh()
    }

    var isReady: Bool { kextLoaded && presets != nil }

    /// 按所选机型重新加载曲线配置
    private func reloadPresets() {
        do {
            presets = try FanPresets.load(for: selectedCode)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// 机主选择/输入机型（按型号名）。切换后重置免责确认，并重新加载对应曲线。
    func selectModel(_ code: String) {
        let c = code.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty, c.uppercased() != selectedCode.uppercased() else { return }
        selectedCode = c
        Prefs.set(c, for: modelOverrideKey)
        acknowledgedMismatch = false
        Prefs.set(false, for: mismatchAckKey)
        reloadPresets()
        if status == .mismatched {
            message = ModelDisclaimer.short(selected: selectedCode, detected: detection.code)
        } else {
            message = "已切换到 \(selectedCode)，曲线随之更新"
        }
        refresh()
    }

    /// 只读刷新。SMC 读 + IORegistry 遍历都放后台，回主线程只写几个 @Published。
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let ctrl = FanController()
            let rpm = ctrl.rpms()
            let loaded = ctrl.isKextLoaded
            let build = loaded ? ctrl.kextBuild : nil
            let mirror = loaded ? ctrl.modeMirror : nil
            DispatchQueue.main.async {
                self.rpmCPU = rpm.cpu
                self.rpmGPU = rpm.gpu
                self.kextLoaded = loaded
                self.kextBuild = build
                self.fanmMirror = mirror
                self.refreshing = false
            }
        }
    }

    /// 下发一条档位（CPU + GPU 两条曲线各写一次）
    func apply(_ name: String) {
        guard applying == nil else { return }

        // 机型不匹配、或压根没认出机型（选的机型无从核对）且尚未确认风险 → 拒绝，
        // 提示先确认（UI 负责弹免责声明）
        if status != .matched, !acknowledgedMismatch {
            message = status == .mismatched
                ? ModelDisclaimer.short(selected: selectedCode, detected: detection.code)
                : ModelDisclaimer.shortUndetected(selected: selectedCode)
            return
        }

        guard let preset = presets?.preset(name) else {
            message = "没有这个档位：\(name)"
            return
        }
        guard preset.cpu.isValid(points: ecProfile?.curvePoints ?? 8,
                                 tempRange: (ecProfile?.tempMin ?? 20)...(ecProfile?.tempMax ?? 110),
                                 dutyRange: (ecProfile?.dutyMin ?? 0)...(ecProfile?.dutyMax ?? 100)),
              preset.gpu.isValid(points: ecProfile?.curvePoints ?? 8,
                                 tempRange: (ecProfile?.tempMin ?? 20)...(ecProfile?.tempMax ?? 110),
                                 dutyRange: (ecProfile?.dutyMin ?? 0)...(ecProfile?.dutyMax ?? 100)) else {
            message = "曲线非法：需要 \(ecProfile?.curvePoints ?? 8) 个点、温度 \(ecProfile?.tempMin ?? 20)..\(ecProfile?.tempMax ?? 110)、占空比 ≤\(ecProfile?.dutyMax ?? 100)"
            return
        }
        applying = name
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "set", name])
            DispatchQueue.main.async {
                self.applying = nil
                if result.ok {
                    self.lastApplied = name
                    Prefs.set(name, for: self.presetKey)
                    self.message = "已切到「\(preset.label ?? name)」，转速通常几秒内跟上"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "下发失败（未拿到输出）" : text
                }
                self.refresh()
            }
        }
    }

    /// UI 在免责弹窗里点了「我已知晓风险并继续」：标记确认风险（后续应用不再拦截）
    func acknowledgeMismatch() {
        acknowledgedMismatch = true
        Prefs.set(true, for: mismatchAckKey)
    }

    /// 仅确认风险（不应用具体档位）后的提示
    func noteConfirmed() {
        message = "已确认风险，现在可以应用曲线了"
    }
}
