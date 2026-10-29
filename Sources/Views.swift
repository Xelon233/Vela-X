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
    case overview, monitor, sensors, keyboard, menubar, performance, nvidia, diagnostics, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "概览"
        case .monitor: return "监控"
        case .sensors: return "传感器"
        case .keyboard: return "键盘背光"
        case .menubar: return "菜单栏"
        case .performance: return "性能与风扇"
        case .nvidia: return "NVIDIA 驱动"
        case .diagnostics: return "诊断"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .monitor: return "waveform.path.ecg"
        case .sensors: return "thermometer.medium"
        case .keyboard: return "keyboard"
        case .menubar: return "menubar.dock.rectangle"
        case .performance: return "fanblades"
        case .nvidia: return "display"
        case .diagnostics: return "stethoscope"
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
                    case .sensors: SensorsView()
                    case .keyboard: KeyboardView()
                    case .menubar: MenuBarSettingsView()
                    case .performance: PerformanceView()
                    case .nvidia: NvidiaView()
                    case .diagnostics: DiagnosticsView()
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
    @EnvironmentObject var theme: ThemeManager
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
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
                ForEach(Page.allCases) { p in
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

                // 开机自启：登录时只在菜单栏起来，不弹主窗口
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(launchAtLogin ? Palette.accent : Palette.textTertiary)
                    Text("开机自启")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
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
                .help("登录时自动在菜单栏启动，不弹主窗口")

                if let launchError {
                    Text(launchError)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("外观")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: 6) {
                    ForEach(ThemeMode.allCases) { m in
                        Button {
                            theme.mode = m
                        } label: {
                            VStack(spacing: 2) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 10, weight: .medium))
                                Text(m.label)
                                    .font(.system(size: 8.5, weight: theme.mode == m ? .semibold : .regular))
                                    .tracking(0.3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
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

                Text("采样间隔")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 4)
                SegmentedButtons(items: SamplingRate.allCases.map { ($0.label, $0) },
                                 selection: Binding(get: { store.samplingRate },
                                                    set: { store.setSamplingRate($0) }))
                    .help(store.samplingRate.summary)
                Text(store.samplingRate.summary)
                    .font(.system(size: 9))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(width: 178)
        // 开机自启的真实状态要在 view 出现后再读一次：
        // AppDelegate 里的 LaunchAgent 迁移/修复晚于视图构建，首帧读到的会是旧值。
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
        // 注意：这里【不能】加 .drawingGroup()。侧栏里的 Toggle（开机自启）是
        // AppKit 托管的控件，被拍进 Metal 纹理后画不出来，会变成一个黄底禁止符号。
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 12) {
                temperatureCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                VStack(spacing: 12) {
                    fanCard
                    batteryCard
                }
                .frame(width: 252)
            }
            .frame(height: 240)

            keyboardCard
            LoadCard()
            capabilitySummary
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

    private var temperatureCard: some View {
        // 原来这里带 accent: 会在卡片左缘竖一条贯穿整卡的橙色霓虹条（随温度变色），
        // 视觉上太抢，已去掉；状态色彩仍由标题小竖条、温度环和数值本身表达。
        Card(padding: 16, glow: true) {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle(text: "CPU 温度", trailing: "SMC · TC0P")
                Spacer(minLength: 10)
                HStack(alignment: .center, spacing: 22) {
                    TempRing(value: store.cpuTemp, size: 162)
                    VStack(alignment: .leading, spacing: 8) {
                        statLine("状态", store.tempStatusText,
                                 color: Palette.forTemp(store.cpuTemp))
                        statLine("最低", String(format: "%.1f °C", tempMin))
                        statLine("最高", String(format: "%.1f °C", tempMax))
                        statLine("热压力", store.load.thermalText,
                                 color: store.load.thermal == .nominal ? Palette.ok : Palette.warn)
                        statLine("采样", "\(store.sampleCount) 点 · \(store.samplingRate.longLabel)")
                    }
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 10)
            }
            .frame(maxHeight: .infinity)
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
        .frame(maxHeight: .infinity)
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
        .frame(maxHeight: .infinity)
    }

    private var keyboardCard: some View {
        Card {
            HStack(spacing: 16) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 17))
                    .foregroundStyle(store.kbdMaxLevel > 0 ? Palette.accent : Palette.textSecondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("键盘背光")
                            .font(.system(size: 12.5, weight: .medium))
                        if store.kbdMaxLevel > 0 {
                            Text("\(store.kbdLevel)/\(store.kbdMaxLevel)")
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(Palette.textSecondary)
                            Pill(text: store.kbdMode.label, color: Palette.textSecondary)
                        } else {
                            Pill(text: "不可控", color: Palette.warn)
                        }
                        if store.kbdBusy {
                            ProgressView().controlSize(.mini).scaleEffect(0.7)
                        }
                    }
                    if store.kbdMaxLevel > 0 {
                        LevelDots(level: store.kbdLevel, maxLevel: store.kbdMaxLevel) {
                            store.setKeyboardBacklight($0)
                        }
                    } else if store.kbdPermission == .needsRestart {
                        Text("已授权，需重启程序后生效 —— 去「键盘背光」页点「立即重启」")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accent2)
                    } else if store.kbdPermission == .denied {
                        Text("「输入监控」被拒绝 —— 去「键盘背光」页重新授权")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.warn)
                    } else if store.kbdPermission == .notDetermined {
                        Text("尚未获得「输入监控」授权 —— 去「键盘背光」页申请")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.warn)
                    } else {
                        Text("ATK 设备无 SKBV，且未找到 Aura HID 控制器 —— 详见「诊断」")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                if store.kbdMaxLevel > 0 {
                    Button {
                        store.setKeyboardBacklight(store.kbdLevel > 0 ? 0 : store.kbdMaxLevel)
                    } label: {
                        Text(store.kbdLevel > 0 ? "关闭" : "开启")
                    }
                    .buttonStyle(GrayButtonStyle())
                }
            }
        }
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

