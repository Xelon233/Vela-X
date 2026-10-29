//
//  Sampling.swift
//  采样档位：可选的轮询间隔（1 / 2 / 3 / 5 秒）
//
//  设计取舍：温度、负载、内存这些值本身变化很慢，1 秒采样对「看曲线」没有实质帮助，
//  但每秒一次的 IOKit / libproc 调用会实打实地占主线程。所以上限放到 5 秒，
//  默认 2 秒，用户按需在「概览」页切换，设置会持久化。
//

import Foundation

enum SamplingRate: Int, CaseIterable, Identifiable, Comparable {
    case fast = 1
    case standard = 2
    case relaxed = 3
    case eco = 5

    var id: Int { rawValue }

    /// 分段控件上的短标签
    var label: String { "\(rawValue)s" }

    var longLabel: String { "\(rawValue) 秒" }

    var summary: String {
        switch self {
        case .fast:     return "1 秒：曲线最细，CPU 开销最高"
        case .standard: return "2 秒：默认，曲线与开销平衡"
        case .relaxed:  return "3 秒：轻负载"
        case .eco:      return "5 秒：常驻最省，适合挂后台"
        }
    }

    /// 温度 / 负载曲线的时间窗口（秒）
    static let tempWindow = 240
    /// 监控页历史窗口（秒）
    static let historyWindow = 900

    /// 曲线保留点数 = 窗口 / 间隔
    var tempCapacity: Int { max(24, Self.tempWindow / rawValue) }
    var historyCapacity: Int { max(60, Self.historyWindow / rawValue) }

    /// 进程采样至少 2 秒一次，且不高于采样间隔（两者取大）
    var processPeriod: TimeInterval { TimeInterval(max(2, rawValue)) }

    /// 电池信息变化慢，按采样间隔放大到 ~15 秒
    var batteryPeriod: TimeInterval { TimeInterval(max(15, rawValue * 5)) }

    static func < (lhs: SamplingRate, rhs: SamplingRate) -> Bool { lhs.rawValue < rhs.rawValue }

    // MARK: - 持久化

    private static let key = "sample.interval"

    static var saved: SamplingRate {
        let v = Prefs.int(key, default: SamplingRate.standard.rawValue)
        return SamplingRate(rawValue: v) ?? .standard
    }

    func persist() {
        Prefs.set(rawValue, for: Self.key)
    }
}
