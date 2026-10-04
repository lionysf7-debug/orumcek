// Prosedürel örümcek: sekiz bacak, iki parçalı ters kinematik ve dalga yürüyüşü.
// Hazır bir animasyon yok; her bacağın ayağı yere sabitlenir, gövde fazla uzaklaşınca adım atılır.
// Çizim CAShapeLayer'larla yapılır: her karede yalnızca yollar güncellenir, pikselleri GPU basar.
import AppKit
import QuartzCore

private struct LegSpec {
    let angle: CGFloat   // gövde yönüne göre açı (derece)
    let reach: CGFloat   // uzanma çarpanı
}

// Sol taraf; sağ taraf aynalanır.
private let legLayout = [
    LegSpec(angle: 36, reach: 1.08), LegSpec(angle: 74, reach: 0.92),
    LegSpec(angle: 110, reach: 0.88), LegSpec(angle: 146, reach: 1.02),
]
private let baseReach: CGFloat = 92

private struct Leg {
    let index: Int
    let row: Int
    let side: CGFloat
    let angle: CGFloat
    let reach: CGFloat
    let femur: CGFloat
    let tibia: CGFloat
    var foot = CGPoint.zero
    var start = CGPoint.zero
    var end = CGPoint.zero
    var t: CGFloat = 1        // 1 = yere basıyor, < 1 = adım atıyor
    var grip: UInt?           // ayağın tutunduğu hedef
}

@MainActor
private final class Strand {
    let to: CGPoint
    let born: Double
    let life: Double
    let node: Node<CAShapeLayer>

    init(to: CGPoint, born: Double, scene: Scene) {
        self.to = to
        self.born = born
        life = Double.random(in: 2.5..<5)
        let color = Palette.threads.randomElement()!
        node = scene.node(z: 8) {
            let shape = CAShapeLayer()
            shape.strokeColor = color.cgColor
            shape.fillColor = nil
            shape.lineWidth = 1
            return shape
        }
    }
}

private struct Pursuit {
    let id: UInt?
    let u: CGFloat            // hedefin genişliği boyunca hangi noktaya gidileceği
    let point: CGPoint        // id yoksa serbest dolaşma noktası
    let since: Double
}

/// İki parçalı ters kinematik: kalça, ayak ve parça uzunluklarından diz noktası.
/// İki olası çözümden `bend` yönüne daha yakın olanı seçilir.
private func solveKnee(hip: CGPoint, foot: CGPoint, femur a: CGFloat, tibia b: CGFloat, bend: CGVector) -> CGPoint {
    let dx = foot.x - hip.x, dy = foot.y - hip.y
    let d = clamp(hypot(dx, dy), abs(a - b) + 0.5, a + b - 0.5)
    let base = atan2(dy, dx)
    let off = acos(clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1))
    let k1 = CGPoint(x: hip.x + cos(base + off) * a, y: hip.y + sin(base + off) * a)
    let k2 = CGPoint(x: hip.x + cos(base - off) * a, y: hip.y + sin(base - off) * a)
    let s1 = (k1.x - hip.x) * bend.dx + (k1.y - hip.y) * bend.dy
    let s2 = (k2.x - hip.x) * bend.dx + (k2.y - hip.y) * bend.dy
    return s1 >= s2 ? k1 : k2
}

private func addDot(_ path: CGMutablePath, _ p: CGPoint, _ r: CGFloat) {
    path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
}

@MainActor
final class Spider {
    private var x: CGFloat
    private var y: CGFloat
    private var vx: CGFloat = 0
    private var vy: CGFloat = 0
    private var heading: CGFloat = -.pi / 2
    private let size: CGFloat
    private let phase = rand(0, 100)
    private let scene: Scene
    private var pursuit: Pursuit?
    private var pause: Double = 0.5
    private var burst: CGFloat = 1
    private var strands: [Strand] = []
    private var carried: [Label] = []
    private var legs: [Leg] = []

    // Katmanlar (alttan üste)
    private let ropes: Node<CAShapeLayer>
    private let halo: Node<CAShapeLayer>
    private let limbs: Node<CAShapeLayer>
    private let body: Node<CAShapeLayer>
    private let pinkDots: Node<CAShapeLayer>
    private let blueDots: Node<CAShapeLayer>

    var position: CGPoint { CGPoint(x: x, y: y) }

