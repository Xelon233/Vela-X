//
//  UIComponents.swift
//  设计系统 —— 参考 ROG 奥创中心（Armoury Crate）：深色底、切角面板、霓虹描边、大字数字
//

import SwiftUI

// MARK: - 配色

enum Palette {
    // 底色（深浅自适应，随主题切换自动解析）
    static let bg = Color.skin(0xF1F3F7, 0x05070B, 0xF2F3F5)
    static let bgSoft = Color.skin(0xE6EAF1, 0x0A0E15, 0xE7E9EC)
    /// 面板色不再用纯白 / 蓝灰：纯白太"实"，一叠上去就是白纸；
    /// 深色那对 0x161C27 / 0x0D121A 又偏灰蓝，视觉上是一层灰。
    /// 现在浅色走极浅的中性灰、深色压到近黑，配低透明度才是"一整块磨砂玻璃"。
    static let panelTop = Color.skin(0xFAFAFB, 0x0A0E13, 0xFFFFFF)
    static let panelBottom = Color.skin(0xF1F2F5, 0x070A0E, 0xF6F7F8)
    static let panelHi = Color.skin(0xE9EDF4, 0x1E2634, 0xECEEF0)

    // 品牌色：取 Finder 侧栏选中态用的那支蓝（系统 accent blue）——
    // 浅色 #007AFF、深色 #0A84FF。它比之前的靛蓝更「系统」，和 macOS 自绘控件同色，
    // 灰阶背景上也不会显得发紫。红依旧只留给「错误/危险」语义。
    static let accent = Color.skin(0x007AFF, 0x0A84FF, 0xC8102E)
    /// 次级强调色：系统色板里的 sky blue，和主蓝同族，做数字/标签的渐层
    static let accent2 = Color.skin(0x32ADE6, 0x64D2FF, 0xE4572E)
    static let ok = Color.skin(0x1DA45F, 0x2FD57C, 0x2E7D4F)
    static let warn = Color.skin(0xC77F00, 0xFFB020, 0xB26A00)
    static let bad = Color.skin(0xD62A3C, 0xFF3B4E, 0xA4161F)

    // 扩展色板：强调色仍是上面那支系统蓝，其余为「分类辅助色」，
    // 用于不同卡片 / 指标做区分，让整体色彩更丰富而不喧宾夺主。
    static let violet = Color.skin(0x7C5CFF, 0xA78BFA, 0x6B4E71)
    static let teal   = Color.skin(0x0FA890, 0x2DD4BF, 0x2F6F6B)
    static let pink   = Color.skin(0xE0529C, 0xFF6FB5, 0xA8322D)
    static let indigo = Color.skin(0x4F46E5, 0x818CF8, 0x4A6FA5)
    static let mint   = Color.skin(0x00A884, 0x34E0B4, 0x2E7D4F)

    // MARK: 指标配色（概览 / 监控 / 菜单栏共用）
    //
    // 一色一义：同一个指标在任何页面都是同一个颜色，靠色相而不是靠所在位置来区分。
    // 温度是唯一的例外 —— 它沿用 `forTemp` 的冷→热梯度，因为「红了就是烫」这件事
    // 比「这一栏是橙色的」更有信息量。其余指标各占一个色相，两两之间至少差 30° 色相角。
    //
    //   CPU 负载 / 内核计数器 → mLoad（蓝）
    //   CPU 频率              → mFreq（青）
    //   CPU 功耗              → mPower（琥珀）
    //   内存                  → mMem（黄绿）
    //   风扇                  → mFan（青绿）；GPU 那列跟随显卡用 mGPU
    //   电池                  → mBattery（绿）
    //   磁盘                  → mDisk（石板）
    //   显卡温度 / 占用率      → mGPU（紫）
    //   显卡功耗              → mGPUPow（粉）
    //   显存                  → mVRAM（靛）
    //   网络                  → mNet（天蓝）
    //   整机功耗              → mSysPower（玫红，CPU+GPU 合计）
    static let mLoad    = Color.skin(0x2F7BEF, 0x5C9DFF, 0xC8102E)
    static let mFreq    = Color.skin(0x06B6D4, 0x22D3EE, 0xE4572E)
    static let mPower   = Color.skin(0xD97706, 0xFBBF24, 0xB26A00)
    static let mMem     = Color.skin(0x65A30D, 0xA3E635, 0x5C6B7A)
    static let mFan     = Color.skin(0x14B8A6, 0x2DD4BF, 0x2F6F6B)
    static let mBattery = Color.skin(0x22C55E, 0x4ADE80, 0x2E7D4F)
    static let mDisk    = Color.skin(0x64748B, 0x94A3B8, 0x6E7378)
    static let mGPU     = Color.skin(0xA855F7, 0xC084FC, 0x8C1C13)
    static let mGPUPow  = Color.skin(0xEC4899, 0xFF6FB5, 0xA8322D)
    static let mVRAM    = Color.skin(0x6366F1, 0x8B93FF, 0x6B4E71)
    static let mNet     = Color.skin(0x0EA5E9, 0x38BDF8, 0x4A6FA5)
    /// 整机功耗（CPU 整包 + GPU 合计）—— 比 CPU 功耗的琥珀更深一档，读作「总和」
    static let mSysPower = Color.skin(0xB91C1C, 0xF87171, 0x6E1210)

    // 文字
    static let text = Color.skin(0x1B2331, 0xE9F0FA, 0x14161A)
    static let textSecondary = Color.skin(0x52627A, 0xA3B2C6, 0x4C5259)
    static let textTertiary = Color.skin(0x8B98AB, 0x6C7C92, 0x878D95)

