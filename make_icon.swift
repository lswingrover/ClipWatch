#!/usr/bin/env swift
/// Generates ClipWatch.icns using AppKit — no dependencies.
/// Usage: swift make_icon.swift <output_dir>
///
/// Design: deep navy gradient (same family as MacWatch/NetWatch),
/// white clipboard silhouette with a small magnifying glass accent.
/// Consistent with the *Watch suite visual language.

import AppKit
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/clipwatch_icon"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let rect = CGRect(origin: .zero, size: CGSize(width: size, height: size))

    // ── Background: deep navy gradient (same as MacWatch/NetWatch) ────────────
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.055, green: 0.165, blue: 0.392, alpha: 1),  // top navy
            CGColor(red: 0.024, green: 0.078, blue: 0.235, alpha: 1),  // bottom deep navy
        ] as CFArray,
        locations: [0, 1]
    )!
    let radius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient,
        start: CGPoint(x: size * 0.5, y: size),
        end:   CGPoint(x: size * 0.5, y: 0),
        options: [])

    // ── Clipboard body ────────────────────────────────────────────────────────
    // Board: rounded rect, centre-left, slightly below centre
    let boardW  = size * 0.44
    let boardH  = size * 0.52
    let boardX  = (size - boardW) / 2
    let boardY  = size * 0.17
    let boardR  = size * 0.06
    let boardPath = NSBezierPath(
        roundedRect: CGRect(x: boardX, y: boardY, width: boardW, height: boardH),
        xRadius: boardR, yRadius: boardR
    )
    NSColor(white: 1.0, alpha: 0.90).setFill()
    boardPath.fill()

    // ── Clipboard clip (top centre) ───────────────────────────────────────────
    let clipW  = size * 0.18
    let clipH  = size * 0.08
    let clipX  = (size - clipW) / 2
    let clipY  = boardY + boardH - clipH * 0.5
    let clipR  = size * 0.03
    let clipPath = NSBezierPath(
        roundedRect: CGRect(x: clipX, y: clipY, width: clipW, height: clipH),
        xRadius: clipR, yRadius: clipR
    )
    // Navy fill so clip sits on the board visually
    NSColor(red: 0.055, green: 0.165, blue: 0.392, alpha: 1.0).setFill()
    clipPath.fill()
    NSColor(white: 1.0, alpha: 0.85).setFill()
    // Inner clip hole
    let holeW = clipW * 0.55
    let holeH = clipH * 0.55
    let holePath = NSBezierPath(
        roundedRect: CGRect(
            x: clipX + (clipW - holeW) / 2,
            y: clipY + (clipH - holeH) / 2,
            width: holeW, height: holeH),
        xRadius: clipR * 0.5, yRadius: clipR * 0.5
    )
    holePath.fill()

    // ── Lines on the clipboard (text suggestion) ──────────────────────────────
    let lineColor = NSColor(red: 0.055, green: 0.165, blue: 0.392, alpha: 0.25)
    let lineX     = boardX + boardW * 0.14
    let lineW     = boardW * 0.72
    let lineH     = max(1.5, size / 80)
    let lineGap   = boardH * 0.13
    let lineStart = boardY + boardH * 0.20

    lineColor.setFill()
    for i in 0..<3 {
        let ly = lineStart + CGFloat(i) * lineGap
        // Third line shorter (paragraph end)
        let lw = i == 2 ? lineW * 0.55 : lineW
        NSBezierPath(
            roundedRect: CGRect(x: lineX, y: ly, width: lw, height: lineH),
            xRadius: lineH / 2, yRadius: lineH / 2
        ).fill()
    }

    // ── Magnifying glass (bottom-right corner accent) ─────────────────────────
    // Only drawn at sizes ≥ 32 where it's legible
    if size >= 32 {
        let mgCX   = boardX + boardW * 0.80
        let mgCY   = boardY + boardH * 0.22
        let mgR    = size * 0.10
        let mgLW   = max(1.5, size / 42)
        let handleL = mgR * 0.75
        let handleA = CGFloat.pi * 0.75  // 135° — goes toward bottom-right

        // Circle
        let circlePath = NSBezierPath()
        circlePath.appendArc(
            withCenter: NSPoint(x: mgCX, y: mgCY),
            radius: mgR,
            startAngle: 0, endAngle: 360, clockwise: false
        )
        circlePath.lineWidth = mgLW
        NSColor(red: 0.39, green: 0.71, blue: 1.00, alpha: 1.0).setStroke()
        circlePath.stroke()

        // Handle
        let hx = mgCX + (mgR + mgLW * 0.5) * cos(handleA)
        let hy = mgCY + (mgR + mgLW * 0.5) * sin(handleA)
        let hxEnd = hx + handleL * cos(handleA)
        let hyEnd = hy + handleL * sin(handleA)
        let handlePath = NSBezierPath()
        handlePath.move(to: NSPoint(x: hx, y: hy))
        handlePath.line(to: NSPoint(x: hxEnd, y: hyEnd))
        handlePath.lineWidth    = mgLW * 1.1
        handlePath.lineCapStyle = .round
        NSColor(red: 0.39, green: 0.71, blue: 1.00, alpha: 1.0).setStroke()
        handlePath.stroke()
    }

    img.unlockFocus()
    return img
}

// ── Write PNGs ───────────────────────────────────────────────────────────────
var pngPaths: [Int: String] = [:]
for size in sizes {
    let img = drawIcon(size: CGFloat(size))
    guard let tiff = img.tiffRepresentation,
          let bmp  = NSBitmapImageRep(data: tiff),
          let png  = bmp.representation(using: .png, properties: [:])
    else { continue }
    let path = "\(outDir)/icon_\(size)x\(size).png"
    try? png.write(to: URL(fileURLWithPath: path))
    pngPaths[size] = path
}

// ── Build .iconset ────────────────────────────────────────────────────────────
let iconsetDir = "\(outDir)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconsetDir)
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let iconsetMap: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]
for (filename, sz) in iconsetMap {
    guard let src = pngPaths[sz] else { continue }
    try? FileManager.default.copyItem(atPath: src, toPath: "\(iconsetDir)/\(filename)")
}

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir, "-o", "\(outDir)/AppIcon.icns"]
try? proc.run()
proc.waitUntilExit()

if proc.terminationStatus == 0 {
    print("✅  Icon written to \(outDir)/AppIcon.icns")
} else {
    print("⚠️   iconutil failed — app will use generic icon")
}
