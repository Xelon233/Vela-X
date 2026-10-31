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

    /// 每核占用率配色：低 → 高走「绿 → 蓝 → 黄 → 红」，与 CPU 负载的身份色（蓝）同源。
    /// 550W 换成「红的深浅」：占用越高越红，白底上一眼看出哪几个核在满载。
    private func color(for v: Double) -> Color {
        if Palette.isMoss {
            switch v {
            case ..<0.35: return Palette.mLoad.opacity(0.30)
            case ..<0.7: return Palette.mLoad.opacity(0.60)
            case ..<0.9: return Palette.accent2
            default: return Palette.accent
            }
        }
        switch v {
        case ..<0.35: return Palette.ok
        case ..<0.7: return Palette.mLoad
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
                    SectionTitle(text: "系统负载", trailing: store.samplingRate.label,
                                 color: Palette.mLoad, code: "COMPUTE")
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
                    Text(Palette.isMoss
                         ? "// MACH.KERNEL · 无需 kext"
                         : "Mach 内核计数器 · 无需 kext")
                        .font(Palette.isMoss
                              ? .system(size: 9.5, design: .monospaced)
                              : .system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.top, 2)
                }
                .frame(width: Palette.isMoss ? 212 : 200, alignment: .leading)

                CoreBars(values: store.load.perCore, height: 46)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    metric("热压力", store.load.thermalText,
                           color: store.load.thermal == .nominal ? Palette.ok : Palette.warn)
                    metric("负载", String(format: "%.2f %.2f %.2f",
                                        store.load.load1, store.load.load5, store.load.load15))
                    metric("内存", String(format: "%.0f%%", store.load.memoryUsedRatio * 100))
                }
                // 550W 的等宽字段名更长（LOAD.AVG），列宽要跟着放宽
                .frame(width: Palette.isMoss ? 172 : 130, alignment: .trailing)
            }
        }
    }

    private func metric(_ label: String, _ value: String, color: Color = Palette.text) -> some View {
        HStack(spacing: 6) {
            if Palette.isMoss {
                // 550W：右侧三项读作三个运行时字段
                Text(["热压力": "THERMAL", "负载": "LOAD.AVG", "内存": "MEM.USED"][label] ?? label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Palette.accent.opacity(0.78))
            } else {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
