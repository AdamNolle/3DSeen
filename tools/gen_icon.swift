#!/usr/bin/env swift
// Generates the 3DSeen app icon (cobalt field + white cube glyph) as PNGs.
// Usage: swift tools/gen_icon.swift <output-dir> <size1> [size2 ...]

import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

func makeIcon(_ size: CGFloat) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                        bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // cobalt gradient background (full bleed; OS masks the corners)
    let colors = [CGColor(red: 0.22, green: 0.45, blue: 0.98, alpha: 1),
                  CGColor(red: 0.12, green: 0.30, blue: 0.86, alpha: 1)] as CFArray
    let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // white cube glyph, scaled from a 24pt viewbox, centered, occupying ~54%
    let scale = size * 0.54 / 24
    let tx = size / 2 - 12 * scale
    let ty = size / 2 - 12 * scale
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tx + x * scale, y: size - (ty + y * scale)) }

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(size * 0.028)
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)

    // outer hexagon
    let hex = [p(12, 2.5), p(21, 7), p(21, 17), p(12, 21.5), p(3, 17), p(3, 7)]
    ctx.beginPath()
    ctx.move(to: hex[0])
    for pt in hex.dropFirst() { ctx.addLine(to: pt) }
    ctx.closePath()
    ctx.strokePath()

    // inner edges: 3,7 -> 12,11.5 -> 21,7 and vertical 12,11.5 -> 12,21.5
    ctx.beginPath()
    ctx.move(to: p(3, 7)); ctx.addLine(to: p(12, 11.5)); ctx.addLine(to: p(21, 7))
    ctx.move(to: p(12, 11.5)); ctx.addLine(to: p(12, 21.5))
    ctx.strokePath()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: gen_icon.swift <dir> <size...>"); exit(1) }
let dir = URL(fileURLWithPath: args[1])
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for s in args.dropFirst(2) {
    guard let size = Double(s) else { continue }
    let img = makeIcon(CGFloat(size))
    let out = dir.appendingPathComponent("icon-\(Int(size)).png")
    writePNG(img, to: out)
    print("wrote \(out.lastPathComponent)")
}
