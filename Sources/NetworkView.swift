//
//  NetworkView.swift
//  网络页：本次启动累计的上传 / 下载总量 + 实时速率
//

import SwiftUI

struct NetworkView: View {
    @EnvironmentObject var store: SensorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "网络流量", trailing: "自本次启动累计", color: Palette.teal)

            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 18) {
                        totalStat("下载总量", store.netTotalDown,
                                  icon: "arrow.down.circle.fill", color: Palette.accent2)
                        Rectangle().fill(Palette.hairline).frame(width: 1, height: 46)
                        totalStat("上传总量", store.netTotalUp,
                                  icon: "arrow.up.circle.fill", color: Palette.violet)
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
                        Text("统计自 \(store.netTotalsSince.formatted(date: .omitted, time: .shortened)) · 每 \(store.samplingRate.rawValue) 秒累加一次")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("重置统计") { store.resetNetTotals() }
                            .buttonStyle(GrayButtonStyle())
                    }
                }
            }

            SectionTitle(text: "说明")
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("总量由各采样点的瞬时速率 × 采样间隔累加得到，采样间隔越大数字越粗；程序休眠或采样暂停时不计入。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("实时速率取自各网卡字节计数器（getifaddrs），已排除回环接口。")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
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