    init(at p: CGPoint, size: CGFloat, scene: Scene) {
        x = p.x
        y = p.y
        self.scene = scene
        let s = size * rand(0.9, 1.1)
        self.size = s

        func shape(_ z: CGFloat, _ configure: (CAShapeLayer) -> Void) -> Node<CAShapeLayer> {
            scene.node(z: z) {
                let layer = CAShapeLayer()
                layer.fillColor = nil
                layer.lineCap = .round
                layer.lineJoin = .round
                configure(layer)
                return layer
            }
        }
        ropes = shape(8) {
            $0.strokeColor = Palette.leg.withAlphaComponent(0.5).cgColor
            $0.lineWidth = 1
        }
        // Bacakların altındaki koyu hale, örümceği açık ve koyu arka planda aynı netlikte gösterir.
        halo = shape(10) {
            $0.strokeColor = Palette.halo.cgColor
            $0.lineWidth = 3.2 * s
        }
        limbs = shape(10.1) {
            $0.strokeColor = Palette.leg.cgColor
            $0.lineWidth = 1.3 * s
        }
        body = shape(10.2) {
            $0.fillColor = Palette.bodyFill.cgColor
            $0.strokeColor = Palette.leg.cgColor
            $0.lineWidth = 1.2
        }
        pinkDots = shape(10.3) { $0.fillColor = Palette.jointA.cgColor }
        blueDots = shape(10.3) { $0.fillColor = Palette.jointB.cgColor }

        for i in 0..<8 {
            let row = i % 4
            let reach = baseReach * legLayout[row].reach * s
            var leg = Leg(index: i, row: row, side: i < 4 ? -1 : 1, angle: legLayout[row].angle * .pi / 180,
                          reach: reach, femur: reach * 0.6, tibia: reach * 0.62)
            let rest = restFoot(leg, lead: 0)
            leg.foot = rest
            leg.start = rest
            leg.end = rest
            legs.append(leg)
        }
        render(clock: 0)
    }

    func remove() {
        for n in [ropes, halo, limbs, body, pinkDots, blueDots] { n.remove() }
        strands.forEach { $0.node.remove() }
        strands.removeAll()
    }

    /// Taşınan etiketleri bırakır; sahneye ne olacağına dünya karar verir.
    func handOverCarried() -> [Label] {
        defer { carried.removeAll() }
        return carried
    }

    private func hip(_ leg: Leg) -> CGPoint {
        let a = heading + leg.side * leg.angle
        let r = 6 * size
        return CGPoint(x: x + cos(a) * r, y: y + sin(a) * r)
    }

    /// Bacağın gövdeye göre olması gereken ayak noktası; `lead` > 0 ise hız yönünde ileri atar.
    private func restFoot(_ leg: Leg, lead: CGFloat) -> CGPoint {
        let a = heading + leg.side * leg.angle
        return CGPoint(x: x + cos(a) * leg.reach + vx * lead, y: y + sin(a) * leg.reach + vy * lead)
    }

    // MARK: Hareket

    func update(_ dt: Double, in w: World) {
        let fdt = CGFloat(dt)
        if pause > 0 {
            pause -= dt
            let k = pow(0.001, fdt)
            vx *= k
            vy *= k
        } else {
            if needsNewTarget(w) { pickTarget(w) }
            steer(fdt, w)
        }

        let area = w.bounds.insetBy(dx: 8, dy: 8)
        x = clamp(x + vx * fdt, area.minX, area.maxX)
        y = clamp(y + vy * fdt, area.minY, area.maxY)
        let speed = hypot(vx, vy)
        if speed > 10 { heading += angleDiff(atan2(vy, vx), heading) * min(1, fdt * 7) }

        updateLegs(fdt, speed: speed, w)
        updateCarried(fdt)
        strands.removeAll { s in
            guard w.clock - s.born >= s.life else { return false }
            s.node.remove()
            return true
        }
        render(clock: w.clock)
    }

    private func needsNewTarget(_ w: World) -> Bool {
        guard let p = pursuit else { return true }
        if w.clock - p.since > 7 { return true }
        if let id = p.id, w.target(id: id) == nil { return true }
        return false
    }

    /// Crawler'ın sıradaki hedefi: ziyaret edilmemiş, makul uzaklıkta ve tercihen önünde duran bir öğe.
    private func pickTarget(_ w: World) {
        let hx = cos(heading), hy = sin(heading)
        var best: CrawlTarget?
        var bestScore = CGFloat.infinity
        for t in w.targets {
            if let last = w.lastVisit(t.id), w.clock - last < 25 { continue }
            let dx = t.rect.midX - x, dy = t.rect.midY - y
            let d = hypot(dx, dy)
            if d < 40 { continue }
            let forward = (dx * hx + dy * hy) / d
            var score = abs(d - 170) + (1 - forward) * 90 + rand(0, 170)
            if d > 900 { score += (d - 900) * 0.5 }
            if score < bestScore {
                bestScore = score
                best = t
            }
        }
        if let best {
            pursuit = Pursuit(id: best.id, u: rand(0.15, 0.85), point: .zero, since: w.clock)
        } else {
            // Taranacak öğe yok: aktif pencerede ya da ekranda serbestçe dolaş.
            let a = w.wanderArea(around: position)
            let p = a.width > 10 && a.height > 10
                ? CGPoint(x: rand(a.minX, a.maxX), y: rand(a.minY, a.maxY))
                : CGPoint(x: a.midX, y: a.midY)
            pursuit = Pursuit(id: nil, u: 0, point: p, since: w.clock)
        }
    }

