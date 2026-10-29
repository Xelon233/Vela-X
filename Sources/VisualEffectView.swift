//
//  VisualEffectView.swift
//  Liquid Glass 的底层材质：用 AppKit 的 NSVisualEffectView 直接控制混合模式。
//
//  为什么不用 SwiftUI 的 Material：
//  SwiftUI 的 `.background(.regularMaterial)` 是 withinWindow 混合，背后只有窗口
//  自己的内容，看不到桌面，所以渲染出来是「磨砂卡片」而不是 Liquid Glass。
//  要桌面透过窗口折射，必须把 NSWindow 设成透明（isOpaque=false、backgroundColor=clear、
//  titlebarAppearsTransparent），再用 blendingMode = .behindWindow 的 NSVisualEffectView
//  当底层 —— 这才是 macOS 26 (Tahoe) 的 Liquid Glass 窗口底。
//

import SwiftUI
import AppKit

/// 运行环境开关
enum AppEnv {
    /// 自测模式（ASUS_SELFTEST=1）：窗口保持不透明，背景由 SwiftUI 自己绘制。
    /// 原因：透明窗 + behindWindow 材质在离屏 cacheDisplay 里抓不到内容层，截图会空白。
    static let selftest = ProcessInfo.processInfo.environment["ASUS_SELFTEST"] != nil
    /// 自测时也保持透明窗（能抓到真实玻璃），用于肉眼核对玻璃质感
    static let glassInSelftest = ProcessInfo.processInfo.environment["ASUS_SELFTEST_GLASS"] != nil
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        // 提高饱和度，让玻璃边缘的高光更明显（Liquid Glass 的关键观感）
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 只提供「弹性空白」的工具栏代理。
/// 目的不是放控件，而是让窗口拥有真正的 NSToolbar —— 系统按 toolbarStyle 决定窗口圆角：
/// 无 toolbar = 16pt、`.unifiedCompact` = 20pt、`.unified` = 26pt（macOS 26 Safari 同款）。
final class WindowToolbarStyler: NSObject, NSToolbarDelegate {
    static let shared = WindowToolbarStyler()

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace] }
}

/// 窗口外观装配：透明窗 + 26pt 圆角 + 顶栏与内容共用同一块背景。
///
/// 两个结论都是实测出来的：
/// 1. 窗口圆角由 toolbarStyle 决定：无 toolbar = 16pt、`.unifiedCompact` = 20pt、
///    `.unified` = 26pt（macOS 26 Safari 同款，实测 NSThemeFrame.cornerRadius）。
/// 2. 标题栏那 52pt 是单独的视图层，会和内容区各画一层背景 —— 只要不去掉它，
///    红绿灯行就永远比内容亮/暗一档。必须开 fullSizeContentView 让 SwiftUI 背景
///    铺满整窗，再把工具栏那层玻璃移走，两边才是同一块背景。
enum WindowChrome {
    /// 保留 resize 通知的 token，避免观察者被释放后自动失效
    private static var resizeObservers: [NSObjectProtocol] = []

    static func install(on window: NSWindow) {
        // 不要标题文字、不要标题栏分隔线
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none

        // 拿到 26pt 大圆角（与 macOS 26 Safari 一致）：
        // 系统按 toolbarStyle 决定窗口圆角，必须真有 NSToolbar 且用 .unified。
        if window.toolbar == nil {
            let toolbar = NSToolbar(identifier: "AsusControlTitlebar")
            toolbar.delegate = WindowToolbarStyler.shared
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
        }
        window.toolbarStyle = .unified
        window.titlebarAppearsTransparent = true

        clearTitlebarGlass(on: window)

        // 透明窗：behindWindow 玻璃才能把桌面折射进来。
        // 自测模式默认保持不透明窗；加 ASUS_SELFTEST_GLASS=1 时仍然透明，
        // 因为截图走的是 CGWindowListCreateImage（窗口服务器合成结果），
        // 这条路径能抓到真正的玻璃，是唯一能亲眼确认「玻璃到不到位」的办法。
        if !AppEnv.selftest || AppEnv.glassInSelftest {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
        }

        // 让 contentView 覆盖整个窗口（含标题栏）：SwiftUI 的背景因此能用 ignoresSafeArea
        // 铺到红绿灯那一行，而内容布局仍被安全区挡在工具栏下方，不会被裁切。
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }

