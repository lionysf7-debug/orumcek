// Her ekran için bir tane: şeffaf, tıklamaları alttaki uygulamalara geçiren, her şeyin üstündeki pencere.
// Pencerenin kendisi hiçbir şey çizmez; sahnedeki her nesne kendi küçük Core Animation katmanıdır.
// Tam ekran tek bir tuval her karede ~22 MB'lık tamponu kopyalatıyordu.
import AppKit
import QuartzCore

@MainActor
final class OverlayWindow: NSPanel {
    let screenRect: CGRect      // sol üst başlangıçlı genel koordinatlarda
    let scale: CGFloat
    /// Alt katmanları doğrudan genel koordinatlarla (AX ile aynı) konumlanan kap.
    let worldLayer = CALayer()

    init(screen: NSScreen) {
        screenRect = Coordinates.topLeft(screen.frame)
        scale = screen.backingScaleFactor
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        // Tüm masaüstlerinde ve tam ekran uygulamaların üstünde görünür; Mission Control'de kıpırdamaz.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        // Görünümün kendi katmanını AppKit yönetir (ters çevirme ayarını sıfırlar); bu yüzden
        // ekranı kaplayan kendi kabımızı ters çeviriyoruz: alt katmanlarda y aşağı doğru artar ve
        // bounds başlangıcı ekranın sol üst köşesinin genel koordinatı olduğundan nesneler
        // doğrudan AX koordinatlarıyla konumlanır.
        let host = CALayer()
        worldLayer.anchorPoint = .zero
        worldLayer.position = .zero
        worldLayer.bounds = screenRect
        worldLayer.isGeometryFlipped = true
        worldLayer.actions = Scene.noActions
        host.addSublayer(worldLayer)
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.layer = host
        view.wantsLayer = true
        contentView = view
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