    private func steer(_ dt: CGFloat, _ w: World) {
        guard let p = pursuit else { return }
        var goal = p.point
        var target: CrawlTarget?
        if let id = p.id {
            guard let t = w.target(id: id) else {
                pursuit = nil
                return
            }
            target = t
            goal = CGPoint(x: t.rect.minX + t.rect.width * p.u, y: t.rect.midY)
        }
        let dx = goal.x - x, dy = goal.y - y
        let d = hypot(dx, dy)
        if d < 14 {
            if let target { bite(target, at: goal, w) }
            pursuit = nil
            pause = chance(0.25) ? Double.random(in: 0.5..<1.1) : Double.random(in: 0.08..<0.35)
            burst = rand(0.7, 1.45)
            return
        }
        // Düz çizgi yerine hafif kıvrılan, böceğimsi bir rota
        let now = CGFloat(w.clock)
        let wander = (sin(now * 1.7 + phase) * 0.45 + sin(now * 3.1 + phase * 2) * 0.2) * clamp((d - 40) / 120, 0, 1)
        let a = atan2(dy, dx) + wander
        var speed = w.speed * burst * clamp(d / 70, 0.3, 1)
        if d > 400 { speed *= min(3, d / 400) }   // uzak hedeflere koşarak git
        let k = min(1, dt * 4)
        vx += (cos(a) * speed - vx) * k
        vy += (sin(a) * speed - vy) * k
    }

    /// Hedefe ulaşınca: öğeyi "indir", işaretle, bazen metnini koparıp sürükle.
    private func bite(_ t: CrawlTarget, at p: CGPoint, _ w: World) {
        w.visit(t)
        w.dress(t, strong: true)
        w.addRing(at: p, radius: 22)
        strands.append(Strand(to: p, born: w.clock, scene: scene))
        if strands.count > 8 { strands.removeFirst().node.remove() }

        guard w.effects, !t.text.isEmpty else { return }
        let r = Double.random(in: 0..<1)
        if r < 0.4 {
            let label = w.makeLabel(t.text, at: p)
            label.length = rand(30, 120)
            label.tilt = rand(-0.35, 0.35)
            carried.append(label)
            if carried.count > 5 { w.drop(carried.removeFirst()) }
        } else if r < 0.64 {
            let label = w.makeLabel(t.text, at: CGPoint(x: p.x + rand(-70, 70), y: p.y + rand(-8, 8)))
            if chance(0.25) { label.angle = rand(-0.5, 0.5) }
            label.sync(alpha: 0.9)
            w.drop(label)
        }
    }

    // MARK: Bacaklar

    private func updateLegs(_ dt: CGFloat, speed: CGFloat, _ w: World) {
        let stepDistance = baseReach * 0.34 * size
        let stepTime = clamp(0.2 - speed / 1800, 0.09, 0.2)

        for i in legs.indices where legs[i].t < 1 {
            legs[i].t = min(1, legs[i].t + dt / stepTime)
            let e = smoothstep(legs[i].t)
            legs[i].foot = CGPoint(x: lerp(legs[i].start.x, legs[i].end.x, e), y: lerp(legs[i].start.y, legs[i].end.y, e))
            if legs[i].t >= 1, let id = legs[i].grip, let t = w.target(id: id) {
                w.dress(t, strong: chance(0.15))
                w.addRing(at: legs[i].foot, radius: 10)
            }
        }

        // En çok geride kalan bacak önce adım atar; komşusu havadaysa bekler (dalga yürüyüşü).
        let order = legs.indices
            .map { i -> (Int, CGFloat) in
                let rest = restFoot(legs[i], lead: 0)
                return (i, hypot(legs[i].foot.x - rest.x, legs[i].foot.y - rest.y))
            }
            .sorted { $0.1 > $1.1 }
        for (i, error) in order {
            if legs[i].t < 1 || error < stepDistance { continue }
            if error < stepDistance * 2.2 && neighborStepping(i) { continue }
            startStep(i, w)
        }
    }

    private func neighborStepping(_ i: Int) -> Bool {
        let leg = legs[i]
        let base = leg.side < 0 ? 0 : 4
        var ids = [(i + 4) % 8]
        if leg.row > 0 { ids.append(base + leg.row - 1) }
        if leg.row < 3 { ids.append(base + leg.row + 1) }
        return ids.contains { legs[$0].t < 1 }
    }