// MARK: - 传感器

struct SensorsView: View {
    @EnvironmentObject var store: SensorStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "温度曲线", trailing: "最近 240 秒")

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.cpuTemp.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 30, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.forTemp(store.cpuTemp))
                        Text("°C")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.textSecondary)
                        Spacer()
                        Text(store.tempStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.forTemp(store.cpuTemp))
                    }
                    TempChart(values: store.tempHistory,
                              color: Palette.forTemp(store.cpuTemp),
                              lower: 35, upper: 100, height: 150)
                }
            }

            SectionTitle(text: "内核计数器", trailing: "不依赖 kext")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 22) {
                        CoreBars(values: store.load.perCore, height: 54, showLabels: true)
                            .frame(width: 300, alignment: .leading)
                        VStack(alignment: .leading, spacing: 5) {
                            LabelValue(label: "总占用",
                                       value: String(format: "%.1f%%  (%d 线程)",
                                                     store.load.total * 100, store.load.perCore.count))
                            LabelValue(label: "负载均值",
                                       value: String(format: "%.2f / %.2f / %.2f",
                                                     store.load.load1, store.load.load5, store.load.load15))
                            LabelValue(label: "内核热压力", value: store.load.thermalText)
                            LabelValue(label: "内存占用",
                                       value: String(format: "%.1f%%", store.load.memoryUsedRatio * 100))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("这些读数来自 Mach 内核计数器（host_processor_info / host_statistics64 / ProcessInfo.thermalState），和 VirtualSMC 无关，也不经过任何 kext。CPU 温度是个例外：macOS 没有 /dev/mem，MSR/SMN 只能在内核态读，所以温度只能取 SMC 的值。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SectionTitle(text: "实时读数", trailing: store.kbdMode.maxLevel > 0 ? "\(store.samplingRate.longLabel)刷新" : "")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                      spacing: 12) {
                ForEach(SMCKeyCatalog.interesting, id: \.key) { meta in
                    readingTile(meta)
                }
            }
        }
        .onAppear { store.setTilesActive(true) }
        .onDisappear { store.setTilesActive(false) }
    }

    private func readingTile(_ meta: SMCKeyMeta) -> some View {
        let fanHidden = (meta.key == "F0Ac" && !store.fanAvailable)
        // 读数来自采样器缓存：原来在 body 里直接 SMC.read，每秒重排 10 次 IOKit 往返
        let r = fanHidden ? nil : store.tiles[meta.key]
        return Card(padding: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(meta.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Text(meta.key)
                        .font(.system(size: 9.5).monospaced())
                        .foregroundStyle(Palette.textTertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(r?.number.map { String(format: "%.\(meta.decimals)f", $0) } ?? "—")
                        .font(.system(size: 19, weight: .semibold).monospacedDigit())
                        .foregroundStyle(r?.number == nil ? Palette.textSecondary : Color.primary)
                    Text(meta.unit)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.textSecondary)
                }
                if fanHidden {
                    Text("FNum 报 \(store.fanCount)，F0Ac 为占位值")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                } else if meta.key == "FNum" && !store.fanAvailable {
                    Text("SMC 上报值，与实机不符")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.textTertiary)
                } else if let r, r.number == nil {
                    Text(r.hex.isEmpty ? "无数据" : r.hex)
                        .font(.system(size: 9).monospaced())
                        .foregroundStyle(Palette.textTertiary)
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
                        // 匹配状态指示
                        let matched = fan.status == .matched
                        HStack(spacing: 4) {
                            Circle().fill(matched ? Palette.ok : Palette.bad)
                                .frame(width: 6, height: 6)
                            Text(matched ? "机型匹配" : "机型不匹配")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(matched ? Palette.ok : Palette.bad)
                        }
                        // 快速选择菜单（检测到的机型 + 已收录机型族）
                        Menu {
                            Button {
                                fan.selectModel(fan.detected.detectedCode)
                            } label: {
                                Label("使用检测到的机型（推荐）", systemImage: "checkmark.circle")
                            }
                            Divider()
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

                    // 检测到的硬件 + 来源
                    HStack(spacing: 4) {
                        Text("检测到")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textTertiary)
                        Text("\(fan.detected.detectedCode)（\(fan.detected.detectedName)）")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        Text("· \(fan.detected.source)")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Palette.textTertiary)
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
                        Text("你选择的「\(fan.selectedCode)」与检测到的硬件「\(fan.detected.detectedCode)」不一致。风扇曲线和 EC 配置是按特定机型逆向的，套错机型可能让风扇停转或狂转，导致过热甚至永久损坏。每次应用曲线前都必须先确认风险。")
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
                    Text(ModelDisclaimer.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    Text(ModelDisclaimer.body(selected: fan.selectedCode,
                                             detected: fan.detected.detectedCode))
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
