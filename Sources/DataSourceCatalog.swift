//
//  DataSourceCatalog.swift
//  诊断页用：每个指标到底走哪条通道、要不要依赖 kext
//

import Foundation

struct DataSourceItem: Identifiable {
    let id = UUID()
    let metric: String
    let channel: String
    let needsKext: Bool
}

enum DataSourceCatalog {
    static let all: [DataSourceItem] = [
        .init(metric: "CPU 温度", channel: "AppleSMC · TC0P (sp78)", needsKext: true),
        .init(metric: "风扇转速", channel: "AppleSMC · F0Ac／FNum", needsKext: true),
        .init(metric: "环境光", channel: "AppleSMC · ALV0", needsKext: true),
        .init(metric: "键盘背光", channel: "Aura HID · report 0x5A", needsKext: false),
        .init(metric: "CPU 负载", channel: "Mach host_processor_info", needsKext: false),
        .init(metric: "热压力", channel: "ProcessInfo.thermalState", needsKext: false),
        .init(metric: "内存占用", channel: "Mach host_statistics64", needsKext: false),
        .init(metric: "电池", channel: "IOKit AppleSmartBattery", needsKext: false),
        .init(metric: "显卡驱动", channel: "IORegistry · CFBundleIdentifier", needsKext: false)
    ]
}
