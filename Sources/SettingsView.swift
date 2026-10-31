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
    @State private var silentApply = SilentApply.isEnabled
    @State private var silentError: String?

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

                    Divider()

                    // 开机自动应用配置：开机与唤醒时静默下发当前功耗墙 + 风扇曲线。
                    // 首次开启需输入一次管理员密码（装 sudoers 免密规则）；之后不再弹框。
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.shield")
                            .font(.system(size: 13))
                            .foregroundStyle(silentApply ? Palette.accent : Palette.textTertiary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("开机自动应用配置")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.text)
                            Text("开机与唤醒时静默下发当前功耗墙和风扇曲线（首次开启需输入一次管理员密码）")
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Toggle("", isOn: $silentApply)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.regular)
                            .tint(Palette.accent)
                            .onChange(of: silentApply) { on in
                                if on {
                                    if SilentApply.isAuthorized {
                                        Prefs.set(true, for: SilentApply.enabledKey)
                                        silentError = nil
                                    } else {
                                        // 首次开启：装 sudoers 免密规则（一次性管理员密码）
                                        let err = SilentApply.installAuthorization()
                                        if err == nil {
                                            Prefs.set(true, for: SilentApply.enabledKey)
                                            silentError = nil
                                        } else {
                                            silentApply = false
                                            silentError = err
                                        }
                                    }
                                } else {
                                    Prefs.set(false, for: SilentApply.enabledKey)
                                    silentError = nil
                                }
                            }
                    }
                    if let silentError {
                        Text(silentError)
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if silentApply {
                        // 上次真的发下去了没有 —— 以前这里没有任何反馈，
                        // 规则坏了（比如 sudoers 语法非法）也看不出来
                        if let last = SilentApply.lastResultText {
                            Text("上次自动下发：\(last)")
                                .font(.system(size: 10))
                                .foregroundStyle(last.contains("失败") ? Palette.bad : Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !SilentApply.isAuthorized {
                            Text("免密规则当前无效（App 移动过或规则被清理）：关掉再打开此开关可重新授权")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.warn)
                                .fixedSize(horizontal: false, vertical: true)
                        }
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
                            // 550W 是限定皮肤：角上挂一条「限定」斜带
                            .overlay(alignment: .topTrailing) {
                                if m == .moss { limitedRibbon }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous))
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
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled; silentApply = SilentApply.isEnabled }
    }
    /// 「限定」斜带：贴右上角斜挂，超出部分由卡片的 clipShape 裁掉，形成缎带效果
    private var limitedRibbon: some View {
        Text("限定")
            .font(.system(size: 7, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 2.5)
            // 缎带描述的是「550W 限定」，所以固定用 550W 的红，不跟随当前主题强调色
            .background(Color(hex: 0xC8102E))
            .rotationEffect(.degrees(45))
            // 缎带中心压在角上：斜条两端被卡片的 clipShape 裁掉，只剩中间一段 + 文字
            .offset(x: -15, y: 15)
            .allowsHitTesting(false)
    }


}
