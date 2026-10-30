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
    case cpuTemp     // CPU 温度（大卡）
    case power       // 整机功耗
    case cpuFreq     // CPU 频率
    case gpu         // 显卡（占用率 + 温度）
    case fan         // 风扇
    case battery     // 电池
    case keyboard    // 键盘背光
    case load        // 系统负载
    case capability  // 能力边界

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpuTemp:    return "CPU 温度"
        case .power:      return "整机功耗"
        case .cpuFreq:    return "CPU 频率"
        case .gpu:        return "显卡"
        case .fan:        return "风扇"
        case .battery:    return "电池"
        case .keyboard:   return "键盘背光"
        case .load:       return "系统负载"
        case .capability: return "能力边界"
        }
    }

    var icon: String {
        switch self {
        case .cpuTemp:    return "thermometer.medium"
        case .power:      return "bolt.fill"
        case .cpuFreq:    return "speedometer"
        case .gpu:        return "display"
        case .fan:        return "fanblades"
        case .battery:    return "battery.75"
        case .keyboard:   return "keyboard"
        case .load:       return "chart.bar.fill"
        case .capability: return "checklist"
        }
    }

    /// 是否占满整行（两列网格里占 2 列），窄卡只占 1 列两两并排
    var isWide: Bool {
        switch self {
        case .cpuTemp, .keyboard, .load, .capability: return true
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
        if let raw = Prefs.string(orderKey), !raw.isEmpty {
            let list = raw.split(separator: ",").compactMap { OverviewCard(rawValue: String($0)) }
            if !list.isEmpty { return list }
        }
        return OverviewCard.allCases
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

/// 概览页卡片的长按拖拽排序：把拖拽中的卡片移到目标卡片的位置
struct OverviewCardDropDelegate: DropDelegate {
    let target: OverviewCard
    @Binding var cards: [OverviewCard]
    @Binding var dragging: OverviewCard?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target,
              let from = cards.firstIndex(of: dragging),
              let to = cards.firstIndex(of: target), from != to else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            let card = cards.remove(at: from)
            cards.insert(card, at: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        OverviewLayoutPrefs.setOrder(cards)
        dragging = nil
        return true
    }
}
