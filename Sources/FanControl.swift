//
//  FanControl.swift
//  风扇档位 / 曲线的状态中枢
//
//  数据来源：SMCAsusFan.kext 暴露的 SMC 键（AFMd 版本号、AFMf 选风扇、AFW1..4 曲线参数、AFWg 提交），
//  以及 F0Ac / F1Ac 两个转速键。
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
        lastApplied = Prefs.string(presetKey) ?? FanControl.toolStatePreset
        do {
            presets = try FanPresets.load()
        } catch {
            loadError = error.localizedDescription
        }
        refresh()
    }

    var isReady: Bool { kextLoaded && presets != nil }

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
        guard let preset = presets?.preset(name) else {
            message = "没有这个档位：\(name)"
            return
        }
        guard preset.cpu.isValid, preset.gpu.isValid else {
            message = "曲线非法：需要 8 个点、单调不减、温度 ≤110、占空比 ≤100"
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
}
