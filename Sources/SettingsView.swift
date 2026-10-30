//
//  SettingsView.swift
//  「设置」页：原本散落在侧栏底部的三项（开机自启 / 外观 / 采样间隔）统一收拢到这里。
//

import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: SensorStore
    @EnvironmentObject var theme: ThemeManager
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "常规")

            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    // 开机自启：登录时只在菜单栏起来，不弹主窗口
                    HStack(spacing: 10) {
                        Image(systemName: "power")
                            .font(.system(size: 13))
                            .foregroundStyle(launchAtLogin ? Palette.accent : Palette.textTertiary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开机自启")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.text)
                            Text("登录时自动在菜单栏启动，不弹主窗口")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: $launchAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .tint(Palette.accent)
                            .onChange(of: launchAtLogin) { on in
                                if let error = LaunchAtLogin.set(on) {
                                    launchError = error
                                    launchAtLogin = LaunchAtLogin.isEnabled
                                } else {
                                    launchError = nil
                                }
                            }
                    }
                    if let launchError {
                        Text(launchError)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SectionTitle(text: "外观")
            Card(padding: 16) {
                HStack(spacing: 8) {
                    ForEach(ThemeMode.allCases) { m in
                        Button {
                            theme.mode = m
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 14, weight: .medium))
                                Text(m.label)
                                    .font(.system(size: 11, weight: theme.mode == m ? .semibold : .regular))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                    .fill(theme.mode == m
                                          ? AnyShapeStyle(Palette.accent.opacity(0.22))
                                          : AnyShapeStyle(Palette.faintFill))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                    .strokeBorder(theme.mode == m ? Palette.accent.opacity(0.55) : .clear, lineWidth: 0.8)
                            )
                            .foregroundStyle(theme.mode == m ? Palette.accent : Palette.textSecondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("外观：\(m.label)")
                    }
                }
            }

            SectionTitle(text: "采样间隔")
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    SegmentedButtons(items: SamplingRate.allCases.map { ($0.label, $0) },
                                     selection: Binding(get: { store.samplingRate },
                                                        set: { store.setSamplingRate($0) }))
                        .help(store.samplingRate.summary)
                    Text(store.samplingRate.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("温度 / 负载曲线保留 \(SamplingRate.tempWindow) 秒，监控页历史保留 \(SamplingRate.historyWindow) 秒。")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
