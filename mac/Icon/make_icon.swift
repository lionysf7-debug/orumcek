// Örümcek uygulama simgesini (1024×1024 PNG) kodla çizer. make-icon.sh bunu .icns'e çevirir.
// Koordinatlar CoreGraphics'in y yukarı düzenindedir.
import AppKit

let canvas: CGFloat = 1024
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)   // Apple simge şablonundaki kare
let radius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

let cyan = color(0x38d6ff), pink = color(0xff3fb4), purple = color(0x7a5cff)
let green = color(0x7ee08a), orange = color(0xff8a5c), ink = color(0x0a0a12)
let legColor = CGColor(srgbRed: 0.70, green: 0.80, blue: 1.0, alpha: 1)
let jointPink = color(0xff4f9a), jointBlue = color(0x6f9bff)

guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas), bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("bağlam yok") }
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

let tilePath = CGPath(roundedRect: tile, cornerWidth: radius, cornerHeight: radius, transform: nil)

// MARK: Zemin ve gölge

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: color(0x000000, 0.35))
ctx.addPath(tilePath)
ctx.setFillColor(color(0x0d1222))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let bg = CGGradient(colorsSpace: space, colors: [color(0x1b2346), color(0x0a0d1a)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.minY), options: [])

let center = CGPoint(x: 512, y: 520)
let glow = CGGradient(colorsSpace: space, colors: [color(0x5b6cff, 0.32), color(0x38d6ff, 0.10), color(0x38d6ff, 0)] as CFArray,
                      locations: [0, 0.45, 1])!
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 380, options: [])

// MARK: Arka plandaki ağ

ctx.setStrokeColor(color(0xffffff, 0.07))
ctx.setLineWidth(3)
let spokes = 12
let spokeAngles = (0..<spokes).map { CGFloat($0) / CGFloat(spokes) * .pi * 2 + 0.13 }
for a in spokeAngles {
    ctx.move(to: center)
    ctx.addLine(to: CGPoint(x: center.x + cos(a) * 800, y: center.y + sin(a) * 800))
}
ctx.strokePath()
for r in [110, 190, 280, 380, 490] as [CGFloat] {
    // Halkalar ışınlar arasında hafifçe içe sarkar
    for i in 0..<spokes {
        let a1 = spokeAngles[i], a2 = spokeAngles[(i + 1) % spokes] + (i == spokes - 1 ? .pi * 2 : 0)
        let p1 = CGPoint(x: center.x + cos(a1) * r, y: center.y + sin(a1) * r)
        let p2 = CGPoint(x: center.x + cos(a2) * r, y: center.y + sin(a2) * r)
        let mid = (a1 + a2) / 2
        let c = CGPoint(x: center.x + cos(mid) * r * 0.86, y: center.y + sin(mid) * r * 0.86)
        if i == 0 { ctx.move(to: p1) }
        ctx.addQuadCurve(to: p2, control: c)
    }
}
ctx.strokePath()

// MARK: Örümcek geometrisi

let heading: CGFloat = .pi / 2 + 0.16          // yukarı, hafif sola dönük
let body = CGPoint(x: 512, y: 500)
let baseReach: CGFloat = 290

struct LegShape { let hip: CGPoint; let knee: CGPoint; let foot: CGPoint }

// Simge için elle tasarlanmış poz (derece, başa göre): dizler yana açılır, ayaklar öne/arkaya uzanır.
// Diz ve ayak açıları sıralı olduğundan hiçbir bacak diğerini kesmez.
struct Pose { let knee: CGFloat; let kneeR: CGFloat; let foot: CGFloat; let footR: CGFloat }
let poses = [
    Pose(knee: 54, kneeR: 0.50, foot: 32, footR: 1.06),
    Pose(knee: 84, kneeR: 0.52, foot: 70, footR: 0.94),
    Pose(knee: 100, kneeR: 0.52, foot: 112, footR: 0.92),
    Pose(knee: 126, kneeR: 0.50, foot: 150, footR: 1.02),
]

var legs: [LegShape] = []
for side in [1.0, -1.0] as [CGFloat] {          // y yukarı düzende +açı sol taraf
    for pose in poses {
        func at(_ deg: CGFloat, _ r: CGFloat) -> CGPoint {
            let a = heading + side * deg * .pi / 180
            return CGPoint(x: body.x + cos(a) * r, y: body.y + sin(a) * r)
        }
        legs.append(LegShape(hip: at(pose.knee, 18), knee: at(pose.knee, baseReach * pose.kneeR),
                             foot: at(pose.foot, baseReach * pose.footR)))
    }
}

// MARK: Bağlantı kutuları

enum BoxStyle { case fill, outline }

func textBars(in r: CGRect, color c: CGColor, widths: [CGFloat]) {
    ctx.setFillColor(c)
    var x = r.minX + 16
    for w in widths {
        let bw = min(w, r.maxX - 16 - x)
        guard bw > 8 else { break }
        let bar = CGRect(x: x, y: r.midY - 7, width: bw, height: 14)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
        x += bw + 12
    }
}

func box(_ r: CGRect, _ c: CGColor, _ style: BoxStyle, bars: [CGFloat]) {
    let path = CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)
    switch style {
    case .fill:
        ctx.addPath(path)
        ctx.setFillColor(c)
        ctx.fillPath()
        textBars(in: r, color: color(0x0a0a12, 0.72), widths: bars)
    case .outline:
        ctx.addPath(path)
        ctx.setFillColor(color(0x0b0e1a, 0.85))
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(c)
        ctx.setLineWidth(6)
        ctx.strokePath()
        textBars(in: r, color: c.copy(alpha: 0.9)!, widths: bars)
    }
}

