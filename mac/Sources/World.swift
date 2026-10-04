// Sahnenin durumu: taranan hedefler, işaretler, koparılan etiketler, halkalar, günlük ve örümcekler.
// Her nesne kendi küçük katmanıdır; kare başına yalnızca yollar, konumlar ve saydamlıklar güncellenir.
import AppKit
import QuartzCore

/// Her ekranın katmanına aynı nesnenin bir kopyasını ekler (çoğu Mac'te tek ekran, tek kopya).
@MainActor
final class Scene {
    struct Root {
        let layer: CALayer
        let scale: CGFloat
    }

    // Katman özellikleri değişince Core Animation'ın kendiliğinden yaptığı canlandırmaları kapatır;
    // her kare zaten yeni değeri veriyor.
    static let noActions: [String: CAAction] = Dictionary(uniqueKeysWithValues: [
        "position", "bounds", "frame", "transform", "opacity", "path", "contents", "hidden",
        "sublayers", "onOrderIn", "onOrderOut", "borderColor", "zPosition",
    ].map { ($0, NSNull() as CAAction) })

    private(set) var roots: [Root] = []

    func attach(_ roots: [Root]) { self.roots = roots }

    func node<L: CALayer>(z: CGFloat, _ make: () -> L) -> Node<L> {
        Node(layers: roots.map { root in
            let layer = make()
            layer.contentsScale = root.scale
            layer.actions = Scene.noActions
            layer.zPosition = z
            root.layer.addSublayer(layer)
            return layer
        })
    }
}

@MainActor
final class Node<L: CALayer> {
    let layers: [L]

    init(layers: [L]) { self.layers = layers }

    func each(_ body: (L) -> Void) { layers.forEach(body) }
    func remove() { each { $0.removeFromSuperlayer() } }
}

/// Kutu + metin, bir kez bitmap'e çizilir ve katman içeriği olarak kullanılır.
@MainActor
struct Sprite {
    enum Box { case fill(NSColor), stroke(NSColor), backed(NSColor) }

    let image: CGImage?
    let size: CGSize

