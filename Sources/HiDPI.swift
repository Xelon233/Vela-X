//
//  HiDPI.swift
//  Vela X — 开启 HiDPI（参考 xzhih/one-key-hidpi）
//
//  原理：向 /Library/Displays/Contents/Resources/Overrides 写入
//  DisplayVendorID-<VID>/DisplayProductID-<PID> 的覆盖 plist，其中 scale-resolutions
//  数组提供若干 HiDPI 缩放档位（宽高各 ×2，再拼固定属性尾）。写入需要管理员权限。
//  目录 /Library/... 属用户数据区，无需关闭 SIP，也不改系统卷。
//

import Foundation
import CoreGraphics
import AppKit

/// 一台显示器的标识与原生分辨率
struct HiDPIDisplay: Identifiable {
    let id: CGDirectDisplayID
    let vendorID: UInt32
    let productID: UInt32
    let nativeWidth: Int
    let nativeHeight: Int
    let name: String

    var vendorHex: String { String(vendorID, radix: 16) }
    var productHex: String { String(productID, radix: 16) }
    var nativeText: String { "\(nativeWidth) × \(nativeHeight)" }
}

enum HiDPI {
    static let overridesRoot = "/Library/Displays/Contents/Resources/Overrides"

    // MARK: - 枚举显示器

    static func displays() -> [HiDPIDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var real: UInt32 = 0
        guard CGGetOnlineDisplayList(count, &ids, &real) == .success else { return [] }
        return ids.prefix(Int(real)).compactMap { info(for: $0) }
    }

    static func info(for id: CGDirectDisplayID) -> HiDPIDisplay? {
        let vid = CGDisplayVendorNumber(id)
        let pid = CGDisplayModelNumber(id)
        let (nw, nh) = nativePixelSize(id)
        guard vid != 0, pid != 0, nw > 0, nh > 0 else { return nil }
        return HiDPIDisplay(id: id, vendorID: vid, productID: pid,
                            nativeWidth: nw, nativeHeight: nh,
                            name: displayName(id) ?? "显示器")
    }

    /// 原生像素尺寸：取所有显示模式里像素面积最大的一档（横屏）
    private static func nativePixelSize(_ id: CGDirectDisplayID) -> (Int, Int) {
        let modes = CGDisplayCopyAllDisplayModes(id, nil) as? [CGDisplayMode] ?? []
        var best = (0, 0)
        var bestArea = 0
        for m in modes {
            let w = CGDisplayModeGetPixelWidth(m)
            let h = CGDisplayModeGetPixelHeight(m)
            guard w >= h, w > 0 else { continue }
            let area = w * h
            if area > bestArea { bestArea = area; best = (w, h) }
        }
        if best.0 == 0 {
            return (CGDisplayPixelsWide(id), CGDisplayPixelsHigh(id))
        }
        return best
    }

