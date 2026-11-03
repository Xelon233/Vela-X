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

            SectionTitle(text: "更新日志", command: "changelog")
            whatsNewCard

            SectionTitle(text: "信息", command: "sysinfo --about")
            infoCard

            SectionTitle(text: "致谢", command: "credits")
            creditCard

            SectionTitle(text: "说明", command: "notes")
            disclaimerCard
        }
    }

    // MARK: - 更新日志

    /// 更新日志：一条一张小卡。
    ///
    /// ⚠️ **不要把十几条塞进同一张卡**：卡片装饰层会拍平成一张纹理（`drawingGroup`），
    /// 这张纹理在滚动时是**逐帧重画**的（采样里 `-[RBLayer display] → RootTexture::make_texture
    /// → nvk_AllocateMemory`，每帧重新分配一整块 1644×3400 的表面）。
    /// 1727pt 高的那张卡实测滚动每步 38~62ms（约 16fps，113/120 帧超预算），
    /// 拆成一条一张之后每步 <2ms。
    private var whatsNewCard: some View {
        // LazyVStack：切进这一页时只构建视口内的几张卡。13 条长文案的排版（逐行断行）很贵，
        // 一次全建完实测切页 200~560ms，改成按需构建后只算看得见的那几张。
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.releaseCards.enumerated()), id: \.offset) { _, group in
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(group.enumerated()), id: \.offset) { i, note in
                            if i > 0 { Divider().opacity(0.30) }
                            whatsNewRow(note.icon, note.title, note.detail)
                        }
                    }
                }
            }
        }
    }

    /// 每张卡放几条：卡太多会碎，太少又会退化成「一张巨卡」（见上面的注释）
    private static let releaseCards: [[(icon: String, title: String, detail: String)]] = {
        let all = releaseNotes
        var out: [[(icon: String, title: String, detail: String)]] = []
        var i = 0
        while i < all.count {
            out.append(Array(all[i..<min(i + 3, all.count)]))
            i += 3
        }
        return out
    }()

    private static let releaseNotes: [(icon: String, title: String, detail: String)] = [
        ("laptopcomputer", "适配枪神9 Plus（G815LM）", "接入该机型的键盘 / 风扇 / 功耗墙通道：键盘背光与灯效在 nkeyd 独占设备时改走 /var/run/nkeyd-aura.sock 转发；风扇新增 AsusECTool 的 EC 直写通道（读三颗风扇 tach、切 CMMV 三档），转速读数在 SMC 占位值时退回 EC tach；功耗墙新增 Intel RAPL（MSR 0x610）通道，可限定 15–50W 并支持登录保持。能力矩阵把「性能模式」与「功耗墙」拆成两条，各自按 EC / RAPL / SMC 判定，不再误报不可用。以上均为机器自适应：非 G815LM 机型保持原行为，本机（AMD）上这些通道优雅报不可用。"),
        ("rectangle.stack", "关于页不再卡顿", "更新日志原来全塞在一张 1727pt 高的卡里：卡片装饰层会拍平成一张纹理，而这张纹理在滚动时是逐帧重画的（每帧重新分配一整块 1644×3400 的表面），实测滚动每步 38~62ms，约 16fps。改成三条一张、并按需构建后，每步 5ms、90 分位 11ms，100 帧无一超 16.6ms。"),
        ("arrow.up.arrow.down", "滚动丝滑到 60fps", "把卡片落地影从 SwiftUI `.shadow` 换成画一次的静态纹理 —— 原来那个阴影会把整张卡的正文一起卷进离屏合成组，每次提交都要重新渲染 + 高斯模糊，滚动每步 8.9ms、90 分位 34ms（60fps 的预算是 16.6ms）。现在每步 1.1~1.5ms、90 分位 <3ms，连测 160 帧没有一帧超预算。深色 / 浅色主题另外藏掉了滚动视图顶部那 4 层实时模糊的「滚动口袋」（每步 8.3ms → 1.8ms）。同时修掉一个启动崩溃：窗口刚上屏那一拍不再一次性铺整页内容，避开 SwiftUI 属性图与 AppKit 通知的重入。"),
        ("speedometer", "550W 主题性能大修", "修掉 550W 下几处常驻吃 CPU 的「活层」：窗口不可见时装饰动画自动暂停；行星公转改由 Core Animation 驱动，4fps → 60fps 且主线程零刷新；页脚扫描线改图层动画；侧栏切页把「重建新页」挪出滑动动画窗口，切换不再掉帧；指针移到 Dock 上时自动暂停这些装饰动画，Dock 放大不再卡；装饰文字改用单一共享时钟，每秒只重排一次；侧栏去掉每行多余的 AppKit 焦点环视图，整窗图层 437 → 338，并清掉滚动区 4 层实时模糊。实测后台占用 9% → 1.5%、窗口可见 34% → 7%，空闲单核 5.7% → 2.2%。"),
        ("bolt.shield", "修复「开机静默下发不生效」", "三层问题叠在一起：① 免密规则的版本号被存成字符串、读取却按整数取，永远判定「未授权」，函数直接返回，连失败记录都没写；② 授权是否可用只看标志位、不看 `sudo -n` 真能不能跑通，规则被移走或改了指向也察觉不到；③ 从 build 目录直接运行 App 时会把免密规则改指到 build 路径，正式安装版反而失去权限。现在启动时先做一次非交互自检：通就自愈标记、不通且确认在 /Applications 才重装；结果与原因都会写在「设置」里。"),
        ("eye.fill", "新增「550W」限定主题", "《流浪地球》550W / MOSS 风格限定皮肤，在「设置 → 外观」切换：白底 + 警示红，切角工程面板、网格底纹与机号标 / 字幕条；概览改为终端形态（命令行标题、滚动输出、运行时长、扫描线），侧栏按电影术语命名，说明标签换大写英文缩写；背景是一层很淡的太阳系透图，侧栏可开关其公转；启动与切进主题各有过场。其余主题不受影响。"),
        ("bolt.shield", "开机静默应用配置", "登录与睡眠唤醒时自动、无密码框地下发当前功耗墙和风扇曲线（首次开启授权一次即可）。同时修复 1.8.5 因 sudoers 规则写法非法导致静默下发完全失效、并每次登录都弹一次密码框的问题。"),
        ("network", "网络统计", "新增「网络」页，显示实时速率与累计流量。总量改读内核 64 位网卡计数器，基线存在本地 —— 退出或重启程序后接着算，只有重启系统或手动重置才归零。"),
        ("menubar.rectangle", "菜单栏新增 GPU 功耗 / 显存占用", "两个可勾选的菜单栏指标，与温度、占用率一样可排序、可选合并显示；未装 SMCNvidiaGPU 驱动时标为不可用并说明原因。"),
        ("powerplug.fill", "新增「整机功耗」监测", "监控页「实时」新增整机功耗卡：CPU 整包 + GPU 合计（macOS 没有系统级功耗接口，只能把两路相加）。缺一路时自动退化为单项，并在副标题里注明「仅 CPU / 仅 GPU」，不会虚报。"),
        ("sparkles", "渲染与缩放性能优化", "每张卡片的装饰层拍平成单张纹理，滚动与缩放时复用，窗口动画不再掉帧。"),
        ("bolt.fill", "新增「功耗墙」档位", "替代原先不可用的「性能模式」：静音 25W / 平衡 30W / 性能 35W 随时可切，自定义 15–50W 默认上锁，需在「高级功能」确认风险后解锁。"),
        ("display", "新增「高级功能」页", "一键开启 / 还原 HiDPI：写入显示器 Override，只改用户数据区、不动系统卷。"),
        ("fanblades", "自定义风扇曲线", "可拖拽 8 点曲线，CPU / GPU 分别编辑与下发；默认关闭，需在「高级功能」确认风险后解锁。"),
        ("slider.horizontal.3", "诊断能力判断修正", "风扇曲线 / Aura RGB / 性能模式（功耗墙）改按实际通道判断，不再写死「不可用」。"),
    ]

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
            if Palette.isMoss {
                mossBrandRow
            } else {
                classicBrandRow
            }
        }
    }

    /// 550W：机号标 + 产品名 + 一句话简介 + 电影字幕条**压在同一行**，
    /// 读起来像一行播出的台标字幕（原来字幕另起一行，整块偏高）。
    private var mossBrandRow: some View {
        HStack(alignment: .center, spacing: 10) {
            // 关于页只留中文字幕条这一行（英文机号标已按需求去掉，避免和 Vela X 争视觉重心）
            MossCaption(width: 250)
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 1, height: 24)
                .padding(.horizontal, 2)
            Text(AppInfo.name)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Palette.text)
                .fixedSize()
            Pill(text: AppInfo.displayVersion, color: Palette.accent)
            Text(AppInfo.tagline)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            copyVersionButton
        }
    }

    private var classicBrandRow: some View {
        HStack(alignment: .center, spacing: 22) {
            // 用程序自身的图标（AppIcon.icns），而不是 ROG 品牌标
            Image(nsImage: Self.brandIcon)
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
            copyVersionButton
        }
    }

    /// 程序图标（摊平成单张位图）。
    /// ⚠️ 直接把 `NSApp.applicationIconImage` 塞进 `Image(nsImage:)`，会让 `ImageRenderer`
    /// 把**整页**渲染成一张全透明空图（只在离屏出图时发作，窗口里正常）。
    /// 先用位图上下文重画一遍再交给 SwiftUI，就没事了。
    static let brandIcon: NSImage = {
        let src = NSApp.applicationIconImage
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        let side: CGFloat = 128
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(side), pixelsHigh: Int(side),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return src }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        src.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let flat = NSImage(size: NSSize(width: side, height: side))
        flat.addRepresentation(rep)
        return flat
    }()

    private var copyVersionButton: some View {
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
                // 550W 皮肤下先来一句 MOSS 的原话（放在卡里，和免责声明同一块面板）
                if Palette.isMoss {
                    HStack(spacing: 6) {
                        Text("▮")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Palette.accent)
                        Text("「文明的命运取决于人类的选择。」")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.text)
                        Text("— MOSS")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.bottom, 2)
                    Divider().opacity(0.3)
                }

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
