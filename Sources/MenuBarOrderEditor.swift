//
//  MenuBarOrderEditor.swift
//  「菜单栏」页：拖动或点击箭头调整指标显示顺序
//

import SwiftUI

struct MenuBarOrderEditor: View {
    @Binding var selected: [MenuMetric]
    let onChange: () -> Void

    @State private var draggedMetric: MenuMetric?
    @State private var chipFrames: [MenuMetric: CGRect] = [:]

    private static let dragCoordinateSpace = "menu-bar-order"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("排列顺序")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 8)
                Text("拖动标签，或点击箭头调整")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(selected, id: \.self) { metric in
                        metricChip(metric)
                    }
                }
                .padding(.vertical, 1)
                .coordinateSpace(name: Self.dragCoordinateSpace)
                .onPreferenceChange(MenuBarChipFramePreferenceKey.self) {
                    chipFrames = $0
                }
            }
        }
    }

    private func metricChip(_ metric: MenuMetric) -> some View {
        let index = selected.firstIndex(of: metric) ?? 0
        let canMoveLeft = index > 0
        let canMoveRight = index < selected.count - 1

        return HStack(spacing: 5) {
            draggableLabel(for: metric)

            HStack(spacing: 1) {
                arrowButton(
                    "chevron.left",
                    help: "向左移动\(metric.title)",
                    enabled: canMoveLeft
                ) {
                    move(metric, by: -1)
                }
                arrowButton(
                    "chevron.right",
                    help: "向右移动\(metric.title)",
                    enabled: canMoveRight
                ) {
                    move(metric, by: 1)
                }
            }
            .padding(.trailing, 3)
            .padding(.vertical, 4)
        }
        .background(Capsule().fill(Palette.faintFill))
        .overlay(Capsule().strokeBorder(Palette.cardStroke, lineWidth: 1))
        .opacity(draggedMetric == metric ? 0.55 : 1)
        .scaleEffect(draggedMetric == metric ? 1.04 : 1)
        .shadow(color: draggedMetric == metric ? Color.black.opacity(0.18) : .clear,
                radius: 4, x: 0, y: 2)
        .zIndex(draggedMetric == metric ? 1 : 0)
        .contentShape(Capsule())
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MenuBarChipFramePreferenceKey.self,
                    value: [metric: proxy.frame(in: .named(Self.dragCoordinateSpace))]
                )
            }
        )
    }

    private func draggableLabel(for metric: MenuMetric) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 11, height: 18)
                .accessibilityHidden(true)

            Image(systemName: metric.menuBarIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .accessibilityHidden(true)

            Text(metric.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.text)
                .fixedSize()
        }
        .padding(.leading, 7)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 2,
                        coordinateSpace: .named(Self.dragCoordinateSpace))
                .onChanged { value in
                    if draggedMetric != metric {
                        withAnimation(.easeOut(duration: 0.1)) {
                            draggedMetric = metric
                        }
                    }
                    reorderIfNeeded(metric, pointerX: value.location.x)
                }
                .onEnded { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        draggedMetric = nil
                    }
                }
        )
        .help("拖动调整\(metric.title)的位置")
        .accessibilityLabel("拖动调整\(metric.title)的位置")
    }

    private func arrowButton(_ symbol: String, help: String,
                             enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 17, height: 17)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Palette.textSecondary : Palette.textTertiary.opacity(0.35))
        .disabled(!enabled)
        .help(help)
    }

    private func move(_ metric: MenuMetric, by offset: Int) {
        guard let from = selected.firstIndex(of: metric) else { return }
        let to = from + offset
        guard selected.indices.contains(to) else { return }

        var next = selected
        next.swapAt(from, to)
        withAnimation(.easeInOut(duration: 0.16)) {
            selected = next
        }
        onChange()
    }

    private func reorderIfNeeded(_ metric: MenuMetric, pointerX: CGFloat) {
        guard draggedMetric == metric,
              let from = selected.firstIndex(of: metric) else { return }

        let centers = selected.compactMap { item -> (MenuMetric, CGFloat)? in
            guard let frame = chipFrames[item] else { return nil }
            return (item, frame.midX)
        }
        guard let target = centers.min(by: {
            abs($0.1 - pointerX) < abs($1.1 - pointerX)
        })?.0,
        let to = selected.firstIndex(of: target),
        to != from else { return }

        var next = selected
        let item = next.remove(at: from)
        next.insert(item, at: min(to, next.count))
        withAnimation(.easeInOut(duration: 0.16)) {
            selected = next
        }
        onChange()
    }
}

private struct MenuBarChipFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MenuMetric: CGRect] = [:]

    static func reduce(value: inout [MenuMetric: CGRect],
                       nextValue: () -> [MenuMetric: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
