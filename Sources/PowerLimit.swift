//
//  PowerLimit.swift
//  VelaX —— 功耗墙档位（交付件，直接放进 Sources/ 即可）
//
//  设计原则：自包含。不修改 FanControl / Views / CLI 里的任何类型定义，
//  只复用它们已有的模块内成员（SMCClient / Admin / Prefs / Palette / Card …）。
//  接入只需在两处各贴一小段（见 VelaX-PowerLimit.patch.swift 与 README.md）。
//
//  链路：
//    GUI 选档 → PowerLimitController 以 root 重跑自身 CLI：fan power-limit <瓦数>
//    → CLI 写 SMC 键 AFsC(0x15) + AFsw(瓦数)
//    → kext（v20-stapm 起）转 SMU 消息，功耗立刻被压到该值
//
//  实测（本机，满载基线约 54W）：
//    写 25 → 24.4W ／ 写 35 → 34.2W ／ 写 45 → 43.9W（线性、精确）
//
//  重要：
//    - 只降不升：上限 50W，且 kext 侧还有一层夹紧；
//    - 生效与否看实际功耗（vela amd），EC 镜像 AFpT/AFp1 不会跟随，别拿它当判据；
//    - 重启 / 睡眠唤醒后会被重置，需要常驻保持就用随附的 powlimit.sh install。
//

import Foundation
import SwiftUI

// MARK: - 档位定义

/// 四档：三档预设 + 自定义（上限 50W）
enum PowerProfile: String, CaseIterable, Identifiable {
    case quiet
    case balanced
    case performance
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .quiet:       return "静音"
        case .balanced:    return "平衡"
        case .performance: return "性能"
        case .custom:      return "自定义"
        }
    }

    /// 预设档位的瓦数；自定义档返回 nil（由用户给值）
    var watts: Int? {
        switch self {
        case .quiet:       return 25
        case .balanced:    return 30
        case .performance: return 35
        case .custom:      return nil
        }
    }

    var hint: String {
        switch self {
        case .quiet:       return "最凉最安静，多核性能下降明显"
        case .balanced:    return "日常主力，发热与性能的折中"
        case .performance: return "接近不限制，适合编译、渲染"
        case .custom:      return "在 \(PowerLimitSpec.minW)–\(PowerLimitSpec.maxW)W 之间自选"
        }
    }
}

/// 与 kext 约定的常量（改这里前先确认 kext 版本是 v20-stapm 及以上）
enum PowerLimitSpec {
    static let minW = 15
    static let maxW = 50
    /// SMU 消息号：0x15 / 0x16 实测精确生效；0x14 回 OK 但不执行，别用
    static let smuCmd: UInt8 = 0x15
    static let keyCmd = "AFsC"
    static let keyWatts = "AFsw"
    static let prefsProfile = "power.profile"
    static let prefsCustom = "power.customWatts"
    static let prefsUnlocked = "power.customUnlocked"
}

// MARK: - 控制器

@MainActor
final class PowerLimitController: ObservableObject {
    static let shared = PowerLimitController()

    @Published private(set) var profile: PowerProfile = .balanced
    @Published private(set) var customWatts: Int = 30
    /// 已下发的瓦数；nil = 未限制（默认功耗墙）
    @Published private(set) var appliedWatts: Int?
    @Published private(set) var applying = false
    @Published private(set) var message: String?
    /// 功能解锁开关：默认关，需在「高级功能」页确认风险后解锁
    @Published private(set) var unlocked: Bool

    private init() {
        unlocked = Prefs.bool(PowerLimitSpec.prefsUnlocked)
        if let raw = Prefs.string(PowerLimitSpec.prefsProfile),
           let p = PowerProfile(rawValue: raw) {
            profile = p
        }
        if let w = Prefs.string(PowerLimitSpec.prefsCustom), let v = Int(w) {
            customWatts = clamped(v)
        }
    }

    /// 从 SMC 回读当前已下发的功耗墙（afsw=0 视为未限制 / 默认）
    /// 注意：这只反映「最后一次写入的值」，不代表 EC 当前真实墙值；真正生效与否看 `vela amd` 实测。
    func refreshApplied() {
        guard kextSupported else { return }
        if let v = try? SMCClient.shared.readUInt8(PowerLimitSpec.keyWatts), v > 0 {
            appliedWatts = Int(v)
        } else {
            appliedWatts = nil
        }
    }

    /// kext 是否具备功耗墙通道：AFsw 键存在即视为 v20-stapm 及以上
    var kextSupported: Bool {
        (try? SMCClient.shared.keyInfo(PowerLimitSpec.keyWatts)) != nil
    }

