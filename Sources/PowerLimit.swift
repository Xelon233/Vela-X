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
        case .performance: return "给足功耗，适合编译、渲染、导出"
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
    /// 实测满载功耗（W），0 = 没测过
    static let prefsMeasured = "power.measuredCeiling"
    /// 实测时间（epoch 秒），0 = 没测过
    static let prefsMeasuredAt = "power.measuredCeilingAt"
}

/// 功耗墙走哪条通道
enum PowerBackend {
    /// SMCAsusFan.kext 暴露的 AFsC / AFsw（AMD 与部分 Intel 机型）
    case smc
    /// AsusECTool.kext 的 MSR 通道（Intel：RAPL 0x610）—— 本机走这条
    case rapl
    /// 都没有
    case none

    var label: String {
        switch self {
        case .smc:  return "SMU · AFsC / AFsw"
        case .rapl: return "Intel RAPL · MSR 0x610"
        case .none: return "无可用通道"
        }
    }

    /// 是否能在进程内直接下发（RAPL 走 kext，不需要管理员授权）
    var needsAdmin: Bool { self == .smc }
}

/// 通道探测（不碰 UI 状态，GUI 与 CLI、能力矩阵共用）
enum PowerWallProbe {
    /// SMC 键优先（原设计主线），其次 RAPL（Intel 机型）
    static var backend: PowerBackend {
        if SMC.exists(PowerLimitSpec.keyCmd) && SMC.exists(PowerLimitSpec.keyWatts) {
            return .smc
        }
        if RAPLBridge.shared.hasChannel { return .rapl }
        return .none
    }
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
    /// 当前走哪条通道（检测一次后缓存，刷新时重测）
    @Published private(set) var backend: PowerBackend = .none
    /// RAPL 通道下从 MSR 读到的硬件值（SMC 通道下为 nil）
    @Published private(set) var hardwarePL1: Int?
    @Published private(set) var hardwarePL2: Int?
    /// RAPL 的 lock 位（true = 硬件会忽略写入，只能进 BIOS 改）
    @Published private(set) var lockedByFirmware = false

    /// 「登录时自动下发」（LaunchAgent）：重启后固件会重编程回标称值，靠它把档位找回来
    @Published private(set) var persistEnabled: Bool
    /// 本机实测满载功耗（W）；nil = 没测过。和寄存器里的标称值完全是两回事。
    @Published private(set) var measuredCeiling: Int?
    @Published private(set) var measuredAt: Date?
    @Published private(set) var measuring = false

    private init() {
        unlocked = Prefs.bool(PowerLimitSpec.prefsUnlocked)
        backend = PowerWallProbe.backend
        persistEnabled = PowerWallPersist.isEnabled
        let measured = Prefs.int(PowerLimitSpec.prefsMeasured, default: 0)
        measuredCeiling = measured > 0 ? measured : nil
        let at = Prefs.int(PowerLimitSpec.prefsMeasuredAt, default: 0)
        measuredAt = at > 0 ? Date(timeIntervalSince1970: TimeInterval(at)) : nil
        if let raw = Prefs.string(PowerLimitSpec.prefsProfile),
           let p = PowerProfile(rawValue: raw) {
            profile = p
        }
        if let w = Prefs.string(PowerLimitSpec.prefsCustom), let v = Int(w) {
            customWatts = clamped(v)
        }
    }

    /// 从硬件回读当前功耗墙
    /// 注意：SMC 通道只反映「最后一次写入的值」，不代表 EC 当前真实墙值；
    /// RAPL 通道读到的是 CPU 寄存器里的真实值。
    func refreshApplied() {
        let detected = Self.detectBackend()
        backend = detected
        persistEnabled = PowerWallPersist.isEnabled
        let measured = Prefs.int(PowerLimitSpec.prefsMeasured, default: 0)
        measuredCeiling = measured > 0 ? measured : nil
        let at = Prefs.int(PowerLimitSpec.prefsMeasuredAt, default: 0)
        measuredAt = at > 0 ? Date(timeIntervalSince1970: TimeInterval(at)) : nil

        switch detected {
        case .smc:
            hardwarePL1 = nil
            hardwarePL2 = nil
            lockedByFirmware = false
            if let v = try? SMCClient.shared.readUInt8(PowerLimitSpec.keyWatts), v > 0 {
                appliedWatts = Int(v)
            } else {
                appliedWatts = nil
            }
        case .rapl:
            if let r = RAPLBridge.shared.reading() {
                hardwarePL1 = Int(r.pl1W.rounded())
                hardwarePL2 = Int(r.pl2W.rounded())
                lockedByFirmware = r.locked
                // 只有我们自己下发过（存了原始值）才显示「已限 XXW」，
                // 否则那只是出厂墙，写成「已限」会误导
                appliedWatts = RAPLBridge.shared.hasOriginal ? Int(r.pl1W.rounded()) : nil
            } else {
                hardwarePL1 = nil
                hardwarePL2 = nil
            }
        case .none:
            hardwarePL1 = nil
            hardwarePL2 = nil
            lockedByFirmware = false
            appliedWatts = nil
        }
    }

