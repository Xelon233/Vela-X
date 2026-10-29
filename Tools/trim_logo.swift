//
//  trim_logo.swift
//  把下载的 ROG logo 裁掉四周透明边，并缩放到界面需要的高度
//  用法：swift Tools/trim_logo.swift <输入.png> <输出.png> <输出高度px>
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 4 else {
    print("用法: trim_logo.swift <输入> <输出> <高度px>")
    exit(2)
}
let inputPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]
let targetHeight = Int(CommandLine.arguments[3]) ?? 240

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("无法读取 \(inputPath)")
    exit(1)
}

let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: width, height: height,
                          bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("无法创建位图上下文")
    exit(1)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

// 以 alpha > 12 判定为可见像素（白色 logo 的 RGB 也是 255，只能靠 alpha）
let threshold: UInt8 = 12
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    let row = y * width * 4
    for x in 0..<width {
        if pixels[row + x * 4 + 3] > threshold {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
}
guard maxX > minX, maxY > minY else {
    print("整张图都是透明的？")
    exit(1)
}

// CGContext 的 y 轴向上，转成 CGImage 的裁剪坐标
let cropRect = CGRect(x: minX, y: minY,
                      width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = image.cropping(to: cropRect) else {
    print("裁剪失败")
    exit(1)
}

let ratio = Double(cropped.width) / Double(cropped.height)
let outH = targetHeight
let outW = max(1, Int((Double(outH) * ratio).rounded()))
guard let outCtx = CGContext(data: nil, width: outW, height: outH,
                             bitsPerComponent: 8, bytesPerRow: 0,
                             space: cs,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("无法创建输出上下文")
    exit(1)
}
outCtx.interpolationQuality = .high
outCtx.draw(cropped, in: CGRect(x: 0, y: 0, width: outW, height: outH))
guard let outImage = outCtx.makeImage() else {
    print("输出失败")
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    print("无法写入 \(outputPath)")
    exit(1)
}
CGImageDestinationAddImage(dest, outImage, nil)
CGImageDestinationFinalize(dest)

print("原始 \(width)×\(height) → 内容框 \(Int(cropRect.width))×\(Int(cropRect.height)) → 输出 \(outW)×\(outH)")
