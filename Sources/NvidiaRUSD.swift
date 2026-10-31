//
//  NvidiaRUSD.swift
//  显卡功耗 / 显存占用：读 SMCNvidiaGPU-PowerVRAM 暴露的 sysctl
//
//  显卡功耗在 macOS 下本来是拿不到的 —— 没有 NVML，驱动也不往
//  PerformanceStatistics 里写功耗（所以 MenuMetrics 里 GPUStats 只有占用率和温度）。
//
//  SMCNvidiaGPU（zzzyy678）是 VirtualSMC 插件，借驱动自身的内核入口把 GSP 固件
//  维护的 RUSD 共享内存建出来读，功耗/显存都在内核侧采集。本仓库用的是它的二改版
//  SMCNvidiaGPU-PowerVRAM，额外把读数挂成 sysctl：
//    kern.nvgpupower      平均功耗（mW）
//    kern.nvgpuinstpower  瞬时功耗（mW）
//    kern.nvgpupwrlimit   强制功耗上限（mW）
//    kern.nvgvramused     已用显存（MB）
//    kern.nvgvramtotal    显存总量（MB）
//
//  读 sysctl 不需要 root，也不需要 IOKit 遍历，比 PerformanceStatistics 那条路便宜得多，
//  所以可以每帧读。kext 没装时这几个 sysctl 不存在，sample() 全返回 nil。
//

import Foundation
import Darwin

struct NvidiaRUSDStats {
    /// 平均功耗（W）
    var powerWatts: Double?
    /// 瞬时功耗（W）
    var instantWatts: Double?
    /// 强制功耗上限（W）
    var limitWatts: Double?
    /// 已用显存（MB）
    var vramUsedMB: Double?
    /// 显存总量（MB）
    var vramTotalMB: Double?
}

enum NvidiaRUSD {
    /// 功耗通道是否可用（首次调用时探一次，之后走静态缓存）
    static let powerAvailable: Bool = integer("kern.nvgpupower") != nil
    /// 显存通道是否可用
    static let vramAvailable: Bool = integer("kern.nvgvramused") != nil

    static var isAvailable: Bool { powerAvailable || vramAvailable }

    static func sample() -> NvidiaRUSDStats {
        var s = NvidiaRUSDStats()
        if powerAvailable {
            if let mw = integer("kern.nvgpupower") { s.powerWatts = Double(mw) / 1000 }
            if let mw = integer("kern.nvgpuinstpower") { s.instantWatts = Double(mw) / 1000 }
            if let mw = integer("kern.nvgpupwrlimit"), mw > 0 { s.limitWatts = Double(mw) / 1000 }
        }
        if vramAvailable {
            if let mb = integer("kern.nvgvramused") { s.vramUsedMB = Double(mb) }
            if let mb = integer("kern.nvgvramtotal"), mb > 0 { s.vramTotalMB = Double(mb) }
        }
        return s
    }

    /// 读一个整型 sysctl。这些键可能是 int32 也可能是 int64，所以先按返回的
    /// 实际长度解码，不写死类型 —— 驱动改一下宽度也不至于读出垃圾。
    static func integer(_ name: String) -> Int64? {
        var buf = [UInt8](repeating: 0, count: 8)
        var size = buf.count
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0, size > 0 else { return nil }
        switch size {
        case 8:
            var v: Int64 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf) }
            return v
        case 4:
            var v: Int32 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf.prefix(4)) }
            return Int64(v)
        case 2:
            var v: Int16 = 0
            withUnsafeMutableBytes(of: &v) { $0.copyBytes(from: buf.prefix(2)) }
            return Int64(v)
        case 1:
            return Int64(Int8(bitPattern: buf[0]))
        default:
            return nil
        }
    }
}
