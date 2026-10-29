//
//  MonitorView.swift
//  监控页：实时指标、历史趋势、应用排行、手动录制
//

import SwiftUI
import AppKit

struct MonitorView: View {
    @EnvironmentObject var store: SensorStore

    @State private var window: Int = 300            // 秒
    @State private var sortByCPU = true
    @State private var recordLabel = ""
    @State private var selectedApp: (name: String, pid: Int32)?
    @State private var showAppPicker = false

    private var samples: [MetricSample] { store.samples(window: window) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            liveRow
            trendSection
            processSection
            recordSection
        }
        // 只有停在这一页时才枚举进程（500+ 进程一次约 2 ms，没必要每秒都跑）
        .onAppear { store.setProcessSamplingActive(true) }
        .onDisappear { store.setProcessSamplingActive(false) }
    }

    // MARK: - 实时

    private var liveRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "实时", trailing: "\(store.samplingRate.longLabel)采样 · 历史保留 15 分钟")
            HStack(spacing: 12) {
                liveTile(title: "CPU 温度",
                         value: store.cpuTemp.map { String(format: "%.1f", $0) } ?? "—",
                         unit: "°C",
                         sub: store.tempStatusText,
                         color: Palette.forTemp(store.cpuTemp),
                         series: samples.compactMap(\.temp),
                         lower: 35, upper: 100)
                liveTile(title: "CPU 负载",
                         value: String(format: "%.0f", store.load.total * 100),
                         unit: "%",
                         sub: "\(store.load.perCore.count) 线程 · 热压力 \(store.load.thermalText)",
                         color: Palette.accent2,
                         series: samples.map { $0.load * 100 },
                         lower: 0, upper: 100)
                liveTile(title: "内存占用",
                         value: String(format: "%.0f", store.load.memoryUsedRatio * 100),
                         unit: "%",
                         sub: memorySubtitle,
                         color: Palette.ok,
                         series: samples.map { $0.mem * 100 },
                         lower: 0, upper: 100)
            }
        }
    }

    private var memorySubtitle: String {
        let used = Double(store.load.memActive + store.load.memWired + store.load.memCompressed) / 1_073_741_824
        let total = Double(store.load.memTotal) / 1_073_741_824
        return String(format: "%.1f / %.0f GB · 交换 %.1f GB", used, total, Double(store.load.swapUsed) / 1_073_741_824)
    }

    private func liveTile(title: String, value: String, unit: String, sub: String,
                          color: Color, series: [Double], lower: Double, upper: Double) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold).monospacedDigit())
                        .foregroundStyle(color)
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
                Sparkline(values: series, color: color, lowerBound: lower, upperBound: upper)
                    .frame(height: 32)
                Text(sub)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - 趋势

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "趋势")
                Spacer()
                SegmentedButtons(items: [("1 分钟", 60), ("5 分钟", 300), ("15 分钟", 900)],
                                 selection: $window)
            }

            Card {
                VStack(spacing: 10) {
                    metricRow(name: "温度", unit: "°C", color: Palette.forTemp(store.cpuTemp),
                              values: samples.compactMap(\.temp), lower: 35, upper: 100,
                              current: store.cpuTemp)
                    Divider().opacity(0.35)
                    metricRow(name: "CPU", unit: "%", color: Palette.accent2,
                              values: samples.map { $0.load * 100 }, lower: 0, upper: 100,
                              current: store.load.total * 100)
                    Divider().opacity(0.35)
                    metricRow(name: "内存", unit: "%", color: Palette.ok,
                              values: samples.map { $0.mem * 100 }, lower: 0, upper: 100,
                              current: store.load.memoryUsedRatio * 100)
                    if store.recording?.appPID != nil {
                        Divider().opacity(0.35)
                        metricRow(name: "目标应用 CPU", unit: "%", color: Palette.warn,
                                  values: samples.compactMap { $0.appCPU.map { $0 * 100 } },
                                  lower: 0, upper: 100,
                                  current: samples.last?.appCPU.map { $0 * 100 })
                    }
                }
            }
        }
    }

    private func metricRow(name: String, unit: String, color: Color,
                           values: [Double], lower: Double, upper: Double,
                           current: Double?) -> some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 72, alignment: .leading)
            Sparkline(values: values, color: color, lowerBound: lower, upperBound: upper)
                .frame(height: 38)
                .frame(maxWidth: .infinity)
            Text(current.map { String(format: "%.1f", $0) } ?? "—")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.text)
                .frame(width: 58, alignment: .trailing)
            Text(unit)
                .font(.system(size: 9))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 18, alignment: .leading)
        }
        .frame(height: 42)
    }

    // MARK: - 应用排行

    private var processSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle(text: "应用", trailing: "按 \(sortByCPU ? "CPU" : "内存") 排序 · 每 2 秒刷新")
                Spacer()
                SegmentedButtons(items: [("CPU", true), ("内存", false)],
                                 selection: $sortByCPU)
            }

            Card(padding: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(topProcesses.enumerated()), id: \.element.id) { idx, p in
                        processRow(p)
                        if idx < topProcesses.count - 1 { Divider().opacity(0.25) }
                    }
                    if topProcesses.isEmpty {
                        Text("首次采样中…")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var topProcesses: [ProcSample] {
        ProcessSampler.top(store.processes, byCPU: sortByCPU, limit: 10)
    }

    private func processRow(_ p: ProcSample) -> some View {
        let maxCPU = max(topProcesses.map(\.cpu).max() ?? 1, 0.01)
        let frac = sortByCPU ? min(p.cpu / max(maxCPU, 0.01), 1) : min(p.memoryMB / max(topProcesses.map(\.memoryMB).max() ?? 1, 1), 1)
        return HStack(spacing: 10) {
            Text(p.name)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
            Text("pid \(p.pid)")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 62, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.trackFill)
                    Capsule()
                        .fill(selectedApp?.pid == p.pid ? Palette.warn : Palette.accent2.opacity(0.85))
                        .frame(width: max(2, geo.size.width * CGFloat(frac)))
                }
            }
            .frame(height: 6)
            Text(sortByCPU ? String(format: "%.0f%%", p.cpu * 100) : String(format: "%.0f MB", p.memoryMB))
                .font(.system(size: 10.5).monospacedDigit())
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedApp = (p.name, p.pid)
            if recordLabel.isEmpty { recordLabel = p.name }
        }
    }

    // MARK: - 录制

    private var recordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "录制", trailing: "把温度 / 负载 / 内存 / 目标应用记成 CSV")

            Card {
                if let rec = store.recording {
                    recordingActive(rec)
                } else {
                    recordingIdle
                }
            }

            if !store.recordings.isEmpty {
                Card(padding: 12) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.recordings.enumerated()), id: \.element.id) { idx, r in
                            recordingRow(r)
                            if idx < store.recordings.count - 1 { Divider().opacity(0.3) }
                        }
                    }
                }
            }
        }
    }

    private var recordingIdle: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    showAppPicker.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 10))
                        Text(selectedApp.map { "目标：\($0.name)" } ?? "绑定应用（可选）")
                    }
                }
                .buttonStyle(GrayButtonStyle())
                .popover(isPresented: $showAppPicker) {
                    AppPicker(processes: store.processes.sorted { $0.cpu > $1.cpu }) { picked in
                        selectedApp = picked
                        showAppPicker = false
                    }
                    .frame(width: 280, height: 320)
                }

                if selectedApp != nil {
                    Button("清除") { selectedApp = nil }
                        .buttonStyle(GrayButtonStyle())
                }

                Spacer()

                Text("将记录：温度 · 负载 · 内存\(selectedApp == nil ? "" : " · \(selectedApp!.name)")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)

                Button {
                    let name = selectedApp?.name ?? "系统"
                    store.startRecording(label: "\(name) · \(Self.stamp())",
                                         appName: selectedApp?.name,
                                         appPID: selectedApp?.pid)
                } label: {
                    Text("开始录制")
                }
                .buttonStyle(GrayButtonStyle(prominent: true))
            }
            Text("录制期间每秒记录一次温度、CPU 负载、内存占用；如果绑定了应用，还会记录该应用的 CPU 与常驻内存。停止后自动写成 CSV。")
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recordingActive(_ rec: ActiveRecording) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.bad)
                    .frame(width: 8, height: 8)
                Text("录制中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.bad)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.label)
                    .font(.system(size: 12, weight: .medium))
                Text("\(rec.appName.map { "目标 \($0)" } ?? "未绑定应用") · \(formatElapsed(rec.elapsed)) · \(rec.samples.count) 个采样")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button {
                _ = store.stopRecording()
            } label: {
                Text("停止并保存")
            }
            .buttonStyle(GrayButtonStyle(prominent: true))
        }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    private func recordingRow(_ r: RecordingSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label)
                    .font(.system(size: 11.5, weight: .medium))
                Text("\(r.appName.map { "\($0) · " } ?? "")\(r.durationText) · \(r.sampleCount) 采样")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 240, alignment: .leading)

            Text(String(format: "温度 %.1f / 峰值 %.1f °C", r.avgTemp, r.maxTemp))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
            Text(String(format: "负载 %.0f%% · 内存 %.0f%%", r.avgLoad * 100, r.avgMem * 100))
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            Button("打开") {
                NSWorkspace.shared.open(RecordingStore.fileURL(for: r))
            }
            .buttonStyle(GrayButtonStyle())
            Button("删除") { store.deleteRecording(r) }
                .buttonStyle(GrayButtonStyle())
        }
        .padding(.vertical, 5)
    }
}

/// 应用选择弹窗
struct AppPicker: View {
    let processes: [ProcSample]
    let onPick: ((name: String, pid: Int32)?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("选择要跟踪的应用")
                    .font(.system(size: 11.5, weight: .semibold))
                Spacer()
                Button("不绑定") { onPick(nil) }
                    .buttonStyle(GrayButtonStyle())
            }
            .padding(10)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(processes.prefix(40)) { p in
                        Button {
                            onPick((p.name, p.pid))
                        } label: {
                            HStack(spacing: 8) {
                                Text(p.name)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f%%", p.cpu * 100))
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(Palette.textSecondary)
                                Text("pid \(p.pid)")
                                    .font(.system(size: 9).monospacedDigit())
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider().opacity(0.2)
                    }
                }
            }
        }
    }
}