        // 改窗口尺寸时系统可能重建工具栏视图，把玻璃又带回来，这里重新抹一次。
        // 用通知中心而不是 window.delegate —— SwiftUI 自己占着 delegate。
        // 必须防抖：拖拽边角时这个通知每秒来几十次，每次都遍历/摘除子视图会把
        // 改变窗口尺寸拖成幻灯片。
        let center = NotificationCenter.default
        let resizeObserver = center.addObserver(forName: NSWindow.didResizeNotification,
                                                object: window, queue: .main) { note in
            guard let w = note.object as? NSWindow else { return }
            PendingTitlebarCleanup.shared.schedule(w)
        }
        resizeObservers.append(resizeObserver)
    }

    /// 每个窗口一个防抖任务，避免 resize 过程中反复清理标题栏
    final class PendingTitlebarCleanup {
        static let shared = PendingTitlebarCleanup()
        private var work: DispatchWorkItem?

        func schedule(_ window: NSWindow) {
            work?.cancel()
            let item = DispatchWorkItem { WindowChrome.clearTitlebarGlass(on: window) }
            work = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }

    /// 抹掉标题栏自带的背景层，只留红绿灯。
    /// macOS 26 的工具栏区叠了几层自绘背景（`NSToolbarView` 里的 `NSGlassContainerView`
    /// 玻璃容器、`_NSTitlebarDecorationView` 装饰层、NSTitlebarView 里的匿名背景视图……），
    /// 它们会在红绿灯行再刷一层和内容不同色的东西。这里把它们去掉（工具栏视图设 alpha
    /// 会被布局重置，直接移出视图树最稳；`window.toolbar` 属性保留，26pt 圆角不受影响），
    /// 让 ContentView 那一整块背景直接透到红绿灯行。
    static func clearTitlebarGlass(on window: NSWindow) {
        // 红绿灯按钮的直接父级就是 NSTitlebarView 本身（不是外层的 container）
        guard let titlebarView = window.standardWindowButton(.closeButton)?.superview else { return }

        func isWidget(_ v: NSView) -> Bool {
            let name = String(describing: type(of: v))
            return name.hasPrefix("_NSTheme") && name.hasSuffix("Widget")
        }

        for sub in titlebarView.subviews where !isWidget(sub) {
            if String(describing: type(of: sub)).contains("ToolbarView") {
                sub.removeFromSuperview()
            } else {
                sub.alphaValue = 0
            }
        }

        // 调试：确认标题栏区域能否被我们自己的视图覆盖（ASUS_TOPBAR_TEST=1 时顶栏应变纯红）
        if ProcessInfo.processInfo.environment["ASUS_TOPBAR_TEST"] != nil {
            let red = NSView(frame: titlebarView.bounds)
            red.wantsLayer = true
            red.layer?.backgroundColor = NSColor.red.cgColor
            red.autoresizingMask = [.width, .height]
            titlebarView.addSubview(red)
        }
        // 装饰层挂在外面那层 container 上
        if let container = titlebarView.superview {
            for sub in container.subviews where String(describing: type(of: sub)).contains("Decoration") {
                sub.alphaValue = 0
            }
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    /// 覆盖全窗口的占位 NSView：必须做成「事件穿透」，否则它会盖在 SwiftUI 内容
    /// 之上把所有鼠标点击吃掉，导致界面看似正常却点不动任何按钮。
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            WindowChrome.install(on: window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
