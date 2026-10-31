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
                whatsNewRow("eye.fill", "新增「550W」限定主题", "《流浪地球》550W / MOSS 风格皮肤：白底 + 警示红，直角切角面板、工程图细网格、标题虚线分栏、标签改等宽代码写法（带 ▸ 前缀），温度环改「灰→红→深红」单色梯度。在「设置 → 外观」里选 550W 即可切换，其余三个主题完全不受影响。")
                whatsNewRow("textformat", "550W 标识与字幕条", "侧栏与「关于」页换成 550W 机号标（550 深色 + 红色 W）与电影字幕条「智能量子计算机 550W [MOSS] / INTELLIGENT QUANTUM COMPUTER」，素材取自你提供的矢量文件，按白底重新着色后内置进 App。")
                whatsNewRow("chart.xyaxis.line", "折线改平滑曲线", "概览与监控页所有统计曲线由折线（直线连点）改为过每个采样点的平滑曲线（Catmull-Rom 转三次贝塞尔），控制点夹在画布内，尖峰数据不会甩出边框。")
                whatsNewRow("menubar.rectangle", "菜单栏开关重排 + 图标区分", "「菜单栏」设置里的指标按 CPU → GPU → 内存 → 网络分组排列，同类挨在一起。GPU 占用率换成板卡形状的小显卡图标（原来是个显示器），GPU 功耗改成「方框里的闪电」，与 CPU 功耗的裸闪电一眼可分。")
                whatsNewRow("arrow.up.arrow.down", "性能与风扇页顺序调整", "「机型识别」卡片移到「风扇情况」下方，两条机型风险提示（不匹配 / 未能识别）紧随其后，不再夹在自定义曲线和说明之间。")
                whatsNewRow("rectangle.compress.vertical", "CPU / GPU 卡压缩 + 曲线加坐标轴", "两张宽卡内部重新排布：温度环 116→96、曲线 84/58→68/46、大数 19→17，并把原本上下两行的「频率/功耗」「功耗/显存」改成左右并排 —— 宽卡横向本来就有余量，竖着堆两整行是浪费，卡片高度少了约三分之一。所有曲线背景补上坐标轴：左竖轴 + 底横轴 + 虚线网格（网格密度随图形高度自动增减）。GPU 卡里重复显示的功耗/显存小字行已去掉。")
                whatsNewRow("bolt.shield", "修「开机静默下发无效」", "1.8.5 写的 sudoers 规则用双引号包了带空格的路径，sudo 判为非法、整份规则被拒读，所以开机后无论风扇还是功耗都没真正下发。现在改用反斜杠转义，并在落盘前用 visudo 校验（不通过就不写，避免连带影响其他 sudo）。同时：规则只在 App 移动 / 被清理 / 格式升级时才重装（以前每次登录都弹一次密码框），授权完成后立刻补发一次，设置页也会显示「上次自动下发」的结果。")
                whatsNewRow("network", "网络统计跟随系统", "总量改读内核 64 位网卡字节计数器（sysctl net.link.generic.ifdata，与系统统计同源，也不会像旧的 32 位计数那样超过 4 GiB 就回绕），基线存在本地 —— 退出或重启本程序后接着算，只有重启系统或点「重置统计」才归零。")
                whatsNewRow("paintpalette", "概览与监控页重新配色", "两项指标配一色：负载蓝、频率青、功耗橙、内存黄绿、风扇青绿、电池绿、磁盘灰蓝、GPU 紫、GPU 功耗粉、显存靛、网络天蓝。同一指标在概览与监控页同色，一眼对得上。概览「显卡」卡改名「GPU」。")
                whatsNewRow("menubar.rectangle", "菜单栏新增 GPU 功耗 / 显存占用", "「菜单栏」设置页多了两个可勾选指标，与温度、占用率一样可排序、可选上下行合并显示；未装 SMCNvidiaGPU 驱动时标为不可用并说明原因。")
                whatsNewRow("display", "显卡卡与 CPU 卡同构", "概览的显卡卡按 CPU 卡重做：温度改用仪表盘呈现，功耗与显存并入同一张卡（状态／占用率／功耗／显存 + 占用率、功耗、显存三条曲线）；监控页「实时」区另保留功耗与显存两张卡。macOS 没有 NVML、驱动也不上报功耗，这两项取自 SMCNvidiaGPU（zzzyy678）的二改驱动——它在内核侧读 GSP 的 RUSD 共享内存并挂成 sysctl，本程序只读不改。没装驱动时显示「—」。")
                whatsNewRow("bolt.shield", "开机静默应用配置", "「设置」新增「开机自动应用配置」：开启后，登录与睡眠唤醒时自动、无密码框地静默下发当前功耗墙和风扇曲线（首次开启需输入一次管理员密码，用于授权本程序的 CLI 免密以 root 运行；EC 在重启 / 唤醒后会重置配置，故两个时机都会重发）。")
                Divider().opacity(0.35)
                whatsNewRow("sparkles", "渲染与缩放缓动优化", "窗口缩放 / 最小化动画改为按需重排（松手才刷新，拖拽时直接缩放上一帧），卡顿消失；每张玻璃卡把装饰层拍平成单张纹理，滚动与悬停时复用，GPU 占用率不升却更跟手。")
                Divider().opacity(0.35)
                whatsNewRow("bolt.fill", "新增「功耗墙」档位", "替代原先不可用的「性能模式」：静音 25W / 平衡 30W / 性能 35W 随时可切，自定义 15–50W 默认上锁，需在「高级功能」确认风险后解锁；支持一键恢复默认。")
                Divider().opacity(0.35)
                whatsNewRow("slider.horizontal.3", "概览新增「当前模式」卡", "一张卡同时显示当前功耗墙档位与风扇档位，可在概览布局里隐藏或调序。")
                Divider().opacity(0.35)
                whatsNewRow("network", "新增「网络」页", "累计统计本次启动的上传 / 下载总量，显示实时速率与网卡接口，可一键重置。")
                Divider().opacity(0.35)
                whatsNewRow("display", "新增「高级功能」页", "一键开启 / 还原 HiDPI：写入显示器 Override，只改用户数据区、不动系统卷。")
                Divider().opacity(0.35)
                whatsNewRow("fanblades", "自定义风扇曲线", "可拖拽 8 点曲线，CPU / GPU 分别编辑与下发；默认关闭，需在「高级功能」确认风险后解锁。")
                Divider().opacity(0.35)
                whatsNewRow("slider.horizontal.3", "诊断能力判断修正", "风扇曲线 / Aura RGB / 性能模式（功耗墙）改按实际通道判断，不再写死「不可用」；移除显卡模式、充电上限、环境光三项。")
                Divider().opacity(0.35)
                whatsNewRow("waveform.path.ecg", "监控页整合", "原「传感器」页的温度曲线、内核计数器并入监控页，侧栏少一项。")
                Divider().opacity(0.35)
                whatsNewRow("cpu", "概览数据增强", "风扇卡显示 CPU / GPU 双转速；CPU 卡右侧改为负载曲线，可直接看负载起伏。")
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