    func clamped(_ w: Int) -> Int {
        min(max(w, PowerLimitSpec.minW), PowerLimitSpec.maxW)
    }

    func select(_ p: PowerProfile) {
        // 三档预设随时可用；只有「自定义」受高级功能的解锁门约束
        if p == .custom && !unlocked {
            requestCustom()
            return
        }
        profile = p
        Prefs.set(p.rawValue, for: PowerLimitSpec.prefsProfile)
    }

    /// 点「自定义」档位：未解锁时不切换，只提示去「高级功能」解锁
    func requestCustom() {
        if unlocked {
            select(.custom)
            return
        }
        message = "自定义功耗档未解锁：请在「高级功能」页打开「自定义功耗墙」开关并确认风险"
    }

    func setCustom(_ w: Int) {
        customWatts = clamped(w)
        Prefs.set(String(customWatts), for: PowerLimitSpec.prefsCustom)
    }

    /// 高级功能页确认风险后解锁 / 关闭
    func unlock() {
        unlocked = true
        Prefs.set(true, for: PowerLimitSpec.prefsUnlocked)
    }

    func lock() {
        unlocked = false
        Prefs.set(false, for: PowerLimitSpec.prefsUnlocked)
        // 上锁时若正停在「自定义」，退回平衡档，避免留一个用不了的档位
        if profile == .custom {
            profile = .balanced
            Prefs.set(profile.rawValue, for: PowerLimitSpec.prefsProfile)
        }
        message = nil
    }

    /// 当前档位对应的瓦数
    var targetWatts: Int {
        profile.watts ?? customWatts
    }

    /// 下发当前档位
    func apply() {
        let w = targetWatts
        guard profile != .custom || unlocked else {
            message = "自定义功耗档未解锁：请在「高级功能」页打开「自定义功耗墙」开关并确认风险"
            return
        }
        guard kextSupported else {
            message = "kext 不支持（需要 v20-stapm 及以上：AFsw 键不存在）"
            return
        }
        guard !applying else { return }

        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "power-limit", String(w)])
            DispatchQueue.main.async {
                self.applying = false
                if result.ok {
                    self.appliedWatts = w
                    self.message = "已设为 \(w)W，功耗通常 1–2 秒内跟上"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "下发失败（未拿到输出）" : text
                }
            }
        }
    }

    /// 恢复默认（AFsw = 0 → 回到 EC 当前 PL1）；「恢复默认」随时可用
    func restore() {
        guard kextSupported else {
            message = "kext 不支持（需要 v20-stapm 及以上）"
            return
        }
        guard !applying else { return }

        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Admin.runSelfAsAdmin(["fan", "power-limit", "0"])
            DispatchQueue.main.async {
                self.applying = false
                if result.ok {
                    self.appliedWatts = nil
                    self.message = "已恢复默认功耗墙"
                } else {
                    let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.message = text.isEmpty ? "恢复失败（未拿到输出）" : text
                }
            }
        }
    }
}

// MARK: - 界面：功耗墙卡片（整段放进「性能与风扇」页即可）

