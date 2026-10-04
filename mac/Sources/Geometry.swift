// Ortak yardımcılar: sayı işlemleri, renkler, yazı tipleri ve koordinat dönüşümleri.
import AppKit

@inline(__always) func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { v < lo ? lo : (v > hi ? hi : v) }
@inline(__always) func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
@inline(__always) func angleDiff(_ to: CGFloat, _ from: CGFloat) -> CGFloat { atan2(sin(to - from), cos(to - from)) }
@inline(__always) func smoothstep(_ t: CGFloat) -> CGFloat { t * t * (3 - 2 * t) }
@inline(__always) func rand(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + CGFloat.random(in: 0..<1) * (b - a) }
@inline(__always) func chance(_ p: Double) -> Bool { Double.random(in: 0..<1) < p }

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                  blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

enum Palette {
    static let colors: [NSColor] = [0x38d6ff, 0xff3fb4, 0x7a5cff, 0x7ee08a, 0xff8a5c, 0x4f7dff, 0xf2e35b].map { NSColor(hex: $0) }
    static let threads: [NSColor] = [0xff4f9a, 0x9fb8ff, 0xffffff, 0x38d6ff].map { NSColor(hex: $0) }
    static let ink = NSColor(hex: 0x0a0a12)
    static let leg = NSColor(srgbRed: 0.70, green: 0.80, blue: 1.0, alpha: 0.95)
    // Bacakların altındaki koyu hale: örümcek açık ve koyu arka planda aynı netlikte görünür.
    static let halo = NSColor(white: 0, alpha: 0.35)
    static let jointA = NSColor(hex: 0xff4f9a)
    static let jointB = NSColor(hex: 0x6f9bff)
    static let bodyFill = NSColor(srgbRed: 0.04, green: 0.05, blue: 0.08, alpha: 0.88)
    static let backing = NSColor(srgbRed: 0.05, green: 0.06, blue: 0.09, alpha: 0.9)
    static let hudText = NSColor(hex: 0xcfe0ff)

    static func random() -> NSColor { colors.randomElement()! }
}

@MainActor
enum Fonts {
    static let names = ["Courier New", "Georgia", "Helvetica Neue", "Menlo", "Times New Roman"]

    static func named(_ name: String, _ size: CGFloat, italic: Bool = false) -> NSFont {
        let font = NSFont(name: name, size: size) ?? .systemFont(ofSize: size)
        return italic ? NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) : font
    }

    static func random(_ size: CGFloat) -> NSFont { named(names.randomElement()!, size, italic: chance(0.3)) }
    static func mono(_ size: CGFloat) -> NSFont { named(chance(0.5) ? "Courier New" : "Menlo", size) }
    static func serifItalic(_ size: CGFloat) -> NSFont { named("Georgia", size, italic: true) }
}

// Simülasyon, Erişilebilirlik API'siyle aynı koordinatları kullanır: ana ekranın sol üst köşesi
// başlangıç, y aşağı doğru artar. AppKit'in sol alt başlangıçlı ekran çerçeveleri buna çevrilir.
@MainActor
enum Coordinates {
    static func topLeft(_ rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.height
        return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