    private static func displayName(_ id: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            if num?.uint32Value == id { return screen.localizedName }
        }
        return nil
    }

    // MARK: - 路径

    static func overrideDir(for d: HiDPIDisplay) -> String {
        "\(overridesRoot)/DisplayVendorID-\(d.vendorHex)"
    }

    static func overrideFile(for d: HiDPIDisplay) -> String {
        "\(overrideDir(for: d))/DisplayProductID-\(d.productHex)"
    }

    static func isEnabled(_ d: HiDPIDisplay) -> Bool {
        FileManager.default.fileExists(atPath: overrideFile(for: d))
    }

    // MARK: - 生成配置

    /// 逻辑分辨率候选（保持原生宽高比，按比例下探；宽高取偶数）
    static func candidateResolutions(for d: HiDPIDisplay) -> [(Int, Int)] {
        let nw = d.nativeWidth, nh = d.nativeHeight
        let scales: [Double] = [1.0, 0.9, 5.0 / 6.0, 0.8, 0.75, 2.0 / 3.0, 0.625, 0.5]
        var seen = Set<String>()
        var out: [(Int, Int)] = []
        for s in scales {
            var w = Int((Double(nw) * s / 2).rounded()) * 2
            let h = Int((Double(nh) * s / 2).rounded()) * 2
            if w > nw { w = nw }
            guard w >= 640, h >= 360 else { continue }
            let key = "\(w)x\(h)"
            if seen.insert(key).inserted { out.append((w, h)) }
        }
        return out
    }

    /// 单条 scale-resolution 的 base64 数据（复刻 one-key-hidpi 的 create_res）：
    /// 宽高各 ×2 → 两个 4 字节大端 → base64（12 字符，末位 = 丢掉）→ 拼固定属性尾。
    private static func scaleEntries(_ logical: (Int, Int)) -> [String] {
        let w2 = UInt32(logical.0 * 2)
        let h2 = UInt32(logical.1 * 2)
        let bytes: [UInt8] = [
            UInt8((w2 >> 24) & 0xFF), UInt8((w2 >> 16) & 0xFF),
            UInt8((w2 >> 8) & 0xFF), UInt8(w2 & 0xFF),
            UInt8((h2 >> 24) & 0xFF), UInt8((h2 >> 16) & 0xFF),
            UInt8((h2 >> 8) & 0xFF), UInt8(h2 & 0xFF)
        ]
        let b64 = Data(bytes).base64EncodedString()   // 12 字符，末尾 '='
        let p = String(b64.prefix(11))                // 去掉补位
        return ["\(p)AAAAB", "\(p)AAAABACAAAA=="]
    }

    static func plist(for d: HiDPIDisplay) -> String {
        var entries = ""
        for r in candidateResolutions(for: d) {
            for e in scaleEntries(r) {
                entries += "        <data>\(e)</data>\n"
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>DisplayProductID</key>
            <integer>\(d.productID)</integer>
            <key>DisplayVendorID</key>
            <integer>\(d.vendorID)</integer>
            <key>scale-resolutions</key>
            <array>
        \(entries)    </array>
            <key>target-default-ppmm</key>
            <real>10.0699301</real>
        </dict>
        </plist>
        """
    }

    // MARK: - 写入 / 移除（需管理员）

    /// 返回 nil 表示成功，否则为错误描述
    static func enable(_ d: HiDPIDisplay) -> String? {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vela-hidpi-\(d.productHex).plist")
        do {
            try plist(for: d).write(to: tmpURL, atomically: true, encoding: .utf8)
        } catch {
            return "生成配置文件失败：\(error.localizedDescription)"
        }
        let dir = overrideDir(for: d)
        let file = overrideFile(for: d)
        let script = """
        set -e
        mkdir -p "\(dir)"
        cp "\(tmpURL.path)" "\(file)"
        chown root:wheel "\(dir)" "\(file)"
        chmod 755 "\(dir)"
        chmod 644 "\(file)"
        defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool YES
        """
        let r = runAdmin(script)
        try? FileManager.default.removeItem(at: tmpURL)
        if r.ok { return nil }
        if r.output.isEmpty || r.output.localizedCaseInsensitiveContains("cancel") || r.output.contains("-128") {
            return "已取消管理员授权，未做任何改动。"
        }
        return r.output
    }

    static func disable(_ d: HiDPIDisplay) -> String? {
        let dir = overrideDir(for: d)
        let file = overrideFile(for: d)
        let script = """
        rm -f "\(file)"
        rmdir "\(dir)" 2>/dev/null || true
        """
        let r = runAdmin(script)
        if r.ok { return nil }
        if r.output.isEmpty || r.output.localizedCaseInsensitiveContains("cancel") || r.output.contains("-128") {
            return "已取消管理员授权，未做任何改动。"
        }
        return r.output
    }

    /// 以管理员身份执行一段 shell（多行会拼成一行，避免 AppleScript 换行问题）
    private static func runAdmin(_ script: String) -> (ok: Bool, output: String) {
        let oneLine = script
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "; ")
        let escaped = oneLine
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "do shell script \"\(escaped)\" with administrator privileges"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let out = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return (p.terminationStatus == 0, out)
        } catch {
            return (false, error.localizedDescription)
        }
    }
}
