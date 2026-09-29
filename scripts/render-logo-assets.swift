import AppKit
import Foundation

// Run from the project root after updating docs/roadreel-logo-source.png.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let sourceURL = root.appendingPathComponent("docs/roadreel-logo-source.png")
guard let source = NSImage(contentsOf: sourceURL),
      let sourceImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read \(sourceURL.path)")
}

func render(to relativePath: String, size: Int) throws {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Cannot create \(size) px graphics context")
    }

    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    context.clear(bounds)
    context.interpolationQuality = .high

    // Match the existing macOS app-icon silhouette; keep the corners transparent.
    let tile = bounds.insetBy(dx: CGFloat(size) * 0.016, dy: CGFloat(size) * 0.016)
    context.addPath(CGPath(
        roundedRect: tile,
        cornerWidth: CGFloat(size) * 0.215,
        cornerHeight: CGFloat(size) * 0.215,
        transform: nil
    ))
    context.clip()
    context.draw(sourceImage, in: bounds)

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Cannot encode \(relativePath)")
    }
    try png.write(to: root.appendingPathComponent(relativePath), options: .atomic)
}

let appIcons: [(String, Int)] = [
    ("appicon-16.png", 16),
    ("appicon-16@2x.png", 32),
    ("appicon-32.png", 32),
    ("appicon-32@2x.png", 64),
    ("appicon-128.png", 128),
    ("appicon-128@2x.png", 256),
    ("appicon-256.png", 256),
    ("appicon-256@2x.png", 512),
    ("appicon-512.png", 512),
    ("appicon-512@2x.png", 1024),
]

for (filename, size) in appIcons {
    try render(to: "RoadReel/Assets.xcassets/AppIcon.appiconset/\(filename)", size: size)
}

for (filename, size) in [
    ("brand-logo.png", 128),
    ("brand-logo@2x.png", 256),
    ("brand-logo@3x.png", 384),
] {
    try render(to: "RoadReel/Assets.xcassets/BrandLogo.imageset/\(filename)", size: size)
}

try render(to: "docs/roadreel-logo.png", size: 1024)
