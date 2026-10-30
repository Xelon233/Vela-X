//
//  UIComponents.swift
//  设计系统 —— 参考 ROG 奥创中心（Armoury Crate）：深色底、切角面板、霓虹描边、大字数字
//

import SwiftUI

// MARK: - 配色

enum Palette {
    // 底色（深浅自适应，随主题切换自动解析）
    static let bg = Color.adaptive(0xF1F3F7, 0x05070B)
    static let bgSoft = Color.adaptive(0xE6EAF1, 0x0A0E15)
    /// 面板色不再用纯白 / 蓝灰：纯白太"实"，一叠上去就是白纸；
    /// 深色那对 0x161C27 / 0x0D121A 又偏灰蓝，视觉上是一层灰。
    /// 现在浅色走极浅的中性灰、深色压到近黑，配低透明度才是"一整块磨砂玻璃"。
    static let panelTop = Color.adaptive(0xFAFAFB, 0x0A0E13)
    static let panelBottom = Color.adaptive(0xF1F2F5, 0x070A0E)
    static let panelHi = Color.adaptive(0xE9EDF4, 0x1E2634)

    // 品牌色：取 Finder 侧栏选中态用的那支蓝（系统 accent blue）——
    // 浅色 #007AFF、深色 #0A84FF。它比之前的靛蓝更「系统」，和 macOS 自绘控件同色，
    // 灰阶背景上也不会显得发紫。红依旧只留给「错误/危险」语义。
    static let accent = Color.adaptive(0x007AFF, 0x0A84FF)
    /// 次级强调色：系统色板里的 sky blue，和主蓝同族，做数字/标签的渐层
    static let accent2 = Color.adaptive(0x32ADE6, 0x64D2FF)
    static let ok = Color.adaptive(0x1DA45F, 0x2FD57C)
    static let warn = Color.adaptive(0xC77F00, 0xFFB020)
    static let bad = Color.adaptive(0xD62A3C, 0xFF3B4E)

    // 文字
    static let text = Color.adaptive(0x1B2331, 0xE9F0FA)
    static let textSecondary = Color.adaptive(0x52627A, 0xA3B2C6)
    static let textTertiary = Color.adaptive(0x8B98AB, 0x6C7C92)

