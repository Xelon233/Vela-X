//
//  PowerBench.swift
//  VelaX —— 满载发生器（只给「实测功耗上限」用）
//
//  为什么需要自己压 CPU：
//    寄存器里的 PL1 是**固件写的标称值**（本机 175W），跟这台机器真能吃到多少没关系。
//    要看真实能力，只能自己造一段满载、边压边用 MSR 0x611 的能量差算功耗。
//
//  实现约束：
//    · 必须真的饱和到 activeProcessorCount 个线程，否则测出来偏低；
//    · 循环体不能被优化掉（累加结果返回到调用方，编译期删不掉）；
//    · 只在后台队列调用 —— concurrentPerform 是阻塞的。
//

import Foundation

enum PowerBench {

    /// 把 CPU 压满 seconds 秒。返回各线程累加值之和（用于阻止编译器消除整个循环）。
    @discardableResult
    static func burn(seconds: Double) -> Double {
        let threads = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let deadline = Date().addingTimeInterval(seconds)
        // 每个线程写自己的槽位，避免并发写同一块内存
        var partial = [Double](repeating: 0, count: threads)

        DispatchQueue.concurrentPerform(iterations: threads) { idx in
            var acc = 0.0
            var i = 1.0
            while Date() < deadline {
                // 内层批量算，减少 Date() 调用的占比（每 2 万次取一次时间）
                for _ in 0..<20_000 {
                    acc += (i * 1.000001).squareRoot()
                    i += 1
                }
            }
            partial[idx] = acc
        }
        return partial.reduce(0, +)
    }
}