    // 描边 / 填充语义色
    /// 卡片描边：卡片变透明后全靠这道边勾轮廓，比填充透明度低的时候要更明显一点
    static let cardStroke = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.11, darkOpacity: 0.09, mossOpacity: 0.16)
    static let subtle = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.05, darkOpacity: 0.04, mossOpacity: 0.05)
    /// 按钮胶囊等弱填充
    static let faintFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.07, mossOpacity: 0.05)
    /// 分隔线、边框
    static let hairline = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.10, darkOpacity: 0.08, mossOpacity: 0.13)
    /// 窗口底色薄纱：整窗只压这一层纯色，光晕/色调全部来自壁纸
    /// （深色 = 黑纱压暗、浅色 = 白纱提亮，都保留壁纸原有的色相，
    ///  所以同一套界面在不同壁纸下会呈现不同氛围。透明度别超过 0.3，
    ///  再高就把壁纸盖死，反而变成一块实色板。）
    static let veil = Color.skin(0xFFFFFF, 0x000000, 0xFFFFFF, lightOpacity: 0.00, darkOpacity: 0.02, mossOpacity: 0.9)
    /// 温度环底环 / 刻度
    static let ringBase = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.08, darkOpacity: 0.06, mossOpacity: 0.1)
    static let ringTick = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.18, darkOpacity: 0.16, mossOpacity: 0.22)
    /// 滑杆 / 电量条轨道
    static let trackFill = Color.skin(0x000000, 0xFFFFFF, 0x000000, lightOpacity: 0.07, darkOpacity: 0.06, mossOpacity: 0.06)

    /// 当前是否为「550W」限定皮肤。样式分支（直角 / 角标 / 网格背景）都读这个。
    static var isMoss: Bool { SkinFlag.moss }

    /// 整体统一圆角（macOS 26 Liquid Glass 组件标准，连续圆角），与 Safari 内控件一致。
    /// 550W 是工业仪表盘风格，圆角压到 4 —— 直角 + 细线是这套主题的骨架。
    static var cornerRadius: CGFloat { isMoss ? 4 : 12 }

    static func forTemp(_ t: Double?) -> Color {
        guard let t else { return textSecondary }
        // 550W：温度只走「灰 → 红 → 深红」，越热越深、越像警报
        if isMoss {
            switch t {
            case ..<55: return textTertiary
            case ..<72: return accent2
            case ..<85: return accent
            default: return bad
            }
        }
        switch t {
        case ..<55: return ok
        case ..<72: return accent2
        case ..<85: return warn
        default: return bad
        }
    }

    static func forStatus(_ s: CapStatus) -> Color {
        switch s {
        case .available: return ok
        case .limited: return warn
        case .unavailable: return textTertiary
        }
    }

    /// 磁盘占用率配色：石板 → 黄 → 红（不用绿色，避免和「健康/够用」混淆；
    /// 也不用靛/紫，那两支已经给显存和显卡了）
    static func forDisk(_ f: Double) -> Color {
        switch f {
        case ..<0.7: return mDisk
        case ..<0.9: return warn
        default: return bad
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - 切角面板形状
// MARK: - 面板

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    /// 可选强调色：左侧会亮一条霓虹短线
    var accent: Color?
    /// 是否带外发光（仅重要卡片开启，避免整页发光过重）
    var glow: Bool = false
    /// 圆角（Liquid Glass 大圆角 + 连续曲线）
    var radius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    /// 缩放期间关掉投影：阴影是离屏模糊，7 张卡每帧各重算一次，是缩放掉帧的大头之一
    @ObservedObject private var visibility = WindowVisibility.shared
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            // 装饰层：纯形状 / 渐变 / 描边，不含任何交互控件（Toggle/Slider/Button 都在 content 里）。
            // 整层一次性拍平成一张 Metal 纹理（drawingGroup）：滚动 / 悬停 / 透明度过渡时
            // 复用这张纹理，不再每帧重新混合「填充 + 高光 + 描边 + 霓虹竖条 + 竖条阴影」五层矢量；
            // 这正是之前整页卡顿、GPU 占用率不高却窗口合成掉帧的根因（阴影离屏模糊很贵，卡一多成负担）。
            // 控件留在 content，不参与拍平，所以照常可点；只拍平装饰层则规避了黄底禁止符号的坑。
            glassShape
                .fill(glassFill)
                .overlay(glassShape.fill(topSheen))
                .overlay(glassShape.strokeBorder(glassEdge, lineWidth: 1))
                .overlay {
                    // 550W：沿着两处大斜边加一段红边，比四角角标更贴合切角轮廓
                    if Palette.isMoss {
                        // 斜边红条缓慢呼吸：整个 550W 界面唯一的「活」的装饰
                        MossDecorGate { MossAccentPulse(cut: 13) }
                    }
                }
                .overlay {
                    // 550W 面板装饰：四角定位刻线 + 顶部斜纹带 + 左缘标尺 + 底部虚线。
                    // 纯静态，和填充/描边一起被拍平进同一张纹理，不参与逐帧绘制。
                    if Palette.isMoss {
                        MossDecorGate { MossPanelDecor() }
                    }
                }
                .overlay(alignment: .leading) {
                    if let accent {
                        LinearGradient(colors: [accent, accent.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(width: 2)
                            .shadow(color: accent.opacity(0.7), radius: 5)
                            .padding(.vertical, 18)
                            .offset(x: 1)
                    }
                }
                .drawingGroup(opaque: false, colorMode: .extendedLinear)
            content
                .padding(padding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 外发光仍是实时阴影（glow 卡才给）；其余卡不发光，靠描边与玻璃分层，观感几乎无差。
        // 550W 不发光（白底上光晕会糊），但给一层很浅的落地影：面板像真的搁在纸面上。
        // 只做一层（radius 9 / y 3），不再叠第二层接触影 —— 7 张卡各两道离屏模糊会立刻把
        // 之前优化掉的合成开销加回来，一层已经足够撑起层次。
        .shadow(color: visibility.isBusy ? .clear : shadowColor,
                radius: visibility.isBusy ? 0 : shadowRadius,
                x: 0, y: shadowY)
    }

    /// 550W 用一层浅投影撑层次；其它主题维持原样（glow 卡才有彩色外发光）
    private var shadowColor: Color {
        if Palette.isMoss { return Color.black.opacity(0.085) }
        return glow ? Palette.accent.opacity(scheme == .light ? 0.07 : 0.10) : .clear
    }
    private var shadowRadius: CGFloat {
        if Palette.isMoss { return 9 }
        return glow ? 7 : 0
    }
    private var shadowY: CGFloat {
        if Palette.isMoss { return 3 }
        return glow ? 3 : 0
    }

    private var glassShape: PanelShape {
        // 550W 走「切角矩形」：四角各切一刀、大小交替，像被裁过的仪表面板；
        // 其余主题保持 Liquid Glass 的大圆角。
        PanelShape(radius: radius, cut: Palette.isMoss ? 13 : 0)
    }
    /// 半透明玻璃填充：卡片只是「一层玻璃」，不是实心面板。
    /// 透明度直接决定玻璃观感 —— 太实就退化成一堆磨砂色块，桌面和背景光晕全被压死。
    /// 浅色 0.24/0.17、深色 0.15/0.11：整窗读起来是同一块磨砂玻璃，
    /// 卡片靠描边和一丝明暗差分层，而不是靠"白纸叠在灰纸上"。
    /// 550W 例外：它就是「白纸叠在浅灰纸上」，用近实心白才有工程图的感觉。
    private var glassFill: LinearGradient {
        if Palette.isMoss {
            return LinearGradient(colors: [Color.white.opacity(0.97), Color.white.opacity(0.90)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return scheme == .light
            ? LinearGradient(colors: [Palette.panelTop.opacity(0.24), Palette.panelBottom.opacity(0.17)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Palette.panelTop.opacity(0.15), Palette.panelBottom.opacity(0.11)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 顶部镜面高光。
    /// 这层和上面的填充在 GPU 上不会真的各画一遍：整张卡最后被 drawingGroup
    /// 拍平成一张纹理，分层只是写起来清楚。
    private var topSheen: LinearGradient {
        if Palette.isMoss {
            // 白底上再打白光等于没打，直接收掉
            return LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.09 : 0.025), .clear],
                              startPoint: .top, endPoint: .init(x: 0.5, y: 0.30))
    }
    /// 玻璃边缘描边：上沿更亮，模拟 Liquid Glass 的折射亮边
    private var glassEdge: LinearGradient {
        if Palette.isMoss {
            return LinearGradient(colors: [Color.black.opacity(0.20),
                                           Color.black.opacity(0.12),
                                           Color.black.opacity(0.20)],
                                  startPoint: .top, endPoint: .bottom)
        }
        return scheme == .light
            ? LinearGradient(colors: [Color.white.opacity(0.90),
                                      Color.black.opacity(0.07),
                                      Color.black.opacity(0.12)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color.white.opacity(0.34),
                                      Color.white.opacity(0.05),
                                      Color.white.opacity(0.14)],
                             startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - 标题

struct SectionTitle: View {
    let text: String
    var trailing: String?
    /// 左侧小竖条的颜色（默认系统蓝；不同板块可传分类辅助色）
    var color: Color = Palette.accent
    /// 550W 皮肤下的子系统代号，会以 `// CODE · 说明` 的形式出现在右侧
    var code: String?
    /// 550W 皮肤下把标题渲染成终端命令行（如 `➜ cpu --stat`）
    var command: String?

    @ViewBuilder
    var body: some View {
        if Palette.isMoss, let command {
            terminalTitle(command)
        } else {
            classicTitle
        }
    }

    /// 550W：`➜ cmd` + 虚线 + `// 注释`，卡片读起来像一次命令的调用与输出
    private func terminalTitle(_ command: String) -> some View {
        HStack(spacing: 6) {
            Text("➜")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            // 550W：命令一律大写（CPU --STAT），像机器自己的表单，而不是人手敲的
            Text(command.uppercased())
                .font(MossFont.display(12.5))
                .tracking(0.2)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            DashedRule()
                .stroke(Palette.accent.opacity(0.22),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .layoutPriority(-1)
            if let trailing {
                Text("// \(MossText.codeList(trailing))")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var classicTitle: some View {
        HStack(alignment: .center, spacing: 8) {
            if Palette.isMoss {
                // 550W：红色实心小方块 + 一条细横线，像仪表盘上的通道标记
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                Rectangle()
                    .fill(Palette.accent.opacity(0.35))
                    .frame(width: 10, height: 1)
            } else {
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(colors: [color, color.opacity(0.15)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 2.5, height: 12)
                    .shadow(color: color.opacity(0.45), radius: 3)
            }
            Text(text)
                .font(.system(size: 12.5, weight: Palette.isMoss ? .bold : .semibold))
                .tracking(Palette.isMoss ? 1.6 : 0.6)
                .foregroundStyle(Palette.isMoss ? color : Palette.text)
                // 标题绝不允许换行：550W 下中间有虚线占位，不给死宽度就会被挤成两行
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if Palette.isMoss {
                // 工程图式虚线分栏：把标题和右侧注释连起来
                DashedRule()
                    .stroke(Palette.accent.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(-1)
            } else {
                Spacer()
            }
            if let trailing {
                // 550W：右侧注释改成「// …」的代码注释写法
                Text(Palette.isMoss
                     ? "// \(code.map { "\($0) · " } ?? "")\(MossText.codeList(trailing))"
                     : trailing)
                    .font(Palette.isMoss
                          ? .system(size: 9.5, design: .monospaced)
                          : .system(size: 10).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
                    .tracking(Palette.isMoss ? 0.3 : 0)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - 550W 字体与雷达仪表

/// 550W 的显示字体：DIN Alternate Bold —— 车站/机场牌与车载仪表用的那款，
/// 数字笔画平直、对比强，读起来像「机器在报数」。中文自动回落到系统字体。
enum MossFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("DINAlternate-Bold", size: size).weight(weight)
    }
    /// 数字（尺寸略大时字面更饱满）
    static func number(_ size: CGFloat) -> Font {
        .custom("DINAlternate-Bold", size: size)
    }
}

/// 550W 的温度「阴影」仪表：
///   不再来回扫描。一圈温度色的实心弧（从正上方顺时针，长度 = 当前温度占比）
///   配一道更粗、更透明的同色「晕」，读起来像热度在表盘上留下的一团雾；
///   弧尾一颗柔光落点标出此刻温度。中心仍是温度数字。
/// 纯静态 —— 角度不随时间变，不挂 TimelineView，也就没有逐帧重绘。
struct MossTempShadow: View {
    let value: Double?
    var size: CGFloat = 96

    private var fraction: Double {
        guard let v = value else { return 0 }
        return min(max((v - 30) / 70, 0), 1)
    }
    /// 温度色：冷 → 热，越热越红（沿用 Palette.forTemp 的语义，但不在 moss 里走灰红梯度）
    private var tempColor: Color {
        guard let v = value else { return Palette.textTertiary }
        if v < 55 { return Palette.mFreq }      // 冷：青
        if v < 72 { return Palette.accent2 }    // 温：橙
        if v < 85 { return Palette.accent }     // 热：红
        return Palette.bad                      // 烫：深红
    }

    var body: some View {
        Canvas { ctx, s in draw(ctx, s) }
            .frame(width: size, height: size)
            .overlay(alignment: .center) { centerLabel }
    }

    private var centerLabel: some View {
        VStack(spacing: -2) {
            // 中心读数用回原字体（DIN 等宽数字）；Text 比七段液晶体 Canvas 自绘更省，
            // 传感器每次刷新只需重画一次文本而非十几段矩形。
            Text(value.map { String(format: "%.0f", $0) } ?? "—")
                .font(MossFont.number(size * 0.30))
                .foregroundStyle(value == nil ? Palette.textSecondary : Palette.text)
            Text("°C")
                .font(.system(size: size * 0.10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private func draw(_ ctx: GraphicsContext, _ s: CGSize) {
        let center = CGPoint(x: s.width / 2, y: s.height / 2)
        let r = min(s.width, s.height) / 2 - 4

        // 底圈与内圈（淡墨，不再用红）
        for (k, o) in [(1.0, 0.10), (0.62, 0.06)] {
            let rr = r * k
            let rect = CGRect(x: center.x - rr, y: center.y - rr, width: rr * 2, height: rr * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.text.opacity(o)), lineWidth: 1)
        }

        // 刻度：每 15° 一根，90° 处加长
        var ticks = Path()
        for i in 0 ..< 24 {
            let a = Double(i) / 24 * 2 * Double.pi - Double.pi / 2
            let long = i % 6 == 0
            let outer = r - 1
            let inner = outer - (long ? 7 : 3.5)
            ticks.move(to: CGPoint(x: center.x + cos(a) * outer, y: center.y + sin(a) * outer))
            ticks.addLine(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
        }
        ctx.stroke(ticks, with: .color(Palette.text.opacity(0.18)), lineWidth: 1)

        guard let _ = value else { return }

        // 温度弧：正上方起，顺时针，长度 = fraction
        let a0 = -90 * Double.pi / 180
        let a1 = (fraction * 360 - 90) * Double.pi / 180
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .radians(a0),
                   endAngle: .radians(a1), clockwise: false)
        // 「阴影」晕：同一道弧再画一遍，更粗更透明 —— 热度留下的雾
        ctx.stroke(arc, with: .color(tempColor.opacity(0.16)), lineWidth: 13)
        // 实心弧
        ctx.stroke(arc, with: .color(tempColor.opacity(0.95)), lineWidth: 6)

        // 弧尾柔光落点：当前温度的「阴影」落点
        let ex = center.x + cos(a1) * r
        let ey = center.y + sin(a1) * r
        var halo = Path()
        halo.addArc(center: CGPoint(x: ex, y: ey), radius: 9,
                    startAngle: .radians(0), endAngle: .radians(Double.pi * 2), clockwise: false)
        ctx.fill(halo, with: .color(tempColor.opacity(0.22)))
        var dot = Path()
        dot.addArc(center: CGPoint(x: ex, y: ey), radius: 4,
                   startAngle: .radians(0), endAngle: .radians(Double.pi * 2), clockwise: false)
        ctx.fill(dot, with: .color(tempColor))
    }
}
struct LabelValue: View {
    let label: String
    let value: String
    var mono = true
    var color: Color = Palette.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 108, alignment: .leading)
            Text(value)
                .font(mono ? .system(size: 11.5).monospaced() : .system(size: 11.5))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 温度环（霓虹仪表）

struct TempRing: View {
    let value: Double?
    var size: CGFloat = 132
    var lineWidth: CGFloat = 9

    private var fraction: Double {
        guard let v = value else { return 0 }
        return min(max((v - 30) / 70, 0.02), 1.0)
    }

    // 用 Canvas 分段描边代替 AngularGradient：
    // 锥形渐变会被 CoreGraphics 逐像素软件光栅化（rgba64_shade_conic_RGB），
    // 一圈 280×280 的环单次重绘就要几十毫秒；分段实色描边几乎零成本。
    var body: some View {
        Canvas { ctx, canvasSize in
            drawBase(ctx, canvasSize)
            drawTicks(ctx, canvasSize)
            drawProgress(ctx, canvasSize)
            drawLabels(ctx, canvasSize)
        }
        .frame(width: size, height: size)
    }

    private func geometry(_ canvasSize: CGSize) -> (center: CGPoint, radius: CGFloat) {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let radius = min(canvasSize.width, canvasSize.height) / 2 - lineWidth / 2 - 6
        return (center, radius)
    }

    private func drawBase(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let rect = CGRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)
        ctx.stroke(Path(ellipseIn: rect), with: .color(Palette.ringBase), lineWidth: lineWidth)
    }

    private func drawTicks(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        var ticks = Path()
        for i in 0..<24 {
            let angle: Double = Double(i) / 24 * 2 * Double.pi - Double.pi / 2
            let length: CGFloat = i % 6 == 0 ? 6 : 3.5
            let outer: CGFloat = radius - lineWidth / 2 - 4
            let inner: CGFloat = outer - length
            ticks.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer,
                                   y: center.y + CGFloat(sin(angle)) * outer))
            ticks.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner,
                                      y: center.y + CGFloat(sin(angle)) * inner))
        }
        ctx.stroke(ticks, with: .color(Palette.ringTick), lineWidth: 1)
    }

    private func drawProgress(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let total = fraction
        guard total > 0.005 else { return }
        let segments = 72
        for i in 0..<segments {
            let t0 = Double(i) / Double(segments)
            if t0 >= total { break }
            let t1 = min(Double(i + 1) / Double(segments), total)
            let startAngle = Angle.radians(t0 * 2 * Double.pi - Double.pi / 2)
            let endAngle = Angle.radians(t1 * 2 * Double.pi - Double.pi / 2 + 0.02)
            var arc = Path()
            arc.addArc(center: center, radius: radius,
                       startAngle: startAngle, endAngle: endAngle, clockwise: false)
            let style = StrokeStyle(lineWidth: lineWidth,
                                    lineCap: t1 >= total ? CGLineCap.round : CGLineCap.butt)
            ctx.stroke(arc, with: .color(TempRing.color(at: t0)), style: style)
        }
    }

    private func drawLabels(_ ctx: GraphicsContext, _ canvasSize: CGSize) {
        let (center, radius) = geometry(canvasSize)
        let numberSize = canvasSize.width * 0.30
        let number = Text(value.map { String(format: "%.0f", $0) } ?? "—")
            .font(.system(size: numberSize, weight: .bold).monospacedDigit())
            .foregroundColor(Palette.text)
        ctx.draw(number, at: CGPoint(x: center.x, y: center.y - 2), anchor: .center)

        let unit = Text("°C")
            .font(.system(size: canvasSize.width * 0.10, weight: .medium))
            .foregroundColor(Palette.textTertiary)
        ctx.draw(unit, at: CGPoint(x: center.x, y: center.y + radius * 0.42), anchor: .center)
    }

    /// 冷→热四段插值（原来是 AngularGradient 的色标）
    static func color(at t: Double) -> Color {
        // 550W：整环只在红–灰之间走，越热越深，没有青绿，符合「白底红警觉」的设定
        let stops: [(Double, Double, Double, Double)] = Palette.isMoss
            ? [(0.00, 0xC9, 0xCD, 0xD2),
               (0.45, 0xD9, 0x53, 0x4F),
               (0.72, 0xC8, 0x10, 0x2E),
               (1.00, 0x7A, 0x0C, 0x16)]
            : [(0.00, 0x2A, 0xD4, 0xEE),
               (0.45, 0x2F, 0xD5, 0x7C),
               (0.72, 0xFF, 0xB0, 0x20),
               (1.00, 0xFF, 0x3B, 0x4E)]
        let x: Double = min(max(t, 0), 1)
        for i in 0..<(stops.count - 1) {
            let p0 = stops[i].0
            let p1 = stops[i + 1].0
            if x <= p1 {
                let k: Double = (x - p0) / (p1 - p0)
                let r: Double = (stops[i].1 + (stops[i + 1].1 - stops[i].1) * k) / 255
                let g: Double = (stops[i].2 + (stops[i + 1].2 - stops[i].2) * k) / 255
                let b: Double = (stops[i].3 + (stops[i + 1].3 - stops[i].3) * k) / 255
                return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
            }
        }
        return Palette.bad
    }
}

// MARK: - 折线图（带发光）

/// 曲线背景的坐标系：左侧竖轴 + 底部横轴 + 几条虚线网格。
/// 全部用一条 `Path` 一次描边（不堆 Rectangle / Divider），逐帧几乎零成本。
struct ChartAxes: View {
    /// 水平网格线条数（不含两条轴）
    var rows: Int = 3
    /// 竖向网格线条数
    var columns: Int = 4
    /// 网格是否画出来（只留两条轴时关掉更干净）
    var grid: Bool = true

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if grid {
                    // 水平虚线：用「距底 1/(n+1)」等分，末条不会贴在轴线上
                    Path { p in
                        for i in 1...max(rows, 1) {
                            let y = h * CGFloat(i) / CGFloat(rows + 1)
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: w, y: y))
                        }
                    }
                    .stroke(Palette.ringTick.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    // 竖向虚线更淡，避免和曲线抢注意力
                    Path { p in
                        for i in 1...max(columns, 1) {
                            let x = w * CGFloat(i) / CGFloat(columns + 1)
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: h))
                        }
                    }
                    .stroke(Palette.ringTick.opacity(0.22),
                            style: StrokeStyle(lineWidth: 1, dash: [1, 4]))
                }

                // 两条实心轴：左竖轴 + 底横轴（比网格实一档，才有「坐标轴」的感觉）
                Path { p in
                    p.move(to: CGPoint(x: 0.5, y: 0))
                    p.addLine(to: CGPoint(x: 0.5, y: h - 0.5))
                    p.move(to: CGPoint(x: 0, y: h - 0.5))
                    p.addLine(to: CGPoint(x: w, y: h - 0.5))
                }
                .stroke(Palette.ringTick, lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.accent2
    var lowerBound: Double = 30
    var upperBound: Double = 100
    /// false = 只画发光线，不填面积（小卡片用，避免整块色块）
    var filled: Bool = true
    /// 背景坐标轴（左竖轴 + 底横轴 + 虚线网格）
    var axes: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = points(size: geo.size)
            ZStack {
                if axes {
                    // 网格密度随可用高度变：小图形少画几根，否则一屏全是虚线
                    ChartAxes(rows: geo.size.height >= 60 ? 3 : 2,
                              columns: geo.size.width >= 280 ? 4 : 3)
                }
                if pts.count > 1 {
                    if filled {
                        area(pts, size: geo.size)
                            .fill(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.0)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    // 用「宽而淡」的第二条线模拟辉光：
                    // 比 .shadow 便宜得多（阴影每帧都要离屏模糊，是这套界面最大的 GPU 开销）
                    Self.smoothPath(pts, in: geo.size)
                        .stroke(color.opacity(0.20),
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    Self.smoothPath(pts, in: geo.size)
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                } else {
                    Text(Palette.isMoss ? "NO DATA" : "等待采样…")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// 按像素宽度降采样：最多 1 点 / 2px，用峰值池化保留尖峰
    private func points(size: CGSize) -> [CGPoint] {
        guard values.count > 1, size.width > 1, size.height > 1 else { return [] }
        let limit = max(2, Int(size.width / 2))
        let data = Self.downsample(values, to: limit)
        let span = max(upperBound - lowerBound, 1)
        let stepX = size.width / CGFloat(max(data.count - 1, 1))
        return data.enumerated().map { idx, v in
            let clamped = min(max(v, lowerBound), upperBound)
            let y = size.height - CGFloat((clamped - lowerBound) / span) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }

    static func downsample(_ values: [Double], to limit: Int) -> [Double] {
        guard values.count > limit, limit > 2 else { return values }
        let bucket = Double(values.count) / Double(limit)
        var out: [Double] = []
        out.reserveCapacity(limit)
        for i in 0..<limit {
            let lo = min(values.count - 1, Int(Double(i) * bucket))
            let hi = min(values.count, max(lo + 1, Int(Double(i + 1) * bucket)))
            var peak = values[lo]
            for j in lo..<hi where abs(values[j]) > abs(peak) { peak = values[j] }
            out.append(peak)
        }
        return out
    }

    /// Catmull-Rom → 三次贝塞尔：把折线变成**过所有采样点**的平滑曲线。
    /// 控制点 y 夹在画布内 —— Path 不会被自动裁剪，不夹的话尖峰数据会把曲线甩出边框。
    static func smoothPath(_ pts: [CGPoint], in size: CGSize, tension: CGFloat = 1.0) -> Path {
        var p = Path()
        guard pts.count > 1 else { return p }
        p.move(to: pts[0])
        guard pts.count > 2 else {
            p.addLine(to: pts[1])
            return p
        }
        let k = tension / 6
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            var c1 = CGPoint(x: p1.x + (p2.x - p0.x) * k, y: p1.y + (p2.y - p0.y) * k)
            var c2 = CGPoint(x: p2.x - (p3.x - p1.x) * k, y: p2.y - (p3.y - p1.y) * k)
            c1.y = min(max(c1.y, 0), size.height)
            c2.y = min(max(c2.y, 0), size.height)
            p.addCurve(to: p2, control1: c1, control2: c2)
        }
        return p
    }

    /// 面积填充：上沿走同一条平滑曲线，再落到底边闭合
    private func area(_ pts: [CGPoint], size: CGSize) -> Path {
        guard let first = pts.first, let last = pts.last else { return Path() }
        var p = Self.smoothPath(pts, in: size)
        p.addLine(to: CGPoint(x: last.x, y: size.height))
        p.addLine(to: CGPoint(x: first.x, y: size.height))
        p.closeSubpath()
        return p
    }
}

/// 心电监护仪风格的 CPU 频率波形：绿色描边 + 细网格 + 末端扫描光点，
/// 把频率随时间的变化画成类似心电图的滚动轨迹（频率本身不是周期信号，
/// 这里只借用监护仪「绿线 + 网格 + 扫描」的视觉语言）。
struct FreqECG: View {
    let values: [Double]
    var color: Color = Palette.ok
    var lower: Double = 0
    var upper: Double = 5.5
    var height: CGFloat = 60
    /// 背景坐标轴（与 Sparkline 共用同一个 ChartAxes）
    var axes: Bool = false

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values: values, size: geo.size, lower: lower, upper: upper)
            ZStack {
                if axes {
                    ChartAxes(rows: geo.size.height >= 60 ? 3 : 2,
                              columns: geo.size.width >= 280 ? 4 : 3)
                }
                if pts.count > 1 {
                    // 宽而淡的辉光（比 .shadow 便宜，避免每帧离屏模糊）
                    Sparkline.smoothPath(pts, in: geo.size)
                        .stroke(color.opacity(0.18),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Sparkline.smoothPath(pts, in: geo.size)
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    // 末端扫描光点
                    if let last = pts.last {
                        Circle()
                            .fill(color)
                            .frame(width: 4.5, height: 4.5)
                            .position(last)
                            .shadow(color: color, radius: 5)
                    }
                } else {
                    Text("等待采样…")
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(height: height)
    }

    private static func points(values: [Double], size: CGSize, lower: Double, upper: Double) -> [CGPoint] {
        guard values.count > 1, size.width > 1, size.height > 1 else { return [] }
        let limit = max(2, Int(size.width / 2))
        let data = Sparkline.downsample(values, to: limit)
        let span = max(upper - lower, 1)
        let stepX = size.width / CGFloat(max(data.count - 1, 1))
        return data.enumerated().map { idx, v in
            let clamped = min(max(v, lower), upper)
            let y = size.height - CGFloat((clamped - lower) / span) * size.height
            return CGPoint(x: CGFloat(idx) * stepX, y: y)
        }
    }
}

// MARK: - 键盘背光档位

struct LevelDots: View {
    let level: Int
    let maxLevel: Int
    var onSelect: ((Int) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<maxLevel, id: \.self) { i in
                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    .fill(i < level
                          ? LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.65)],
                                           startPoint: .bottom, endPoint: .top)
                          : LinearGradient(colors: [Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.07, darkOpacity: 0.08),
                                                    Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.035, darkOpacity: 0.04)],
                                           startPoint: .bottom, endPoint: .top))
                    .frame(height: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                            .strokeBorder(i < level
                                          ? Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.22, darkOpacity: 0.25)
                                          : Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.12, darkOpacity: 0.10),
                                          lineWidth: 0.6)
                    )
                    .shadow(color: i < level ? Palette.accent.opacity(0.55) : .clear, radius: 4)
                    .onTapGesture { onSelect?(i + 1) }
            }
        }
    }
}

// MARK: - 能力行

struct CapabilityRow: View {
    let cap: Capability

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Palette.forStatus(cap.status))
                .frame(width: 6, height: 6)
                .shadow(color: Palette.forStatus(cap.status).opacity(0.9), radius: 4)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(cap.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.text)
                    Text(cap.status.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.4)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                .fill(Palette.forStatus(cap.status).opacity(0.14))
                        )
                        .foregroundStyle(Palette.forStatus(cap.status))
                }
                Text(cap.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                Text(cap.backend)
                    .font(.system(size: 9.5).monospaced())
                    .foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 标签

struct Pill: View {
    let text: String
    var color: Color = Palette.accent2

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium))
            .tracking(0.3)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    .fill(color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    .strokeBorder(color.opacity(0.40), lineWidth: 0.8)
            )
            .foregroundStyle(color)
    }
}

// MARK: - 按钮

struct GrayButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        // 550W：按钮不再是圆角胶囊，而是「切角小面板 + 红描边 + 等宽字」，
        // 和卡片/侧栏同一套语言。按下时底变淡红，不做缩放（缩放会触发重排）。
        if Palette.isMoss {
            configuration.label
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    PanelShape(radius: 0, cut: 5)
                        .fill(prominent
                              ? Palette.accent.opacity(configuration.isPressed ? 1.0 : 0.92)
                              : Palette.accent.opacity(configuration.isPressed ? 0.14 : 0.05))
                )
                .overlay(
                    PanelShape(radius: 0, cut: 5)
                        .stroke(Palette.accent.opacity(prominent ? 0.9 : 0.45), lineWidth: 1)
                )
                .foregroundStyle(prominent ? Color.white : Palette.accent)
        } else {
            classicBody(configuration: configuration)
        }
    }

    private func classicBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .tracking(0.3)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                        .fill(prominent
                              ? LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.78)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                              : LinearGradient(colors: [Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: configuration.isPressed ? 0.11 : 0.07, darkOpacity: configuration.isPressed ? 0.16 : 0.10),
                                                        Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: configuration.isPressed ? 0.05 : 0.03, darkOpacity: configuration.isPressed ? 0.07 : 0.045)],
                                               startPoint: .top, endPoint: .bottom))
                    // 顶部镜面高光
                    RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [Color.white.opacity(prominent ? 0.22 : 0.12), .clear],
                                             startPoint: .top, endPoint: .init(x: 0.5, y: 0.45)))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.12, darkOpacity: prominent ? 0.20 : 0.15), lineWidth: 0.8)
            )
            .foregroundStyle(prominent ? Color.white : Palette.text)
            .shadow(color: prominent ? Palette.accent.opacity(0.26) : Color.black.opacity(0.13),
                    radius: 5, x: 0, y: 1)
            .contentShape(Rectangle())
    }
}

