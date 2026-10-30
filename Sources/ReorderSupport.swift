//
//  ReorderSupport.swift
//  卡片 / 菜单栏标签拖拽排序共用件
//
//  拖拽排序的「防整窗被带跑」采用 iOS 小组件式的「编辑模式」开关：
//  - 编辑模式开：窗口固定（isMovableByWindowBackground = false），只有卡片/标签可拖；
//  - 编辑模式关：窗口可拖动（isMovableByWindowBackground = true），卡片/标签固定。
//
//  为什么不用「鼠标落点探测」：窗口 isMovableByWindowBackground = true（标题栏透明，
//  只能靠背景拖窗），AppKit 在 mouseDown 里同步开拖窗循环，SwiftUI 手势来不及接管，
//  且两套坐标系（AppKit Y 向上 / SwiftUI .global Y 向下）一翻转就失效 —— 实测一直没修好。
//  显式编辑模式彻底绕开这个坑：窗口可移动性由开关直接决定，不需要探测鼠标在哪。

import SwiftUI
import AppKit
import Combine

/// 编辑模式开关（单例，供 SwiftUI 视图与 AppKit 窗口共享）。
/// 概览页 / 菜单栏页的「编辑」按钮控制它；WindowChrome 订阅它在 AppKit 侧切换窗口
/// 的 isMovableByWindowBackground。
final class WindowState: ObservableObject {
    static let shared = WindowState()
    @Published var isEditMode = false
    /// 临时交互锁：自定义曲线画布这类「内部要拖拽」的区域，指针悬停其上时
    /// 关掉窗口背景拖动，避免拖圆点时整窗跟着鼠标跑；指针移出即恢复。
    @Published var interactionLocked = false
}

/// 收集子视图在全局坐标系下的 frame，按可哈希 id 存起来，供松手时判断落在哪张卡上。
/// 与 DragGesture(coordinateSpace: .global) 的 value.location 同一坐标系，落点判断才准。
struct FramePreferenceKey<ID: Hashable>: PreferenceKey {
    static var defaultValue: [ID: CGRect] { [:] }
    static func reduce(value: inout [ID: CGRect], nextValue: () -> [ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// 把自身在全局坐标系下的 frame 以 id 为键上报，供拖拽落点判断使用。
    func collectFrame<ID: Hashable>(id: ID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: FramePreferenceKey<ID>.self,
                                       value: [id: geo.frame(in: .global)])
            }
        )
    }
}
