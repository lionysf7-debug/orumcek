// Örümcek — menü çubuğundan yönetilen, tüm uygulamaların üstünde gezen "web crawler" örümceği.
// Ön plandaki uygulamanın bağlantılarını, düğmelerini ve yazılarını Erişilebilirlik API'siyle bulur,
// örümcek bunların üzerinde dolaşıp onları renkli kutularla işaretler.
import AppKit
import ApplicationServices
import ServiceManagement

@MainActor
final class Settings {
    private let defaults = UserDefaults.standard

    private func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? fallback }

    var visible: Bool {
        get { bool("visible", true) }
        set { defaults.set(newValue, forKey: "visible") }
    }
    var spiderCount: Int {
        get { defaults.object(forKey: "spiderCount") as? Int ?? 1 }
        set { defaults.set(newValue, forKey: "spiderCount") }
    }
    var speed: Double {
        get { defaults.object(forKey: "speed") as? Double ?? 150 }
        set { defaults.set(newValue, forKey: "speed") }
    }
    var size: Double {
        get { defaults.object(forKey: "size") as? Double ?? 0.85 }
        set { defaults.set(newValue, forKey: "size") }
    }
    var effects: Bool {
        get { bool("effects", true) }
        set { defaults.set(newValue, forKey: "effects") }
    }
    var scanWeb: Bool {
        get { bool("scanWeb", true) }
        set { defaults.set(newValue, forKey: "scanWeb") }
    }
    var scanDock: Bool {
        get { bool("scanDock", true) }
        set { defaults.set(newValue, forKey: "scanDock") }
    }
    var showLog: Bool {
        get { bool("showLog", false) }
        set { defaults.set(newValue, forKey: "showLog") }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let world = World()
    private let scanner = Scanner()
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var overlays: [OverlayWindow] = []
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var scanTimer: Timer?
    private var scanning = false

    private static let counts = [1, 2, 3, 5, 8]
    private static let speeds: [(String, Double)] = [("Yavaş", 90), ("Normal", 150), ("Hızlı", 240)]
    private static let sizes: [(String, Double)] = [("Küçük", 0.6), ("Orta", 0.85), ("Büyük", 1.15)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        item.button?.image = Self.statusIcon()
        item.button?.toolTip = "Örümcek"
        menu.delegate = self
        item.menu = menu

        world.speed = CGFloat(settings.speed)
        world.size = CGFloat(settings.size)
        world.effects = settings.effects
        world.showLog = settings.showLog

        buildOverlays()
        world.setSpiderCount(settings.spiderCount)

        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(appActivated),
                                                          name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if !AXIsProcessTrusted() { requestAccessibility(openSettings: false) }
        setVisible(settings.visible)
    }

    func applicationWillTerminate(_ notification: Notification) {
        scanner.releaseWeb()
    }

    // MARK: Katmanlar ve kare döngüsü

    private func buildOverlays() {
        link?.invalidate()
        link = nil
        for o in overlays { o.orderOut(nil) }
        overlays = NSScreen.screens.map { OverlayWindow(screen: $0) }
        let main = NSScreen.screens.first
        world.configure(screens: overlays.map(\.screenRect),
                        mainVisible: main.map { Coordinates.topLeft($0.visibleFrame) } ?? .zero,
                        roots: overlays.map { Scene.Root(layer: $0.worldLayer, scale: $0.scale) })
        if let view = overlays.first?.contentView {
            let l = view.displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)
            l.isPaused = !settings.visible
            link = l
        }
        if settings.visible { overlays.forEach { $0.orderFrontRegardless() } }
    }

    @objc private func screensChanged(_ notification: Notification) {
        buildOverlays()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp == 0 ? 1.0 / 60 : min(0.05, max(0, now - lastTimestamp))
        lastTimestamp = now
        // Karenin tüm katman değişiklikleri tek işlemde gider; kendiliğinden canlandırma yok.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.step(dt)
        CATransaction.commit()
    }

    private func setVisible(_ visible: Bool) {
        settings.visible = visible
        item.button?.appearsDisabled = !visible
        if visible {
            overlays.forEach { $0.orderFrontRegardless() }
            lastTimestamp = 0
            link?.isPaused = false
            startScanning()
        } else {
            link?.isPaused = true
            scanTimer?.invalidate()
            scanTimer = nil
            for o in overlays { o.orderOut(nil) }
        }
    }

    // MARK: Tarama

    private func startScanning() {
        scanTimer?.invalidate()
        let timer = Timer(timeInterval: 1.5, repeats: true) { _ in
            MainActor.assumeIsolated { self.scanNow() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        scanTimer = timer
        scanNow()
    }

    @objc private func appActivated(_ notification: Notification) {
        if settings.visible { scanNow() }
    }

    private func scanNow() {
        guard !scanning, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        scanning = true
        let dockPid = settings.scanDock
            ? NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
            : nil
        scanner.scan(pid: app.processIdentifier, name: app.localizedName ?? "", bundleID: app.bundleIdentifier,
                     includeWeb: settings.scanWeb, dockPid: dockPid, clip: world.bounds) { result in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanning = false
                    self.world.apply(result)
                }
            }
        }
    }

    private func requestAccessibility(openSettings: Bool) {
        // Uygulamayı Gizlilik > Erişilebilirlik listesine ekler ve sistemin izin penceresini gösterir.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options), openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Menü

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: settings.visible ? "Örümcekleri gizle" : "Örümcekleri göster",
                     action: #selector(toggleVisible), keyEquivalent: "")
        menu.addItem(.separator())

        menu.addItem(submenu("Örümcek sayısı", Self.counts.map { ("\($0)", $0, $0 == settings.spiderCount) },
                             action: #selector(setCount(_:))))
        menu.addItem(submenu("Hız", Self.speeds.map { ($0.0, Int($0.1), $0.1 == settings.speed) },
                             action: #selector(setSpeed(_:))))
        menu.addItem(submenu("Boyut", Self.sizes.map { ($0.0, Int($0.1 * 100), $0.1 == settings.size) },
                             action: #selector(setSize(_:))))
        menu.addItem(.separator())

        toggle(menu, "Renkli işaretler ve etiketler", settings.effects, #selector(toggleEffects))
        toggle(menu, "Web sayfalarını da tara (Chrome, Electron)", settings.scanWeb, #selector(toggleWeb))
        toggle(menu, "Menü çubuğu ve Dock'ta da gez", settings.scanDock, #selector(toggleDock))
        toggle(menu, "Tarama günlüğünü göster", settings.showLog, #selector(toggleLog))
        menu.addItem(.separator())

        if AXIsProcessTrusted() {
            let granted = menu.addItem(withTitle: "Erişilebilirlik izni verildi", action: nil, keyEquivalent: "")
            granted.state = .on
            granted.isEnabled = false
        } else {
            menu.addItem(withTitle: "Erişilebilirlik izni ver…", action: #selector(openAccessibility), keyEquivalent: "")
        }
        toggle(menu, "Açılışta başlat", SMAppService.mainApp.status == .enabled, #selector(toggleLoginItem))
        menu.addItem(.separator())
        menu.addItem(withTitle: "Örümcek'ten Çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            .target = NSApp
        for entry in menu.items where entry.target == nil && entry.action != nil { entry.target = self }
    }

    private func toggle(_ menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector) {
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").state = on ? .on : .off
    }

    private func submenu(_ title: String, _ options: [(String, Int, Bool)], action: Selector) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (name, tag, selected) in options {
            let entry = sub.addItem(withTitle: name, action: action, keyEquivalent: "")
            entry.tag = tag
            entry.target = self
            entry.state = selected ? .on : .off
        }
        parent.submenu = sub
        return parent
    }

    @objc private func toggleVisible() { setVisible(!settings.visible) }

    @objc private func setCount(_ sender: NSMenuItem) {
        settings.spiderCount = sender.tag
        world.setSpiderCount(sender.tag)
    }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        settings.speed = Double(sender.tag)
        world.speed = CGFloat(sender.tag)
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        settings.size = Double(sender.tag) / 100
        world.size = CGFloat(settings.size)
        world.respawn()
    }

    @objc private func toggleEffects() {
        settings.effects.toggle()
        world.effects = settings.effects
    }

    @objc private func toggleWeb() {
        settings.scanWeb.toggle()
        if !settings.scanWeb { scanner.releaseWeb() }
    }

    @objc private func toggleDock() { settings.scanDock.toggle() }

    @objc private func toggleLog() {
        settings.showLog.toggle()
        world.showLog = settings.showLog
    }

    @objc private func openAccessibility() { requestAccessibility(openSettings: true) }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Açılışta başlatma ayarlanamadı"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    // MARK: Simge

    /// Menü çubuğu için yukarıdan görünen küçük bir örümcek; şablon görsel olduğundan
    /// açık/koyu menü çubuğuna kendiliğinden uyar.
    static func statusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            NSBezierPath(ovalIn: CGRect(x: 6.9, y: 3.4, width: 4.2, height: 4.0)).fill()   // baş-göğüs
            NSBezierPath(ovalIn: CGRect(x: 6.1, y: 7.0, width: 5.8, height: 7.2)).fill()   // karın
            let legs = NSBezierPath()
            legs.lineWidth = 1.15
            legs.lineCapStyle = .round
            legs.lineJoinStyle = .round
            // (kalça, diz, ayak) — sol taraf; sağ taraf x = 18 - x ile aynalanır
            let left: [(CGPoint, CGPoint, CGPoint)] = [
                (CGPoint(x: 7.4, y: 4.6), CGPoint(x: 4.4, y: 2.6), CGPoint(x: 3.0, y: 0.8)),
                (CGPoint(x: 7.2, y: 5.6), CGPoint(x: 3.4, y: 4.6), CGPoint(x: 1.0, y: 4.4)),
                (CGPoint(x: 7.2, y: 6.6), CGPoint(x: 3.4, y: 8.4), CGPoint(x: 1.2, y: 10.4)),
                (CGPoint(x: 7.4, y: 7.4), CGPoint(x: 4.6, y: 11.6), CGPoint(x: 3.2, y: 15.6)),
            ]
            for (h, k, f) in left {
                for mirror in [false, true] {
                    let m = { (p: CGPoint) in mirror ? CGPoint(x: 18 - p.x, y: p.y) : p }
                    legs.move(to: m(h))
                    legs.line(to: m(k))
                    legs.line(to: m(f))
                }
            }
            legs.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Örümcek"
        return image
    }
}

@main
struct OrumcekApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // Dock'ta simge yok, yalnızca menü çubuğunda
        app.run()
    }
}
