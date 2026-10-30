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
                whatsNewRow("fanblades", "自定义风扇曲线", "可拖拽 8 点曲线，CPU / GPU 分别编辑与下发；默认关闭，需在「高级功能」确认风险后解锁。")
                Divider().opacity(0.35)
                whatsNewRow("display", "一键开启 HiDPI", "「高级功能」页写入显示器 Override，支持开启与还原，只改用户数据区、不动系统卷。")
                Divider().opacity(0.35)
                whatsNewRow("chart.line.uptrend.xyaxis", "概览增强", "风扇卡显示 CPU / GPU 双转速；显卡卡加入占用率折线；磁盘卡按占用分级配色。")
                Divider().opacity(0.35)
                whatsNewRow("waveform.path.ecg", "监控页整合", "原「传感器」页的温度曲线、内核计数器并入监控页，侧栏更精简。")
                Divider().opacity(0.35)
                whatsNewRow("paintpalette", "配色扩展", "新增紫 / 青 / 粉 / 靛 / 薄荷等分类色；菜单栏图标 13pt、网速最小单位 KB/s。")
                Divider().opacity(0.35)
                whatsNewRow("menubar.rectangle", "菜单栏与侧栏", "状态项恢复系统字体、图标按原比例显示；「菜单栏」与「键盘背光」顺序调整。")
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
                // 用程序自身的图标（AppIcon.icns），而不是 ROG 品牌标
                Image(nsImage: NSApp.applicationIconImage
                      ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 46, height: 46)

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