    init(text: NSAttributedString, box: Box, padding: CGSize, minSize: CGSize = .zero) {
        let textSize = text.size()
        size = CGSize(width: max(minSize.width, ceil(textSize.width) + padding.width * 2),
                      height: max(minSize.height, ceil(textSize.height) + padding.height * 2))
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            image = nil
            return
        }
        ctx.scaleBy(x: scale, y: scale)
        let rect = CGRect(origin: .zero, size: size)
        ctx.setLineWidth(1)
        switch box {
        case .fill(let c):
            ctx.setFillColor(c.cgColor)
            ctx.fill(rect)
        case .stroke(let c):
            ctx.setStrokeColor(c.cgColor)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        case .backed(let c):
            ctx.setFillColor(Palette.backing.cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(c.cgColor)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        text.draw(at: CGPoint(x: padding.width, y: (size.height - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        image = ctx.makeImage()
    }
}

/// Bir bağlantıdan koparılıp örümceğe iple bağlanan ya da sayfada bırakılan etiket.
@MainActor
final class Label {
    private let node: Node<CALayer>
    let width: CGFloat
    let height: CGFloat
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat = 0
    var vy: CGFloat = 0
    var angle: CGFloat = 0
    var tilt: CGFloat = 0
    var length: CGFloat = 60
    var born: Double = 0
    var life: Double = 6

    init(text: String, at p: CGPoint, scene: Scene) {
        let font = Fonts.random(CGFloat(Int.random(in: 11...22)))
        let color = Palette.random()
        let filled = chance(0.6)
        let attr = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: filled ? Palette.ink : color,
        ])
        let sprite = Sprite(text: attr, box: filled ? .fill(color) : .stroke(color), padding: CGSize(width: 4, height: 2))
        width = sprite.size.width
        height = sprite.size.height
        x = p.x
        y = p.y
        node = scene.node(z: 9) {
            let layer = CALayer()
            layer.contents = sprite.image
            layer.bounds = CGRect(origin: .zero, size: sprite.size)
            return layer
        }
        sync(alpha: 1)
    }

    func sync(alpha: CGFloat) {
        let p = CGPoint(x: x, y: y), t = CGAffineTransform(rotationAngle: angle), a = Float(alpha)
        node.each {
            $0.position = p
            $0.setAffineTransform(t)
            $0.opacity = a
        }
    }

    func lower() { node.each { $0.zPosition = 1 } }
    func remove() { node.remove() }
}

/// Örümceğin dokunduğu öğenin üstüne çizilen renkli kutu ya da yeniden yazılmış metin.
@MainActor
final class Mark {
    enum Style { case outline, fill, ink }

    private(set) var rect: CGRect
    let style: Style
    var born: Double
    let life: Double
    private let spriteSize: CGSize?
    private let node: Node<CALayer>
    private var shownAlpha: Float = -1

    init(rect: CGRect, color: NSColor, style: Style, attr: NSAttributedString?, born: Double, life: Double, scene: Scene) {
        self.rect = rect
        self.born = born
        self.life = life
        var sprite: Sprite?
        if let attr, style != .outline {
            sprite = Sprite(text: attr, box: style == .fill ? .fill(color) : .backed(color),
                            padding: CGSize(width: 3, height: 1),
                            minSize: CGSize(width: rect.width + 4, height: rect.height + 2))
        }
        self.style = sprite == nil ? .outline : style
        spriteSize = sprite?.size
        node = scene.node(z: 0) {
            let layer = CALayer()
            if let sprite {
                layer.contents = sprite.image
            } else {
                layer.borderWidth = 1
                layer.borderColor = color.cgColor
            }
            return layer
        }
        layout()
    }

    func move(to rect: CGRect) {
        self.rect = rect
        layout()
    }

    private func layout() {
        let box: CGRect
        if let s = spriteSize {
            box = CGRect(x: rect.minX - 2, y: rect.midY - s.height / 2, width: s.width, height: s.height)
        } else {
            box = rect.insetBy(dx: -1.5, dy: -1.5)
        }
        node.each { $0.frame = box }
    }

    /// Belirirken 0,15 sn, kaybolurken 1,5 sn solar; arada saydamlık değişmez.
    func sync(at t: Double) {
        let a = Float(clamp(CGFloat(min((t - born) / 0.15, (born + life - t) / 1.5)), 0, 1))
        guard a != shownAlpha else { return }
        shownAlpha = a
        node.each { $0.opacity = a }
    }

    func remove() { node.remove() }
}

/// Isırık ve adım halkası: büyüme ve solma tamamen Core Animation'da çalışır.
@MainActor
final class Ring {
    let born: Double
    private let node: Node<CAShapeLayer>

    init(center: CGPoint, radius: CGFloat, color: NSColor, born: Double, scene: Scene) {
        self.born = born
        node = scene.node(z: 5) {
            let shape = CAShapeLayer()
            shape.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            shape.fillColor = nil
            shape.strokeColor = color.cgColor
            shape.lineWidth = 1.2
            shape.position = center
            return shape
        }
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 0.1
        grow.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.45
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        node.each { $0.add(group, forKey: "ring") }
    }

    func remove() { node.remove() }
}

@MainActor
final class World {
    let scene = Scene()

    // Ayarlar (menüden değişir)
    var speed: CGFloat = 150
    var size: CGFloat = 0.85
    var effects = true { didSet { if !effects { clearEffects() } } }
    var showLog = false

    // Ekranlar ve ön plandaki uygulama
    private(set) var bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var screens: [CGRect] = []
    private var mainVisible = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private var activeWindow: CGRect?
    private var appName = ""
    private var trusted = true

    // Hedefler
    private(set) var targets: [CrawlTarget] = []
    private var index: [UInt: Int] = [:]
    private var visited: [UInt: Double] = [:]
    private var lastPrune: Double = 0
    private var visitedCount = 0

    // Sahne
    private(set) var clock: Double = 0
    private var spiders: [Spider] = []
    private var marks: [UInt: Mark] = [:]
    private var ghosts: [Label] = []
    private var rings: [Ring] = []
    private var log: [String] = []

    // Tarama günlüğü paneli
    private var hud: Node<CALayer>?
    private var hudText = ""
    private var hudAt: Double = -1

    // MARK: Ekranlar ve tarama sonuçları

    /// Ekranlar değişince tüm katmanlar yeni pencerelere taşınır (örümcek sayısı korunur).
    func configure(screens rects: [CGRect], mainVisible: CGRect, roots: [Scene.Root]) {
        let count = spiders.count
        spiders.forEach { $0.remove() }
        spiders.removeAll()
        marks.values.forEach { $0.remove() }
        marks.removeAll()
        ghosts.forEach { $0.remove() }
        ghosts.removeAll()
        rings.forEach { $0.remove() }
        rings.removeAll()
        hud?.remove()
        hud = nil
        hudText = ""

        screens = rects
        bounds = rects.reduce(CGRect.null) { $0.union($1) }
        self.mainVisible = mainVisible
        scene.attach(roots)
        setSpiderCount(count)
    }

    func apply(_ result: ScanResult) {
        targets = result.targets
        index.removeAll(keepingCapacity: true)
        for (i, t) in targets.enumerated() where index[t.id] == nil { index[t.id] = i }
        activeWindow = result.window
        appName = result.appName
        trusted = result.trusted
        // Kaydırılan sayfalarda işaretler öğeyle birlikte kayar.
        for (id, mark) in marks {
            if let i = index[id], targets[i].rect != mark.rect { mark.move(to: targets[i].rect) }
        }
    }

    func target(id: UInt) -> CrawlTarget? { index[id].map { targets[$0] } }

    func lastVisit(_ id: UInt) -> Double? { visited[id] }

    /// Ayağın tutunabileceği en yakın hedef noktası.
    func foothold(near p: CGPoint, within maxD: CGFloat) -> (id: UInt, point: CGPoint)? {
        var best: (UInt, CGPoint)?
        var bestD = maxD
        for t in targets {
            let r = t.rect
            if r.minY > p.y + maxD || r.maxY < p.y - maxD || r.minX > p.x + maxD || r.maxX < p.x - maxD { continue }
            let q = CGPoint(x: clamp(p.x, r.minX + 1, max(r.minX + 1, r.maxX - 1)),
                            y: clamp(p.y, r.minY + 1, max(r.minY + 1, r.maxY - 1)))
            let d = hypot(q.x - p.x, q.y - p.y)
            if d < bestD {
                bestD = d
                best = (t.id, q)
            }
        }
        return best.map { (id: $0.0, point: $0.1) }
    }

    func wanderArea(around p: CGPoint) -> CGRect {
        if let w = activeWindow, w.width > 160, w.height > 160 { return w.insetBy(dx: 40, dy: 40) }
        let screen = screens.first { $0.contains(p) } ?? mainVisible
        return screen.insetBy(dx: 60, dy: 60)
    }

    private func spawnPoint() -> CGPoint {
        CGPoint(x: mainVisible.midX + rand(-200, 200), y: mainVisible.maxY - rand(120, 220))
    }

    // MARK: Örümcekler

    func setSpiderCount(_ n: Int) {
        while spiders.count < n { spiders.append(Spider(at: spawnPoint(), size: size, scene: scene)) }
        while spiders.count > n {
            let s = spiders.removeLast()
            s.handOverCarried().forEach(drop)
            s.remove()
        }
    }

    /// Boyut değişince örümcekleri aynı yerlerinde yeniden oluşturur.
    func respawn() {
        spiders = spiders.map { old in
            old.handOverCarried().forEach(drop)
            old.remove()
            return Spider(at: old.position, size: size, scene: scene)
        }
    }

    // MARK: Örümceklerin çağırdığı efektler

    func visit(_ t: CrawlTarget) {
        if visited[t.id] == nil { visitedCount += 1 }
        visited[t.id] = clock
        var s: String
        if let u = t.url, let url = URL(string: u), let host = url.host {
            // Yalnızca alan adı gösterilir: yolda sıfırlama jetonları, paylaşım ve toplantı kodları
            // (meet.google.com/abc-defg-hij, discord.gg/davet) olabilir ve günlük ekran kaydına girebilir.
            s = host.replacingOccurrences(of: "www.", with: "") + (url.path.count > 1 ? "/…" : "")
        } else {
            s = t.role.replacingOccurrences(of: "AX", with: "") + (t.text.isEmpty ? "" : " “\(t.text)”")
        }
        if s.count > 56 { s = String(s.prefix(55)) + "…" }
        log.append("GET " + s)
        if log.count > 6 { log.removeFirst() }
    }

    func dress(_ t: CrawlTarget, strong: Bool) {
        guard effects, t.markable else { return }
        if let existing = marks[t.id], existing.style != .outline, !strong {
            existing.born = clock - 0.15   // güçlü işareti dokunuşla bozma, sadece ömrünü tazele
            return
        }
        var style = Mark.Style.outline
        var attr: NSAttributedString?
        let color = Palette.random()
        if strong, !t.text.isEmpty {
            let r = Double.random(in: 0..<1)
            style = r < 0.4 ? .fill : (r < 0.75 ? .ink : .outline)
            if style != .outline {
                // Kısa metinler (bağlantı, düğme) büyüyebilir; uzun satırlar satırın boyunu aşmaz.
                var size = clamp(t.rect.height * 0.72, 9, 22)
                if chance(0.3), t.text.count <= 20 { size *= rand(1.25, 1.8) }
                let font = style == .fill ? Fonts.random(size) : (chance(0.5) ? Fonts.mono(size) : Fonts.serifItalic(size))
                attr = NSAttributedString(string: t.text, attributes: [
                    .font: font, .foregroundColor: style == .fill ? Palette.ink : color,
                ])
            }
        }
        marks[t.id]?.remove()
        marks[t.id] = Mark(rect: t.rect, color: color, style: style, attr: attr, born: clock,
                           life: strong ? 10 : 6, scene: scene)
        if marks.count > 150, let oldest = marks.min(by: { $0.value.born < $1.value.born }) {
            oldest.value.remove()
            marks.removeValue(forKey: oldest.key)
        }
    }

    func addRing(at p: CGPoint, radius: CGFloat) {
        rings.append(Ring(center: p, radius: radius, color: Palette.random(), born: clock, scene: scene))
    }

    func makeLabel(_ text: String, at p: CGPoint) -> Label { Label(text: text, at: p, scene: scene) }

    func drop(_ label: Label) {
        guard effects else {
            label.remove()
            return
        }
        label.born = clock
        label.life = Double(rand(4, 8))
        label.lower()
        ghosts.append(label)
        if ghosts.count > 40 { ghosts.removeFirst().remove() }
    }

    private func clearEffects() {
        marks.values.forEach { $0.remove() }
        marks.removeAll()
        ghosts.forEach { $0.remove() }
        ghosts.removeAll()
        spiders.forEach { $0.handOverCarried().forEach { $0.remove() } }
    }

    // MARK: Kare döngüsü

    func step(_ dt: Double) {
        clock += dt
        for s in spiders { s.update(dt, in: self) }

        for (id, m) in marks {
            if clock > m.born + m.life {
                m.remove()
                marks.removeValue(forKey: id)
            } else {
                m.sync(at: clock)
            }
        }
        ghosts.removeAll { g in
            let remaining = g.born + g.life - clock
            if remaining <= 0 {
                g.remove()
                return true
            }
            if remaining < 1.2 { g.sync(alpha: CGFloat(remaining / 1.2) * 0.9) }
            return false
        }
        rings.removeAll { r in
            guard clock - r.born > 0.45 else { return false }
            r.remove()
            return true
        }
        if clock - lastPrune > 30 {
            lastPrune = clock
            visited = visited.filter { clock - $0.value < 60 }
        }
        updateHUD()
    }

    // MARK: Tarama günlüğü

    private func updateHUD() {
        guard showLog else {
            hud?.remove()
            hud = nil
            hudText = ""
            return
        }
        guard clock - hudAt > 0.12 else { return }
        hudAt = clock
        let frontier = targets.reduce(0) { $0 + (visited[$1.id] == nil ? 1 : 0) }
        var lines = ["ÖRÜMCEK · \(appName) · ziyaret: \(visitedCount) · kuyruk: \(frontier) · örümcek: \(spiders.count)"]
        if !trusted { lines.append("Erişilebilirlik izni yok: yalnızca pencere kenarlarında geziyor") }
        lines += log
        let text = lines.joined(separator: "\n")
        guard text != hudText else { return }
        hudText = text
        let attr = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: Palette.hudText,
        ])
        let sprite = Sprite(text: attr, box: .fill(NSColor(white: 0.03, alpha: 0.8)), padding: CGSize(width: 10, height: 8))
        let frame = CGRect(x: mainVisible.minX + 12, y: mainVisible.maxY - 12 - sprite.size.height,
                           width: sprite.size.width, height: sprite.size.height)
        if hud == nil {
            hud = scene.node(z: 20) {
                let layer = CALayer()
                layer.cornerRadius = 6
                layer.masksToBounds = true
                return layer
            }
        }
        hud?.each {
            $0.contents = sprite.image
            $0.frame = frame
        }
    }
}