// MARK: - 温度图（带纵轴）

struct TempChart: View {
    let values: [Double]
    var color: Color = Palette.accent2
    var lower: Double = 35
    var upper: Double = 100
    var height: CGFloat = 132

    private var labels: [String] {
        (0...3).map { i in
            let v = upper - (upper - lower) * Double(i) / 3.0
            return String(format: "%.0f°", v)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(labels.indices, id: \.self) { i in
                    Text(labels[i])
                        .font(.system(size: 8.5).monospacedDigit())
                        .foregroundStyle(Palette.textTertiary)
                    if i < labels.count - 1 { Spacer(minLength: 0) }
                }
            }
            .frame(width: 26, height: height)

            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Palette.hairline).frame(height: 1) }
                        if i < 3 { Spacer(minLength: 0) }
                    }
                }
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        if i > 0 { Rectangle().fill(Palette.subtle).frame(width: 1) }
                        if i < 6 { Spacer(minLength: 0) }
                    }
                }
                Sparkline(values: values, color: color, lowerBound: lower, upperBound: upper)
            }
            .frame(height: height)
        }
    }
}

// MARK: - 自绘滑杆

struct LevelSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...16
    var step: Double = 1
    var tint: Color = Palette.accent

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 9
            let usable = max(geo.size.width - inset * 2, 1)
            let frac = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobX = inset + usable * CGFloat(min(max(frac, 0), 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.trackFill)
                    .frame(height: 5)

                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(knobX - inset + 1, 1), height: 5)
                    .shadow(color: tint.opacity(0.7), radius: 6)
                    .offset(x: inset)

                Circle()
                    .fill(Palette.text)
                    .frame(width: 14, height: 14)
                    .shadow(color: tint.opacity(0.9), radius: 8)
                    .offset(x: knobX - 7)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let p = min(max(g.location.x - inset, 0), usable)
                    let raw = range.lowerBound + Double(p / usable) * (range.upperBound - range.lowerBound)
                    let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
                    if snapped != value { value = snapped }
                }
            )
        }
        .frame(height: 22)
    }
}

