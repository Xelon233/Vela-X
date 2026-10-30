//
//  AboutView.swift
//  「关于」页：版本、作者、致谢
//

import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject var store: SensorStore
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            brandCard

            SectionTitle(text: "本次更新")
            whatsNewCard

            SectionTitle(text: "信息")
            infoCard

            SectionTitle(text: "致谢")
            creditCard

            SectionTitle(text: "说明")
            disclaimerCard
        }
    }

    // MARK: - 本次更新

    private var whatsNewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                whatsNewRow("gearshape", "新增「设置」页", "侧栏底部的「开机自启 / 外观 / 采样间隔」统一收拢进独立的「设置」页，侧栏更清爽。")
                Divider().opacity(0.35)
                whatsNewRow("internaldrive", "概览新增「磁盘」卡", "监测启动宗卷的总容量、已用与剩余，占用率超 80% 起渐变预警。")
                Divider().opacity(0.35)
                whatsNewRow("menubar.rectangle", "菜单栏比例复位", "状态项字号 / 图标恢复原始比例（数值 12.5pt、图标 12pt），不再被压缩。")
                Divider().opacity(0.35)
                whatsNewRow("cpu", "CPU 温度 / 频率合并", "温度环与频率合为一张「CPU」卡，并以心电监护仪风格波形表示频率起伏。")
                Divider().opacity(0.35)
                whatsNewRow("bolt.fill", "功耗指标更名", "「整机功耗」因 GPU 功耗无公开接口，统一标注为「CPU 功耗」。")
                Divider().opacity(0.35)
                whatsNewRow("speedometer", "整体性能优化", "降低采样与重绘开销，减少 CPU / GPU / 内存占用。")
            }
        }
    }

    private func whatsNewRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.text)
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 品牌

    private var brandCard: some View {
        Card(padding: 20, accent: Palette.accent, glow: true) {
            HStack(alignment: .center, spacing: 22) {
                ROGLogo(height: 46)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(AppInfo.name)
                            .font(.system(size: 26, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(LinearGradient(colors: [Palette.text, Palette.text.opacity(0.7)],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: Palette.accent.opacity(0.35), radius: 12, y: 2)
                        Pill(text: AppInfo.displayVersion, color: Palette.accent)
                    }
                    Text(AppInfo.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppInfo.oneLine, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
                    } label: {
                        Text(copied ? "已复制" : "复制版本信息")
                    }
                    .buttonStyle(GrayButtonStyle())
                }
            }
        }
    }

    // MARK: - 信息

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                LabelValue(label: "版本", value: "\(AppInfo.displayVersion)  (build \(AppInfo.build))")
                LabelValue(label: "作者", value: AppInfo.author, mono: false)
                LabelValue(label: "构建时间", value: AppInfo.buildDateText)
                LabelValue(label: "系统", value: AppInfo.osVersion)
                LabelValue(label: "机型",
                           value: store.hardware.productName.isEmpty
                                  ? store.hardware.modelCode
                                  : "\(store.hardware.productName)  [\(store.hardware.modelCode)]",
                           mono: false)
                LabelValue(label: "处理器", value: store.hardware.cpu, mono: false)
            }
        }
    }

    // MARK: - 致谢

    private var creditCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                creditRow(icon: "wand.and.stars",
                          title: "灵感参考",
                          name: "\(AppInfo.helperName)  ·  \(AppInfo.helperAuthor)",
                          detail: "风扇曲线、性能模式、MUX、充电上限这些功能的取舍，以及对 ASUS ACPI/WMI 的理解，都来自这个 Windows 项目。本程序是 macOS 上的独立重写。",
                          action: ("打开项目", { open(AppInfo.helperURL) }))

                Divider().opacity(0.35)

                creditRow(icon: "paintpalette",
                          title: "UI 灵感",
                          name: AppInfo.uiInspiration,
                          detail: "深色底、四角切边面板、霓虹描边与大字数字的整体视觉，参考奥创中心的仪表台风格。",
                          action: nil)

                Divider().opacity(0.35)

                creditRow(icon: "bolt.fill",
                          title: "EC 灯效修复思路",
                          name: "angus666888",
                          detail: "提供 EC 层灯效修复思路，本项目的键盘背光 / Aura 通道握手因此得以在 macOS 上正确工作。",
                          action: ("打开主页", { open("https://github.com/angus666888?tab=repositories") }))
            }
        }
    }

    private func creditRow(icon: String, title: String, name: String,
                           detail: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Palette.accent)
                .frame(width: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 10))
                        .tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                }
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(GrayButtonStyle())
            }
        }
    }

    // MARK: - 说明

    private var disclaimerCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("本程序与 ASUSTeK 无关，也不是官方软件。所有硬件访问都走 macOS 已有的通道：AppleSMC（VirtualSMC + AsusSMC）、IORegistry、IOHID、libproc，不注入任何内核代码。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Pill(text: "MIT License", color: Palette.textSecondary)
                    Pill(text: "x86_64 + arm64", color: Palette.textSecondary)
                    Pill(text: "已采样 \(store.sampleCount) 次", color: Palette.textTertiary)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}
