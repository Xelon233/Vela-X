//
//  MenuBarTitleView.swift
//  菜单栏「图标 + 紧凑数值」标题
//

import SwiftUI
import AppKit

/// 设置页预览与真实菜单栏共用，保证两处布局一致。
struct MenuBarTitleView: View {
    let segments: [MenuBarSegment]
    var preview = false

    var body: some View {
        Group {
            if preview {
                previewTitle
            } else {
                // MenuBarExtra 会裁掉 HStack 的其余子项，也会丢弃内联 Text(Image)
                // 里的图标。把整段内容预先合成成一张模板图片，才能完整显示所有指标。
                Image(nsImage: MenuBarStatusImage.make(segments: segments))
                    .renderingMode(.template)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var previewTitle: some View {
        HStack(spacing: preview ? 7 : 5) {
            if segments.isEmpty {
                Text("Vela X")
                    .font(.system(size: preview ? 14 : 12, weight: .medium))
                    .monospacedDigit()
            } else {
                ForEach(segments) { segment in
                    HStack(spacing: preview ? 3 : 2) {
                        Image(systemName: segment.metric.menuBarIcon)
                            .font(.system(size: preview ? 11.5 : 10.5, weight: .semibold))
                            .foregroundStyle(preview ? Palette.accent : Color.primary)
                            .accessibilityHidden(true)
                        Text(segment.text)
                            .font(.system(size: preview ? 14 : 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(preview ? Palette.text : Color.primary)
                    }
                }
            }
        }
    }

    private var accessibilityText: String {
        segments.isEmpty
            ? "Vela X"
            : segments.map { "\($0.metric.title) \($0.text)" }.joined(separator: "，")
    }
}

/// 把状态栏标题画进一张模板图片。模板图片由系统统一着色，
/// 因此浅色 / 深色菜单栏都能自动得到正确对比度。
private enum MenuBarStatusImage {
    private static let textFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    private static let iconPointSize: CGFloat = 10.5
    private static let imageHeight: CGFloat = 18
    private static let iconTextGap: CGFloat = 2
    private static let segmentGap: CGFloat = 6

    static func make(segments: [MenuBarSegment]) -> NSImage {
        guard !segments.isEmpty else { return fallbackImage() }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.black
        ]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .semibold)
        let measured = segments.map { segment -> (MenuBarSegment, NSAttributedString, NSSize, NSSize) in
            let text = NSAttributedString(string: segment.text, attributes: attributes)
            let textSize = text.size()
            let symbol = NSImage(systemSymbolName: segment.metric.menuBarIcon,
                                 accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfig)
            let symbolSize = symbol?.size ?? NSSize(width: iconPointSize, height: iconPointSize)
            return (segment, text, textSize, symbolSize)
        }

        let contentWidth = measured.reduce(CGFloat.zero) { width, item in
            width + item.3.width + iconTextGap + item.2.width
        } + segmentGap * CGFloat(max(0, measured.count - 1))
        let size = NSSize(width: max(1, ceil(contentWidth)), height: imageHeight)

        let image = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (index, item) in measured.enumerated() {
                let (segment, text, textSize, symbolSize) = item
                let symbol = NSImage(systemSymbolName: segment.metric.menuBarIcon,
                                     accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig)
                let symbolRect = NSRect(x: x,
                                        y: (imageHeight - symbolSize.height) / 2,
                                        width: symbolSize.width,
                                        height: symbolSize.height)
                symbol?.draw(in: symbolRect,
                             from: .zero,
                             operation: .sourceOver,
                             fraction: 1,
                             respectFlipped: true,
                             hints: nil)
                x += symbolSize.width + iconTextGap

                let textRect = NSRect(x: x,
                                      y: (imageHeight - textSize.height) / 2,
                                      width: textSize.width,
                                      height: textSize.height)
                text.draw(in: textRect)
                x += textSize.width
                if index < measured.count - 1 { x += segmentGap }
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func fallbackImage() -> NSImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.black
        ]
        let text = NSAttributedString(string: "Vela X", attributes: attributes)
        let size = NSSize(width: ceil(text.size().width), height: imageHeight)
        let image = NSImage(size: size, flipped: false) { _ in
            text.draw(at: NSPoint(x: 0, y: (imageHeight - text.size().height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}