// MARK: - 电量条

struct BatteryBar: View {
    let percent: Int

    private var color: Color {
        if percent > 60 { return Palette.ok }
        if percent > 20 { return Palette.warn }
        return Palette.bad
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.trackFill)
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.6), color],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * CGFloat(min(max(percent, 0), 100)) / 100, 4))
                    .shadow(color: color.opacity(0.6), radius: 5)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - 自绘分段控件

struct SegmentedButtons<Value: Hashable>: View {
    let items: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { i in
                Button {
                    selection = items[i].1
                } label: {
                    Text(items[i].0)
                        .font(.system(size: 10, weight: selection == items[i].1 ? .semibold : .regular))
                        .tracking(0.3)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                                .fill(selection == items[i].1
                                      ? AnyShapeStyle(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.7)],
                                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(Color.clear))
                        )
                        .foregroundStyle(selection == items[i].1 ? Color.white : Palette.textSecondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.faintFill))
    }
}

// MARK: - ROG Logo

/// 品牌标：深色模式用白色版（ROGLogo.png），浅色模式用红色版（ROGLogoRed.png）
struct ROGLogo: View {
    var height: CGFloat = 20
    var opacity: Double = 0.92
    @Environment(\.colorScheme) private var scheme

    /// 正常运行时从 bundle 取；CLI 经 build/asuscontrol 符号链接调用时
    /// Bundle.main 会落到 build/ 目录，所以再按可执行文件路径回溯几层。
    static func loadImage(_ name: String) -> NSImage? {
        var candidates: [URL] = []
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            candidates.append(url)
        }
        if let exe = Bundle.main.executablePath ?? CommandLine.arguments.first {
            let exeURL = URL(fileURLWithPath: exe)
            let dir = exeURL.deletingLastPathComponent()
            candidates.append(dir.appendingPathComponent("../Resources/\(name).png"))
            candidates.append(dir.appendingPathComponent("Resources/\(name).png"))
            candidates.append(dir.deletingLastPathComponent()
                                 .appendingPathComponent("Resources/\(name).png"))
        }
        candidates.append(URL(fileURLWithPath: "Resources/\(name).png"))

