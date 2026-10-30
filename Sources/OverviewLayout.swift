//
//  OverviewLayout.swift
//  概览页卡片的自由选择与调换顺序
//
//  概览页不再是写死的一屏卡片：每张卡（温度 / 功耗 / 频率 / 显卡 / 风扇 /
//  电池 / 键盘 / 负载 / 能力边界）都可单独显示或隐藏，顺序也可拖拽调整。
//  顺序与显隐都存在 Prefs 里，重启不丢。
//

import SwiftUI

/// 概览页可选的一张卡片
enum OverviewCard: String, CaseIterable, Identifiable {
    case cpuTemp     // CPU（温度环 + 状态/极值/热压力/功耗/采样 + 频率与心电图，已合并功耗）
    case gpu         // 显卡（占用率 + 温度）
    case fan         // 风扇
    case battery     // 电池
    case disk        // 磁盘（启动宗卷容量 / 已用）
    case load        // 系统负载
    case capability  // 能力边界

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuTemp:    return "CPU"
        case .gpu:        return "显卡"
        case .fan:        return "风扇"
        case .battery:    return "电池"
        case .disk:       return "磁盘"
        case .load:       return "系统负载"
        case .capability: return "能力边界"
        }
    }

    var icon: String {
        switch self {
        case .cpuTemp:    return "cpu"
        case .gpu:        return "display"
        case .fan:        return "fanblades"
        case .battery:    return "battery.75"
        case .disk:       return "internaldrive"
        case .load:       return "chart.bar.fill"
        case .capability: return "checklist"
        }
    }

    /// 是否占满整行（两列网格里占 2 列），窄卡只占 1 列两两并排
    var isWide: Bool {
        switch self {
        case .cpuTemp, .load, .capability: return true
        default: return false
        }
    }
}

/// 概览页布局偏好：卡片顺序 + 隐藏集合
enum OverviewLayoutPrefs {
    private static let orderKey = "overview.order"
    private static let hiddenKey = "overview.hidden"

    /// 显示顺序（默认 = 枚举声明顺序）
    static var order: [OverviewCard] {
        guard let raw = Prefs.string(orderKey), !raw.isEmpty else {
            return OverviewCard.allCases
        }
        var list = raw.split(separator: ",").compactMap { OverviewCard(rawValue: String($0)) }
        // 迁移：补齐存储顺序之后才加入的新卡片（如 disk），
        // 这样老用户（已存过旧顺序）升级后也能自动看到新卡，且不破坏他们自定义的顺序。
        let missing = OverviewCard.allCases.filter { !list.contains($0) }
        if !missing.isEmpty { list.append(contentsOf: missing) }
        if list.isEmpty { return OverviewCard.allCases }
        return list
    }

    static func setOrder(_ list: [OverviewCard]) {
        Prefs.set(list.map(\.rawValue).joined(separator: ","), for: orderKey)
    }

    static var hidden: Set<OverviewCard> {
        guard let raw = Prefs.string(hiddenKey), !raw.isEmpty else { return [] }
        return Set(raw.split(separator: ",").compactMap { OverviewCard(rawValue: String($0)) })
    }

    static func setHidden(_ set: Set<OverviewCard>) {
        Prefs.set(set.map(\.rawValue).joined(separator: ","), for: hiddenKey)
    }

    /// 按顺序、剔除隐藏后的实际显示列表
    static var visibleCards: [OverviewCard] {
        order.filter { !hidden.contains($0) }
    }
}

/// 概览页「自定义布局」弹窗：拖拽排序 + 开关显示/隐藏
struct OverviewLayoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var order: [OverviewCard]
    @State private var hidden: Set<OverviewCard>

    init() {
        _order = State(initialValue: OverviewLayoutPrefs.order)
        _hidden = State(initialValue: OverviewLayoutPrefs.hidden)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("自定义概览布局")
                    .font(.system(size: 15, weight: .bold))
                Text("拖拽调整卡片顺序；关掉开关可隐藏某张卡。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(order, id: \.self) { card in
                    row(card)
                }
                .onMove { from, to in
                    order.move(fromOffsets: from, toOffset: to)
                }
            }
            .listStyle(.inset)

            HStack {
                Button("恢复默认") {
                    order = OverviewCard.allCases
                    hidden = []
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                Spacer()
                Button("完成") {
                    OverviewLayoutPrefs.setOrder(order)
                    OverviewLayoutPrefs.setHidden(hidden)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 380, height: 460)
    }

    private func row(_ card: OverviewCard) -> some View {
        let isShown = !hidden.contains(card)
        return HStack(spacing: 10) {
            Image(systemName: card.icon)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(isShown ? Palette.accent : Palette.textTertiary)
            Text(card.title)
                .font(.system(size: 12))
                .foregroundStyle(isShown ? Palette.text : Palette.textSecondary)
            Spacer()
            Toggle("", isOn: binding(for: card))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.vertical, 2)
    }

    private func binding(for card: OverviewCard) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(card) },
            set: { shown in
                if shown { hidden.remove(card) } else { hidden.insert(card) }
            }
        )
    }
}

/// 概览页卡片的长按拖拽排序已改用手势实现，见 Views.swift 的 `dragCardGesture`。
/// （原先的 OverviewCardDropDelegate 基于 .onDrop，会在拖拽过程中持续重排导致整片
///  网格回流、并且压不住窗口随卡片一起被拖走，已移除。）

