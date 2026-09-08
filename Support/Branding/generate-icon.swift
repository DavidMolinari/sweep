import AppKit
import CoreGraphics
import Foundation
import ImageIO

enum IconGenerator {
    static let canvas: CGFloat = 1024
    static let margin: CGFloat = 100
    static let body: CGFloat = canvas - margin * 2
    static let center = CGPoint(x: canvas / 2, y: canvas / 2)

    static let squircleExponent: Double = 5.0
    static let squircleSamples = 192

    static let ringOuter: CGFloat = 308
    static let ringThickness: CGFloat = 132
    static var ringInner: CGFloat { ringOuter - ringThickness }
    static let gapCenter = 45.0 * Double.pi / 180
    static let gapHalf = 51.0 * Double.pi / 180
    static let sparkleRadius: CGFloat = 108
    static let sparkleDistance: CGFloat = 254

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    static let brandMidnight: UInt32 = 0x0A0E2E
    static let brandViolet: UInt32 = 0x7B4DFF
    static let motifIce: UInt32 = 0xDFE8FF

    struct Stop {
        let hex: UInt32
        let alpha: CGFloat
        let location: CGFloat

        init(_ hex: UInt32, _ alpha: CGFloat = 1, at location: CGFloat) {
            self.hex = hex
            self.alpha = alpha
            self.location = location
        }
    }

    struct Output {
        let name: String
        let pixels: Int
        let iconsetName: String?
    }

    static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static func gradient(_ stops: [Stop]) -> CGGradient {
        CGGradient(
            colorsSpace: colorSpace,
            colors: stops.map { color($0.hex, $0.alpha) } as CFArray,
            locations: stops.map(\.location)
        )!
    }