        for url in candidates {
            let path = url.standardizedFileURL.path
            if FileManager.default.fileExists(atPath: path), let image = NSImage(contentsOfFile: path) {
                return image
            }
        }
        return nil
    }

    static let image = loadImage("ROGLogo")
    static let redImage = loadImage("ROGLogoRed")

    private var currentImage: NSImage? {
        scheme == .light ? (Self.redImage ?? Self.image) : Self.image
    }

    @ViewBuilder
    var body: some View {
        if let image = currentImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .opacity(opacity)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 字节格式化（磁盘容量）

extension ByteCountFormatter {
    /// 统一用「十进制 + 省略 decimals」风格展示磁盘容量（如 512 GB、1.2 TB），
    /// 避免系统默认在 B/KB 档跳来跳去，也更贴近厂商标称。
    static let vela: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB, .useTB, .useMB]
        f.countStyle = .decimal
        f.includesUnit = true
        f.zeroPadsFractionDigits = false
        return f
    }()
}

// MARK: - 550W 限定主题标识

/// 550W 的两份素材（用户提供的 traced 矢量 SVG，已按白底重新着色并栅格化）：
///   · moss-logo.png    —— 纯英文机号标「550 + 红色 W」
///   · moss-caption.png —— 电影字幕条「智能量子计算机 550W [MOSS] / INTELLIGENT QUANTUM COMPUTER …」
/// 只在 550W 皮肤下出现；素材缺失时退回手绘标识，不至于开天窗。
enum MossAssets {
    static let logo = ROGLogo.loadImage("moss-logo")
    static let caption = ROGLogo.loadImage("moss-caption")
}

