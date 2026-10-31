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

            SectionTitle(text: "更新日志")
            whatsNewCard

            SectionTitle(text: "信息")
            infoCard

            SectionTitle(text: "致谢")
            creditCard

            SectionTitle(text: "说明")
            disclaimerCard
        }
    }

    // MARK: - 更新日志

    private var whatsNewCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 9) {
                whatsNewRow("eye.fill", "新增「550W」限定主题", "《流浪地球》550W / MOSS 风格皮肤，在「设置 → 外观」切换：白底 + 警示红，切角面板与工程图网格；内置 550W 机号标与电影字幕条；概览在该皮肤下改为终端形态（命令行标题、滚动输出、运行时长与扫描线）。其余三个主题不受影响。")
                Divider().opacity(0.35)
                whatsNewRow("bolt.shield", "开机静默应用配置", "登录与睡眠唤醒时自动、无密码框地下发当前功耗墙和风扇曲线（首次开启授权一次即可）。同时修复 1.8.5 因 sudoers 规则写法非法导致静默下发完全失效、并每次登录都弹一次密码框的问题。")
                Divider().opacity(0.35)
                whatsNewRow("network", "网络统计", "新增「网络」页，显示实时速率与累计流量。总量改读内核 64 位网卡计数器，基线存在本地 —— 退出或重启程序后接着算，只有重启系统或手动重置才归零。")
                Divider().opacity(0.35)
                whatsNewRow("menubar.rectangle", "菜单栏新增 GPU 功耗 / 显存占用", "两个可勾选的菜单栏指标，与温度、占用率一样可排序、可选合并显示；未装 SMCNvidiaGPU 驱动时标为不可用并说明原因。")
                Divider().opacity(0.35)
                whatsNewRow("sparkles", "渲染与缩放性能优化", "每张卡片的装饰层拍平成单张纹理，滚动与缩放时复用，窗口动画不再掉帧。")
                Divider().opacity(0.35)
                whatsNewRow("bolt.fill", "新增「功耗墙」档位", "替代原先不可用的「性能模式」：静音 25W / 平衡 30W / 性能 35W 随时可切，自定义 15–50W 默认上锁，需在「高级功能」确认风险后解锁。")
                Divider().opacity(0.35)
                whatsNewRow("display", "新增「高级功能」页", "一键开启 / 还原 HiDPI：写入显示器 Override，只改用户数据区、不动系统卷。")
                Divider().opacity(0.35)
                whatsNewRow("fanblades", "自定义风扇曲线", "可拖拽 8 点曲线，CPU / GPU 分别编辑与下发；默认关闭，需在「高级功能」确认风险后解锁。")
                Divider().opacity(0.35)
                whatsNewRow("slider.horizontal.3", "诊断能力判断修正", "风扇曲线 / Aura RGB / 性能模式（功耗墙）改按实际通道判断，不再写死「不可用」。")
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
                // 用程序自身的图标（AppIcon.icns），而不是 ROG 品牌标。
                // 550W 限定皮肤下换成 550W 的机号标，整页跟着换气质。
                if Palette.isMoss {
                    MossLogo(height: 34)
                        .frame(width: 112, alignment: .leading)
                } else {
                    Image(nsImage: NSApp.applicationIconImage
                          ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 46, height: 46)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(AppInfo.name)
                            .font(.system(size: 26, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(LinearGradient(colors: [Palette.text, Palette.text.opacity(0.7)],
                                                            startPoint: .top, endPoint: .bottom))
                            .shadow(color: Palette.isMoss ? .clear : Palette.accent.opacity(0.35),
                                    radius: Palette.isMoss ? 0 : 12, y: Palette.isMoss ? 0 : 2)
                        Pill(text: AppInfo.displayVersion, color: Palette.accent)
                    }
                    Text(AppInfo.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    // 550W 皮肤：把电影里那行字幕放到标语下面
                    if Palette.isMoss {
                        MossCaption(width: 300)
                            .padding(.top, 3)
                    }
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
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("GitHub")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 108, alignment: .leading)
                    Button {
                        open(AppInfo.githubURL)
                    } label: {
                        Text(AppInfo.githubDisplay)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .help("打开 \(AppInfo.githubURL)")
                    Spacer(minLength: 0)
                }
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

                Divider().opacity(0.35)

                creditRow(icon: "display",
                          title: "GPU 功耗与显存占用",
                          name: "zzzyy678 · SMCNvidiaGPU",
                          detail: "GPU功耗与显存占用来自该项目的二改驱动。它在内核侧借驱动入口读出 GSP 的 RUSD 共享内存并把结果挂成 sysctl，本程序只读取这些读数——macOS 没有 NVML，驱动也不上报功耗，否则这两项无从获取。",
                          action: ("打开项目", { open("https://github.com/zzzyy678/SMCNvidiaGPU") }))
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