struct PowerLimitCard: View {
    @ObservedObject private var controller = PowerLimitController.shared
    @State private var draftCustom: Double = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "功耗墙",
                         trailing: controller.kextSupported ? "可下发" : "kext 不支持")

            Card {
                VStack(alignment: .leading, spacing: 11) {
                    profileRow

                    if controller.profile == .custom {
                        customSlider
                    }

                    Text(controller.profile == .custom && !controller.unlocked
                         ? "自定义档默认上锁：在「高级功能」页打开「自定义功耗墙」开关、确认风险后可用"
                         : controller.profile.hint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(controller.profile == .custom && !controller.unlocked
                                         ? Palette.warn
                                         : Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    statusLine

                    actionRow

                    if let m = controller.message {
                        Text(m)
                            .font(.system(size: 10))
                            .foregroundStyle(m.hasPrefix("已") ? Palette.ok : Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text("只降不升，上限 \(PowerLimitSpec.maxW)W。重启或睡眠唤醒后会回到默认，想一直保持请在终端执行：sudo powlimit.sh install")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            draftCustom = Double(controller.customWatts)
            controller.refreshApplied()
        }
    }

    // MARK: 子视图

    private var profileRow: some View {
        HStack(spacing: 7) {
            ForEach(PowerProfile.allCases) { p in
                Button {
                    controller.select(p)
                } label: {
                    VStack(spacing: 2) {
                        Text(p.label)
                            .font(.system(size: 10.5, weight: .medium))
                        if p == .custom && !controller.unlocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8.5))
                                .frame(height: 11)
                                .opacity(0.8)
                        } else if let w = p.watts {
                            Text("\(w)W")
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.75)
                        } else {
                            Text("\(controller.customWatts)W")
                                .font(.system(size: 9, design: .monospaced))
                                .opacity(0.75)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(controller.profile == p
                                  ? Palette.accent.opacity(0.18)
                                  : Palette.panelTop.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(controller.profile == p
                                    ? Palette.accent.opacity(0.42)
                                    : Palette.cardStroke, lineWidth: 0.8)
                    )
                    .foregroundStyle(controller.profile == p ? Palette.accent : Palette.textSecondary)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var customSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("自定义功耗")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text("\(Int(draftCustom)) W")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.accent)
            }
            // 显式写 onEditingChanged：Slider 另有 label 参数，用尾随闭包会被解析到 label 上
            Slider(value: $draftCustom,
                   in: Double(PowerLimitSpec.minW)...Double(PowerLimitSpec.maxW),
                   step: 1,
                   onEditingChanged: { editing in
                       if !editing { controller.setCustom(Int(draftCustom)) }
                   })
            .accentColor(Palette.accent)
            HStack {
                Text("\(PowerLimitSpec.minW)W")
                Spacer()
                Text("\(PowerLimitSpec.maxW)W")
            }
            .font(.system(size: 8.5))
            .foregroundStyle(Palette.textTertiary)
        }
        .padding(.vertical, 2)
    }

    private var statusLine: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(controller.appliedWatts == nil ? Palette.textTertiary : Palette.ok)
                .frame(width: 5, height: 5)
            Text(controller.appliedWatts.map { "当前：已限 \($0)W" }
                 ?? "当前：默认功耗墙（未限制）")
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                controller.apply()
            } label: {
                Group {
                    if controller.applying {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text("应用 \(controller.targetWatts)W")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .padding(.horizontal, 13).padding(.vertical, 5)
                .background(Capsule().fill(Palette.accent.opacity(0.18)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.36), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(controller.applying || !controller.kextSupported)
            .opacity(controller.kextSupported ? 1 : 0.45)

            Button {
                controller.restore()
            } label: {
                Text("恢复默认")
                    .font(.system(size: 10.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .disabled(controller.applying || !controller.kextSupported)

            Spacer()
        }
    }
}

// MARK: - 概览页：「当前模式」卡（功耗墙模式 + 风扇模式，合成一张）

/// 概览页的一张窄卡：左边显示当前功耗墙档位、右边显示当前风扇档位。
/// 设计为只读状态展示，调节仍去「性能与风扇」页。
struct ModeStatusCard: View {
    @ObservedObject private var power = PowerLimitController.shared
    @ObservedObject private var fan = FanControl.shared

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "当前模式", trailing: Palette.isMoss ? "PWR / FAN" : "功耗 / 风扇",
                             color: Palette.warn, code: "MISSION", command: "mission --profile")
                HStack(spacing: 0) {
                    modeColumn("功耗墙",
                               powerLabel,
                               powerSub,
                               color: power.profile == .quiet ? Palette.teal : Palette.warn)
                        .frame(maxWidth: .infinity)
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: 1, height: 36)
                    modeColumn("风扇", fanLabel, fanSub, color: Palette.teal)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 108)
        .onAppear { power.refreshApplied() }
    }

    private func modeColumn(_ title: String, _ value: String, _ sub: String,
                            color: Color) -> some View {
        VStack(spacing: 2) {
            if Palette.isMoss {
                // 550W：两列读起来像两条运行时配置项
                Text(title == "功耗墙" ? "CAP.WALL" : "COOLANT")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(Palette.accent.opacity(0.8))
            } else {
                Text(title)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
            }
            Text(Palette.isMoss ? MossText.code(value) : value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 当前选中的功耗墙档位名（自定义档未解锁时也不会显示）
    private var powerLabel: String {
        power.profile == .custom && !power.unlocked ? "平衡" : power.profile.label
    }

    private var powerSub: String {
        guard power.kextSupported else { return Palette.isMoss ? "KEXT N/A" : "kext 不支持" }
        if let w = power.appliedWatts {
            return Palette.isMoss ? "CAP \(w) W" : "已限 \(w)W"
        }
        return Palette.isMoss ? "NO LIMIT" : "未限制"
    }

    private var fanLabel: String {
        guard let name = fan.lastApplied else { return "未记录" }
        if name == "custom" { return "自定义曲线" }
        return fan.presets?.preset(name)?.label ?? name
    }

    private var fanSub: String {
        if Palette.isMoss { return fan.kextLoaded ? "KEXT ONLINE" : "KEXT OFFLINE" }
        return fan.kextLoaded ? "kext 已加载" : "kext 未加载"
    }
}
