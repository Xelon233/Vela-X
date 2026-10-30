//
//  StatusBarController.swift
//  自己管理菜单栏状态项（NSStatusItem），替代 SwiftUI 的 MenuBarExtra。
//
//  为什么要自己管：MenuBarExtra 的状态栏按钮会强制使用系统状态栏字体，
//  之前设的小标签字号一直不生效；而且我们要的是「只显示图标 + 数据、不显示文字标签」，
//  直接控制 NSStatusItem.button.attributedTitle 才能精确控制字号与间距。
//
//  点击按钮弹出的面板（原来的 MenuBarView）用 NSPopover 承载，行为与原 MenuBarExtra
//  的 .window 风格一致：点一下弹出，点外面自动收起。

import SwiftUI
import AppKit
import Combine

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var ticket: AnyCancellable?

    /// 缓存 SF Symbol 图标，避免每次刷新标题都重新生成 NSImage（状态栏每 250ms 可能刷一次）。
    private static var iconCache: [String: NSImage] = [:]
    /// 上一次写进按钮的标题纯文本，避免「值没变却反复 setAttributedTitle」造成的状态项重排开销。
    private var lastTitleKey: String?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        rebuildTitle()
        // 传感器读数一变就刷新状态项标题（去抖 250ms，避免每帧重排）。
        // SensorStore 用 objectWillChange.send() 主动触发，这里订阅它即可。
        ticket = SensorStore.shared.objectWillChange
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] in self?.rebuildTitle() }
    }

    func stop() {
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        statusItem = nil
        ticket?.cancel()
        popover?.performClose(nil)
        popover = nil
    }

    private func rebuildTitle() {
        guard let button = statusItem?.button else { return }
        let items = SensorStore.shared.menuBarItems
        // 用「图标 + 数值」拼一个稳定 key，值没变就跳过重新赋值，省去 NSStatusItem 的重排。
        let key = items.map { "\($0.metric.icon):\($0.value)" }.joined(separator: "|")
        if key == lastTitleKey { return }
        lastTitleKey = key
        button.attributedTitle = NSAttributedString(Self.attributedTitle(items))
        // 标题本身已含内嵌图标（NSTextAttachment），不再单独设 button.image，
        // 否则会重复出现一个图标位。
        button.image = nil
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: MenuBarView().environmentObject(SensorStore.shared)
        )
        popover = pop
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }

    /// 状态项标题：图标 + 数值（不显示文字标签）。
    /// 字号保持原始比例（数值 12.5pt、图标 12pt、基线偏移 -2），图标区分类型、一目了然，不把状态栏撑高。
    /// 网速项在状态栏里不显示前置箭头图标——数值本身已带 ↓/↑，
    /// 再加一个 arrow.up.arrow.down 反而干扰上下行判断。
    static func attributedTitle(_ items: [MenuBarItem]) -> AttributedString {
        guard !items.isEmpty else { return AttributedString("Vela X") }
        let out = NSMutableAttributedString()
        for (idx, item) in items.enumerated() {
            // 网速不在状态栏显示前置图标（避免与数值里的 ↓/↑ 混淆）
            if item.metric != .netSpeed,
               let img = Self.cachedIcon(item.metric.icon) {
                let att = NSTextAttachment()
                att.image = img
                // 图标 12pt、贴齐数值基线；SF Symbol 是模板图，会跟随状态栏文字色
                att.bounds = CGRect(x: 0, y: -2, width: 12, height: 12)
                out.append(NSAttributedString(attachment: att))
            }
            out.append(NSAttributedString(string: " " + item.value, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .medium)
            ]))
            if idx < items.count - 1 {
                out.append(NSAttributedString(string: "  "))
            }
        }
        return AttributedString(out)
    }

    /// 按 symbol 名缓存 SF Symbol 图标：状态栏刷新频繁，重复创建 NSImage 是无谓的分配。
    private static func cachedIcon(_ name: String) -> NSImage? {
        if let cached = iconCache[name] { return cached }
        let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        if let img { iconCache[name] = img }
        return img
    }
}
