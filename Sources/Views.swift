//
//  Views.swift
//  主界面与各功能页
//

import SwiftUI
import AppKit
import Combine

/// 让底层 NSScrollView 的滚动条采用 overlay 浮层风格，并在空闲时自动隐藏。
/// 无论系统「滚动条」偏好是「始终」还是「滚动时」，右侧那条滚动条都只在滚动时
/// 短暂浮出、平时隐藏，避免常驻条破坏 Liquid Glass 的沉浸观感。
struct ScrollerAutoHide: NSViewRepresentable {
    /// 只配置一次的占位视图：updateNSView 每秒都会被调一次，
    /// 每次都往主队列塞一个 async 纯属白开销。
    final class Once: NSView {
        var done = false
    }

    func makeNSView(context: Context) -> NSView { Once() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let once = nsView as? Once, !once.done else { return }
        DispatchQueue.main.async {
            guard !once.done, let sv = nsView.enclosingScrollView else { return }
            sv.scrollerStyle = .overlay
            sv.autohidesScrollers = true
            sv.verticalScroller?.scrollerStyle = .overlay
            sv.horizontalScroller?.scrollerStyle = .overlay
            once.done = true
        }
    }
}

enum Page: String, CaseIterable, Identifiable {
    case overview, monitor, keyboard, menubar, performance, nvidia, diagnostics, advanced, settings, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .monitor: return "监控"
        case .keyboard: return "键盘背光"
        case .menubar: return "菜单栏"
        case .performance: return "性能与风扇"
        case .nvidia: return "NVIDIA 驱动"
        case .diagnostics: return "诊断"
        case .advanced: return "高级功能"
        case .settings: return "设置"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .monitor: return "waveform.path.ecg"
        case .keyboard: return "keyboard"
        case .menubar: return "menubar.dock.rectangle"
        case .performance: return "fanblades"
        case .nvidia: return "display"
        case .diagnostics: return "stethoscope"
        case .advanced: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

/// 当前页面。做成共享对象，这样菜单栏弹窗里的「去设置」也能把主窗口切到指定页
final class PageRouter: ObservableObject {
    static let shared = PageRouter()
    @Published var page: Page =
        Page(rawValue: ProcessInfo.processInfo.environment["ASUS_PAGE"] ?? "") ?? .overview
    private init() {}
}

struct ContentView: View {
    @EnvironmentObject var store: SensorStore
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var router = PageRouter.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(page: $router.page)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch router.page {
                    case .overview: OverviewView()
                    case .monitor: MonitorView()
                    case .keyboard: KeyboardView()
                    case .menubar: MenuBarSettingsView()
                    case .performance: PerformanceView()
                    case .nvidia: NvidiaView()
                    case .diagnostics: DiagnosticsView()
                    case .advanced: AdvancedView()
                    case .settings: SettingsView()
                    case .about: AboutView()
                    }
                }
                .padding(22)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(ScrollerAutoHide())
            }
        }
        // 整窗【一块】玻璃 + 【一层】工作区光晕。窗口开了 fullSizeContentView，
        // 所以背景用 ignoresSafeArea 就能铺到红绿灯那一行（内容布局仍被安全区挡在下面，
        // 不会像早先那样被裁切）。顶栏与内容因此共用同一块背景，真正沉浸。
        .background {
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                // 背景只剩一层纯色薄纱：不再有渐变/网格，也就没有重绘成本，
                // 不需要 equatable / drawingGroup 那一套了。
                WorkspaceBackground()
            }
            .ignoresSafeArea()
        }
        .overlay(WindowAccessor())
        .onAppear {
            store.start()
            theme.applyAppearance()
        }
        .preferredColorScheme(theme.mode.colorScheme)
    }
}

/// 工作区背景：一层纯色薄纱，仅此而已。
///
/// 这里原来硬画了三团径向光晕（右上红、左下青）+ 一层 26pt 细网格。
/// 问题在于光晕的颜色是写死的，跟壁纸无关 —— 换什么壁纸看到的都是同一套
/// 红青滤镜，而且在暗壁纸上会糊成一片脏色；细网格在高分屏缩小时还会变噪点。
/// 现在只压一层低不透明度纯色，颜色全部交给壁纸：
/// 透过 behindWindow 玻璃折射进来的就是桌面本身的颜色，换壁纸就换氛围。
struct WorkspaceBackground: View {
    var body: some View {
        Palette.veil
            .ignoresSafeArea()
    }
}

struct SidebarView: View {
    @Binding var page: Page
    @EnvironmentObject var store: SensorStore
    /// 选中玻璃滑块的共享坐标空间
    @Namespace private var selectionNS
    /// 液态玻璃的滑动节奏：偏软、带一点回弹，像液体被推过去而不是硬切
    static let selectionSpring = Animation.spring(response: 0.36, dampingFraction: 0.68)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 品牌区
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Palette.accent)
                        .frame(width: 3, height: 14)
                        .shadow(color: Palette.accent.opacity(0.9), radius: 6)
                    Text("VELA")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(2.2)
                        .foregroundStyle(Palette.text)
                    Text("X")
                        .font(.system(size: 14, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Palette.accent)
                }
                Text(store.hardware.productName.isEmpty
                     ? (store.hardware.modelCode.isEmpty ? "macOS" : store.hardware.modelCode)
                     : store.hardware.productName)
                    .font(.system(size: 9.5))
                    .tracking(0.4)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 18)

            VStack(spacing: 2) {
                // 设置不进侧栏导航列表（避免和左下角的「设置」入口重复）；
                // 仍保留在 Page 枚举里，由左下角按钮导航过去。
                ForEach(Page.allCases.filter { $0 != .settings }) { p in
                    Button {
                        guard page != p else { return }
                        // 只在切换选中项时带弹簧动画：整块玻璃滑块会从上一行滑到新行
                        withAnimation(SidebarView.selectionSpring) { page = p }
                    } label: {
                        HStack(spacing: 9) {
                            // 发光竖条画在 SelectionGlass 里，跟着滑块一起移动；
                            // 这里留同宽的透明占位，保证没选中时文字位置不跳
                            Color.clear.frame(width: 2, height: 14)
                            Image(systemName: p.icon)
                                .font(.system(size: 12, weight: page == p ? .semibold : .regular))
                                .frame(width: 15)
                                .foregroundStyle(page == p ? Palette.accent : Palette.textSecondary)
                            Text(p.title)
                                .font(.system(size: 12, weight: page == p ? .semibold : .regular))
                                .tracking(0.4)
                                .foregroundStyle(page == p ? Palette.text : Palette.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 10)
                        .padding(.vertical, 7)
                        .background {
                            // 全场只有这一块玻璃：选中项变了，它靠 matchedGeometryEffect
                            // 在行与行之间滑动，而不是每行各自亮一下
                            if page == p {
                                SelectionGlass(radius: Palette.cornerRadius)
                                    .matchedGeometryEffect(id: "sidebar.selection", in: selectionNS)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                }
            }

            Spacer()

            // 状态区
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(store.smcReady ? Palette.ok : Palette.bad)
                        .frame(width: 5, height: 5)
                        .shadow(color: (store.smcReady ? Palette.ok : Palette.bad).opacity(0.9), radius: 4)
                    Text(store.smcReady ? "AppleSMC 已连接" : "SMC 不可用")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textSecondary)
                }
                Text("\(store.availableCount)/\(store.capabilities.count) 项能力可用")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)

                Divider()
                    .overlay(Palette.hairline)
                    .padding(.vertical, 6)

                // 设置入口：原本散落在侧栏底部的「开机自启 / 外观 / 采样间隔」已收拢到「设置」页
                Button {
                    PageRouter.shared.page = .settings
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Text("设置")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.text)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                        .fill(Palette.faintFill))
                }
                .buttonStyle(.plain)
                .help("开机自启、外观、采样间隔")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 178)
    }
}

