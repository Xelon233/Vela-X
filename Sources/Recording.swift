//
//  Recording.swift
//  监控采样点、录制会话、CSV 导出
//

import Foundation

/// 一次采样（1 秒一个）
struct MetricSample {
    let time: Date
    let temp: Double?          // SMC 温度
    let load: Double           // CPU 总占用 0...1
    let mem: Double            // 内存占用 0...1
    let appCPU: Double?        // 绑定应用的 CPU（1.0 = 一核）
    let appMemMB: Double?      // 绑定应用的常驻内存
    let freqGHz: Double?       // CPU 平均有效频率（来自 AMDRyzenCPUPowerManagement）
    let power: Double?         // CPU 整包功耗（W）
}

/// 录制概要（存进索引）
struct RecordingSummary: Codable, Identifiable {
    let id: UUID
    var label: String
    var appName: String?
    var start: Date
    var end: Date
    var sampleCount: Int
    var avgTemp: Double
    var maxTemp: Double
    var avgLoad: Double
    var avgMem: Double
    var fileName: String

    var duration: TimeInterval { end.timeIntervalSince(start) }

    var durationText: String {
        let s = Int(duration.rounded())
        return s >= 60 ? "\(s / 60) 分 \(s % 60) 秒" : "\(s) 秒"
    }
}

enum RecordingStore {

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let dir = base.appendingPathComponent("AsusControl/Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func loadIndex() -> [RecordingSummary] {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([RecordingSummary].self, from: data) else { return [] }
        return list.sorted { $0.start > $1.start }
    }

    private static func saveIndex(_ list: [RecordingSummary]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(list) { try? data.write(to: indexURL) }
    }

    /// 写入 CSV 并把概要塞进索引，返回文件地址
    @discardableResult
    static func save(label: String, appName: String?, appPID: Int32?,
                     start: Date, end: Date, samples: [MetricSample]) -> RecordingSummary? {
        guard !samples.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let safeLabel = label.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        let name = "\(formatter.string(from: start))-\(safeLabel.isEmpty ? "record" : safeLabel).csv"
        let url = directory.appendingPathComponent(name)

        let iso = ISO8601DateFormatter()
        var csv = "timestamp,iso_time,temp_c,cpu_load_pct,mem_used_pct,app_cpu_pct,app_mem_mb,cpu_freq_ghz,cpu_power_w\n"
        for s in samples {
            let temp = s.temp.map { String(format: "%.2f", $0) } ?? ""
            let appCPU = s.appCPU.map { String(format: "%.1f", $0 * 100) } ?? ""
            let appMem = s.appMemMB.map { String(format: "%.1f", $0) } ?? ""
            let freq = s.freqGHz.map { String(format: "%.3f", $0) } ?? ""
            let power = s.power.map { String(format: "%.2f", $0) } ?? ""
            csv += "\(Int(s.time.timeIntervalSince1970)),\(iso.string(from: s.time)),"
            csv += "\(temp),\(String(format: "%.1f", s.load * 100)),"
            csv += "\(String(format: "%.1f", s.mem * 100)),\(appCPU),\(appMem),\(freq),\(power)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)

        let temps = samples.compactMap(\.temp)
        let summary = RecordingSummary(
            id: UUID(),
            label: label.isEmpty ? "未命名录制" : label,
            appName: appName,
            start: start,
            end: end,
            sampleCount: samples.count,
            avgTemp: temps.isEmpty ? 0 : temps.reduce(0, +) / Double(temps.count),
            maxTemp: temps.max() ?? 0,
            avgLoad: samples.map(\.load).reduce(0, +) / Double(samples.count),
            avgMem: samples.map(\.mem).reduce(0, +) / Double(samples.count),
            fileName: name
        )

        var index = loadIndex()
        index.insert(summary, at: 0)
        saveIndex(index)
        return summary
    }

    static func delete(_ summary: RecordingSummary) {
        var index = loadIndex()
        index.removeAll { $0.id == summary.id }
        saveIndex(index)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(summary.fileName))
    }

    static func fileURL(for summary: RecordingSummary) -> URL {
        directory.appendingPathComponent(summary.fileName)
    }
}

/// 正在进行的录制
struct ActiveRecording {
    var label: String
    var appName: String?
    var appPID: Int32?
    var start: Date
    var samples: [MetricSample] = []

    var elapsed: TimeInterval { Date().timeIntervalSince(start) }
}