    private func startStep(_ i: Int, _ w: World) {
        var p = restFoot(legs[i], lead: 0.22)
        p.x += rand(-6, 6)
        p.y += rand(-6, 6)
        // Ayak yakınında bir öğe varsa ona tutun
        if let hold = w.foothold(near: p, within: 26 * size) {
            p = hold.point
            legs[i].grip = hold.id
        } else {
            legs[i].grip = nil
        }
        legs[i].start = legs[i].foot
        legs[i].end = p
        legs[i].t = 0
    }

    /// Koparılan etiketler ipe bağlıymış gibi gövdeyi takip eder.
    private func updateCarried(_ dt: CGFloat) {
        let drag = pow(0.05, dt)
        for c in carried {
            let dx = c.x - x, dy = c.y - y
            let d = max(hypot(dx, dy), 0.001)
            if d > c.length {
                let pull = (d - c.length) * 22 * dt
                c.vx -= dx / d * pull
                c.vy -= dy / d * pull
            }
            for o in carried where o !== c {
                let ox = c.x - o.x, oy = c.y - o.y, od = hypot(ox, oy)
                if od > 0.01 && od < 24 {
                    c.vx += ox / od * 140 * dt
                    c.vy += oy / od * 140 * dt
                }
            }
            c.vx *= drag
            c.vy *= drag
            c.x += c.vx * dt
            c.y += c.vy * dt
            var a = atan2(dy, dx)
            if a > .pi / 2 { a -= .pi } else if a < -.pi / 2 { a += .pi }
            c.angle += angleDiff(a + c.tilt, c.angle) * min(1, dt * 5)
        }
    }

    // MARK: Çizim (katman yollarını güncelle)

    private func render(clock: Double) {
        let center = position

        for s in strands {
            let path = CGMutablePath()
            path.move(to: center)
            path.addLine(to: s.to)
            let alpha = Float((1 - (clock - s.born) / s.life) * 0.8)
            s.node.each {
                $0.path = path
                $0.opacity = alpha
            }
        }
        let ropePath = CGMutablePath()
        for c in carried {
            ropePath.move(to: center)
            ropePath.addLine(to: CGPoint(x: c.x, y: c.y))
            c.sync(alpha: 0.95)
        }
        ropes.each { $0.path = ropePath }

        let limbPath = CGMutablePath()
        let pink = CGMutablePath()
        let blue = CGMutablePath()
        for leg in legs {
            let h = hip(leg)
            var f = leg.foot
            if leg.t < 1 {
                // Kalkan ayak, yukarıdan bakınca kalçaya biraz yaklaşır
                let lift = sin(.pi * leg.t) * 0.16
                f = CGPoint(x: lerp(f.x, h.x, lift), y: lerp(f.y, h.y, lift))
            }
            // Dizler dışa doğru: ön bacaklar geriye, arka bacaklar öne kıvrılır
            let kneeAngle = heading + leg.side * (leg.angle + (leg.row < 2 ? 0.5 : -0.5))
            let k = solveKnee(hip: h, foot: f, femur: leg.femur, tibia: leg.tibia,
                              bend: CGVector(dx: cos(kneeAngle), dy: sin(kneeAngle)))
            limbPath.move(to: h)
            limbPath.addLine(to: k)
            limbPath.addLine(to: f)
            addDot(pink, k, 1.9 * size)
            if leg.grip != nil && leg.t >= 1 { addDot(pink, f, 2.6 * size) } else { addDot(blue, f, 1.5 * size) }
        }

        // Gövde: karın + baş-göğüs, yönüne döndürülmüş
        let s = size
        let t = CGAffineTransform(translationX: x, y: y).rotated(by: heading)
        let bodyPath = CGMutablePath()
        bodyPath.addEllipse(in: CGRect(x: -24 * s, y: -8 * s, width: 22 * s, height: 16 * s), transform: t)
        bodyPath.addEllipse(in: CGRect(x: -6.5 * s, y: -5.5 * s, width: 13 * s, height: 11 * s), transform: t)
        bodyPath.move(to: CGPoint(x: -5 * s, y: 0), transform: t)
        bodyPath.addLine(to: CGPoint(x: -22 * s, y: 0), transform: t)
        bodyPath.move(to: CGPoint(x: -13 * s, y: -6 * s), transform: t)
        bodyPath.addLine(to: CGPoint(x: -13 * s, y: 6 * s), transform: t)
        addDot(pink, CGPoint(x: 4.2 * s, y: -2 * s).applying(t), 1.2 * s)
        addDot(pink, CGPoint(x: 4.2 * s, y: 2 * s).applying(t), 1.2 * s)
        if pause > 0 { addDot(blue, center, (1.5 + sin(CGFloat(clock) * 20) * 0.8) * s) }

        halo.each { $0.path = limbPath }
        limbs.each { $0.path = limbPath }
        body.each { $0.path = bodyPath }
        pinkDots.each { $0.path = pink }
        blueDots.each { $0.path = blue }
    }
}