// MARK: - 侧栏选中滑块

/// 侧栏选中项的「液态玻璃」滑块。
///
/// 它不是每行各自高亮，而是**一整块玻璃**在行与行之间滑动（由 matchedGeometryEffect
/// 驱动，见 SidebarView）。所以这里画的是「一块有厚度的玻璃」而不是「一层颜色」：
///   · 竖向渐变：顶部镜面高光 → 底部略深，模拟光穿过玻璃的厚度差
///   · 一圈亮边：上沿最亮、往下渐弱，这是玻璃最有辨识度的折射边
///   · 左侧发光竖条放在滑块内部，跟着一起走，不再是「跳过去亮一下」
///
/// 注意：滑块本身**不上强调色**。染色玻璃看起来像一块塑料贴片，
/// 真正的系统侧栏选中态是中性玻璃（浅色偏灰、深色偏白），颜色留给那根竖条。
private struct SelectionGlass: View {
    var radius: CGFloat = 12
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let light = scheme == .light
        // 浅色主题下背景已经接近白色，用「微微压暗的灰玻璃」才有形；
        // 深色主题下反过来用白玻璃提亮。
        let base = light ? Color.black : Color.white
        shape
            .fill(LinearGradient(stops: [
                .init(color: Color.white.opacity(light ? 0.55 : 0.16), location: 0),
                .init(color: base.opacity(light ? 0.055 : 0.075), location: 0.45),
                .init(color: base.opacity(light ? 0.035 : 0.035), location: 1)
            ], startPoint: .top, endPoint: .bottom))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(light ? 0.90 : 0.34),
                                            Color.white.opacity(light ? 0.10 : 0.06)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.8)
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Palette.accent)
                    .frame(width: 2, height: 14)
                    .padding(.leading, 6)
                    .shadow(color: Palette.accent.opacity(0.9), radius: 5)
            }
            // 一点点中性投影，让滑块在玻璃上「浮」起来（不带颜色）
            .shadow(color: Color.black.opacity(light ? 0.10 : 0.28), radius: 6, y: 1)
    }
}

// MARK: - 概览

struct OverviewView: View {
    @EnvironmentObject var store: SensorStore
    @State private var showModelPicker = false
    /// 全量顺序（含被隐藏的卡）；显示时再过滤。这样拖拽排序后存回去不会把隐藏项弄丢。
    @State private var cards: [OverviewCard] = OverviewLayoutPrefs.order
    @State private var hidden: Set<OverviewCard> = OverviewLayoutPrefs.hidden
    /// 正在拖拽的卡片（拖拽排序用）
    @State private var draggingCard: OverviewCard?
    /// 各卡片在全局坐标系下的 frame，松手时用来判断落在哪张卡上
    @State private var dragFrames: [OverviewCard: CGRect] = [:]
    /// 编辑模式（iOS 小组件式）：开 = 窗口固定、卡片可拖/可增删；关 = 窗口可拖、卡片固定。
    @ObservedObject private var windowState = WindowState.shared

    /// 窄卡（功耗/频率/显卡/风扇/电池）统一高度，保证两两并排时对齐
    private let smallCardHeight: CGFloat = 108

