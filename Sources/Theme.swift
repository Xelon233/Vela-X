//
//  Theme.swift
//  深浅色主题系统 —— 默认深色，可切浅色或跟随系统
//

import SwiftUI
import AppKit

// MARK: - 主题模式

enum ThemeMode: String, CaseIterable, Identifiable, Hashable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: return "深色"
        case .light: return "浅色"
        case .system: return "系统"
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }

    /// nil = 跟随系统
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

// MARK: - 主题管理器

final class ThemeManager: ObservableObject {
    /// 默认深色；持久化在 Prefs，可用环境变量 ASUS_THEME=dark|light|system 临时覆盖
    @Published var mode: ThemeMode {
        didSet {
            Prefs.set(mode.rawValue, for: "appearance")
            applyAppearance()
        }
    }

    init() {
        let env = ProcessInfo.processInfo.environment["ASUS_THEME"]
            .flatMap(ThemeMode.init(rawValue:))
        let stored = Prefs.string("appearance").flatMap(ThemeMode.init(rawValue:))
        mode = env ?? stored ?? .dark
    }

    /// SwiftUI 的 preferredColorScheme 负责界面配色，
    /// 这里同步 NSApp.appearance，让动态 NSColor（Palette）按同一模式解析。
    func applyAppearance() {
        guard NSApp != nil else { return }
        switch mode {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }
}

// MARK: - 自适应颜色

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Color {
    /// 深浅色自适应颜色：绘制时按当前外观解析
    static func adaptive(_ light: UInt32, _ dark: UInt32,
                         lightOpacity: Double = 1, darkOpacity: Double = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isLight = appearance.bestMatch(from: [.aqua, .darkAqua]) == .aqua
            return isLight
                ? NSColor(hex: light, alpha: lightOpacity)
                : NSColor(hex: dark, alpha: darkOpacity)
        })
    }
}
