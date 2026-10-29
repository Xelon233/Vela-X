//
//  ProcessSampler.swift
//  按进程采集 CPU / 内存（libproc，无需 root）
//
//  CPU 百分比算法：两次采样之间 pti_total_user+system 的差值（纳秒）除以实际间隔。
//  单核跑满 = 100%，多线程可以超过 100%（和 top 一致）。
//

import Foundation

struct ProcSample: Identifiable {
    let pid: Int32
    let name: String
    let cpu: Double        // 1.0 = 一个核心跑满
    let memory: UInt64     // 常驻内存（字节）

    var id: Int32 { pid }
    var memoryMB: Double { Double(memory) / 1_048_576 }
}

enum ProcessSampler {

    private static var previous: [Int32: UInt64] = [:]
    private static var previousTime: Date?
    private static var calibrated = false

    /// 采样一次。首次调用时 CPU 值全为 0（没有基线），calibrated 会变 true
    @discardableResult
    static func sample() -> [ProcSample] {
        let capacity = 2048
        var pids = [Int32](repeating: 0, count: capacity)
        let count = Int(pids.withUnsafeMutableBufferPointer { asus_proc_list($0.baseAddress, Int32(capacity)) })
        guard count > 0 else { return [] }

        let now = Date()
        let elapsed = previousTime.map { max(now.timeIntervalSince($0), 0.001) } ?? 1.0
        var result: [ProcSample] = []
        result.reserveCapacity(count)
        var newTicks: [Int32: UInt64] = [:]
        newTicks.reserveCapacity(count)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var nameBuf = [CChar](repeating: 0, count: 64)
            var cpuNs: UInt64 = 0
            var rss: UInt64 = 0
            let rc = nameBuf.withUnsafeMutableBufferPointer { buf in
                asus_proc_info(pid, buf.baseAddress, Int32(buf.count), &cpuNs, &rss)
            }
            guard rc == 0 else { continue }
            newTicks[pid] = cpuNs

            let name = String(cString: nameBuf)
            var cpu = 0.0
            if let prev = previous[pid], cpuNs >= prev {
                cpu = Double(cpuNs - prev) / (elapsed * 1_000_000_000)
            }
            result.append(ProcSample(pid: pid,
                                     name: name.isEmpty ? "pid \(pid)" : name,
                                     cpu: min(cpu, Double(ProcessInfo.processInfo.activeProcessorCount)),
                                     memory: rss))
        }

        previous = newTicks
        previousTime = now
        calibrated = true
        return result
    }

    static var hasBaseline: Bool { calibrated }

    /// 按 CPU 或内存排序取前 N
    static func top(_ samples: [ProcSample], byCPU: Bool, limit: Int = 12) -> [ProcSample] {
        let sorted = samples.sorted {
            byCPU ? $0.cpu > $1.cpu : $0.memory > $1.memory
        }
        return Array(sorted.prefix(limit))
    }

    /// 按名称找进程（用于录制时绑定应用）
    static func findByPID(_ samples: [ProcSample], pid: Int32) -> ProcSample? {
        samples.first { $0.pid == pid }
    }
}