    /// 通道探测：SMC 键优先（那是原设计的主线），其次 RAPL（Intel 机型）
    static func detectBackend() -> PowerBackend { PowerWallProbe.backend }

    /// 当前通道是否可用（历史名字，UI 与能力矩阵都在用）
    var kextSupported: Bool { backend != .none }

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
        guard !applying else { return }

        switch backend {
        case .smc:
            applyViaSMC(w)
        case .rapl:
            applyViaRAPL(w)
        case .none:
            message = "没有可用的功耗墙通道：SMC 的 AFsC / AFsw 不存在，AsusECTool.kext 也没有 MSR 通道（需要 v1.4.0 及以上）"
        }
    }

    /// SMC 通道：写 AFsC / AFsw，需要管理员授权（走自己的 CLI）
    private func applyViaSMC(_ w: Int) {
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

    /// RAPL 通道：kext 直接写 MSR 0x610，不需要提权
    private func applyViaRAPL(_ w: Int) {
        applying = true
        message = nil
        DispatchQueue.global(qos: .userInitiated).async {
            // PL1 与 PL2 一起压：只压长期墙的话，爆发期仍会按 PL2 放行
            let r = RAPLBridge.shared.setLimits(pl1: w, pl2: w)
            DispatchQueue.main.async {
                self.applying = false
                switch r {
                case .success(let actual):
                    self.appliedWatts = actual
                    self.hardwarePL1 = actual
                    self.hardwarePL2 = RAPLBridge.shared.reading().map { Int($0.pl2W.rounded()) }
                    self.lockedByFirmware = false
                    // 记下目标瓦数：重启后由 LaunchAgent（或下次启动） replay 回来
                    PowerWallPersist.noteApplied(actual)
                    self.message = actual == w
                        ? "已设为 \(w)W（PL1 + PL2 一起压），跑 1–2 秒负载看功耗曲线是否被按住"
                        : "已写入 \(w)W，硬件回读为 \(actual)W（刻度取整，误差 ±1W 属正常）"
                case .failure(let e):
                    self.message = e.description
                    self.lockedByFirmware = (e == .locked)
                    self.refreshApplied()
                }
            }
        }
    }

    /// 恢复默认（AFsw = 0 → 回到 EC 当前 PL1；RAPL → 写回第一次读到的原始值）
    func restore() {
        guard !applying else { return }

        switch backend {
        case .smc:
            applying = true
            message = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let result = Admin.runSelfAsAdmin(["fan", "power-limit", "0"])
                DispatchQueue.main.async {
                    self.applying = false
                    if result.ok {
                        self.appliedWatts = nil
                        PowerWallPersist.clearTarget()
                        self.message = "已恢复默认功耗墙"
                    } else {
                        let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.message = text.isEmpty ? "恢复失败（未拿到输出）" : text
                    }
                }
            }
        case .rapl:
            guard RAPLBridge.shared.hasOriginal else {
                message = "没有存过的原始功耗墙可恢复（本程序还没下发过）"
                return
            }
            applying = true
            message = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let r = RAPLBridge.shared.restoreOriginal()
                DispatchQueue.main.async {
                    self.applying = false
                    switch r {
                    case .success(let w):
                        self.appliedWatts = nil
                        // 没限制就没有「重启后要恢复的东西」了，避免登录时白写一次
                        PowerWallPersist.clearTarget()
                        self.message = "已恢复出厂功耗墙（回读 PL1 = \(w)W）"
                        self.refreshApplied()
                    case .failure(let e):
                        self.message = e.description
                    }
                }
            }
        case .none:
            message = "没有可用的功耗墙通道"
        }
    }

    // MARK: - 登录自动下发

    /// 打开 / 关闭「登录时自动保持」
    func setPersist(_ on: Bool) {
        if let err = PowerWallPersist.set(on) {
            message = err
            persistEnabled = PowerWallPersist.isEnabled
            return
        }
        persistEnabled = PowerWallPersist.isEnabled
        message = on
            ? (appliedWatts == nil
               ? "已开启。当前没设限，等你应用某个瓦数后，登录时才会自动写回"
               : "已开启。下次登录会自动写回 \(appliedWatts!)W（重启后固件会先把它冲回标称值）")
            : "已关闭登录自动下发，重启后回到标称功耗墙"
    }

    /// App 启动 / 唤醒时补一次（不依赖 LaunchAgent 是否装了）
    func replayOnLaunch() {
        guard backend == .rapl, PowerWallPersist.target != nil else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let w = PowerWallPersist.replay() else { return }
            DispatchQueue.main.async {
                self.appliedWatts = w
                self.hardwarePL1 = w
                self.message = "已按上次的档位恢复 \(w)W"
                self.refreshApplied()
            }
        }
    }

    // MARK: - 实测本机上限

    /// 造一段满载，用 MSR 0x611 的能量差算出真能吃多少瓦。
    /// 必须在「未限制」状态下测，否则量到的是你自己设的墙。
    func measureCeiling() {
        guard backend == .rapl else {
            message = "只有 RAPL 通道能实测（SMC 通道读不到封装功耗）"
            return
        }
        guard !applying, !measuring else { return }
        if appliedWatts != nil {
            message = "先点「恢复默认」再实测，否则量到的是你设的墙"
            return
        }
        measuring = true
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            var best: Double = 0
            // 跑两轮取较大值：单次 0.2s 窗口的 MSR 采样有 ±5W 抖动
            for _ in 0..<2 {
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.global(qos: .userInitiated).async {
                    PowerBench.burn(seconds: 4.0)
                    done.signal()
                }
                // 等负载真正压上来再开采样窗，否则会摊掉开头那段爬坡
                Thread.sleep(forTimeInterval: 1.0)
                if let w = RAPLBridge.shared.packageWatts(window: 2.5) {
                    best = max(best, w)
                }
                done.wait()
            }
            let watts = Int(best.rounded())
            DispatchQueue.main.async {
                self.measuring = false
                guard watts > 0 else {
                    self.message = "实测失败：读不到 MSR 0x611 的能量计数"
                    return
                }
                self.measuredCeiling = watts
                self.measuredAt = Date()
                Prefs.set(watts, for: PowerLimitSpec.prefsMeasured)
                Prefs.set(Int(Date().timeIntervalSince1970), for: PowerLimitSpec.prefsMeasuredAt)
                self.message = "实测满载约 \(watts)W（两轮取较大值）"
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
                         trailing: controller.kextSupported
                             ? (controller.backend == .rapl ? "RAPL" : "SMU")
                             : "无此通道",
                         command: "power --limit")

            if !controller.kextSupported {
                // 两条通道都没有时，与其摆一排点了没反应的档位按钮，
                // 不如说清楚缺什么、退路是什么。
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有可用的功耗墙通道，无法按瓦数限制")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ECFanBridge.shared.isAvailable
                             ? "Intel 机型需要 AsusECTool.kext v1.4.0 及以上提供 MSR 通道（RAPL 0x610）；临时可用上方「性能模式」的 EC 三档。"
                             : "需要 SMCAsusFan.kext v20-stapm 及以上（AFsC / AFsw），或 AsusECTool.kext v1.4.0 及以上提供 MSR 通道。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
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

                        // RAPL 才有「重启后要写回」的问题（SMC 值的持久化由 SilentApply 管）
                        if controller.backend == .rapl {
                            Divider().overlay(Palette.hairline)
                            persistRow
                        }

                        if let m = controller.message {
                            Text(m)
                                .font(.system(size: 10))
                                .foregroundStyle(m.hasPrefix("已") ? Palette.ok : Palette.bad)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text(footerText)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .onAppear {
            draftCustom = Double(controller.customWatts)
            controller.refreshApplied()
        }
    }

    // MARK: 子视图

    /// 底部说明随通道变化：SMC 那条「只降不升 + powlimit.sh」的说法对 RAPL 不成立
    private var footerText: String {
        switch controller.backend {
        case .smc:
            return "只降不升，上限 \(PowerLimitSpec.maxW)W。重启或睡眠唤醒后会回到默认，想一直保持请在终端执行：sudo powlimit.sh install"
        case .rapl:
            return "范围 \(PowerLimitSpec.minW)–\(PowerLimitSpec.maxW)W，PL1 与 PL2 一起压（只压 PL1 的话爆发期仍会冲到 PL2）。写的是 CPU 寄存器，立即生效；重启后固件会重新编程回标称值 —— 想一直保持就打开上面的「登录时自动保持」。「恢复默认」会写回本程序首次读到的原值。"
        case .none:
            return ""
        }
    }

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
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(controller.appliedWatts == nil ? Palette.textTertiary : Palette.ok)
                    .frame(width: 5, height: 5)
                Text(controller.appliedWatts.map { "当前：已限 \($0)W" }
                     ?? "当前：默认功耗墙（未限制）")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
            // RAPL 通道能直接读寄存器。这里刻意把「标称」和「实测」分成两行：
            // 175W 是固件写进 0x610 的上限值，跟这台机器真能吃到多少（≈54W）是两回事，
            // 混成一行「硬件回读 PL1 175W」最容易被读成「这机能跑 175W」。
            if let p1 = controller.hardwarePL1 {
                HStack(alignment: .top, spacing: 6) {
                    Text("标称")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 22, alignment: .leading)
                    Text("PL1 \(p1)W · PL2 \(controller.hardwarePL2 ?? p1)W（固件写入的上限值）")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 6) {
                    Text("实测")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 22, alignment: .leading)
                    Text(measuredText)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(controller.measuredCeiling == nil
                                         ? Palette.textTertiary : Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 目标高于实测上限 = 这个档位实际达不到，说清楚比让人以为没生效强
                if let ceiling = controller.measuredCeiling,
                   controller.targetWatts > ceiling {
                    Text("目标 \(controller.targetWatts)W 高于实测上限，实际会被压住在 \(ceiling)W 附近")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if controller.lockedByFirmware {
                Text("MSR 0x610 的 lock 位已置位：硬件会忽略写入，需在 BIOS 解锁功耗墙")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.warn)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var measuredText: String {
        if controller.measuring { return "正在跑满载实测，约 10 秒…" }
        guard let w = controller.measuredCeiling else {
            return "没测过 · 点「测上限」跑一段满载量一次"
        }
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        let at = controller.measuredAt.map { "（\(f.string(from: $0))）" } ?? ""
        return "满载约 \(w)W\(at)"
    }

    /// 「登录时自动保持」开关（RAPL 专有：重启后固件会重新编程回标称值）
    private var persistRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("登录时自动保持")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                Text(controller.persistEnabled
                     ? "已装后台项：登录时按当前档位写回 0x610（不需要管理员权限）"
                     : "重启后固件会把它冲回标称值；打开这个才会自动写回")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(
                get: { controller.persistEnabled },
                set: { controller.setPersist($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Palette.accent)
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

            if controller.backend == .rapl {
                Button {
                    controller.measureCeiling()
                } label: {
                    Text(controller.measuring ? "实测中…" : "测上限")
                        .font(.system(size: 10.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.measuring ? Palette.textTertiary : Palette.textSecondary)
                .disabled(controller.measuring || controller.applying)
            }

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
    /// EC 通道在时，这一列显示的是 EC 的性能模式档位（功耗墙本身不可用）
    @ObservedObject private var thermal = ThermalControl.shared

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "当前模式", trailing: Palette.isMoss ? "PWR / FAN" : "功耗 / 风扇",
                             color: Palette.warn, code: "MISSION", command: "mission --profile")
                HStack(spacing: 0) {
                    modeColumn(power.kextSupported ? "功耗墙" : "性能模式",
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
    /// 没有 SMU 功耗墙时改为显示 EC 的性能模式档位，而不是空着或写「kext 不支持」
    private var powerLabel: String {
        if !power.kextSupported {
            return thermal.mode?.title ?? "—"
        }
        return power.profile == .custom && !power.unlocked ? "平衡" : power.profile.label
    }

    private var powerSub: String {
        if !power.kextSupported {
            guard thermal.available else { return Palette.isMoss ? "NO CHANNEL" : "无通道" }
            return Palette.isMoss ? "EC CMMV" : "EC 三档"
        }
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
        // EC 直连时风扇是通的，只是没 kext，别写成「kext 未加载」让人以为风扇不可用
        let ec = ECFanBridge.shared.isAvailable
        if Palette.isMoss {
            return fan.kextLoaded ? "KEXT ONLINE" : (ec ? "EC DIRECT" : "KEXT OFFLINE")
        }
        return fan.kextLoaded ? "kext 已加载" : (ec ? "EC 直连" : "kext 未加载")
    }
}
