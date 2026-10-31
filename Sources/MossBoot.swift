//
//  MossBoot.swift
//  切进 550W 时的「系统启动」过场
//
//  只在「从其它主题切到 550W」时播放：盖住整窗播一段启动日志，
//  最后停在「行星发动机网络已连接」，然后淡出露出界面 —— 伪装成设备重新上线。
//  全程离散跳变（每 0.32 秒一行），没有任何连续动画，讲完就结束。
//

import SwiftUI

struct MossBootOverlay: View {
    var onFinish: () -> Void

    /// 0 = 刚起，1…4 = 已经打出几行，4 = 定格在「已连接」
    @State private var step: Int

    /// initialStep 只给离屏出图用（让静态快照能停在中途/收官那一帧）
    init(initialStep: Int = 0, onFinish: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinish = onFinish
    }

    private static let lines: [(text: String, tail: String)] = [
        ("载入载体 MOSS // 550W", "OK"),
        ("校验联合政府授权", "OK"),
        ("同步行星发动机网络", "LINK"),
        ("接管本地节点", "OK"),
    ]

    var body: some View {
        ZStack {
            // 盖住整窗：不从旧主题透一点颜色，启动就该是干净的一块白
            Color(hex: 0xF2F3F5)
            MossGrid()
            panel
        }
        .ignoresSafeArea()
        .task { await run() }
    }

    // MARK: 面板

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MossMark(size: 15)
                Text("MOSS // 550W")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Palette.text)
                Spacer(minLength: 12)
                Text("BOOT SEQUENCE")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Palette.textTertiary)
            }

            DashedRule()
                .stroke(Palette.accent.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                .frame(height: 1)
                .padding(.vertical, 11)

            // 启动日志：逐行点亮，最后一行带方块光标
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(Self.lines.enumerated()), id: \.offset) { i, line in
                    HStack(spacing: 6) {
                        Text(">")
                            .foregroundStyle(Palette.accent.opacity(i < step ? 0.9 : 0.25))
                        Text(line.text)
                            .foregroundStyle(i < step ? Palette.text : Palette.textTertiary.opacity(0.45))
                        Text(String(repeating: "·", count: 6))
                            .foregroundStyle(Palette.hairline)
                            .lineLimit(1)
                            .layoutPriority(-1)
                        Spacer(minLength: 6)
                        Text(i < step ? line.tail : "···")
                            .foregroundStyle(i < step ? Palette.accent : Palette.textTertiary.opacity(0.5))
                    }
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.3)
                }
            }

            // 进度：四格方块，跟着日志一起推进
            HStack(spacing: 4) {
                ForEach(0 ..< Self.lines.count, id: \.self) { i in
                    Rectangle()
                        .fill(i < step ? Palette.accent : Palette.accent.opacity(0.16))
                        .frame(height: 5)
                }
            }
            .padding(.top, 13)

            // 收官：核心那句话
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(step >= Self.lines.count ? "行星发动机网络已连接" : "正在接入行星发动机网络…")
                    .font(.system(size: step >= Self.lines.count ? 17 : 11,
                                 weight: step >= Self.lines.count ? .bold : .medium,
                                 design: .monospaced))
                    .tracking(step >= Self.lines.count ? 1.2 : 0.3)
                    .foregroundStyle(step >= Self.lines.count ? Palette.accent : Palette.textSecondary)
                if step >= Self.lines.count {
                    Text("PLANETARY ENGINE NETWORK · ONLINE")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .padding(.top, 14)
            .animation(nil, value: step)

            Text("// 请勿关闭电源")
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundStyle(Palette.textTertiary)
                .padding(.top, 8)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .frame(width: 470, alignment: .leading)
        .background(
            PanelShape(radius: 0, cut: 14)
                .fill(Color.white.opacity(0.97))
        )
        .overlay(
            PanelShape(radius: 0, cut: 14)
                .stroke(Palette.accent.opacity(0.5), lineWidth: 1.4)
        )
        .overlay(alignment: .topLeading) {
            // 左上角一小段加粗红边，和主界面的切角强调同一套语言
            PanelAccents(cut: 14)
                .stroke(Palette.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .square))
        }
    }

    // MARK: 时序

    private func run() async {
        // 先停一拍，让遮罩先盖稳（父视图的淡入 0.15s）
        try? await Task.sleep(nanoseconds: 180_000_000)
        for i in 1 ... Self.lines.count {
            step = i
            try? await Task.sleep(nanoseconds: 320_000_000)
        }
        // 「已连接」定格一会儿再退场
        try? await Task.sleep(nanoseconds: 780_000_000)
        onFinish()
    }
}