    static func smoothClosedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let count = points.count
        guard count > 2 else { return path }
        path.move(to: points[0])
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]
            let afterNext = points[(index + 2) % count]
            let control1 = CGPoint(
                x: current.x + (next.x - previous.x) / 6,
                y: current.y + (next.y - previous.y) / 6
            )
            let control2 = CGPoint(
                x: next.x - (afterNext.x - current.x) / 6,
                y: next.y - (afterNext.y - current.y) / 6
            )
            path.addCurve(to: next, control1: control1, control2: control2)
        }
        path.closeSubpath()
        return path
    }

    static func superellipsePath(in rect: CGRect, exponent: Double, samples: Int) -> CGPath {
        let a = rect.width / 2
        let b = rect.height / 2
        var points: [CGPoint] = []
        points.reserveCapacity(samples)
        for index in 0..<samples {
            let t = Double(index) / Double(samples) * 2 * .pi
            let cosine = cos(t)
            let sine = sin(t)
            let x = rect.midX + a * copysign(pow(abs(cosine), 2 / exponent), cosine)
            let y = rect.midY + b * copysign(pow(abs(sine), 2 / exponent), sine)
            points.append(CGPoint(x: x, y: y))
        }
        return smoothClosedPath(points)
    }

    static func sweptRingPath(
        center: CGPoint,
        centerline: CGFloat,
        thickness: CGFloat,
        start: Double,
        end: Double,
        samples: Int = 240,
        taperFraction: Double = 0.28,
        startThicknessScale: CGFloat = 1.0,
        endThicknessScale: CGFloat = 0.18
    ) -> CGPath {
        let path = CGMutablePath()

        func smoothstep(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped * clamped * (3 - 2 * clamped)
        }

        func thicknessAt(_ s: Double) -> CGFloat {
            if s < taperFraction {
                let factor = smoothstep(s / taperFraction)
                let scale = Double(startThicknessScale)
                return thickness * CGFloat(scale + (1 - scale) * factor)
            }
            if s > 1 - taperFraction {
                let factor = smoothstep((1 - s) / taperFraction)
                let scale = Double(endThicknessScale)
                return thickness * CGFloat(scale + (1 - scale) * factor)
            }
            return thickness
        }

        func point(angle: Double, radius: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + radius * CGFloat(cos(angle)),
                y: center.y + radius * CGFloat(sin(angle))
            )
        }

        var outerPoints: [CGPoint] = []
        var innerPoints: [CGPoint] = []
        outerPoints.reserveCapacity(samples + 1)
        innerPoints.reserveCapacity(samples + 1)
        for index in 0...samples {
            let s = Double(index) / Double(samples)
            let angle = start + (end - start) * s
            let radius = CGFloat(thicknessAt(s) / 2)
            outerPoints.append(point(angle: angle, radius: centerline + radius))
            innerPoints.append(point(angle: angle, radius: centerline - radius))
        }

        let startRadius = CGFloat(thicknessAt(0) / 2)
        let endRadius = CGFloat(thicknessAt(1) / 2)
        let startCenter = point(angle: start, radius: centerline)
        let endCenter = point(angle: end, radius: centerline)

        path.move(to: outerPoints[0])
        for point in outerPoints.dropFirst() {
            path.addLine(to: point)
        }
        path.addArc(center: endCenter, radius: endRadius, startAngle: end, endAngle: end + .pi, clockwise: false)
        for point in innerPoints.reversed().dropFirst() {
            path.addLine(to: point)
        }
        path.addArc(center: startCenter, radius: startRadius, startAngle: start + .pi, endAngle: start + 2 * .pi, clockwise: false)
        path.closeSubpath()
        return path
    }

    static func sparklePath(center: CGPoint, radius: CGFloat, waist: CGFloat = 0.21) -> CGPath {
        let path = CGMutablePath()
        let w = radius * waist
        let top = CGPoint(x: center.x, y: center.y + radius)
        let right = CGPoint(x: center.x + radius, y: center.y)
        let bottom = CGPoint(x: center.x, y: center.y - radius)
        let left = CGPoint(x: center.x - radius, y: center.y)
        let upperRight = CGPoint(x: center.x + w, y: center.y + w)
        let lowerRight = CGPoint(x: center.x + w, y: center.y - w)
        let lowerLeft = CGPoint(x: center.x - w, y: center.y - w)
        let upperLeft = CGPoint(x: center.x - w, y: center.y + w)

        path.move(to: top)
        path.addCurve(to: right, control1: upperRight, control2: upperRight)
        path.addCurve(to: bottom, control1: lowerRight, control2: lowerRight)
        path.addCurve(to: left, control1: lowerLeft, control2: lowerLeft)
        path.addCurve(to: top, control1: upperLeft, control2: upperLeft)
        path.closeSubpath()
        return path
    }

    static func drawBase(_ context: CGContext, squircle: CGPath) {
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 38,
            color: color(0x04061A, 0.46)
        )
        context.addPath(squircle)
        context.setFillColor(color(brandMidnight))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(squircle)
        context.clip()

        let base = gradient([
            Stop(0x0C1134, at: 0.00),
            Stop(0x1E2280, at: 0.38),
            Stop(0x4634CE, at: 0.74),
            Stop(0x7F52FF, at: 1.00)
        ])
        context.drawLinearGradient(
            base,
            start: CGPoint(x: 168, y: 896),
            end: CGPoint(x: 880, y: 148),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        let halo = gradient([
            Stop(0xA9C4FF, 0.13, at: 0.00),
            Stop(0xA9C4FF, 0.04, at: 0.55),
            Stop(0xA9C4FF, 0.00, at: 1.00)
        ])
        context.drawRadialGradient(
            halo,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: 520,
            options: []
        )

        context.restoreGState()
    }

    static func drawMotif(_ context: CGContext) {
        let ring = sweptRingPath(
            center: center,
            centerline: ringOuter - ringThickness / 2,
            thickness: ringThickness,
            start: gapCenter + gapHalf,
            end: gapCenter - gapHalf + 2 * .pi
        )
        let sparkleCenter = CGPoint(
            x: center.x + sparkleDistance * cos(gapCenter),
            y: center.y + sparkleDistance * sin(gapCenter)
        )
        let sparkle = sparklePath(center: sparkleCenter, radius: sparkleRadius)

        context.saveGState()
        context.addPath(ring)
        context.addPath(sparkle)
        context.clip()
        context.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 36,
            color: color(0x05071C, 0.30)
        )
        context.setFillColor(color(0xFFFFFF))
        context.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: CGRect(
            x: center.x - ringInner * 0.98,
            y: center.y - ringInner * 0.98,
            width: ringInner * 1.96,
            height: ringInner * 1.96
        ))
        context.clip()
        let holeLight = gradient([
            Stop(0xFFFFFF, 0.08, at: 0.00),
            Stop(0xFFFFFF, 0.00, at: 1.00)
        ])
        context.drawRadialGradient(
            holeLight,
            startCenter: center,
            startRadius: 0,
            endCenter: center,
            endRadius: ringInner * 0.98,
            options: []
        )
        context.restoreGState()

        let sparkleGlow = gradient([
            Stop(0xFFFFFF, 0.24, at: 0.00),
            Stop(0xFFFFFF, 0.00, at: 1.00)
        ])
        context.drawRadialGradient(
            sparkleGlow,
            startCenter: sparkleCenter,
            startRadius: 0,
            endCenter: sparkleCenter,
            endRadius: sparkleRadius * 2.0,
            options: []
        )

        context.saveGState()
        context.addPath(ring)
        context.addPath(sparkle)
        context.clip()
        let motif = gradient([
            Stop(0xFFFFFF, at: 0.00),
            Stop(motifIce, at: 1.00)
        ])
        context.drawLinearGradient(
            motif,
            start: CGPoint(x: 800, y: 820),
            end: CGPoint(x: 260, y: 240),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    static func drawRim(_ context: CGContext, squircle: CGPath) {
        let stroked = squircle.copy(strokingWithWidth: 3, lineCap: .round, lineJoin: .round, miterLimit: 10)
        context.saveGState()
        context.addPath(squircle)
        context.clip()

        context.saveGState()
        context.addPath(stroked)
        context.clip()
        let topLight = gradient([
            Stop(0xFFFFFF, 0.34, at: 0.00),
            Stop(0xFFFFFF, 0.00, at: 1.00)
        ])
        context.drawLinearGradient(
            topLight,
            start: CGPoint(x: 512, y: 924),
            end: CGPoint(x: 512, y: 600),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        context.saveGState()
        context.addPath(stroked)
        context.clip()
        let bottomShade = gradient([
            Stop(0x03040F, 0.00, at: 0.00),
            Stop(0x03040F, 0.30, at: 1.00)
        ])
        context.drawLinearGradient(
            bottomShade,
            start: CGPoint(x: 512, y: 340),
            end: CGPoint(x: 512, y: 100),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()

        context.restoreGState()
    }

    static func drawIcon(_ context: CGContext) {
        let bodyRect = CGRect(x: margin, y: margin, width: body, height: body)
        let squircle = superellipsePath(in: bodyRect, exponent: squircleExponent, samples: squircleSamples)
        drawBase(context, squircle: squircle)
        drawMotif(context)
        drawRim(context, squircle: squircle)
    }

    static func render(pixels: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
        drawIcon(context)
        return context.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw NSError(domain: "SweepIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot create PNG destination at \(url.path)"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "SweepIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize PNG at \(url.path)"])
        }
    }

    static func runIconutil(iconset: URL, output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "SweepIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(process.terminationStatus)"])
        }
    }

    static let outputs: [Output] = [
        Output(name: "icon-16.png", pixels: 16, iconsetName: "icon_16x16.png"),
        Output(name: "icon-16@2x.png", pixels: 32, iconsetName: "icon_16x16@2x.png"),
        Output(name: "icon-32.png", pixels: 32, iconsetName: "icon_32x32.png"),
        Output(name: "icon-32@2x.png", pixels: 64, iconsetName: "icon_32x32@2x.png"),
        Output(name: "icon-64.png", pixels: 64, iconsetName: nil),
        Output(name: "icon-128.png", pixels: 128, iconsetName: "icon_128x128.png"),
        Output(name: "icon-128@2x.png", pixels: 256, iconsetName: "icon_128x128@2x.png"),
        Output(name: "icon-256.png", pixels: 256, iconsetName: "icon_256x256.png"),
        Output(name: "icon-256@2x.png", pixels: 512, iconsetName: "icon_256x256@2x.png"),
        Output(name: "icon-512.png", pixels: 512, iconsetName: "icon_512x512.png"),
        Output(name: "icon-512@2x.png", pixels: 1024, iconsetName: "icon_512x512@2x.png"),
        Output(name: "icon-1024.png", pixels: 1024, iconsetName: nil)
    ]

    static func run() {
        let outputDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

            let iconsetDirectory = fileManager.temporaryDirectory
                .appendingPathComponent("SweepAppIcon-\(UUID().uuidString).iconset", isDirectory: true)
            try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: iconsetDirectory) }

            var cache: [Int: CGImage] = [:]
            for output in outputs {
                let image: CGImage
                if let cached = cache[output.pixels] {
                    image = cached
                } else {
                    image = render(pixels: output.pixels)
                    cache[output.pixels] = image
                }
                let fileURL = outputDirectory.appendingPathComponent(output.name)
                try writePNG(image, to: fileURL)
                print("wrote \(output.name) (\(output.pixels)px)")
                if let iconsetName = output.iconsetName {
                    try writePNG(image, to: iconsetDirectory.appendingPathComponent(iconsetName))
                }
            }

            let icnsURL = outputDirectory.appendingPathComponent("AppIcon.icns")
            try runIconutil(iconset: iconsetDirectory, output: icnsURL)
            print("wrote \(icnsURL.lastPathComponent)")
        } catch {
            FileHandle.standardError.write(Data("icon generation failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

IconGenerator.run()
