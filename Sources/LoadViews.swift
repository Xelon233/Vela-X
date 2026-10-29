//
//  LoadViews.swift
//  内核计数器相关视图：每核占用条、负载卡片
//

import SwiftUI

/// 每核占用的小竖条
///
/// 用 Canvas 一次画完：原来是「每核一个 ZStack + 两条 RoundedRectangle + 阴影 + 隐式动画」，
/// 16 线程就是 48 个视图、32 个阴影，每个采样点全部重建一次，是滚动时的另一个卡顿源。
struct CoreBars: View {
    let values: [Double]
    var height: CGFloat = 42
    var spacing: CGFloat = 2
    var showLabels = false

    var body: some View {
        Canvas { ctx, size in
            guard !values.isEmpty else { return }
            let n = values.count
            let labelHeight: CGFloat = showLabels ? 10 : 0
            let barHeight = max(size.height - labelHeight, 1)
            let width = max((size.width - spacing * CGFloat(n - 1)) / CGFloat(n), 1)

            for i in 0..<n {
                let x = CGFloat(i) * (width + spacing)
                let track = CGRect(x: x, y: 0, width: width, height: barHeight)
                ctx.fill(Path(roundedRect: track, cornerRadius: 1.5), with: .color(Palette.trackFill))

                let v = min(max(values[i], 0), 1)
                let h = max(2, barHeight * CGFloat(v))
                let bar = CGRect(x: x, y: barHeight - h, width: width, height: h)
                ctx.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(color(for: v)))

                if showLabels {
                    let text = Text("\(i)")
                        .font(.system(size: 7).monospacedDigit())
                        .foregroundColor(Palette.textTertiary)
                    ctx.draw(text, at: CGPoint(x: x + width / 2, y: size.height - 4))
                }
            }
        }
        .frame(height: height)
    }

    private func color(for v: Double) -> Color {
        switch v {
        case ..<0.35: return Palette.ok
        case ..<0.7: return Palette.accent2
        case ..<0.9: return Palette.warn
        default: return Palette.bad
        }
    }
}

/// 概览页的负载卡片
struct LoadCard: View {
    @EnvironmentObject var store: SensorStore

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    SectionTitle(text: "系统负载", trailing: store.samplingRate.label)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", store.load.total * 100))
                            .font(.system(size: 24, weight: .semibold).monospacedDigit())
                        Text("%")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                        Text("\(store.load.perCore.count) 线程")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.leading, 4)
                    }
                    if store.loadHistory.count > 3 {
                        Sparkline(values: store.loadHistory.map { $0 * 100 },
                                  color: Palette.accent,
                                  lowerBound: 0, upperBound: 100)
                            .frame(height: 30)
                            .frame(maxWidth: 180)
                    } else {
                        Text("Mach 内核计数器 · 无需 kext")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                            .padding(.top, 2)
                    }
                }
                .frame(width: 200, alignment: .leading)

                CoreBars(values: store.load.perCore, height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    metric("热压力", store.load.thermalText,
                           color: store.load.thermal == .nominal ? Palette.ok : Palette.warn)
                    metric("负载", String(format: "%.2f %.2f %.2f",
                                        store.load.load1, store.load.load5, store.load.load15))
                    metric("内存", String(format: "%.0f%%", store.load.memoryUsedRatio * 100))
                }
                .frame(width: 130, alignment: .trailing)
            }
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = Palette.text) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textTertiary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
