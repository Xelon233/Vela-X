//
//  MenuBarSettingsView.swift
//  「菜单栏」页：挑哪些指标显示在顶部菜单栏
//
//  原则：拿不到数据的项不给假数字，直接在列表里标「不可用 + 原因」并禁止勾选。
//  换机器或者装了新 kext 之后，这些项会自动变回可用。
//

import SwiftUI

struct MenuBarSettingsView: View {
    @EnvironmentObject var store: SensorStore
    @State private var selected: [MenuMetric] = MenuBarPrefs.enabled
    @State private var netMode: NetSpeedDisplay = MenuBarPrefs.netMode
    /// 正在长按拖拽的指标（预览界面排序用）
    @State private var draggingMetric: MenuMetric?
    /// 各标签在全局坐标系下的 frame，松手时用来判断落在哪个标签上
    @State private var dragFrames: [MenuMetric: CGRect] = [:]
    /// 编辑模式（iOS 小组件式）：开 = 窗口固定、预览标签可拖；关 = 窗口可拖、标签固定。
    @ObservedObject private var windowState = WindowState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题
            VStack(alignment: .leading, spacing: 6) {
                Text("菜单栏")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(0.4)
                Text("勾选想常驻在顶部菜单栏的监控项。勾得越少，标题栏越短；"
                     + "灰色项说明这台机器上拿不到数据，原因写在下面。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(text: "可显示的监控项",
                                 trailing: "\(selected.count)/\(MenuMetric.allCases.count) 已选")
                        .padding(.bottom, 4)

                    HStack(spacing: 4) {
                        Image(systemName: "hand.draw")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                        Text("勾选想要的指标；顺序在下方「标题栏预览」里点「排序」后拖动调整")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                    }
                    .padding(.bottom, 10)

                    ForEach(MenuMetric.allCases) { metric in
                        metricRow(metric)
                        if metric != MenuMetric.allCases.last {
                            Divider().opacity(0.5).padding(.vertical, 10)
                        }
                    }
                }
            }

            if selected.contains(.netSpeed) {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: "网速显示方式")
                        Picker("", selection: $netMode) {
                            ForEach(NetSpeedDisplay.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        // 单参数写法：双参数闭包是 macOS 14 才有的 API，
                        // 部署目标还是 13.0，用了会在老系统上崩
                        .onChange(of: netMode) { newValue in
                            MenuBarPrefs.setNetMode(newValue)
                        }

                        HStack(spacing: 5) {
                            Text("当前接口")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textTertiary)
                            Text(store.netSpeed.interfaceName.isEmpty
                                 ? "—" : store.netSpeed.interfaceName)
                                .font(.system(size: 10.5).monospaced())
                                .foregroundStyle(Palette.textSecondary)
                            Spacer()
                            Text("↓ \(store.netSpeed.down.asRate)  ↑ \(store.netSpeed.up.asRate)")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        SectionTitle(text: "标题栏预览")
                        Spacer()
                        Button {
                            windowState.isEditMode.toggle()
                        } label: {
                            Text(windowState.isEditMode ? "完成" : "排序")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(windowState.isEditMode ? Palette.accent : Palette.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(windowState.isEditMode ? Palette.accent.opacity(0.15) : Palette.faintFill))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(windowState.isEditMode ? Palette.accent : Palette.hairline, lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        if selected.isEmpty {
                            Text("Vela X")
                        } else {
                            ForEach(selected) { metric in
                                if let value = store.shortText(metric) {
                                    MenuBarMetricLabel(item: MenuBarItem(metric: metric, value: value),
                                                       iconSize: 13, valueSize: 14)
                                        .opacity(draggingMetric == metric ? 0.6 : 1)
                                        .scaleEffect(draggingMetric == metric ? 1.08 : (windowState.isEditMode ? 1.06 : 1.0))
                                        .animation(.easeInOut(duration: 0.12), value: draggingMetric)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .stroke(windowState.isEditMode ? Palette.accent.opacity(0.55) : Color.clear,
                                                        lineWidth: 1.2)
                                        )
                                        .collectFrame(id: metric)
                                        .gesture(windowState.isEditMode ? dragMetricGesture(metric) : nil)
                                }
                            }
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onPreferenceChange(FramePreferenceKey<MenuMetric>.self) { dragFrames = $0 }
                    .background(
                        RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    Text(windowState.isEditMode
                         ? "编辑中 · 拖动标签调整顺序，窗口已锁定；点「完成」恢复。"
                         : "这是状态栏上那个按钮现在的样子（仅图标 + 数据）。点「排序」进入编辑模式后拖拽调整顺序，窗口会临时锁定；项目太多会被系统截断，建议控制在 4 项以内。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(windowState.isEditMode ? Palette.accent : Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onAppear {
            // 可能在别处改过（比如 CLI），进来时重新读一次
            selected = MenuBarPrefs.enabled
            netMode = MenuBarPrefs.netMode
        }
        .onDisappear {
            // 离开菜单栏页时退出编辑模式，窗口恢复可拖动
            windowState.isEditMode = false
        }
    }

    // MARK: - 每一行

    private func metricRow(_ metric: MenuMetric) -> some View {
        let usable = store.isAvailable(metric)
        let value = store.menuValue(metric)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: metric.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                    .foregroundStyle(usable ? Palette.accent : Palette.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(metric.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(usable ? Palette.text : Palette.textSecondary)
                        if !usable {
                            Pill(text: "不可用", color: Palette.warn)
                        }
                    }
                    Text(metric.backend)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                }

                Spacer(minLength: 8)

                Text(value.text)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(usable ? Palette.text : Palette.textTertiary)

                Toggle("", isOn: binding(for: metric))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!usable)
            }

            if !usable, let reason = store.unavailableReason(metric) {
                Text(reason)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.warn.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
        }
    }

    private func binding(for metric: MenuMetric) -> Binding<Bool> {
        Binding(
            get: { selected.contains(metric) },
            set: { on in
                if on {
                    if !selected.contains(metric) { selected.append(metric) }
                } else {
                    selected.removeAll { $0 == metric }
                }
                MenuBarPrefs.setEnabled(selected)
            }
        )
    }
}

/// 菜单栏预览界面里的长按拖拽排序：把拖拽中的指标移到目标指标的位置。
/// 同样用手势实现（见 `dragMetricGesture`），避免拖拽时窗口被带跑、整行回流。
private extension MenuBarSettingsView {
    func dragMetricGesture(_ metric: MenuMetric) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { _ in
                if draggingMetric == nil { draggingMetric = metric }
            }
            .onEnded { value in
                defer { draggingMetric = nil }
                guard let target = dragFrames.first(where: { $0.key != metric && $0.value.contains(value.location) })?.key else { return }
                reorderMetric(metric, to: target)
            }
    }

    /// 把 metric 移动到 target 的位置（往下拖插到后面，往上拖插到前面）
    func reorderMetric(_ metric: MenuMetric, to target: MenuMetric) {
        guard let from = selected.firstIndex(of: metric),
              let to = selected.firstIndex(of: target), from != to else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            selected.remove(at: from)
            if from < to {
                if let idx = selected.firstIndex(of: target) { selected.insert(metric, at: idx + 1) }
                else { selected.append(metric) }
            } else {
                if let idx = selected.firstIndex(of: target) { selected.insert(metric, at: idx) }
                else { selected.insert(metric, at: 0) }
            }
        }
        MenuBarPrefs.setEnabled(selected)
    }
}