    private var visibleCards: [OverviewCard] { cards.filter { !hidden.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if visibleCards.isEmpty {
                emptyHint
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(cardRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            ForEach(row) { card in
                                cardSlot(card)
                            }
                            // 落单的窄卡：补一个等宽透明占位，让它保持半宽。
                            // 否则同一张窄卡「旁边有伴=半宽、落单=整行」会随拖拽位置变宽变窄，
                            // 造成保存后卡片大小不一致。
                            if row.count == 1, let only = row.first, !only.isWide {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .onPreferenceChange(FramePreferenceKey<OverviewCard>.self) { dragFrames = $0 }
            }

            if windowState.isEditMode {
                editToolbar
            }
        }
        .onDisappear {
            // 离开概览页时退出编辑模式，窗口恢复可拖动
            windowState.isEditMode = false
        }
    }

    /// 把可见卡片分成行：宽卡独占一行，窄卡两两并排；落单窄卡占满整行（避免左右不对称）
    private var cardRows: [[OverviewCard]] {
        let list = visibleCards
        var rows: [[OverviewCard]] = []
        var i = 0
        while i < list.count {
            let card = list[i]
            if card.isWide {
                rows.append([card])
                i += 1
            } else if i + 1 < list.count, !list[i + 1].isWide {
                rows.append([card, list[i + 1]])
                i += 2
            } else {
                rows.append([card])
                i += 1
            }
        }
        return rows
    }

    // MARK: - 编辑模式（iOS 小组件式）下的增删与工具栏

    private var hiddenCards: [OverviewCard] { cards.filter { hidden.contains($0) } }

    private var emptyHint: some View {
        Text("还没有显示任何卡片 —— 进编辑模式，用底部「+ 添加小部件」把它们加回来。")
            .font(.system(size: 12))
            .foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    /// 一张卡片在编辑模式下的「槽位」：accent 描边 + 右上角移除角标 + 可拖拽。
    /// 非编辑模式就是普通卡片（无描边、无角标、不可拖）。
    @ViewBuilder
    private func cardSlot(_ card: OverviewCard) -> some View {
        cardView(card)
            // 宽度只由行内布局决定：宽卡独占整行、窄卡固定占半行（落单也补占位），
            // 因此一张卡的大小与它被拖到哪个位置无关，拖拽前后尺寸一致。
            .frame(maxWidth: .infinity)
            .scaleEffect(draggingCard == card ? 1.05 : 1)
            .shadow(color: draggingCard == card ? Color.black.opacity(0.28) : Color.clear,
                    radius: draggingCard == card ? 12 : 0, y: draggingCard == card ? 4 : 0)
            .zIndex(draggingCard == card ? 100 : 0)
            .opacity(draggingCard == card ? 0.95 : 1)
            .overlay(
                RoundedRectangle(cornerRadius: Palette.cornerRadius, style: .continuous)
                    .stroke(windowState.isEditMode ? Palette.accent.opacity(0.6) : Color.clear,
                            lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if windowState.isEditMode {
                    removeBadge(card)
                }
            }
            .animation(.spring(response: 0.30, dampingFraction: 0.8), value: draggingCard)
            .collectFrame(id: card)
            .gesture(windowState.isEditMode ? dragCardGesture(card) : nil)
    }

    /// 编辑模式下每张卡右上角的「移除」角标（minus 圆标）。
    private func removeBadge(_ card: OverviewCard) -> some View {
        Button {
            removeCard(card)
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 18))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Palette.accent)
        }
        .buttonStyle(.plain)
        .offset(x: 8, y: -8)
        .help("移除该卡片")
    }

    /// 编辑模式底部的工具栏：左侧「+ 添加小部件」（弹菜单列出被隐藏的卡），右侧「恢复默认」。
    private var editToolbar: some View {
        HStack(spacing: 10) {
            if hiddenCards.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                    Text("已全部添加")
                }
                .font(.system(size: 11))
                .foregroundStyle(Palette.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.faintFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.hairline, lineWidth: 0.8))
            } else {
                Menu {
                    ForEach(hiddenCards) { card in
                        Button {
                            addCard(card)
                        } label: {
                            Label(card.title, systemImage: card.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加小部件")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.faintFill))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.hairline, lineWidth: 0.8))
                }
                .menuStyle(.borderlessButton)
            }

            Spacer()

            Button("恢复默认") {
                restoreDefaults()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Palette.textSecondary)
        }
    }

    private func removeCard(_ card: OverviewCard) {
        hidden.insert(card)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    private func addCard(_ card: OverviewCard) {
        hidden.remove(card)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    private func restoreDefaults() {
        cards = OverviewCard.allCases
        hidden = []
        OverviewLayoutPrefs.setOrder(cards)
        OverviewLayoutPrefs.setHidden(hidden)
    }

    // MARK: - 长按拖拽排序

    /// 跟手拖拽排序（仅在编辑模式下挂载，见 body 的 .gesture 条件）：
    /// 拖的过程中实时重排——手指移到另一张卡片的槽位上时，立即把被拖卡片插到它旁边，
    /// 其它卡片用弹簧动画让位，整个过程连续顺滑，不再等松手才「啪」地跳一下。
    /// 窗口背景拖动由 WindowState.isEditMode 联动关掉，所以拖卡片时窗口绝不会被带跑。
    private func dragCardGesture(_ card: OverviewCard) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                if draggingCard == nil {
                    // 抓起卡片：弹簧抬起（放大 + 投影），手感更跟手
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.8)) {
                        draggingCard = card
                    }
                }
                // 手指下方（且不是被拖卡片自己）的槽位 → 实时把被拖卡片挪到它旁边
                guard let target = dragFrames.first(where: {
                    $0.key != card && $0.value.contains(value.location)
                })?.key, target != card else { return }
                reorderLive(card, to: target)
            }
            .onEnded { _ in
                // 松手：先把卡片「放下」（缩回 + 投影消失），再持久化顺序。
                // 被拖卡片的槽位在拖拽过程中已经实时挪到位，所以松手没有位置跳变，只是收尾动画。
                withAnimation(.spring(response: 0.30, dampingFraction: 0.8)) {
                    draggingCard = nil
                }
                OverviewLayoutPrefs.setOrder(cards)
            }
    }

    /// 实时重排（不落盘，松手才持久化）：把 card 移动到 target 旁边。
    /// 往下拖插到目标后面，往上拖插到目标前面。外部已用弹簧 withAnimation 包住，卡片让位更顺。
    private func reorderLive(_ card: OverviewCard, to target: OverviewCard) {
        guard let from = cards.firstIndex(of: card),
              let to = cards.firstIndex(of: target), from != to else { return }
        withAnimation(.spring(response: 0.30, dampingFraction: 0.78)) {
            cards.remove(at: from)
            if from < to {
                if let idx = cards.firstIndex(of: target) { cards.insert(card, at: idx + 1) }
                else { cards.append(card) }
            } else {
                if let idx = cards.firstIndex(of: target) { cards.insert(card, at: idx) }
                else { cards.insert(card, at: 0) }
            }
        }
        // 每次实时重排都立刻落盘，而不是只等松手（onEnded）——
        // 拖拽若被中断（切页、手势取消等）导致 onEnded 没触发，顺序也不会丢，重启即还原。
        OverviewLayoutPrefs.setOrder(cards)
    }

    @ViewBuilder
    private func cardView(_ card: OverviewCard) -> some View {
        switch card {
        case .cpuTemp:    cpuCard
        case .gpu:        gpuCard
        case .fan:        fanCard
        case .battery:    batteryCard
        case .disk:       diskCard
        case .load:       LoadCard()
        case .capability: capabilitySummary
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    ROGLogo(height: 21)
                    Text(store.hardware.productName.isEmpty
                         ? (store.hardware.modelName.isEmpty ? "ASUS 笔记本" : store.hardware.modelName)
                         : store.hardware.productName)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(LinearGradient(colors: [Palette.text, Palette.text.opacity(0.65)],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: Palette.accent.opacity(0.35), radius: 12, y: 2)
                    Button {
                        showModelPicker = true
                    } label: {
                        Text("改名")
                            .font(.system(size: 9.5, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.faintFill))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Palette.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("改机型名称")
                    Button {
                        windowState.isEditMode.toggle()
                    } label: {
                        Text(windowState.isEditMode ? "完成" : "编辑")
                            .font(.system(size: 9.5, weight: .medium))
                            .tracking(0.5)
                            .foregroundStyle(windowState.isEditMode ? Palette.accent : Palette.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(windowState.isEditMode ? Palette.accent.opacity(0.15) : Palette.faintFill))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(windowState.isEditMode ? Palette.accent : Palette.hairline, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .help("编辑模式：拖动排序、角标移除卡片、底部「+」添加小部件；窗口临时锁定")
                }
                Spacer()
                HStack(spacing: 0) {
                    headerKPI("温度", store.cpuTemp.map { String(format: "%.0f", $0) } ?? "—", "°C",
                              Palette.forTemp(store.cpuTemp))
                    headerDivider
                    headerKPI("负载", String(format: "%.0f", store.load.total * 100), "%", Palette.accent2)
                    headerDivider
                    headerKPI("内存", String(format: "%.0f", store.load.memoryUsedRatio * 100), "%", Palette.ok)
                }
            }
            HStack(spacing: 6) {
                if !store.hardware.globalName.isEmpty {
                    Pill(text: store.hardware.globalName, color: Palette.textSecondary)
                }
                Pill(text: store.hardware.modelCode.isEmpty ? "—" : store.hardware.modelCode,
                     color: Palette.textSecondary)
                Pill(text: store.hardware.cpuShort)
                Pill(text: String(format: "%.0f GB", store.hardware.ramGB), color: Palette.textSecondary)
                Pill(text: store.hardware.osVersion, color: Palette.textSecondary)
                ForEach(store.hardware.gpus) { gpu in
                    Pill(text: gpu.shortDriver, color: gpu.accelerated ? Palette.ok : Palette.warn)
                }
                if case .available(_, let latest) = store.nvidiaUpdate {
                    Pill(text: "驱动可更新 \(latest)", color: Palette.warn)
                } else if case .failed = store.nvidiaUpdate {
                    Pill(text: "驱动检查失败", color: Palette.textTertiary)
                }
            }
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet().environmentObject(store)
        }
    }

    private func headerKPI(_ label: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .tracking(0.8)
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.5), radius: 8)
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(width: 74, alignment: .trailing)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(Palette.hairline)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 10)
    }

    private var cpuCard: some View {
        // CPU 合并卡：温度环（缩小）+ 状态/最低/最高/热压力/采样，
        // 下方频率（大数 + 心电波形）与功耗（大数 + 折线图）。功耗原独立卡片已并入此处。
        Card(padding: 16, glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "CPU", trailing: "温度 · 频率 · 功耗")
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: 18) {
                    // 仪表盘过大，缩小到 116 更协调
                    TempRing(value: store.cpuTemp, size: 116)
                    VStack(alignment: .leading, spacing: 6) {
                        statLine("状态", store.tempStatusText,
                                 color: Palette.forTemp(store.cpuTemp))
                        statLine("最低", String(format: "%.1f °C", tempMin))
                        statLine("最高", String(format: "%.1f °C", tempMax))
                        statLine("热压力", store.load.thermalText,
                                 color: store.load.thermal == .nominal ? Palette.ok : Palette.warn)
                        statLine("采样", "\(store.sampleCount) 点 · \(store.samplingRate.longLabel)")
                    }
                    // 右侧空白用 CPU 温度曲线填充（Sparkline 无网格 / 表格背景）
                    VStack(alignment: .leading, spacing: 4) {
                        Text("温度曲线")
                            .font(.system(size: 10))
                            .tracking(0.5)
                            .foregroundStyle(Palette.textTertiary)
                        Sparkline(values: store.tempHistory,
                                  color: Palette.forTemp(store.cpuTemp),
                                  lowerBound: 30, upperBound: 100,
                                  filled: false)
                            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 84)
                    }
                    .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 10)
                // 频率：大数 + 心电监护仪风格波形（表征 CPU 频率随时间起伏）
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("频率")
                            .font(.system(size: 10))
                            .tracking(0.5)
                            .foregroundStyle(Palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(store.cpuFreq.liveGHz.map { String(format: "%.2f", $0) } ?? "—")
                                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                                .foregroundStyle(store.cpuFreq.liveGHz != nil ? Color.primary : Palette.textSecondary)
                            Text("GHz")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(width: 78, alignment: .leading)
                    FreqECG(values: store.freqHistory,
                            color: Palette.ok,
                            lower: 0, upper: 5.5, height: 58)
                        .frame(maxWidth: .infinity)
                }
                Spacer(minLength: 8)
                // 功耗：大数 + 折线图（表征 CPU 整包功耗随时间起伏）
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("功耗")
                            .font(.system(size: 10))
                            .tracking(0.5)
                            .foregroundStyle(Palette.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(store.powerWatts.map { String(format: "%.1f", $0) } ?? "—")
                                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                                .foregroundStyle(store.powerWatts != nil ? Color.primary : Palette.textSecondary)
                            Text("W")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(width: 78, alignment: .leading)
                    Sparkline(values: store.powerHistory,
                              color: Palette.accent2,
                              lowerBound: 0, upperBound: 100,
                              filled: true)
                        .frame(maxWidth: .infinity, minHeight: 58, maxHeight: 58)
                }
            }
        }
    }

    private var tempMin: Double { store.tempHistory.min() ?? store.cpuTemp ?? 0 }
    private var tempMax: Double { store.tempHistory.max() ?? store.cpuTemp ?? 0 }

    private func statLine(_ label: String, _ value: String,
                          color: Color = Palette.text) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .tracking(0.5)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var fanCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "风扇", trailing: store.fanAvailable ? "实时" : "不可用")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(store.fanAvailable ? (store.fanRPM.map { String(format: "%.0f", $0) } ?? "—") : "—")
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                        .foregroundStyle(store.fanAvailable ? Color.primary : Palette.textSecondary)
                    Text("RPM")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: store.fanAvailable ? "fanblades.fill" : "fanblades")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Text(store.fanAvailable
                     ? "F0Ac 实时转速"
                     : "FNum 报 \(store.fanCount)、F0Ac 恒为 10000，属占位值")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var batteryCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "电池")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(store.battery.charge)")
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Image(systemName: store.battery.externalPower ? "powerplug.fill" : "battery.50")
                        .font(.system(size: 11))
                        .foregroundStyle(store.battery.externalPower ? Palette.ok : .secondary)
                }
                BatteryBar(percent: store.battery.charge)
                Text("健康 \(String(format: "%.0f%%", store.battery.healthPercent)) · \(store.battery.cycleCount) 次循环")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var diskCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionTitle(text: "磁盘", trailing: store.disk.volumeName.isEmpty ? "启动宗卷" : store.disk.volumeName)
                // 占用率大字 + 剩余
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.0f", store.disk.usedFraction * 100))
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.forDisk(store.disk.usedFraction))
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text("可用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.availableBytes))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
                // 占用率条
                GeometryReader { geo in
                    let w = max(geo.size.width, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.trackFill).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [Palette.forDisk(store.disk.usedFraction),
                                                         Palette.forDisk(store.disk.usedFraction).opacity(0.7)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(w * CGFloat(store.disk.usedFraction), 2), height: 6)
                    }
                }
                .frame(height: 6)
                Text("已用 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.usedBytes)) / 共 \(ByteCountFormatter.vela.string(fromByteCount: store.disk.totalBytes))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var gpuCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                SectionTitle(text: "显卡", trailing: GPUProbe.displayName)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(store.gpuUsage.map { String(format: "%.0f", $0) } ?? "—")
                        .font(.system(size: 25, weight: .semibold).monospacedDigit())
                        .foregroundStyle(store.gpuUsage != nil ? Palette.accent2 : Palette.textSecondary)
                    Text("%")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    if let t = store.gpuTemp {
                        HStack(spacing: 2) {
                            Image(systemName: "thermometer.sun")
                                .font(.system(size: 10))
                            Text(String(format: "%.0f°", t))
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                        }
                        .foregroundStyle(Palette.forTemp(t))
                    }
                }
                Spacer(minLength: 0)
                Text("占用率 + 温度 · 功耗无公开接口")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(height: smallCardHeight)
    }

    private var capabilitySummary: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: "macOS 上的能力边界", trailing: "详见「诊断」")
                ForEach(store.capabilities.prefix(5)) { cap in
                    CapabilityRow(cap: cap)
                }
            }
        }
    }
}


