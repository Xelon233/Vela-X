//
//  App.swift
//  SwiftUI 应用入口 + 菜单栏常驻
//

import SwiftUI
import AppKit

struct AsusControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = SensorStore.shared
    @StateObject private var theme = ThemeManager()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(theme)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1000, height: 730)
        // 必须是 `.unified`：系统按 toolbarStyle 决定窗口圆角，
        // `.unified` = 26pt（与 macOS 26 Safari 一致），`.unifiedCompact` 只有 20pt。
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("刷新全部 SMC 读数") { store.reloadAllReadings() }
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    /// 菜单栏状态项：图标 + 数值 + 缩小字标签，合并成单个富文本。
    /// 为什么不能拼多个 View：macOS 的 MenuBarExtra label 对多元素 HStack
    /// 只渲染第一个子视图，必须合并成单个 Text（AttributedString）。
    private var menuBarLabel: some View {
        Text(Self.menuBarAttributedText(store.menuBarItems))
    }

    private static func menuBarAttributedText(_ items: [MenuBarItem]) -> AttributedString {
        guard !items.isEmpty else { return AttributedString("Vela X") }
        let out = NSMutableAttributedString()
        for (idx, item) in items.enumerated() {
            if let img = NSImage(systemSymbolName: item.metric.icon, accessibilityDescription: nil) {
                let att = NSTextAttachment()
                att.image = img
                // 图标缩小到 10pt、贴齐文字基线；SF Symbol 是模板图，会跟随菜单栏文字色
                att.bounds = CGRect(x: 0, y: -1.5, width: 10, height: 10)
                out.append(NSAttributedString(attachment: att))
            }
            out.append(NSAttributedString(string: item.value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            ]))
            out.append(NSAttributedString(string: " \(item.metric.shortLabel)", attributes: [
                .font: NSFont.systemFont(ofSize: 8),
                .foregroundColor: NSColor.secondaryLabelColor
            ]))
            if idx < items.count - 1 {
                out.append(NSAttributedString(string: "  "))
            }
        }
        return AttributedString(out)
    }
}

/// 菜单栏状态项里的单个指标：小图标 + 数值 + 缩小字的标签。
/// 预览（菜单栏设置页）传更大的字号即可复用。
struct MenuBarMetricLabel: View {
    let item: MenuBarItem
    var iconSize: CGFloat = 9
    var valueSize: CGFloat = 11
    var labelSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: item.metric.icon)
                .font(.system(size: iconSize))
            Text(item.value)
                .font(.system(size: valueSize, weight: .medium).monospacedDigit())
            Text(item.metric.shortLabel)
                .font(.system(size: labelSize))
                .foregroundStyle(.secondary)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var store: SensorStore
    @Environment(\.openWindow) private var openWindow

    /// 档位上限由当前通道决定：Aura HID 是 0–3，SMC(LKSB) 是 0–16，不可控时是 0。
    /// 早先这里写死成 16 档，在 HID 机型上会给出设备根本不认的档位。
    private var maxLevel: Int { store.kbdMaxLevel }

    /// 用户在「菜单栏」页勾选的监控项。菜单栏窗口每次弹出都会重建，
    /// 这里在 onAppear 里重读一次，保证改完设置立刻能看到
    @State private var metrics: [MenuMetric] = MenuBarPrefs.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Palette.forTemp(store.cpuTemp))
                    .frame(width: 6, height: 6)
                Text(store.hardware.modelCode.isEmpty ? "Vela X" : store.hardware.modelCode)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Button {
                    openMainWindow(page: .menubar)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("菜单栏显示哪些项目")
            }

            Divider()

            // 勾选了哪些就显示哪些，顺序跟「菜单栏」页里的一致
            ForEach(metrics, id: \.self) { metric in
                metricRow(metric)
            }

            if metrics.isEmpty {
                Text("没有勾选任何监控项")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Button("去「菜单栏」页勾选") { openMainWindow(page: .menubar) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.accent)
            }

            Divider()

            HStack {
                Text("键盘背光")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(maxLevel > 0 ? "\(store.kbdLevel)/\(maxLevel)" : "不可控")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if maxLevel > 0 {
                backlightPicker
            } else {
                backlightUnavailable
            }

            Divider()

            HStack {
                Button("主窗口") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 236)
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        // 菜单栏是临时窗口，打开时重新探一次通道，
        // 这样刚在「输入监控」里勾完授权，不必重启整个程序就能拿到新档位
        .onAppear {
            metrics = MenuBarPrefs.enabled
            store.recheckBacklightPermission()
        }
    }

    // MARK: - 监控项

    private func metricRow(_ metric: MenuMetric) -> some View {
        let value = store.menuValue(metric)
        return HStack(spacing: 6) {
            Image(systemName: metric.icon)
                .font(.system(size: 10))
                .frame(width: 13)
                .foregroundStyle(value.available ? Palette.accent : Palette.textTertiary)
            Text(metric.title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value.text)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(value.available ? Color.primary : Palette.textTertiary)
                .help(value.reason ?? "")
        }
    }

    /// 打开主窗口并切到指定页
    private func openMainWindow(page: Page) {
        PageRouter.shared.page = page
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 背光档位

    @ViewBuilder
    private var backlightPicker: some View {
        if maxLevel <= 8 {
            // 档位少（HID 通道 0–3）：直接给离散按钮，点哪个就是哪个
            HStack(spacing: 4) {
                ForEach(0...maxLevel, id: \.self) { lv in
                    levelButton(lv)
                }
            }
        } else {
            // 档位多（SMC 通道 0–16）：17 个按钮挤不下，改用连续条 + 一个「关」
            HStack(spacing: 6) {
                levelButton(0)
                    .frame(width: 30)
                LevelDots(level: store.kbdLevel, maxLevel: maxLevel) {
                    store.setKeyboardBacklight($0)
                }
                .frame(maxWidth: .infinity, maxHeight: 18)
            }
        }
    }

    private func levelButton(_ lv: Int) -> some View {
        Button {
            store.setKeyboardBacklight(lv)
        } label: {
            Text(lv == 0 ? "关" : "\(lv)")
                .font(.system(size: 10).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: Palette.cornerRadius)
                        .fill(store.kbdLevel == lv ? Palette.accent.opacity(0.85) : Color.primary.opacity(0.07))
                )
                .foregroundStyle(store.kbdLevel == lv ? Color.white : Color.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(store.kbdBusy)
    }

    /// 通道不可用 / 还没授权时的引导，文案与「键盘背光」页保持一致
    private var backlightUnavailable: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(unavailableText)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.warn)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Text("去主窗口处理")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private var unavailableText: String {
        switch store.kbdPermission {
        case .granted:       return "背光通道探测中…"
        case .denied:        return "「输入监控」被拒绝，需在系统设置里重新勾选"
        case .needsRestart:  return "已授权，重启程序后生效"
        case .notDetermined: return "尚未获得「输入监控」授权"
        case .busy:          return "键盘设备被其它进程占用"
        case .noDevice:      return "未找到 Aura HID 控制器"
        }
    }
}

