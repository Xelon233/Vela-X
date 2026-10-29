//
//  SystemLoad.swift
//  不依赖任何 kext 的负载数据：Mach 内核计数器 + 公开 API
//
//  说明：macOS 没有 /dev/mem、没有 IOPort 用户客户端，MSR/SMN/物理内存都需要 ring0，
//  所以「CPU 温度」只能拿 SMC（也就是 VirtualSMC + SMCAMDProcessor 这两个 kext）的值。
//  但 CPU 负载、内核热压力、内存占用这些走 Mach 内核计数器，跟 kext 无关，
//  可以独立拿到，也算是一份不会被虚拟 SMC 污染的交叉验证数据。
//

import Foundation
import Darwin

struct SystemLoadSnapshot {
    var perCore: [Double] = []          // 0...1
    var total: Double = 0
    var load1: Double = 0
    var load5: Double = 0
    var load15: Double = 0
    var thermal: ProcessInfo.ThermalState = .nominal
    var memoryUsedRatio: Double = 0
    var memTotal: UInt64 = 0
    var memActive: UInt64 = 0
    var memWired: UInt64 = 0
    var memCompressed: UInt64 = 0
    var memFree: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    var sampled = false

    var thermalText: String {
        switch thermal {
        case .nominal: return "正常"
        case .fair: return "偏热"
        case .serious: return "过热"
        case .critical: return "临界"
        @unknown default: return "未知"
        }
    }
}

enum SystemLoad {

    private static var previousTicks: [[UInt32]] = []

    static func sample() -> SystemLoadSnapshot {
        var snap = SystemLoadSnapshot()

        // 1) 每核占用：host_processor_info(PROCESSOR_CPU_LOAD_INFO)
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                     &cpuCount, &info, &infoCount)
        if kr == KERN_SUCCESS, let info {
            defer {
                let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
            }
            let stride = Int(CPU_STATE_MAX)
            var ticks: [[UInt32]] = []
            for core in 0..<Int(cpuCount) {
                let base = core * stride
                ticks.append([
                    UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                    UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                    UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
                    UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
                ])
            }
            if previousTicks.count == ticks.count {
                var totalBusy = 0.0
                var totalAll = 0.0
                for (i, now) in ticks.enumerated() {
                    let prev = previousTicks[i]
                    var delta = [Double](repeating: 0, count: 4)
                    for k in 0..<4 {
                        delta[k] = now[k] >= prev[k] ? Double(now[k] - prev[k])
                                                     : Double(UInt32.max - prev[k] + now[k])
                    }
                    let busy = delta[0] + delta[1] + delta[2]
                    let all = busy + delta[3]
                    snap.perCore.append(all > 0 ? min(busy / all, 1) : 0)
                    totalBusy += busy
                    totalAll += all
                }
                snap.total = totalAll > 0 ? min(totalBusy / totalAll, 1) : 0
                snap.sampled = true
            }
            previousTicks = ticks
        }

        // 2) load average
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            snap.load1 = loads[0]; snap.load5 = loads[1]; snap.load15 = loads[2]
        }

        // 3) 内核热压力（公开 API，不是 SMC 温度）
        snap.thermal = ProcessInfo.processInfo.thermalState

        // 4) 内存占用：host_statistics64
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let memKR = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        if memKR == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            snap.memTotal = ProcessInfo.processInfo.physicalMemory
            snap.memActive = UInt64(Double(stats.active_count) * page)
            snap.memWired = UInt64(Double(stats.wire_count) * page)
            snap.memCompressed = UInt64(Double(stats.compressor_page_count) * page)
            snap.memFree = UInt64(Double(stats.free_count + stats.speculative_count) * page)
            let used = Double(snap.memActive + snap.memWired + snap.memCompressed)
            snap.memoryUsedRatio = snap.memTotal > 0 ? min(used / Double(snap.memTotal), 1) : 0
        }

        // 5) swap：sysctl vm.swapusage
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 {
            snap.swapUsed = usage.xsu_used
            snap.swapTotal = usage.xsu_total
        }

        return snap
    }
}