    // 描边 / 填充语义色
    /// 卡片描边：卡片变透明后全靠这道边勾轮廓，比填充透明度低的时候要更明显一点
    static let cardStroke = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.11, darkOpacity: 0.09)
    static let subtle = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.05, darkOpacity: 0.04)
    /// 按钮胶囊等弱填充
    static let faintFill = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.07, darkOpacity: 0.07)
    /// 分隔线、边框
    static let hairline = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.10, darkOpacity: 0.08)
    /// 窗口底色薄纱：整窗只压这一层纯色，光晕/色调全部来自壁纸
    /// （深色 = 黑纱压暗、浅色 = 白纱提亮，都保留壁纸原有的色相，
    ///  所以同一套界面在不同壁纸下会呈现不同氛围。透明度别超过 0.3，
    ///  再高就把壁纸盖死，反而变成一块实色板。）
    static let veil = Color.adaptive(0xFFFFFF, 0x000000, lightOpacity: 0.00, darkOpacity: 0.02)
    /// 温度环底环 / 刻度
    static let ringBase = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.08, darkOpacity: 0.06)
    static let ringTick = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.18, darkOpacity: 0.16)
    /// 滑杆 / 电量条轨道
    static let trackFill = Color.adaptive(0x000000, 0xFFFFFF, lightOpacity: 0.07, darkOpacity: 0.06)

    /// 整体统一圆角（macOS 26 Liquid Glass 组件标准，连续圆角），与 Safari 内控件一致
    static let cornerRadius: CGFloat = 12

    static func forTemp(_ t: Double?) -> Color {
        guard let t else { return textSecondary }
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

    /// 磁盘占用率配色：绿 → 蓝 → 黄 → 红，与温度同一套语义
    static func forDisk(_ f: Double) -> Color {
        switch f {
        case ..<0.6: return ok
        case ..<0.8: return accent2
        case ..<0.92: return warn
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

struct ChamferShape: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = min(cut, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX + c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + c))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.maxX - c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + c))
        p.closeSubpath()
        return p
    }
}

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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    // 玻璃本体（半透明，让桌面和背景光晕透出来）
                    glassShape.fill(glassFill)
                    // 顶部镜面高光（Liquid Glass 的关键反光）
                    glassShape.fill(topSheen)
                }
            )
            .overlay(
                // 玻璃边缘：上亮 → 中淡 → 下微亮，模拟折射
                glassShape.strokeBorder(glassEdge, lineWidth: 1)
            )
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
            // 阴影是离屏高斯模糊，半径 12 意味着每个像素几十次采样 —— 卡片一多，
            // GPU 一半时间都耗在这。只有 glow 卡（少数重点卡）保留外发光，
            // 其余靠描边和玻璃渐变分层，观感几乎无差。
            .shadow(color: glow ? Palette.accent.opacity(scheme == .light ? 0.07 : 0.10) : .clear,
                    radius: glow ? 7 : 0, x: 0, y: glow ? 3 : 0)
            // 这里【不能】用 .drawingGroup() 把整张卡拍平成一张纹理：
            // 卡片里常放 Toggle / Slider / Button，被拍进 Metal 纹理后画不出来，
            // 会变成黄底禁止符号（菜单栏页那一排开关会全废）。实测踩过这个坑。
    }

    private var glassShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
    /// 半透明玻璃填充：卡片只是「一层玻璃」，不是实心面板。
    /// 透明度直接决定玻璃观感 —— 太实就退化成一堆磨砂色块，桌面和背景光晕全被压死。
    /// 浅色 0.24/0.17、深色 0.15/0.11：整窗读起来是同一块磨砂玻璃，
    /// 卡片靠描边和一丝明暗差分层，而不是靠"白纸叠在灰纸上"。
    private var glassFill: LinearGradient {
        scheme == .light
            ? LinearGradient(colors: [Palette.panelTop.opacity(0.24), Palette.panelBottom.opacity(0.17)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Palette.panelTop.opacity(0.15), Palette.panelBottom.opacity(0.11)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    /// 顶部镜面高光。
    /// 这层和上面的填充在 GPU 上不会真的各画一遍：整张卡最后被 drawingGroup
    /// 拍平成一张纹理，分层只是写起来清楚。
    private var topSheen: LinearGradient {
        LinearGradient(colors: [Color.white.opacity(scheme == .light ? 0.09 : 0.025), .clear],
                       startPoint: .top, endPoint: .init(x: 0.5, y: 0.30))
    }
    /// 玻璃边缘描边：上沿更亮，模拟 Liquid Glass 的折射亮边
    private var glassEdge: LinearGradient {
        scheme == .light
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

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.15)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 2.5, height: 12)
                .shadow(color: Palette.accent.opacity(0.45), radius: 3)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.text)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
            }
        }
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
        let stops: [(Double, Double, Double, Double)] = [
            (0.00, 0x2A, 0xD4, 0xEE),
            (0.45, 0x2F, 0xD5, 0x7C),
            (0.72, 0xFF, 0xB0, 0x20),
            (1.00, 0xFF, 0x3B, 0x4E)
        ]
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

struct Sparkline: View {
    let values: [Double]
    var color: Color = Palette.accent2
    var lowerBound: Double = 30
    var upperBound: Double = 100
    /// false = 只画发光线，不填面积（小卡片用，避免整块色块）
    var filled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let pts = points(size: geo.size)
            ZStack {
                if pts.count > 1 {
                    if filled {
                        area(pts, size: geo.size)
                            .fill(LinearGradient(colors: [color.opacity(0.16), color.opacity(0.0)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    // 用「宽而淡」的第二条线模拟辉光：
                    // 比 .shadow 便宜得多（阴影每帧都要离屏模糊，是这套界面最大的 GPU 开销）
                    line(pts)
                        .stroke(color.opacity(0.20),
                                style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    line(pts)
                        .stroke(color,
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                } else {
                    Text("等待采样…")
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

    private func line(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        return p
    }

    private func area(_ pts: [CGPoint], size: CGSize) -> Path {
        var p = Path()
        p.addLines(pts)
        p.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: size.height))
        p.addLine(to: CGPoint(x: pts.first?.x ?? 0, y: size.height))
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

    var body: some View {
        GeometryReader { geo in
            let pts = Self.points(values: values, size: geo.size, lower: lower, upper: upper)
            ZStack {
                if pts.count > 1 {
                    // 宽而淡的辉光（比 .shadow 便宜，避免每帧离屏模糊）
                    Self.path(pts)
                        .stroke(color.opacity(0.18),
                                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    Self.path(pts)
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

    private static func path(_ pts: [CGPoint]) -> Path {
        var p = Path()
        p.addLines(pts)
        return p
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