// MARK: - 键盘背光

struct KeyboardView: View {
    @EnvironmentObject var store: SensorStore

    private var presets: [(String, Int)] {
        switch store.kbdMaxLevel {
        case 3:  return [("关", 0), ("低", 1), ("中", 2), ("高", 3)]
        case 16: return [("关", 0), ("低", 4), ("中", 8), ("高", 12), ("最大", 16)]
        default: return []
        }
    }

    private var binding: Binding<Double> {
        Binding(
            get: { Double(store.kbdLevel) },
            set: { store.setKeyboardBacklight(Int($0.rounded())) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "键盘背光",
                         trailing: store.kbdMaxLevel > 0
                            ? "\(store.kbdMode.label) · 0–\(store.kbdMaxLevel) 档"
                            : "不可控")

            if store.kbdMaxLevel == 0 {
                unavailableCard
            } else {
                controlCard
            }

            if let err = store.kbdError {
                Card(padding: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warn)
                        Text(err)
                            .font(.system(size: 11.5))
                            .textSelection(.enabled)
                    }
                }
            }

            channelCard

            AuraPanel()
        }
    }

    // MARK: 正常可调

    private var controlCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.kbdLevel)")
                        .font(.system(size: 46, weight: .semibold).monospacedDigit())
                        .foregroundStyle(store.kbdLevel > 0 ? Palette.accent : Palette.textSecondary)
                    Text("/ \(store.kbdMaxLevel)")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    if store.kbdBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("下发中…")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }

                LevelDots(level: store.kbdLevel, maxLevel: store.kbdMaxLevel) {
                    store.setKeyboardBacklight($0)
                }
                .frame(height: 20)

                if store.kbdMaxLevel > 3 {
                    LevelSlider(value: binding, range: 0...Double(store.kbdMaxLevel), step: 1)
                }

                HStack(spacing: 8) {
                    ForEach(presets.indices, id: \.self) { i in
                        Button(presets[i].0) { store.setKeyboardBacklight(presets[i].1) }
                            .buttonStyle(GrayButtonStyle(prominent: store.kbdLevel == presets[i].1))
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: 不可控

    private var unavailableCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: permissionIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(permissionColor)
                    Text(permissionTitle)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(permissionDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    switch store.kbdPermission {
                    case .needsRestart:
                        Button("立即重启") { HIDBacklight.relaunch() }
                            .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("重置授权") {
                            _ = HIDBacklight.resetPermission()
                            _ = HIDBacklight.requestPermission()
                            store.recheckBacklightPermission()
                        }
                        .buttonStyle(GrayButtonStyle())
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())

                    case .busy:
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle(prominent: true))

                    case .denied:
                        Button("打开系统设置") {
                            if let url = HIDBacklight.privacySettingsURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("重置授权并重新申请") {
                            _ = HIDBacklight.resetPermission()
                            _ = HIDBacklight.requestPermission()
                            store.recheckBacklightPermission()
                        }
                        .buttonStyle(GrayButtonStyle())

                    case .notDetermined:
                        Button("申请权限") {
                            _ = HIDBacklight.requestPermission()
                        }
                        .buttonStyle(GrayButtonStyle(prominent: true))
                        Button("打开系统设置") {
                            if let url = HIDBacklight.privacySettingsURL { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(GrayButtonStyle())

                    default:
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())
                    }

                    if store.kbdPermission == .needsRestart || store.kbdPermission == .denied
                        || store.kbdPermission == .notDetermined {
                        Button("重新检测") { store.recheckBacklightPermission() }
                            .buttonStyle(GrayButtonStyle())
                    }
                    Spacer()
                }

                Text(permissionHint)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 权限文案

    private var permissionIcon: String {
        switch store.kbdPermission {
        case .needsRestart: return "arrow.clockwise.circle"
        case .busy: return "exclamationmark.triangle"
        case .denied: return "lock.slash"
        case .notDetermined: return "lock.shield"
        case .noDevice: return "keyboard.slash"
        default: return "keyboard.slash"
        }
    }

    private var permissionColor: Color {
        switch store.kbdPermission {
        case .needsRestart: return Palette.accent2
        case .noDevice: return Palette.textTertiary
        default: return Palette.warn
        }
    }

    private var permissionTitle: String {
        switch store.kbdPermission {
        case .needsRestart: return "已授权，但当前进程还没生效"
        case .busy: return "背光设备被其他进程占用"
        case .denied: return "「输入监控」权限被拒绝"
        case .notDetermined: return "还没有拿到「输入监控」权限"
        case .noDevice: return "没有找到 Aura HID 控制器"
        default: return "这台机器在 macOS 下没有可用的背光通道"
        }
    }

    private var permissionDetail: String {
        switch store.kbdPermission {
        case .busy:
            return "Aura 控制器已经能打开到一半，但被别的进程独占了（kIOReturnExclusiveAccess）。常见原因是还开着一个旧的 Vela X 实例，或者别的键盘灯工具在跑。"
        case .needsRestart:
            return "系统设置里已经勾选了本程序，macOS 也确认授权状态是 granted，但这一次进程启动时还没读到这条授权 —— 权限判断在进程启动那一刻缓存，必须在授权之后重新打开才会生效。"
        case .denied:
            return "macOS 明确拒绝了键盘类 HID 设备的访问（kIOReturnNotPermitted）。可能是授权被撤销，也可能是重新编译后二进制变了：ad-hoc 签名下 TCC 用 cdhash 记录授权，换一次构建就对不上了。"
        case .notDetermined:
            return "这台机器的键盘背光由键盘控制器的 Aura HID 接口负责（0x0B05:0x19B6）。macOS 只允许拿到「输入监控」权限的进程打开键盘类 HID 设备。"
        case .noDevice:
            return "枚举了 IOHIDDevice 也没找到 0x0B05 的 Aura 控制器，背光通道完全不存在，跟权限无关。"
        default:
            return "ATK 设备没有 SKBV 方法（AsusSMC 报 IsKeyboardBacklightSupported=No），也没找到 Aura HID 控制器，写 LKSB 只会改影子值。"
        }
    }

    private var permissionHint: String {
        switch store.kbdPermission {
        case .busy:
            return "退出其它 Vela X 实例（菜单栏图标右键退出，或活动监视器里结束），再点「重新检测」。"
        case .needsRestart:
            return "点「立即重启」会自动重开本程序；之后「键盘背光」页应直接变成 0–3 档可调。"
        case .denied:
            return "顺序：打开系统设置 → 隐私与安全性 → 输入监控 → 勾选 Vela X；如果列表里的开关已经是开的，先点「重置授权并重新申请」再去勾选，然后重启程序。"
        case .notDetermined:
            return "点「申请权限」后系统会弹窗，勾选完必须重启程序（菜单栏图标右键 → 退出，再重新打开 App），之后这里会变成 0–3 档可调。"
        case .noDevice:
            return "可能这是 2021 年前的老机型，背光走 SMC 的 LKSB 通道；可以到「诊断」页看 AsusSMC 的 SKBV 状态。"
        default:
            return "怎么修：见「诊断」页（给 ATK 设备补 SKBV，或让 AsusSMC 改走 ASUS WMI 的 0x00050021 背光设备）。"
        }
    }

    private var channelDetail: String {
        switch store.kbdPermission {
        case .needsRestart:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），授权也拿到了，只剩「重启程序」这一步 —— TCC 的判定在进程启动时读取一次，不重启就一直被拒。"
        case .denied:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），但「输入监控」被拒绝；重置授权后重新勾选，再重启程序。"
        case .notDetermined:
            return "Aura HID 控制器已找到（0x0B05:0x19B6），还没有申请「输入监控」授权。"
        default:
            return store.kbdMode.detail
        }
    }

    // MARK: 通道说明

    private var channelCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前走的是哪条通道")
                    .font(.system(size: 12.5, weight: .semibold))
                LabelValue(label: "通道", value: store.kbdMode.label, mono: true)
                LabelValue(label: "档位", value: store.kbdMaxLevel > 0 ? "0 – \(store.kbdMaxLevel)" : "—", mono: true)
                if case .hid = store.kbdMode {
                    LabelValue(label: "写入方式", value: HIDBacklight.shared.writeMethodText, mono: true)
                }
                Text(channelDetail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .hid = store.kbdMode {
                    Text("Aura HID 通道没有回读接口，界面上显示的档位是本程序上次成功下发的值；如果你用 Fn+F7 改了亮度，这里的数字不会跟着变。命令 asuscontrol kbd 可以查看当前通道和记录值。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                } else if case .smc = store.kbdMode {
                    Text("写入 LKSB 需要 root：AsusSMC 的 handler 会把它换算成 ACPI SKBV 的参数。首次修改会弹一次系统授权框，同一会话内后续调整不再弹。")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - 性能与风扇

struct PerformanceView: View {
    @EnvironmentObject var store: SensorStore
    /// 风扇档位状态（kext 状态、双风扇转速、下发进度、机型选择）
    @StateObject private var fan = FanControl.shared
    /// 手动输入机型代码的临时文本
    @State private var manualModel = ""
    /// 是否展开「判定依据」（各候选机型的得分与命中项）
    @State private var showEvidence = false
    /// 免责声明弹窗的当前任务（nil = 不显示）。preset 为要应用的档位，nil 表示仅确认
    @State private var disclaimerItem: DisclaimerItem?

    /// 免责弹窗要确认的任务
    private struct DisclaimerItem: Identifiable {
        let id = UUID()
        /// 确认后要应用的档位名；nil 表示只是「查看风险并继续」的确认
        let preset: String?
    }

    struct ModeInfo: Identifiable {
        let id = UUID()
        let name: String
        let icon: String
        let desc: String
    }


    private let modes: [ModeInfo] = [
        .init(name: "静音", icon: "leaf", desc: "风扇低速、CPU 限功耗"),
        .init(name: "平衡", icon: "equal", desc: "按负载动态调度"),
        .init(name: "增强", icon: "flame", desc: "风扇全速、功耗放开")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "性能模式", trailing: "ASUS WMI · 不可用")

            HStack(spacing: 12) {
                ForEach(modes) { mode in
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.textSecondary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Text(mode.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.textSecondary)
                            Text(mode.desc)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .opacity(0.62)
                }
            }

            SectionTitle(text: "风扇曲线",
                         trailing: fan.kextLoaded ? (fan.kextBuild ?? "kext 已加载") : "kext 未加载")

            // MARK: 机型识别
            // 不同机型 EC 配置不同：先认出真实机型，机主可手动选（按型号名），
            // 所选机型与检测到的硬件不一致时，应用曲线前必须确认硬件损坏风险。
            Card {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(spacing: 10) {
                        Text("机型")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer(minLength: 6)
                        // 匹配状态指示（三态：匹配 / 没能自动识别 / 不匹配）
                        HStack(spacing: 4) {
                            Circle().fill(modelStatusColor(fan.status))
                                .frame(width: 6, height: 6)
                            Text(modelStatusLabel(fan.status))
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(modelStatusColor(fan.status))
                        }
                        // 快速选择菜单（判定出的机型 + 已收录机型族）
                        Menu {
                            if fan.detection.confidence != .none {
                                Button {
                                    fan.selectModel(fan.detection.code)
                                } label: {
                                    Label("使用判定的机型 \(fan.detection.code)（推荐）",
                                          systemImage: "checkmark.circle")
                                }
                                Divider()
                            }
                            ForEach(ECProfiles.catalog, id: \.id) { p in
                                Button {
                                    fan.selectModel(p.modelCodes.first ?? p.familyName)
                                } label: {
                                    Text("\(p.familyName)  ·  \(p.modelCodes.first ?? "")")
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(fan.selectedCode.isEmpty ? "选择机型" : fan.selectedCode)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Palette.accent.opacity(0.16)))
                            .foregroundStyle(Palette.accent)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // 判定出的机型 + 置信度
                    HStack(spacing: 4) {
                        Text(fan.detection.confidence == .none ? "未能识别" : "推断")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                        Text(fan.detection.confidence == .none
                             ? "本机硬件指纹不匹配任何已收录机型"
                             : "\(fan.detection.code)（\(fan.detection.name)）")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        if fan.detection.confidence != .none {
                            Text("· \(fan.detection.confidence.label)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }

                    // 硬件指纹（判定依据的原始数据）
                    if !fan.detection.evidenceLine.isEmpty {
                        Text(fan.detection.evidenceLine)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // 电池部件号：明确说明它不作数，免得机主以为「程序认错机型了」
                    if let part = fan.detection.fingerprint.batteryName {
                        Text("电池部件号 \(part)：多机型共用，不作判定依据")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
                    }

                    // 展开每个候选机型的命中项
                    Button {
                        showEvidence.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Text(showEvidence ? "收起判定依据" : "查看判定依据")
                                .font(.system(size: 9.5, weight: .medium))
                            Image(systemName: showEvidence ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                        }
                        .foregroundStyle(Palette.accent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showEvidence {
                        VStack(alignment: .leading, spacing: 5) {
                            if fan.detection.scores.isEmpty {
                                Text("没有任何已收录机型命中本机硬件。请对照机身底部或包装箱上的型号手动选择。")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(fan.detection.scores, id: \.profile.id) { s in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(s.profile.modelCodes.first ?? s.profile.familyName) · \(s.points) 分")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(Palette.textSecondary)
                                        ForEach(s.reasons, id: \.self) { r in
                                            Text("· \(r)")
                                                .font(.system(size: 9.5))
                                                .foregroundStyle(Palette.textTertiary)
                                        }
                                    }
                                }
                            }
                            Text("推断以独显型号为主（同 CPU 的枪神/魔霸靠独显档位区分），CPU 只看世代；不看 SMBIOS（黑苹果下已换成 Mac），也不看电池部件号。")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 2)
                    }

                    // 手动输入机型（按型号名）
                    HStack(spacing: 8) {
                        TextField("输入机型代码，如 G513RM", text: $manualModel)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Palette.panelTop.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Palette.cardStroke, lineWidth: 0.6)))
                        Button {
                            fan.selectModel(manualModel)
                            manualModel = ""
                        } label: {
                            Text("应用此机型")
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .disabled(manualModel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .foregroundStyle(Palette.accent)
                    }

                    // 已收录机型的 EC 配置摘要
                    if let p = fan.ecProfile {
                        HStack(spacing: 4) {
                            Text("EC 配置")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textTertiary)
                            Text("\(p.ecChip) · \(p.ecFirmware)")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textSecondary)
                            Text("· \(p.verification.label)")
                                .font(.system(size: 10))
                                .foregroundStyle(p.verification == .verifiedOnDevice
                                                 ? Palette.ok : Palette.warn)
                            if fan.ecLevel == .compatible {
                                Text("（家族兼容，未本机验证）")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(Palette.warn)
                            }
                        }

                        // 逆向未实机验证的机型：把「先做只读验证」讲清楚，
                        // 别让人误以为和实机验证过的机型一样可以放心直接下发
                        if let caveat = p.verification.caveat {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.warn)
                                Text(caveat)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.warn)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(alignment: .center, spacing: 20) {
                        fanStat("CPU 风扇", "\(fan.rpmCPU)")
                        fanStat("GPU 风扇", "\(fan.rpmGPU)")
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("当前档位")
                                .font(.system(size: 9.5))
                                .foregroundStyle(Palette.textTertiary)
                            Text(currentPresetLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(fan.lastApplied == nil ? Palette.textSecondary : Palette.accent)
                        }
                    }

                    if !fan.kextLoaded {
                        Text("没有检测到 SMCAsusFan kext（SMC 键 AFMd 不存在）。转速和曲线下发都依赖它：装上 kext 重启后，这里会自动出现三个档位。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.warn)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let presets = fan.presets {
                        VStack(spacing: 6) {
                            ForEach(FanControl.order, id: \.self) { name in
                                if let preset = presets.preset(name) {
                                    presetRow(name: name, preset: preset)
                                }
                            }
                        }
                    } else if let err = fan.loadError {
                        Text("读不到风扇曲线配置：\(err)")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let message = fan.message {
                        Text(message)
                            .font(.system(size: 10.5))
                            .foregroundStyle(message.hasPrefix("已切到") ? Palette.ok : Palette.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 机型不匹配 → 硬件损坏风险警告（应用曲线前必须先确认）
            if fan.status == .mismatched {
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Palette.bad).font(.system(size: 14))
                            Text("机型不匹配：写入曲线可能损坏硬件")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.bad)
                        }
                        Text("你选择的「\(fan.selectedCode)」与本机判定出的「\(fan.detection.code)」不一致（判定依据：\(fan.detection.evidenceLine)）。风扇曲线和 EC 配置是按特定机型逆向的，套错机型可能让风扇停转或狂转，导致过热甚至永久损坏。每次应用曲线前都必须先确认风险。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !fan.acknowledgedMismatch {
                            Button {
                                // 打开免责声明弹窗（不立即应用，仅做确认）
                                disclaimerItem = DisclaimerItem(preset: nil)
                            } label: {
                                Text("查看风险并继续")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .padding(.horizontal, 11).padding(.vertical, 5)
                                    .background(Capsule().fill(Palette.bad.opacity(0.15)))
                                    .overlay(Capsule().stroke(Palette.bad.opacity(0.4), lineWidth: 0.8))
                                    .foregroundStyle(Palette.bad)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("已确认风险，可以继续应用曲线。")
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.ok)
                        }
                    }
                }
            }

            // 没能自动识别机型 → 提示先核对型号（同样要求确认一次，因为无从核对）
            if fan.status == .undetected, !fan.acknowledgedMismatch {
                Card {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 7) {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundStyle(Palette.warn).font(.system(size: 14))
                            Text("机型未能自动识别")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.warn)
                        }
                        Text("本机硬件指纹（\(fan.detection.evidenceLine)）没有匹配到任何已收录机型，无法核对你选的「\(fan.selectedCode)」。曲线和 EC 配置是按特定机型逆向的，机型不对可能损坏硬件：请对照机身底部或包装箱上的型号核对后，再点下面的按钮确认。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            disclaimerItem = DisclaimerItem(preset: nil)
                        } label: {
                            Text("核对并确认机型")
                                .font(.system(size: 10.5, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 5)
                                .background(Capsule().fill(Palette.warn.opacity(0.15)))
                                .overlay(Capsule().stroke(Palette.warn.opacity(0.4), lineWidth: 0.8))
                                .foregroundStyle(Palette.warn)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("这条通道是怎么打通的")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("""
                    SMCAsusFan.kext 在内核态把 EC 的风扇曲线邮箱（MMIO 0xFE700C00）映射成 SMC 键：\
                    AFMf 选风扇、AFW1…AFW4 装 8 个温度点和 8 个占空比、AFWg 提交；转速走 F0Ac / F1Ac。

                    写 SMC 键必须 root，所以点「应用」时会走一次系统授权，只在那一下提权，\
                    程序本身不常驻 root。EC 不回显写进去的曲线，唯一可靠的证据是转速变化。

                    风险：EC 写入错误可能导致风扇失控。真出问题时断电重启即可回到出厂曲线；\
                    动手前建议先用 tools/curve.py read 0 备份原始曲线。
                    """)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(2.5)
                }
            }
        }
        .onAppear { fan.refresh() }
        // 只有这一页需要实时转速，定时器随页面出现/消失，不常驻
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            if fan.applying == nil { fan.refresh() }
        }
        // 机型不匹配的硬件损坏风险免责弹窗（由本地 @State 驱动，避免属性环）
        .sheet(item: $disclaimerItem) { item in
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.bad).font(.system(size: 22))
                    Text(fan.status == .mismatched
                         ? ModelDisclaimer.title
                         : ModelDisclaimer.titleUndetected)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    Text(fan.status == .mismatched
                         ? ModelDisclaimer.body(selected: fan.selectedCode,
                                                detected: fan.detection.code)
                         : ModelDisclaimer.bodyUndetected(selected: fan.selectedCode))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.text)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 230)
                HStack(spacing: 10) {
                    Button {
                        disclaimerItem = nil
                    } label: {
                        Text("取消").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        fan.acknowledgeMismatch()
                        if let name = item.preset {
                            fan.apply(name)
                        } else {
                            fan.noteConfirmed()
                        }
                        disclaimerItem = nil
                    } label: {
                        Text("我已知晓风险并继续").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.bad)
                }
            }
            .padding(20)
            .frame(width: 430)
        }
    }

    private func modelStatusColor(_ s: ModelMatch) -> Color {
        switch s {
        case .matched: return Palette.ok
        case .undetected: return Palette.warn
        case .mismatched: return Palette.bad
        }
    }

    private func modelStatusLabel(_ s: ModelMatch) -> String {
        switch s {
        case .matched: return "机型匹配"
        case .undetected: return "机型待确认"
        case .mismatched: return "机型不匹配"
        }
    }

    private var currentPresetLabel: String {
        guard let name = fan.lastApplied else { return "未记录" }
        return fan.presets?.preset(name)?.label ?? name
    }

    /// 点「应用」档位：机型匹配或已确认风险 → 直接下发；否则先弹免责声明
    private func requestFanApply(_ name: String) {
        if fan.status == .matched || fan.acknowledgedMismatch {
            fan.apply(name)
        } else {
            disclaimerItem = DisclaimerItem(preset: name)
        }
    }

    private func fanStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9.5))
                .foregroundStyle(Palette.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.text)
                Text("RPM")
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func presetRow(name: String, preset: FanPreset) -> some View {
        let active = fan.lastApplied == name
        return HStack(spacing: 12) {
            FanCurveSparkline(curve: preset.cpu, highlighted: active)
                .frame(width: 92, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(preset.label ?? name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    if active {
                        Text("使用中")
                            .font(.system(size: 8.5, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Palette.accent.opacity(0.18)))
                            .foregroundStyle(Palette.accent)
                    }
                }
                Text(preset.desc ?? "—")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                requestFanApply(name)
            } label: {
                Group {
                    if fan.applying == name {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Text(active ? "重新下发" : "应用")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .frame(width: 54)
                .padding(.vertical, 4)
                .background(Capsule().fill(Palette.accent.opacity(active ? 0.10 : 0.16)))
                .overlay(Capsule().stroke(Palette.accent.opacity(0.32), lineWidth: 0.8))
                .foregroundStyle(Palette.accent)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(fan.applying != nil || !fan.kextLoaded)
            .opacity(fan.kextLoaded ? 1 : 0.4)
            .help("写入这条曲线需要管理员授权")
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 风扇曲线缩略图

/// 把 8 个温度/占空比断点画成一条折线。
/// 不用 Canvas 的曲线平滑：这条线要能看出拐点，平滑后反而失真。
private struct FanCurveSparkline: View {
    let curve: FanCurve
    var highlighted: Bool

    var body: some View {
        Canvas { ctx, size in
            let n = curve.temp.count
            guard n > 1 else { return }
            func point(_ i: Int) -> CGPoint {
                let x = CGFloat(i) / CGFloat(n - 1) * size.width
                let duty = CGFloat(min(max(curve.duty[i], 0), 100)) / 100
                return CGPoint(x: x, y: size.height - duty * size.height)
            }
            var line = Path()
            for i in 0..<n {
                let p = point(i)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()

            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [Palette.accent.opacity(highlighted ? 0.22 : 0.10),
                                  Palette.accent.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(Palette.accent.opacity(highlighted ? 0.95 : 0.55)),
                       style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
            for i in 0..<n {
                let p = point(i)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8)),
                         with: .color(Palette.accent.opacity(highlighted ? 0.95 : 0.5)))
            }
        }
    }
}

// MARK: - 诊断

struct DiagnosticsView: View {
    @EnvironmentObject var store: SensorStore
    @State private var showKeys = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "能力矩阵", trailing: "实时探测")

            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.capabilities.enumerated()), id: \.element.id) { idx, cap in
                        CapabilityRow(cap: cap)
                        if idx < store.capabilities.count - 1 {
                            Divider().opacity(0.4)
                        }
                    }
                }
            }

            SectionTitle(text: "数据来源")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(DataSourceCatalog.all.enumerated()), id: \.element.id) { idx, item in
                        HStack(spacing: 10) {
                            Text(item.metric)
                                .font(.system(size: 11.5, weight: .medium))
                                .frame(width: 92, alignment: .leading)
                            Text(item.channel)
                                .font(.system(size: 10.5).monospaced())
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 250, alignment: .leading)
                            Text(item.needsKext ? "依赖 kext" : "无需 kext")
                                .font(.system(size: 10))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Capsule().fill((item.needsKext ? Palette.warn : Palette.ok).opacity(0.13)))
                                .foregroundStyle(item.needsKext ? Palette.warn : Palette.ok)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        if idx < DataSourceCatalog.all.count - 1 { Divider().opacity(0.35) }
                    }
                }
            }

            SectionTitle(text: "硬件与驱动")
            Card {
                VStack(alignment: .leading, spacing: 9) {
                    LabelValue(label: "商品名", value: store.hardware.productName.isEmpty ? "—" : store.hardware.productName)
                    LabelValue(label: "海外名", value: store.hardware.globalName.isEmpty ? "—" : store.hardware.globalName)
                    LabelValue(label: "机型代码", value: store.hardware.modelCode.isEmpty ? "—" : store.hardware.modelCode)
                    LabelValue(label: "名称来源", value: store.hardware.nameSource)
                    LabelValue(label: "厂商", value: store.hardware.vendor)
                    LabelValue(label: "处理器", value: store.hardware.cpu)
                    LabelValue(label: "线程数", value: "\(store.hardware.cores)")
                    LabelValue(label: "内存", value: String(format: "%.0f GB", store.hardware.ramGB))
                    LabelValue(label: "系统", value: store.hardware.osVersion)
                    ForEach(store.hardware.gpus) { gpu in
                        LabelValue(label: "显卡", value: "\(gpu.name) — \(gpu.driver)")
                    }
                    LabelValue(label: "内核扩展", value: store.kexts.summary)
                    LabelValue(label: "SMC 键数量", value: "\(store.keyNames.count)")
                    LabelValue(label: "采样间隔", value: "\(store.samplingRate.longLabel) · \(store.samplingRate.summary)")
                    LabelValue(label: "已完成采样", value: "\(store.sampleCount) 次")
                    LabelValue(label: "用户", value: Admin.isRoot ? "root（可直接写 SMC）" : "普通用户（写入需授权）")
                }
            }

            HStack(spacing: 8) {
                Button {
                    copyReport()
                } label: {
                    Text(copied ? "已复制" : "复制诊断报告")
                }
                .buttonStyle(GrayButtonStyle(prominent: true))

                Button {
                    showKeys.toggle()
                } label: {
                    Text(showKeys ? "隐藏 SMC 键" : "查看全部 SMC 键")
                }
                .buttonStyle(GrayButtonStyle())

                if showKeys {
                    Button {
                        store.reloadAllReadings()
                    } label: {
                        Text("刷新读数")
                    }
                    .buttonStyle(GrayButtonStyle())
                }
                Spacer()
            }

            if showKeys {
                Card(padding: 12) {
                    if store.readings.isEmpty {
                        Text("正在读取…")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 6)], spacing: 4) {
                                ForEach(store.readings, id: \.key) { r in
                                    HStack(spacing: 6) {
                                        Text(r.key)
                                            .font(.system(size: 10).monospaced())
                                            .foregroundStyle(Palette.accent)
                                        Text(r.display)
                                            .font(.system(size: 10).monospacedDigit())
                                        Spacer(minLength: 0)
                                        Text(r.type.trimmingCharacters(in: .whitespaces))
                                            .font(.system(size: 8.5).monospaced())
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: 260)
                    }
                }
                .onAppear {
                    if store.readings.isEmpty { store.reloadAllReadings() }
                }
            }
        }
    }

    private func copyReport() {
        var lines: [String] = []
        lines.append("Vela X 诊断报告")
        lines.append("机型: \(store.hardware.modelName) (\(store.hardware.modelCode))")
        lines.append("CPU: \(store.hardware.cpu) / \(store.hardware.cores) 线程")
        lines.append("系统: \(store.hardware.osVersion)")
        lines.append("驱动: \(store.kexts.summary)")
        lines.append("SMC 键: \(store.keyNames.count)")
        lines.append("")
        for cap in store.capabilities {
            lines.append("[\(cap.status.badge)] \(cap.title): \(cap.summary)")
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lines.joined(separator: "\n"), forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
    }
}

