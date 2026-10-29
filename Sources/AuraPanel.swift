//
//  AuraPanel.swift
//  键盘 RGB 灯效面板（ASUS Aura，2021+ N-KEY 机型）
//
//  协议见 AuraEffects.swift：5D B3 <Zone> <Mode> <R> <G> <B> <Speed> <Dir> <Flag> <R2> <G2> <B2>
//  生效序列：效果 → 提交(5D B5) → 应用(5D B4)
//

import SwiftUI
import AppKit

/// Aura 灯效面板
struct AuraPanel: View {
    @State private var mode: AuraMode = .rainbow
    @State private var color1: Color = Color(red: 1.0, green: 0.0, blue: 0.0)
    @State private var color2: Color = Color(red: 0.0, green: 0.4, blue: 1.0)
    @State private var speed: AuraSpeed = .med
    @State private var direction: AuraDirection = .right
    @State private var useSecondColor = false
    @State private var status: String = "—"
    @State private var busy = false

    private var effect: AuraEffect {
        var e = AuraEffect()
        e.mode = mode
        e.color1 = AuraPanel.rgb(color1)
        e.color2 = useSecondColor ? AuraPanel.rgb(color2) : (0, 0, 0)
        e.speed = speed
        e.direction = direction
        return e
    }

    static func rgb(_ c: Color) -> (r: Int, g: Int, b: Int) {
        let ns = NSColor(c)
        let rgb = ns.usingColorSpace(.sRGB) ?? ns
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private func apply() {
        busy = true
        // 让 UI 先刷新出「下发中」
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let err = AuraEffects.shared.apply(effect) {
                status = err
            } else {
                let c = AuraPanel.rgb(color1)
                status = "已应用「\(mode.title)」· #\(String(format: "%02X%02X%02X", c.r, c.g, c.b)) · \(speed.title)"
            }
            busy = false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(text: "RGB 灯效",
                         trailing: AuraEffects.shared.isAvailable ? "Aura HID · 0x5D" : "不可用")

            if !AuraEffects.shared.isAvailable {
                Card(padding: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warn)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("无法打开 ASUS Aura HID 控制器")
                                .font(.system(size: 12, weight: .semibold))
                            Text("需要「系统设置 → 隐私与安全性 → 输入监控」授权本程序，并完全退出后重开。")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            } else {
                modeCard
                colorCard
                optionCard
                applyCard
            }
        }
    }

    // MARK: 模式

    private var modeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("灯效模式")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                    ForEach(AuraMode.allCases, id: \.rawValue) { m in
                        Button {
                            mode = m
                        } label: {
                            HStack(spacing: 5) {
                                Text("\(m.rawValue)")
                                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(mode == m ? Palette.accent : Palette.textTertiary)
                                Text(m.title)
                                    .font(.system(size: 12, weight: mode == m ? .semibold : .regular))
                                    .foregroundStyle(mode == m ? Palette.text : Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: Palette.cornerRadius)
                                    .fill(mode == m ? Palette.accent.opacity(0.13) : Palette.faintFill)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Palette.cornerRadius)
                                    .stroke(mode == m ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: 颜色

    private var colorCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("颜色")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("主色")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        ColorPicker("", selection: $color1, supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 130, height: 26)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("辅色")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        HStack(spacing: 6) {
                            ColorPicker("", selection: $color2, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 130, height: 26)
                                .disabled(!useSecondColor)
                                .opacity(useSecondColor ? 1 : 0.4)
                            Toggle("启用", isOn: $useSecondColor)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                        }
                    }
                    Spacer()
                }

                // 常用色快选
                HStack(spacing: 6) {
                    ForEach(Self.quickColors, id: \.0) { item in
                        Button {
                            if useSecondColor { color2 = item.1 } else { color1 = item.1 }
                        } label: {
                            Circle()
                                .fill(item.1)
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Circle().stroke(Palette.hairline, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.0)
                    }
                    Spacer()
                }
            }
        }
    }

    private static let quickColors: [(String, Color)] = [
        ("红", Color(red: 1.0, green: 0.15, blue: 0.15)),
        ("橙", Color(red: 1.0, green: 0.55, blue: 0.0)),
        ("黄", Color(red: 1.0, green: 0.95, blue: 0.15)),
        ("绿", Color(red: 0.15, green: 1.0, blue: 0.3)),
        ("青", Color(red: 0.0, green: 0.9, blue: 0.9)),
        ("蓝", Color(red: 0.2, green: 0.45, blue: 1.0)),
        ("紫", Color(red: 0.7, green: 0.25, blue: 1.0)),
        ("粉", Color(red: 1.0, green: 0.35, blue: 0.75)),
        ("白", Color(red: 1.0, green: 1.0, blue: 1.0))
    ]

    // MARK: 速度 / 方向

    private var optionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("速度")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        Picker("", selection: $speed) {
                            ForEach(AuraSpeed.allCases, id: \.rawValue) { s in
                                Text(s.title).tag(s)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("方向")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        Picker("", selection: $direction) {
                            ForEach(AuraDirection.allCases, id: \.rawValue) { d in
                                Text(d.title).tag(d)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 110)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: 应用

    private var applyCard: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        apply()
                    } label: {
                        if busy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("应用灯效")
                        }
                    }
                    .buttonStyle(GrayButtonStyle(prominent: true))
                    .disabled(busy)

                    Spacer()

                    Text(status)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }

                Text("报文 " + hexPreview)
                    .font(.system(size: 9.5).monospaced())
                    .foregroundStyle(Palette.textTertiary)
                    .textSelection(.enabled)
            }
        }
    }

    /// 效果报文的十六进制预览（前 13 字节）
    private var hexPreview: String {
        effect.message.prefix(13)
            .map { String(format: "%02X", $0) }
            .joined(separator: " ")
    }
}
