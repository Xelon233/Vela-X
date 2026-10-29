// 生成 App 图标：仪表盘造型（CoreGraphics，无外部依赖）
// 用法: swift Tools/make_icon.swift <输出目录>

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func drawIcon(size: CGFloat) -> CGImage? {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }

    let s = size
    // 圆角底板
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        CGColor(red: 0.106, green: 0.322, blue: 0.643, alpha: 1),
        CGColor(red: 0.153, green: 0.541, blue: 0.902, alpha: 1),
        CGColor(red: 0.322, green: 0.780, blue: 0.827, alpha: 1)
    ] as CFArray
    if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 0.55, 1]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: rect.minX, y: rect.maxY),
                               end: CGPoint(x: rect.maxX, y: rect.minY),
                               options: [])
    }
    ctx.restoreGState()

    // 内部细描边，增加层次
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(s * 0.006)
    ctx.strokePath()
    ctx.restoreGState()

    // 仪表盘弧线
    let center = CGPoint(x: s / 2, y: s / 2 - s * 0.015)
    let radiusOuter = s * 0.245
    let startAngle = CGFloat.pi * 0.78
    let endAngle = CGFloat.pi * 2.22

    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.058)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
    ctx.addArc(center: center, radius: radiusOuter,
               startAngle: startAngle, endAngle: endAngle, clockwise: false)
    ctx.strokePath()

    // 已用刻度（约 72%）
    let usedEnd = startAngle + (endAngle - startAngle) * 0.72
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addArc(center: center, radius: radiusOuter,
               startAngle: startAngle, endAngle: usedEnd, clockwise: false)
    ctx.strokePath()

    // 指针
    let needleAngle = usedEnd
    let needleLen = radiusOuter * 0.62
    ctx.setLineWidth(s * 0.030)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(needleAngle) * needleLen,
                            y: center.y + sin(needleAngle) * needleLen))
    ctx.strokePath()

    // 中心轴
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: center.x - s * 0.032, y: center.y - s * 0.032,
                               width: s * 0.064, height: s * 0.064))

    // 底部三条“档位”短横线
    ctx.setLineWidth(s * 0.024)
    ctx.setLineCap(.round)
    for (i, alpha) in [0.95, 0.6, 0.32].enumerated() {
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
        let y = s * 0.235 + CGFloat(i) * s * 0.055
        let x0 = s / 2 - s * 0.11
        ctx.move(to: CGPoint(x: x0, y: y))
        ctx.addLine(to: CGPoint(x: x0 + s * 0.22, y: y))
        ctx.strokePath()
    }

    return ctx.makeImage()
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let iconset = URL(fileURLWithPath: outDir).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let specs: [(Int, Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
for (base, scale) in specs {
    let px = base * scale
    guard let img = drawIcon(size: CGFloat(px)) else { continue }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    writePNG(img, to: iconset.appendingPathComponent(name))
}

print("iconset: \(iconset.path)")
