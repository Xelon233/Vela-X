//
//  SMC.swift
//  AppleSMC 的 Swift 封装：解码 sp78 / fpe2 / ui* / {lkb 等数据类型
//

import Foundation

struct SMCReading {
    let key: String
    let type: String
    let size: Int
    let bytes: [UInt8]
    let number: Double?

    var hex: String {
        bytes.prefix(size).map { String(format: "%02x", $0) }.joined()
    }

    var display: String {
        if let n = number {
            if type == "sp78" || type == "flt " { return String(format: "%.1f", n) }
            return String(format: "%.0f", n)
        }
        return hex.isEmpty ? "—" : hex
    }
}

enum SMC {
    static let available: Bool = {
        smc_open() == 0
    }()

    static func exists(_ key: String) -> Bool {
        guard key.count == 4 else { return false }
        var size: UInt32 = 0
        var type = [CChar](repeating: 0, count: 5)
        return key.withCString { smc_key_info($0, &size, &type) } == 0
    }

    static func read(_ key: String) -> SMCReading? {
        guard key.count == 4 else { return nil }
        var buf = [UInt8](repeating: 0, count: 32)
        var size: UInt32 = 0
        var type = [CChar](repeating: 0, count: 5)
        let rc = key.withCString { k in
            smc_read(k, &buf, &size, &type)
        }
        guard rc == 0, size > 0 else { return nil }
        let typeStr = String(cString: type)
        let n = Int(size)
        return SMCReading(key: key, type: typeStr, size: n,
                          bytes: Array(buf.prefix(n)),
                          number: decode(bytes: buf, size: n, type: typeStr))
    }

    /// 写入原始字节。返回 0 成功 / 1 需要 root / -1 失败
    @discardableResult
    static func write(_ key: String, bytes: [UInt8]) -> Int32 {
        guard key.count == 4, !bytes.isEmpty else { return -1 }
        return key.withCString { k in
            bytes.withUnsafeBufferPointer { ptr in
                Int32(smc_write(k, ptr.baseAddress, UInt32(bytes.count)))
            }
        }
    }

    static func allKeys() -> [String] {
        let count = Int(smc_key_count())
        guard count > 0, count < 4096 else { return [] }
        var result: [String] = []
        for i in 0..<count {
            var name = [CChar](repeating: 0, count: 5)
            if smc_key_at(Int32(i), &name) == 0 {
                let s = String(cString: name)
                if s.count == 4 { result.append(s) }
            }
        }
        return result
    }

    // MARK: - 数据类型解码（SMC 使用大端）

    static func decode(bytes: [UInt8], size: Int, type: String) -> Double? {
        guard size >= 1 else { return nil }
        func be(_ n: Int) -> UInt64 {
            var v: UInt64 = 0
            for i in 0..<n where i < bytes.count { v = (v << 8) | UInt64(bytes[i]) }
            return v
        }
        switch type {
        case "sp78":
            guard size >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(be(2)))) / 256.0
        case "sp87", "sp5a", "sp96":
            guard size >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(be(2)))) / 256.0
        case "fpe2":
            guard size >= 2 else { return nil }
            return Double(UInt16(be(2))) / 4.0
        case "flt ":
            guard size >= 4 else { return nil }
            return Double(Float(bitPattern: UInt32(be(4))))
        case "ui8 ", "ui8":
            return Double(bytes[0])
        case "ui16":
            guard size >= 2 else { return nil }
            return Double(be(2))
        case "ui32":
            guard size >= 4 else { return nil }
            return Double(be(4))
        case "ui64":
            guard size >= 8 else { return nil }
            return Double(be(8))
        case "si8 ":
            return Double(Int8(bitPattern: bytes[0]))
        case "si16":
            guard size >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(be(2))))
        case "{lkb", "{lks":
            guard size >= 2 else { return nil }
            return Double(be(2))
        case "flag":
            return Double(bytes[0])
        case "fp1f":
            guard size >= 2 else { return nil }
            return Double(UInt16(be(2))) / 32768.0
        default:
            return nil
        }
    }

    /// 写入 16 位大端（键盘背光等 2 字节键）
    @discardableResult
    static func writeU16(_ key: String, _ value: Int) -> Int32 {
        let v = UInt16(clamping: value)
        return write(key, bytes: [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)])
    }
}

// MARK: - SMC 键目录（用于界面展示）

struct SMCKeyMeta {
    let key: String
    let name: String
    let unit: String
    var decimals: Int = 0
}

enum SMCKeyCatalog {
    static let interesting: [SMCKeyMeta] = [
        .init(key: "TC0P", name: "CPU 核心温度", unit: "°C", decimals: 1),
        .init(key: "TC0E", name: "CPU 有效温度", unit: "°C", decimals: 1),
        .init(key: "TC0F", name: "CPU 风扇区温度", unit: "°C", decimals: 1),
        .init(key: "F0Ac", name: "风扇转速", unit: "RPM"),
        .init(key: "FNum", name: "风扇数量", unit: "个"),
        .init(key: "LKSB", name: "键盘背光亮度", unit: "/16"),
        .init(key: "LKSS", name: "键盘背光开关", unit: ""),
        .init(key: "ALV0", name: "环境光强", unit: "lux"),
        .init(key: "B0RM", name: "电池剩余容量(SMC)", unit: "mAh"),
        .init(key: "B0FC", name: "电池满充容量(SMC)", unit: "mAh")
    ]
}