/// 550W 机号标
struct MossLogo: View {
    var height: CGFloat = 20

    var body: some View {
        if let img = MossAssets.logo {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                // 图片的 ideal width 是原始像素宽，不锁死会被 HStack 压成 0 宽（实测被挤没）
                .fixedSize()
                .accessibilityLabel("550W")
        } else {
            HStack(spacing: height * 0.28) {
                MossMark(size: height)
                Text("550W")
                    .font(.system(size: height * 0.82, weight: .black, design: .monospaced))
                    .tracking(height * 0.09)
                    .foregroundStyle(Palette.text)
            }
        }
    }
}

/// 550W 字幕条：给宽度、按原比例定高
struct MossCaption: View {
    var width: CGFloat = 260

    var body: some View {
        if let img = MossAssets.caption {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: width)
                .accessibilityLabel("智能量子计算机 550W")
        }
    }
}

/// 手绘兜底标识（素材缺失时才用）：红环 + 四向刻线 + 中央镜头
struct MossMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.accent, lineWidth: max(1.2, size * 0.075))
            ForEach(0..<4, id: \.self) { i in
                Rectangle()
                    .fill(Palette.accent)
                    .frame(width: max(1, size * 0.05), height: size * 0.15)
                    .offset(y: -size / 2 + size * 0.055)
                    .rotationEffect(.degrees(Double(i) * 90))
            }
            Circle()
                .fill(Palette.accent)
                .frame(width: size * 0.40, height: size * 0.40)
            Circle()
                .fill(Color.white.opacity(0.88))
                .frame(width: size * 0.11, height: size * 0.11)
                .offset(x: -size * 0.07, y: -size * 0.07)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - 550W 代码标签

/// 550W 皮肤下的「代码标签」：等宽小字 + 指令前缀，像终端里的一行 key。
/// 只替换标签文字，值仍然是正常字体、图标照旧 —— 全改成等宽反而读不动。
/// 其它主题下与普通小标题完全一致，不影响观感。
/// 550W 的标签词典：概览卡里那些中文小标签统一换成大写英文缩写
/// （TEM / FRE / PWR …）。未收录的词**原样返回**，所以「最近 240 秒」「ROG」这类动态文案不会被误改。
enum MossText {
    private static let map: [String: String] = [
        // CPU / GPU 卡的说明词
        "温度": "TEM", "频率": "FRE", "功耗": "PWR", "显存": "VRAM",
        "占用": "UTIL", "占用率": "UTIL", "状态": "STAT",
        "最低": "MIN", "最高": "MAX", "热压力": "THERM",
        // 曲线与指标
        "负载曲线": "LOAD", "占用率曲线": "UTIL",
        "内存": "MEM", "风扇": "FAN", "磁盘": "DSK", "电池": "BAT",
        "采样": "SMP", "实时": "LIVE", "不可用": "N/A",
        // 状态值也跟着翻，否则会出现「STAT 偏高」这种中英混排
        "凉爽": "COOL", "正常": "NOMINAL", "偏高": "HIGH", "高温": "HOT",
        "过热": "CRIT", "偏热": "FAIR", "临界": "CRIT", "无数据": "NODATA", "未知": "N/A",
        // 档位 / 风扇曲线
        "静音": "SILENT", "平衡": "BALANCED", "性能": "PERF", "自定义": "CUSTOM",
        "自定义曲线": "CUSTOM", "未记录": "NO REC", 
        "温度曲线": "TEMP.CURVE", "内核计数器": "KERNEL",
    ]

    /// 单个词翻译
    static func code(_ text: String) -> String {
        map[text.trimmingCharacters(in: .whitespaces)] ?? text
    }

    /// 「温度 · 频率 · 功耗」这类用「·」分隔的说明，逐词翻译后拼回去
    static func codeList(_ text: String) -> String {
        guard text.contains("·") else { return code(text) }
        return text.split(separator: "·")
            .map { code($0.trimmingCharacters(in: .whitespaces)) }
            .joined(separator: " · ")
    }
}

struct CodeLabel: View {
    let text: String
    var size: CGFloat = 9.5

