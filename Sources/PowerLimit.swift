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

    private init() {
        if let raw = Prefs.string(PowerLimitSpec.prefsProfile),
           let p = PowerProfile(rawValue: raw) {
            profile = p
        }
        if let w = Prefs.string(PowerLimitSpec.prefsCustom), let v = Int(w) {
            customWatts = clamped(v)
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
        profile = p
        Prefs.set(p.rawValue, for: PowerLimitSpec.prefsProfile)
    }

    func setCustom(_ w: Int) {
        customWatts = clamped(w)
        Prefs.set(String(customWatts), for: PowerLimitSpec.prefsCustom)
    }

    /// 当前档位对应的瓦数
    var targetWatts: Int {
        profile.watts ?? customWatts
    }

    /// 下发当前档位
    func apply() {
        let w = targetWatts
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

    /// 恢复默认（AFsw = 0 → 回到 EC 当前 PL1）
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

                    Text(controller.profile.hint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textTertiary)
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
        .onAppear { draftCustom = Double(controller.customWatts) }
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
                        if let w = p.watts {
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
