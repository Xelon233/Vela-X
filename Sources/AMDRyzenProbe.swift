//
//  AMDRyzenProbe.swift
//  VelaX —— 通过 AMDRyzenCPUPowerManagement.kext 读取 AMD CPU 实时功耗与每核有效频率
//
//  参考 trulyspinach/SMCAMDProcessor（AMD Power Gadget 的实现）：
//    SMCAMDProcessor.kext 只是 VirtualSMC 插件，发布温度 / 能量；真正的功耗与频率
//    由依赖的 AMDRyzenCPUPowerManagement.kext 提供，用户态通过它的 IOService 用户客户端读。
//
//    IOServiceOpen("AMDRyzenCPUPowerManagement") 后，external method selector 4（loadMetric）
//    返回 (numberOfCores + 3) 个 float：
//      [0]           整包功耗（Watt）
//      [1]           封装温度（°C）
//      [2]           当前 P-state 索引
//      [3 ..< 3+核数) 每核有效频率（MHz，由 APERF / MPERF 增量算出）
//
//  这是普通用户态调用，不需要 root（AMD Power Gadget 就是普通 App 这么读的）。
//  kext 没装时 available = false，sample() 直接返回空，所有相关指标降级为「不可用」。
//

import Foundation
import IOKit

public final class AMDRyzenProbe {

    public static let shared = AMDRyzenProbe()

    private var connect: io_connect_t = 0
    public private(set) var available = false

    private init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault,
                                              IOServiceMatching("AMDRyzenCPUPowerManagement"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        available = IOServiceOpen(svc, mach_task_self_, 0, &connect) == KERN_SUCCESS
    }

    deinit {
        if connect != 0 { IOServiceClose(connect); connect = 0 }
    }

    /// 一次采样的解析结果（kext 没装 / 调用失败都为 nil）
    public struct Sample {
        public var powerWatts: Double?
        public var avgFreqGHz: Double?
        public var maxFreqGHz: Double?
        public var coreCount: Int = 0
    }

    /// 普通用户态即可调用。selector 4 由 kext 内部做 APERF/MPERF 增量，
    /// 调用间隔（本 App 约 2s）越长越接近区间均值，正是菜单栏想要的平滑值。
    public func sample() -> Sample {
        guard available else { return Sample() }

        let cap = 128
        var scalerOut: UInt64 = 0
        var outputCount: UInt32 = 1
        var floats = [Float](repeating: 0, count: cap)
        var floatCount = cap * MemoryLayout<Float>.size   // size_t → Int in Swift

        let kr = IOConnectCallMethod(connect, 4, nil, 0, nil, 0,
                                     &scalerOut, &outputCount,
                                     &floats, &floatCount)
        guard kr == KERN_SUCCESS else { return Sample() }

        let n = Int(scalerOut)
        guard n >= 1, floatCount >= (n + 3) * MemoryLayout<Float>.size else {
            return Sample()
        }

        let power = Double(floats[0])
        let cores = floats[3..<(3 + n)]
        let avgMHz = cores.reduce(0, +) / Float(cores.count)
        let maxMHz = cores.max() ?? 0

        return Sample(powerWatts: power > 0 ? power : nil,
                      avgFreqGHz: Double(avgMHz) / 1000.0,
                      maxFreqGHz: Double(maxMHz) / 1000.0,
                      coreCount: n)
    }
}