/// 自检：设置 ASUS_SELFTEST=1 启动时，把自身窗口内容渲染成 PNG 后退出。
/// 用途：在没有「屏幕录制」权限的环境里验证界面是否真的画出来了。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 改过 App 名字 / 换过安装位置时，把开机自启的 LaunchAgent 指到新路径
        // （先迁 label：AsusControl 时期用的是 dev.asuscontrol.mac.autostart）
        LaunchAtLogin.migrateLegacyLabel()
        LaunchAtLogin.repairIfMoved()
        // 由开机自启拉起时只驻留菜单栏：SwiftUI 的 WindowGroup 默认会给一个窗口，
        // 这里在它建好之后收起来，避免登录时突然弹一个窗口。
        if LaunchAtLogin.isAutostartLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                for w in NSApp.windows where w.frame.width > 600 {
                    w.orderOut(nil)
                }
            }
        }

        // 外观由 ThemeManager 决定（默认深色，可切浅色 / 跟随系统）
        guard ProcessInfo.processInfo.environment["ASUS_SELFTEST"] != nil else { return }
        setbuf(stdout, nil)   // 自测输出不缓冲，崩溃时也能看到进度
        // 默认等 4 秒。机器慢的时候 4 秒只够采一轮，网速和 CPU 占用率
        // 都要两次采样才有值，截图上会显示成「—」，看着像坏了。用
        // ASUS_SELFTEST_DELAY 把等待时间调长即可。
        let delay = Double(ProcessInfo.processInfo.environment["ASUS_SELFTEST_DELAY"] ?? "") ?? 4.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // 取主窗口（宽 > 600 的那个），避免抓到菜单栏那个几十像素宽的状态项窗口
            let window = NSApp.windows
                .filter { $0.contentView != nil && $0.frame.width > 600 }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            // 抓「窗口真实合成结果」：CGWindowListCreateImage 抓的是窗口服务器合成后的画面，
            // 包含透明、圆角、behindWindow 玻璃，比 cacheDisplay/layer.render 更接近真机观感。
            if let window {
                if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow,
                                                    CGWindowID(window.windowNumber),
                                                    [.boundsIgnoreFraming, .bestResolution]) {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "/tmp/live_window.png"))
                } else if let view = window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    // 兜底：该 API 不可用时退回离屏渲染（会丢 ScrollView 内容，仅供粗看）
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: "/tmp/live_window.png"))
                    }
                }
            }
            // 自测顺带输出窗口外观状态，便于确认「26pt 圆角 + 顶栏同源背景」是否到位
            if let window {
                let tf = window.contentView?.superview
                print("[selftest] toolbar=\(window.toolbar != nil) style=\(window.toolbarStyle.rawValue) "
                      + "cornerRadius=\(tf?.value(forKey: "cornerRadius") ?? "nil") "
                      + "themeFrame=\(tf?.bounds.size ?? .zero) contentView=\(window.contentView?.bounds.size ?? .zero)")
            }
            NSApp.terminate(nil)
        }
    }

}