    var body: some View {
        if Palette.isMoss {
            // 550W：中文标签一律换成大写英文缩写（TEM / FRE / PWR…），读起来是机器输出的字段名
            HStack(spacing: 3) {
                Text("▸")
                    .font(.system(size: size - 0.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Palette.accent.opacity(0.85))
                Text(MossText.code(text))
                    .font(.system(size: size, weight: .medium, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
        } else {
            Text(text)
                .font(.system(size: size))
                .tracking(0.5)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
    }
}

// MARK: - 550W 面板形状

/// 行星发动机阵列：一排引擎剪影 + 向上喷出的等离子束，作为概览底部的装饰带。
/// 纯静态 Canvas（一次绘制、drawingGroup 拍平）：
///   · 底座是梯形，机身高而窄 —— 电影里那万座发动机的轮廓
///   · 每座上面一道竖直光束，高度按下标错开，读起来像一整片在同时点火
/// 不带任何数值含义，纯粹是气氛。
struct MossEngineArray: View {
    var engines: Int = 12
    var height: CGFloat = 36

    var body: some View {
        Canvas { ctx, size in
            let ink = Color(red: 0.784, green: 0.063, blue: 0.180)
            let baseY = size.height - 3
            let spacing = size.width / CGFloat(max(engines, 1) + 1)

            var bodies = Path()
            var beams = Path()
            var ground = Path()

            ground.move(to: CGPoint(x: 0, y: baseY + 1))
            ground.addLine(to: CGPoint(x: size.width, y: baseY + 1))

            for i in 0 ..< engines {
                let x = spacing * CGFloat(i + 1)
                let bodyH = size.height * 0.40
                let halfW: CGFloat = 5.6
                // 梯形机身：下宽上窄，顶上留一段喷口
                bodies.move(to: CGPoint(x: x - halfW, y: baseY))
                bodies.addLine(to: CGPoint(x: x - halfW * 0.44, y: baseY - bodyH))
                bodies.addLine(to: CGPoint(x: x - halfW * 0.30, y: baseY - bodyH - 2))
                bodies.move(to: CGPoint(x: x + halfW, y: baseY))
                bodies.addLine(to: CGPoint(x: x + halfW * 0.44, y: baseY - bodyH))
                bodies.addLine(to: CGPoint(x: x + halfW * 0.30, y: baseY - bodyH - 2))
                // 地面基座
                bodies.move(to: CGPoint(x: x - halfW - 1.6, y: baseY))
                bodies.addLine(to: CGPoint(x: x + halfW + 1.6, y: baseY))

                // 等离子柱：向上收窄的两条线，比一根竖线更像“喷流”
                let beamH = size.height * (i % 3 == 0 ? 0.52 : (i % 3 == 1 ? 0.36 : 0.24))
                let topY = baseY - bodyH - 2 - beamH
                beams.move(to: CGPoint(x: x - 1.6, y: baseY - bodyH - 2))
                beams.addLine(to: CGPoint(x: x - 0.35, y: topY))
                beams.move(to: CGPoint(x: x + 1.6, y: baseY - bodyH - 2))
                beams.addLine(to: CGPoint(x: x + 0.35, y: topY))
            }

            ctx.stroke(ground, with: .color(ink.opacity(0.22)), lineWidth: 1)
            ctx.stroke(bodies, with: .color(ink.opacity(0.42)), lineWidth: 1)
            ctx.stroke(beams, with: .color(ink.opacity(0.30)), lineWidth: 1)
        }
        .frame(height: height)
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// 550W 面板装饰层。
/// 画的是「仪器面板上那些没人读、但少了就不像仪器」的东西：
/// 四角定位刻线、顶部 45° 斜纹带（危险区域的条纹）、左缘刻度尺、底部分段虚线。
/// 全部静态路径，随卡片一起拍平，不影响滚动性能。
struct MossPanelDecor: View {
    var body: some View {
        Canvas { ctx, size in
            let ink = Color(red: 0.784, green: 0.063, blue: 0.180)   // 550W 红
            let w = size.width, h = size.height
            let cut: CGFloat = 13

            // 四角定位刻线（L 形），避开放大的切角
            var ticks = Path()
            let inset: CGFloat = 7
            let len: CGFloat = 11
            for corner in 0 ..< 4 {
                let right = corner % 2 == 1
                let bottom = corner > 1
                let x = right ? w - inset : inset
                let y = bottom ? h - inset : inset
                let dx: CGFloat = right ? -len : len
                let dy: CGFloat = bottom ? -len : len
                // 贴着切角内侧起笔，避免和斜边重叠
                let startX = right ? x - cut * 0.55 : x + cut * 0.55
                let startY = bottom ? y - cut * 0.55 : y + cut * 0.55
                ticks.move(to: CGPoint(x: startX, y: y))
                ticks.addLine(to: CGPoint(x: startX + dx * 0.8, y: y))
                ticks.move(to: CGPoint(x: x, y: startY))
                ticks.addLine(to: CGPoint(x: x, y: startY + dy * 0.8))
            }
            ctx.stroke(ticks, with: .color(ink.opacity(0.46)), lineWidth: 1.4)

            // 顶部 45° 斜纹带
            var hatch = Path()
            let band: CGFloat = 7
            var hx: CGFloat = -band
            while hx < w {
                hatch.move(to: CGPoint(x: hx, y: 0))
                hatch.addLine(to: CGPoint(x: hx + band, y: band))
                hx += 7
            }
            ctx.clip(to: Path(CGRect(x: 0, y: 0, width: w, height: band)))
            ctx.stroke(hatch, with: .color(ink.opacity(0.16)), lineWidth: 1)
            ctx.clip(to: Path(CGRect(origin: .zero, size: size)))

            // 左缘刻度尺（每 10pt 一格，每 5 格长一点）
            var rail = Path()
            var ry = band + 10
            var n = 0
            while ry < h - 10 {
                let long = n % 5 == 0
                rail.move(to: CGPoint(x: 0, y: ry))
                rail.addLine(to: CGPoint(x: long ? 6 : 3.5, y: ry))
                ry += 10; n += 1
            }
            ctx.stroke(rail, with: .color(ink.opacity(0.26)), lineWidth: 1)

            // 底部分段虚线
            var perf = Path()
            var px: CGFloat = 16
            while px < w - 16 {
                perf.move(to: CGPoint(x: px, y: h - 6))
                perf.addLine(to: CGPoint(x: px + 5, y: h - 6))
                px += 9
            }
            ctx.stroke(perf, with: .color(ink.opacity(0.22)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

/// 切角矩形：四角各切一刀、两处大、两处小，整体仍是矩形、布局边框不变，
/// 只是轮廓不规则 —— 550W 的仪表板就是这个味道（对齐靠布局，不靠圆角）。
struct PanelShape: Shape {
    var radius: CGFloat = 22
    /// 0 = 普通圆角矩形；>0 = 切角尺寸
    var cut: CGFloat = 0
    /// 描边时向内收的量（InsettableShape 用）
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = insetAmount == 0 ? rect
            : rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard cut > 0 else {
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }
        let big = min(cut, min(rect.width, rect.height) / 2.5)
        let small = big * 0.44
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + big, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - small, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + small))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        p.addLine(to: CGPoint(x: rect.maxX - big, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + small, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - small))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + big))
        p.closeSubpath()
        return p
    }
}

extension PanelShape: InsettableShape {
    func inset(by amount: CGFloat) -> PanelShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// 只画两处大斜边（左上、右下），用来给红色强调
struct PanelAccents: Shape {
    var cut: CGFloat = 13

    func path(in rect: CGRect) -> Path {
        let big = min(cut, min(rect.width, rect.height) / 2.5)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + big, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + big))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - big))
        p.addLine(to: CGPoint(x: rect.maxX - big, y: rect.maxY))
        return p
    }
}

/// 标题里的虚线横规：撑满剩余宽度，像工程图的分栏线
struct DashedRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// 550W 皮肤下的一行「配置项」：等宽 KEY + 等宽 VALUE。
/// 像读一份 MOSS 的运行时配置，而不是看一个仪表盘。
struct CodeRow: View {
    let key: String
    let value: String
    var size: CGFloat = 10
    var valueColor: Color = Palette.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.system(size: size - 0.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.accent.opacity(0.78))
                .lineLimit(1)
            Text(value)
                .font(.system(size: size, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

// MARK: - 550W 动态终端

/// 550W 装饰文本的**共享时钟**。
///
/// 为什么要有它：这些「每秒跳一下」的小组件（光标、日志轮播、运行时长、轮播标语…）
/// 原来各挂一个 `TimelineView(.periodic(by: 1))`。`TimelineView` 的相位从各自出现时
/// 算起，彼此的跳变点错开 → 每秒会分成 **4~5 个独立的显示周期**，而本窗口每个显示周期
/// 都是「整窗 AppKit 重排 + SwiftUI 属性图更新」，实测约 7ms/次。也就是说光是这些
/// 装饰文字就要吃掉 3~4% 单核。
///
/// 改成一个定时器 + 一个 `@Published` 时间戳后，所有组件在同一次状态变更里更新，
/// 落进**同一个事务**，每秒只剩一次整窗重排。窗口不可见时直接停表（保持最后一帧）。
final class MossClock: ObservableObject {
    static let shared = MossClock()

    @Published private(set) var tick = Date()

    private var timer: Timer?
    private init() {}

    /// 窗口可见才走表；不可见时保留最后一个时间戳，界面就停在那一帧
    func setActive(_ on: Bool) {
        if on {
            guard timer == nil else { return }
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick = Date()
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    /// 把当前节拍对齐到 `interval` 的整数倍：
    /// 需要 6 秒轮播的组件看着 6s 才变一次，但仍然只共用这一个时钟。
    func beat(_ interval: TimeInterval) -> Date {
        guard interval > 0 else { return tick }
        let s = tick.timeIntervalSince1970
        return Date(timeIntervalSince1970: (s / interval).rounded(.down) * interval)
    }
}

/// 装饰动画的统一节拍器（读 `MossClock`，不再自己挂 `TimelineView`）。
struct MossTicker<Content: View>: View {
    var interval: TimeInterval
    @ObservedObject private var clock = MossClock.shared
    private let content: (Date) -> Content

    init(interval: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.interval = interval
        self.content = content
    }

    var body: some View {
        content(clock.beat(interval))
    }
}

/// 方块光标：0.55s 一闪。
/// 用 `TimelineView` 做**离散跳变**（不做插值动画）—— 只有它自己那一小块文字重绘，
/// 比 `repeatForever` 的动画链便宜得多，长时间挂着也不会把 GPU 拖起来。
struct MossCursor: View {
    var size: CGFloat = 9
    var body: some View {
        // 1s 一闪：0.55s 的闪烁在这个窗口里等于每秒多两次整窗重排，不值得
        MossTicker(interval: 1) { date in
            let on = Int(date.timeIntervalSince1970 / 1) % 2 == 0
            Text("▮")
                .font(.system(size: size, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.accent.opacity(on ? 0.95 : 0.18))
        }
    }
}

/// 终端里「正在算」的一行输出：轮播几条日志，末尾带闪烁光标。
/// 同一次 0.5s 跳变里同时推进「换行」和「闪光标」，一张卡只挂一个时钟。
struct MossLogLine: View {
    let lines: [String]
    var size: CGFloat = 9
    /// 每条停留几个 tick（1s/tick）
    var ticksPerLine: Int = 3

    var body: some View {
        // 1s 一跳（原 0.5s）：这个窗口每跳一次都是整窗重排，日志轮播没必要那么勤
        MossTicker(interval: 1) { date in
            let tick = Int(date.timeIntervalSince1970 / 1)
            let count = max(lines.count, 1)
            let idx = (tick / max(ticksPerLine, 1)) % count
            let cursorOn = tick % 2 == 0
            let raw = lines.isEmpty ? "" : lines[idx]
            HStack(spacing: 3) {
                Text("›")
                    .foregroundStyle(Palette.accent.opacity(0.9))
                Text(raw)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("▮")
                    .fontWeight(.bold)
                    .foregroundStyle(Palette.accent.opacity(cursorOn ? 0.9 : 0.15))
            }
            .font(.system(size: size, weight: .medium, design: .monospaced))
        }
    }
}

/// 资源调度条：把 CPU / 内存 / GPU / 功耗四条压成一行「方块读数」。
/// 全部取自真实采样，不编数字；纯文本方块（▓░），不画图，零绘制开销。
struct MossDispatchStrip: View {
    var cpu: Double?        // 0…1
    var mem: Double?        // 0…1
    var gpu: Double?        // 0…1
    var watts: Double?
    var cap: Double

    var body: some View {
        HStack(spacing: 0) {
            Text("▮")
                .foregroundStyle(Palette.accent)
            Text("资源调度")
                .foregroundStyle(Palette.text)
                .padding(.leading, 3)
            sep
            group("CPU", cpu, Palette.mLoad)
            sep
            group("GPU", gpu, Palette.mGPU)
            sep
            group("MEM", mem, Palette.mMem)
            sep
            HStack(spacing: 4) {
                Text("PWR").foregroundStyle(Palette.accent.opacity(0.8))
                Text(watts.map { String(format: "%.0f", $0) } ?? "—")
                    .foregroundStyle(Palette.text)
                Text("/ \(Int(cap)) W").foregroundStyle(Palette.textTertiary)
            }
            Spacer(minLength: 8)
            Text("// 1s 采样")
                .foregroundStyle(Palette.textTertiary)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(0.3)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }

    private var sep: some View {
        Text("│")
            .foregroundStyle(Palette.accent.opacity(0.28))
            .padding(.horizontal, 7)
    }

    private func group(_ name: String, _ value: Double?, _ color: Color) -> some View {
        let v = min(max(value ?? 0, 0), 1)
        let filled = Int((v * 5).rounded())
        return HStack(spacing: 4) {
            Text(name).foregroundStyle(Palette.accent.opacity(0.8))
            Text(String(repeating: "▓", count: filled)
                 + String(repeating: "░", count: 5 - filled))
                .foregroundStyle(color.opacity(0.85))
            Text(value.map { String(format: "%.0f%%", $0 * 100) } ?? "—")
                .foregroundStyle(Palette.text)
        }
    }
}

/// 页脚观测条：概览最下面一行，和顶部状态行首尾呼应。
/// 左边是滚动日志（真实采样），右边是运行时间码与节点 —— 整页读起来像一块持续工作的面板。
struct MossFooterStrip: View {
    var lines: [String]
    var node: String

    var body: some View {
        HStack(spacing: 0) {
            Text("▮")
                .foregroundStyle(Palette.accent)
            Text("观测日志")
                .foregroundStyle(Palette.text)
                .padding(.leading, 3)
            Text("│")
                .foregroundStyle(Palette.accent.opacity(0.28))
                .padding(.horizontal, 7)
            MossLogLine(lines: lines, size: 9)
            Spacer(minLength: 10)
            MossTicker(interval: 1) { _ in
                Text("T+\(MossUptime.text())")
            }
            .foregroundStyle(Palette.textSecondary)
            Text("// \(node) · 1s 采样")
                .foregroundStyle(Palette.textTertiary)
                .padding(.leading, 10)
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .tracking(0.3)
        .lineLimit(1)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.hairline).frame(height: 1)
        }
    }
}

/// 已运行时长（MOSS 的启动秒表）
enum MossUptime {
    static func text() -> String {
        let total = Int(ProcessInfo.processInfo.systemUptime)
        let d = total / 86_400
        let h = (total % 86_400) / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        return d > 0
            ? String(format: "%dd %02d:%02d:%02d", d, h, m, s)
            : String(format: "%02d:%02d:%02d", h, m, s)
    }
}

/// 缩放期间的装饰层闸门：拖动边角缩放时，纯装饰内容（面板刻线、斜纹带、
/// 发动机剪影…）每帧都要跟着重新栅格化，而它们在缩放过程中几乎看不清。
/// 缩放期间直接不渲染，松手立刻回来 —— 每帧少几十个矢量绘制与图层合成。
struct MossDecorGate<Content: View>: View {
    @ObservedObject private var visibility = WindowVisibility.shared
    @ViewBuilder var content: Content

    var body: some View {
        if !visibility.isBusy { content }
    }
}

/// 卡片斜边的强调描边。
///
/// 早期这里是「2.2s 呼吸一次」的 `TimelineView` —— 但每张卡各挂一个定时器，
/// 7 张卡就是每秒 ~3 次整窗重排；在整窗布局约 7ms 的成本下，这笔账不划算。
/// 现在固定为一档亮度（视觉上几乎无差），把逐帧开销归零。
struct MossAccentPulse: View {
    var cut: CGFloat = 13
    var body: some View {
        // 「不要红色晕开」：用中性墨，不用红
        PanelAccents(cut: cut)
            .stroke(Palette.text.opacity(0.30),
                    style: StrokeStyle(lineWidth: 2, lineCap: .square))
    }
}

// MARK: - 550W 故障特效