// MARK: - 机型改名

struct ModelPickerSheet: View {
    @EnvironmentObject var store: SensorStore
    @Environment(\.dismiss) private var dismiss
    @State private var customName = ""
    @State private var filter = ""

    private var filtered: [ASUSModel] {
        guard !filter.isEmpty else { return ModelCatalog.all }
        return ModelCatalog.all.filter {
            $0.china.localizedCaseInsensitiveContains(filter)
                || $0.code.localizedCaseInsensitiveContains(filter)
                || $0.global.localizedCaseInsensitiveContains(filter)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("机型名称")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(store.hardware.nameSource)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }

            Text("黑苹果用 OpenCore 覆盖了 SMBIOS，macOS 里读不到真实 DMI。下面是 EC 上报的代码 \(store.hardware.modelCode) 对应的零售名，选不对可以直接输入。")
                .font(.system(size: 11))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("搜索型号 / 名称", text: $filter)
                .textFieldStyle(.roundedBorder)

            List(filtered) { model in
                Button {
                    store.setProductName(model.china, global: model.global)
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Text(model.code).font(.system(size: 11).monospaced())
                            .foregroundStyle(Palette.textSecondary).frame(width: 52, alignment: .leading)
                        Text(model.china).font(.system(size: 12))
                        Text(model.note.isEmpty ? "" : model.note)
                            .font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                        Spacer()
                        Text(model.global).font(.system(size: 10)).foregroundStyle(Palette.textSecondary)
                        if store.hardware.productName == model.china {
                            Image(systemName: "checkmark").font(.system(size: 10))
                                .foregroundStyle(Palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 200)

            Divider()

            HStack(spacing: 8) {
                TextField("自定义名称", text: $customName)
                    .textFieldStyle(.roundedBorder)
                Button("应用") {
                    let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        store.setProductName(trimmed)
                        dismiss()
                    }
                }
                .buttonStyle(GrayButtonStyle(prominent: true))
                .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack {
                Button("恢复自动识别") {
                    store.setProductName(nil)
                    dismiss()
                }
                .buttonStyle(GrayButtonStyle())
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(GrayButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 520, height: 470)
    }
}
