//
//  ThermalControl.swift
//  VelaX —— 三档性能模式（静音 / 平衡 / 增强）的状态中枢
//
//  为什么是 CMMV 而不是 FANM：
//    EC 的 IT55 窗口（0xFE700600）偏移 0xCE 是 CMMV —— 这才是真正改变风扇策略的寄存器。
//    MB00 窗口的 FANM（0xF9）也能写、也能留住，但 EC 不据它改转速，它只是 DEFC
//    写曲线前的内部标志。早期把性能模式接到 FANM 上，结果就是「点了没反应」。
//
//    实测（G815LM）：静音时中置风扇 3521 RPM，平衡 3902，增强 3964；
//    GPU 风扇 平衡 2820 / 增强 3060 / 静音 2820。
//
//  权限：写入走 AsusECTool.kext 的 memWrite（窗口 T + 0xCE），普通用户即可，
//        不需要 root，也不弹授权框。kext 内部写后回读，所以这里能拿到真实结果。
//

import Foundation
import Combine

/// 三档散热模式。原始值与 EC 的 CMMV 一一对应（注意不是按 UI 顺序）。
enum ThermalMode: Int, CaseIterable, Identifiable {
    case silent = 2      // 静音
    case balanced = 0    // 平衡
    case boost = 1       // 增强

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .silent:   return "静音"
        case .balanced: return "平衡"
        case .boost:    return "增强"
        }
    }

    var icon: String {
        switch self {
        case .silent:   return "leaf"
        case .balanced: return "equal"
        case .boost:    return "flame"
        }
    }

    var desc: String {
        switch self {
        case .silent:   return "风扇低速、噪音优先，长时间负载会降频"
        case .balanced: return "按负载动态调度，日常默认"
        case .boost:    return "风扇提前拉高、功耗放开"
        }
    }

    /// 命令行/配置里的名字（英文代号 + 中文 + 数字都认）
    var slug: String {
        switch self {
        case .silent:   return "silent"
        case .balanced: return "balanced"
        case .boost:    return "boost"
        }
    }

    static func parse(_ s: String) -> ThermalMode? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = Int(t), let m = ThermalMode(rawValue: n) { return m }
        for m in ThermalMode.allCases {
            if t == m.slug || t == m.title { return m }
        }
        switch t {
        case "quiet", "cool", "静": return .silent
        case "normal", "standard", "auto", "性能": return .balanced
        case "turbo", "performance", "enhanced", "狂暴": return .boost
        default: return nil
        }
    }
}

@MainActor
final class ThermalControl: ObservableObject {

    static let shared = ThermalControl()

    /// 当前 EC 里读到的模式（nil = 读不到或值不认识）
    @Published private(set) var mode: ThermalMode?
    @Published private(set) var available = false
    /// 正在切换到哪一档（nil = 空闲）
    @Published private(set) var applying: ThermalMode?
    @Published private(set) var message: String?

    private var refreshing = false

    private init() {
        refresh()
    }

    /// 只读刷新（EC 访问放到后台，回主线程只写几个 @Published）
    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let ec = ECFanBridge.shared
            let av = ec.isAvailable
            let raw = av ? ec.thermalMode() : nil
            DispatchQueue.main.async {
                self.available = av
                self.mode = raw.flatMap(ThermalMode.init(rawValue:))
                self.refreshing = false
            }
        }
    }

    /// 切换模式。写后回读，只有回读一致才算成功。
    func set(_ target: ThermalMode) {
        guard applying == nil else { return }
        applying = target
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let ec = ECFanBridge.shared
            let ok = ec.setThermalMode(target.rawValue)
            let readBack = ec.thermalMode()
            DispatchQueue.main.async {
                self.applying = nil
                if ok, readBack == target.rawValue {
                    self.mode = target
                    self.available = true
                    self.message = "已切到「\(target.title)」，CMMV 回读 = \(readBack!)"
                } else if ok {
                    self.message = "写入返回成功，但回读是 \(readBack.map(String.init) ?? "—")，可能没落盘"
                } else {
                    self.message = "EC 写入失败：AsusECTool 没返回成功（检查 kext 是否加载、窗口 T 是否可写）"
                }
                self.refresh()
            }
        }
    }
}

/// 充电上限（EC 的 MB00 窗口 MBF3 = 0xF3）。
/// 0 = 不限充，其余为百分比（实测 60 / 80 / 100 可落盘）。
@MainActor
final class ChargeControl: ObservableObject {

    static let shared = ChargeControl()

    /// 当前上限（nil = 读不到；0 = 不限充）
    @Published private(set) var limit: Int?
    @Published private(set) var available = false
    @Published private(set) var applying = false
    @Published private(set) var message: String?

    private var refreshing = false

    private init() {
        refresh()
    }

    /// 常用档位
    static let presets = [60, 80, 100]

    var limitText: String {
        guard let l = limit else { return "读不到" }
        return l == 0 ? "不限充" : "\(l)%"
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async {
            let ec = ECFanBridge.shared
            let av = ec.isAvailable
            let raw = av ? ec.chargeLimit() : nil
            DispatchQueue.main.async {
                self.available = av
                self.limit = raw
                self.refreshing = false
            }
        }
    }

    /// 设置上限。写后回读，只有回读一致才算成功。
    func set(_ pct: Int) {
        guard !applying else { return }
        applying = true
        message = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let ec = ECFanBridge.shared
            let ok = ec.setChargeLimit(pct)
            let readBack = ec.chargeLimit()
            DispatchQueue.main.async {
                self.applying = false
                if ok, readBack == pct {
                    self.limit = pct
                    self.available = true
                    self.message = pct == 0
                        ? "已解除充电上限"
                        : "已限制到 \(pct)%，MBF3 回读 = \(readBack!)"
                } else if ok {
                    self.message = "写入返回成功，但回读是 \(readBack.map(String.init) ?? "—")，可能没落盘"
                } else {
                    self.message = "EC 写入失败：AsusECTool 没返回成功（检查 kext 是否加载、窗口 B 是否可写）"
                }
                self.refresh()
            }
        }
    }
}
