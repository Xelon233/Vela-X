//
//  NetworkView.swift
//  网络页：本次启动累计的上传 / 下载总量 + 实时速率
//

import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var store: SensorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "网络流量", trailing: totalsTrailing, color: Palette.mNet, command: "net --flow")

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        totalStat("下载总量", store.netTotalDown,
                                  icon: "arrow.down.circle.fill", color: Palette.mNet)
                        Rectangle().fill(Palette.hairline).frame(width: 1, height: 46)
                        totalStat("上传总量", store.netTotalUp,
                                  icon: "arrow.up.circle.fill", color: Palette.mVRAM)
                    }

                    Divider().opacity(0.35)

                    HStack(spacing: 26) {
                        speed("当前下载", store.netSpeed.down)
                        speed("当前上传", store.netSpeed.up)
                        Spacer()
                        if !store.netSpeed.interfaceName.isEmpty {
                            Pill(text: store.netSpeed.interfaceName, color: Palette.textSecondary)
                        }
                    }

                    HStack(spacing: 10) {
                        Text(totalsFootnote)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("重置统计") { store.resetNetTotals() }
                            .buttonStyle(GrayButtonStyle())
                    }
                }
            }

            SectionTitle(text: "说明", command: "net --notes")
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("总量直接读内核的 64 位网卡字节计数器（sysctl net.link.generic.ifdata），与系统统计同源；基线存在本地，所以退出或重启本程序后接着算，只有重启系统或点「重置统计」才会归零。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("实时速率由相邻两次采样的计数器差值除以间隔得到，已排除回环接口。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - 文案

    /// 基线停在开机时刻 → 就是「自系统启动累计」；被「重置统计」推过 → 显示起点时间
    private var totalsSinceBoot: Bool {
        let boot = store.netSpeed.bootTime
        return boot > 0 && abs(store.netTotalsSince.timeIntervalSince1970 - boot) < 60
    }

    private var totalsTrailing: String {
        totalsSinceBoot ? "自系统启动累计"
                        : "自 \(store.netTotalsSince.formatted(date: .omitted, time: .shortened)) 起累计"
    }

    private var totalsFootnote: String {
        (totalsSinceBoot ? "系统开机起算 · 跟随系统计数器，重启本程序不重置"
                         : "统计自 \(store.netTotalsSince.formatted(date: .omitted, time: .shortened)) · 重启本程序不重置")
            + " · 每 \(store.samplingRate.rawValue) 秒刷新一次"
    }

    private func totalStat(_ label: String, _ bytes: Double,
                           icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(color)
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(ByteCountFormatter.vela.string(fromByteCount: Int64(max(bytes, 0))))
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func speed(_ label: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
            Text(value.asRate)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.text)
        }
    }
}
