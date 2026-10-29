//
//  SMCClient.swift
//  VelaX —— AppleSMC 读写封装（读写 SMC 键，用于风扇档位切换）
//
//  设计说明：
//    SMC 的 IOConnectCallStructMethod 收发的是一个 80 字节的 C 结构体。
//    直接用 Swift struct 映射会踩到对齐/填充的坑（不同 SDK 可能不一致），
//    所以这里用固定 80 字节的 [UInt8] 缓冲区 + 手写偏移来保证 ABI 稳定。
//
//    偏移量（x86_64 / arm64 均为小端）：
//      0   key            UInt32
//      28  keyInfo.dataSize    UInt32
//      32  keyInfo.dataType    UInt32   (四字符，如 'fpe2')
//      36  keyInfo.dataAttributes UInt8
//      40  result / 41 status / 42 data8
//      44  data32
//      48  bytes[32]
//
//  权限：
//    读键普通用户即可；**写键需要 root**（否则返回 kIOReturnNotPrivileged 0xE00002C1）。
//

import Foundation
import IOKit

public enum SMCError: LocalizedError {
    case serviceNotFound
    case openFailed(kern_return_t)
    case keyNotFound(String)
    case notWritable(String)
    case ioFailed(kern_return_t)
    case badKeyName(String)

    public var errorDescription: String? {
        switch self {
        case .serviceNotFound:            return "找不到 AppleSMC 服务（VirtualSMC 未运行？）"
        case .openFailed(let kr):         return "打开 AppleSMC 失败：0x\(String(kr, radix: 16))"
        case .keyNotFound(let k):         return "SMC 键不存在：\(k)"
        case .notWritable(let k):         return "SMC 键不可写：\(k)"
        case .ioFailed(let kr):           return "SMC 调用失败：0x\(String(kr, radix: 16))"
        case .badKeyName(let k):          return "键名必须是 4 个字符：\(k)"
        }
    }
}

public final class SMCClient {

    public static let shared = SMCClient()

    private var conn: io_connect_t = 0
    private static let structSize = 80
    private static let kernelIndexSMC: UInt32 = 2

    private enum Cmd {
        static let readBytes: UInt8   = 5
        static let writeBytes: UInt8  = 6
        static let readKeyInfo: UInt8 = 9
    }
    private enum Off {
        static let key = 0
        static let dataSize = 28
        static let dataType = 32
        static let dataAttrs = 36
        static let data8 = 42
        static let bytes = 48
    }

    public struct KeyInfo {
        public let dataSize: UInt32
        public let dataType: String
        public let attributes: UInt8
        public var isWritable: Bool { attributes & 0x40 != 0 }
    }

    private init() {}

    // MARK: - 连接

    public func open() throws {
        if conn != 0 { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }

        var c: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &c)
        guard kr == KERN_SUCCESS else { throw SMCError.openFailed(kr) }
        conn = c
    }

    public func close() {
        if conn != 0 { IOServiceClose(conn); conn = 0 }
    }

    deinit { close() }

    // MARK: - 底层

    private static func packKey(_ name: String) throws -> UInt32 {
        let chars = Array(name.utf8)
        guard chars.count == 4 else { throw SMCError.badKeyName(name) }
        return (UInt32(chars[0]) << 24) | (UInt32(chars[1]) << 16) |
               (UInt32(chars[2]) << 8)  |  UInt32(chars[3])
    }

    private static func put32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
        buf[off]     = UInt8(v & 0xFF)
        buf[off + 1] = UInt8((v >> 8) & 0xFF)
        buf[off + 2] = UInt8((v >> 16) & 0xFF)
        buf[off + 3] = UInt8((v >> 24) & 0xFF)
    }

    private static func get32(_ buf: [UInt8], _ off: Int) -> UInt32 {
        UInt32(buf[off]) | (UInt32(buf[off + 1]) << 8) |
        (UInt32(buf[off + 2]) << 16) | (UInt32(buf[off + 3]) << 24)
    }

    private func call(_ input: inout [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: Self.structSize)
        var outSize = Self.structSize

        let kr: kern_return_t = input.withUnsafeBytes { inRaw in
            output.withUnsafeMutableBytes { outRaw in
                IOConnectCallStructMethod(conn, Self.kernelIndexSMC,
                                          inRaw.baseAddress, Self.structSize,
                                          outRaw.baseAddress, &outSize)
            }
        }
        guard kr == KERN_SUCCESS else { throw SMCError.ioFailed(kr) }
        return output
    }

    // MARK: - 对外

    public func keyInfo(_ name: String) throws -> KeyInfo {
        try open()
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put32(&input, Off.key, try Self.packKey(name))
        input[Off.data8] = Cmd.readKeyInfo

        let out = try call(&input)
        guard out[40] == 0 else { throw SMCError.keyNotFound(name) }   // result != 0

        let typeValue = Self.get32(out, Off.dataType)
        let typeChars = (0..<4).map { UInt8((typeValue >> (8 * (3 - $0))) & 0xFF) }
        let type = typeChars.allSatisfy { $0 >= 0x20 && $0 < 0x7F }
            ? String(bytes: typeChars, encoding: .ascii) ?? "?"
            : "?"

        return KeyInfo(dataSize: Self.get32(out, Off.dataSize),
                       dataType: type,
                       attributes: out[Off.dataAttrs])
    }

    public func read(_ name: String) throws -> [UInt8] {
        let info = try keyInfo(name)
        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put32(&input, Off.key, try Self.packKey(name))
        Self.put32(&input, Off.dataSize, info.dataSize)
        input[Off.data8] = Cmd.readBytes

        let out = try call(&input)
        let n = min(Int(info.dataSize), 32)
        return Array(out[Off.bytes..<(Off.bytes + n)])
    }

    public func write(_ name: String, _ data: [UInt8]) throws {
        let info = try keyInfo(name)
        guard info.isWritable else { throw SMCError.notWritable(name) }
        guard data.count == Int(info.dataSize) else { throw SMCError.ioFailed(KERN_INVALID_ARGUMENT) }

        var input = [UInt8](repeating: 0, count: Self.structSize)
        Self.put32(&input, Off.key, try Self.packKey(name))
        Self.put32(&input, Off.dataSize, info.dataSize)
        input[Off.data8] = Cmd.writeBytes
        for (i, b) in data.enumerated() where i < 32 { input[Off.bytes + i] = b }

        _ = try call(&input)
    }

    // MARK: - 便捷封装（对应本项目的 ui8 / ui32 键）

    public func readUInt8(_ name: String) throws -> UInt8 {
        try read(name).first ?? 0
    }

    public func writeUInt8(_ name: String, _ value: UInt8) throws {
        try write(name, [value])
    }

    /// SMC 的 ui32 是大端
    public func readUInt32(_ name: String) throws -> UInt32 {
        let b = try read(name)
        guard b.count == 4 else { throw SMCError.ioFailed(KERN_INVALID_ARGUMENT) }
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    public func writeUInt32(_ name: String, _ value: UInt32) throws {
        let b: [UInt8] = [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                          UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        try write(name, b)
    }

    /// fpe2 转 RPM（风扇转速键 F0Ac/F1Ac 都是这个类型）
    public func readRPM(_ name: String) throws -> Int {
        let b = try read(name)
        guard b.count == 2 else { return 0 }
        return Int(UInt16(b[0]) << 8 | UInt16(b[1])) / 4
    }
}