/// Ayağın tam üstüne denk gelen kutu: u, ayağın kutu genişliği boyunca nerede durduğu.
func boxUnder(_ leg: Int, width: CGFloat, u: CGFloat, _ c: CGColor, _ style: BoxStyle, bars: [CGFloat]) {
    let f = legs[leg].foot
    box(CGRect(x: f.x - width * u, y: f.y - 30, width: width, height: 60), c, style, bars: bars)
}

boxUnder(0, width: 230, u: 0.62, cyan, .fill, bars: [90, 70])
boxUnder(4, width: 210, u: 0.30, pink, .outline, bars: [60, 80])
boxUnder(6, width: 200, u: 0.35, purple, .fill, bars: [110, 40])
boxUnder(3, width: 190, u: 0.55, green, .outline, bars: [70, 60])

// Bir sonraki hedef: iplik oraya uzanıyor, temas halkası çiziliyor
let next = CGRect(x: 405, y: 832, width: 170, height: 52)
box(next, orange, .outline, bars: [55, 50])
let nextPoint = CGPoint(x: next.minX + 38, y: next.midY)

// Koparılıp sürüklenen etiket (gövdenin arkasında, ipe bağlı)
let carriedCenter = CGPoint(x: 640, y: 215)

// MARK: İplikler

ctx.setLineWidth(5)
ctx.setStrokeColor(color(0xff4f9a, 0.9))
ctx.move(to: body)
ctx.addLine(to: nextPoint)
ctx.strokePath()
ctx.setStrokeColor(legColor.copy(alpha: 0.55)!)
ctx.setLineWidth(4)
ctx.move(to: body)
ctx.addLine(to: carriedCenter)
ctx.strokePath()
for (r, alpha) in [(26, 0.95), (44, 0.45)] as [(CGFloat, CGFloat)] {
    ctx.setStrokeColor(color(0xff8a5c, alpha))
    ctx.setLineWidth(5)
    ctx.strokeEllipse(in: CGRect(x: nextPoint.x - r, y: nextPoint.y - r, width: r * 2, height: r * 2))
}

ctx.saveGState()
ctx.translateBy(x: carriedCenter.x, y: carriedCenter.y)
ctx.rotate(by: -0.42)
box(CGRect(x: -85, y: -26, width: 170, height: 52), pink, .fill, bars: [60, 50])
ctx.restoreGState()

// MARK: Bacaklar

let limbs = CGMutablePath()
for leg in legs {
    limbs.move(to: leg.hip)
    limbs.addLine(to: leg.knee)
    limbs.addLine(to: leg.foot)
}
ctx.addPath(limbs)
ctx.setStrokeColor(color(0x000000, 0.45))
ctx.setLineWidth(30)
ctx.strokePath()
ctx.addPath(limbs)
ctx.setStrokeColor(legColor)
ctx.setLineWidth(13)
ctx.strokePath()

func dot(_ p: CGPoint, _ r: CGFloat, _ c: CGColor) {
    ctx.setFillColor(c)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}
let gripping: Set<Int> = [0, 4, 6, 3]
for (i, leg) in legs.enumerated() {
    dot(leg.knee, 14, jointPink)
    dot(leg.foot, gripping.contains(i) ? 19 : 12, gripping.contains(i) ? jointPink : jointBlue)
}

// MARK: Gövde

ctx.saveGState()
ctx.translateBy(x: body.x, y: body.y)
ctx.rotate(by: heading)                           // yerel +x = baş yönü
let abdomen = CGRect(x: -150, y: -52, width: 136, height: 104)
let thorax = CGRect(x: -40, y: -36, width: 82, height: 72)
ctx.setShadow(offset: .zero, blur: 24, color: color(0x000000, 0.6))
for oval in [abdomen, thorax] {
    ctx.setFillColor(color(0x0a0c14))
    ctx.fillEllipse(in: oval)
}
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(legColor)
ctx.setLineWidth(9)
for oval in [abdomen, thorax] { ctx.strokeEllipse(in: oval) }
ctx.setLineWidth(7)
ctx.move(to: CGPoint(x: -30, y: 0))
ctx.addLine(to: CGPoint(x: -138, y: 0))
ctx.move(to: CGPoint(x: -82, y: -38))
ctx.addLine(to: CGPoint(x: -82, y: 38))
ctx.strokePath()
dot(CGPoint(x: 24, y: -13), 8, jointPink)
dot(CGPoint(x: 24, y: 13), 8, jointPink)
dot(.zero, 9, jointBlue)
ctx.restoreGState()

// MARK: İnce iç kenar ve parlama

ctx.restoreGState()   // kırpmayı kaldır
let gloss = CGGradient(colorsSpace: space, colors: [color(0xffffff, 0.10), color(0xffffff, 0)] as CFArray, locations: [0, 1])!
ctx.saveGState()
ctx.addPath(tilePath)
ctx.clip()
ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: tile.maxY), end: CGPoint(x: 512, y: tile.midY + 120), options: [])
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius - 1.5, cornerHeight: radius - 1.5, transform: nil))
ctx.setStrokeColor(color(0xffffff, 0.12))
ctx.setLineWidth(3)
ctx.strokePath()

// MARK: Kaydet

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png")
guard let image = ctx.makeImage(),
      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { fatalError("PNG yok") }
try data.write(to: out)
print("✓ \(out.path)")
