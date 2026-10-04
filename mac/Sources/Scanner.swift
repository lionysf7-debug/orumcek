// Ön plandaki uygulamanın ekrandaki öğelerini (bağlantılar, düğmeler, yazılar…) Erişilebilirlik
// API'si ile toplar. Örümceğin "taradığı" bağlantılar bunlardır.
import AppKit
import ApplicationServices

struct CrawlTarget {
    let id: UInt
    var rect: CGRect          // sol üst başlangıçlı genel koordinatlar (AX ile aynı)
    let text: String
    let url: String?
    let role: String
    let markable: Bool        // üstüne renkli kutu çizilecek kadar küçük mü
}

struct ScanResult {
    let appName: String
    let window: CGRect?
    let targets: [CrawlTarget]
    let trusted: Bool
    let nodes: Int
    let duration: TimeInterval
}

final class Scanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.yusufarslan.orumcek.scanner", qos: .utility)
    private var boosted = Set<pid_t>()   // yalnızca queue üzerinde kullanılır

    // İçine girilmeyen, tek parça hedef sayılan roller.
    private static let atomicRoles: Set<String> = [
        "AXLink", "AXButton", "AXMenuButton", "AXPopUpButton", "AXCheckBox", "AXRadioButton",
        "AXTextField", "AXComboBox", "AXMenuBarItem", "AXDockItem", "AXStaticText", "AXImage",
        "AXSlider", "AXDisclosureTriangle", "AXColorWell", "AXIncrementor",
    ]
    // Hiç girilmeyen roller: içerikleri ya çok büyük ya da görünmez.
    private static let skipRoles: Set<String> = ["AXTextArea", "AXScrollBar", "AXMenu", "AXRuler"]
    // Değeri kullanıcının yazdığı metin olan roller: gizlilik için yalnızca başlıkları okunur.
    private static let privateValueRoles: Set<String> = ["AXTextField", "AXComboBox"]
    // Web içeriğini yalnızca bir yardımcı teknoloji (VoiceOver vb.) bildirince açan tarayıcılar.
    private static let enhancedBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "org.chromium.Chromium", "com.brave.Browser",
        "com.microsoft.edgemac", "company.thebrowser.Browser", "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera", "org.mozilla.firefox",
    ]

    private static let basicAttributes = [
        kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute,
    ] as CFArray
    private static let detailAttributes = [
        kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXURLAttribute,
    ] as CFArray

    /// Taramayı arka planda yapar; `completion` arka plan kuyruğunda çağrılır.
    func scan(pid: pid_t, name: String, bundleID: String?, includeWeb: Bool, dockPid: pid_t?, clip: CGRect,
              completion: @escaping (ScanResult) -> Void) {
        queue.async {
            completion(self.perform(pid: pid, name: name, bundleID: bundleID, includeWeb: includeWeb,
                                    dockPid: dockPid, clip: clip))
        }
    }

    /// Açtığımız web erişilebilirlik bayraklarını geri alır (ayar kapatılınca ve çıkışta).
    func releaseWeb() {
        queue.sync {
            for pid in boosted {
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.25)
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanFalse)
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            }
            boosted.removeAll()
        }
    }

    private func perform(pid: pid_t, name: String, bundleID: String?, includeWeb: Bool, dockPid: pid_t?,
                         clip: CGRect) -> ScanResult {
        let start = Date()
        guard AXIsProcessTrusted() else {
            return ScanResult(appName: name, window: nil, targets: Self.windowEdgeTargets(pid: pid, clip: clip),
                              trusted: false, nodes: 0, duration: 0)
        }

        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        if includeWeb, !boosted.contains(pid) {
            // Web içeriğinin erişilebilirlik ağacı ancak istenince kurulur:
            // Electron uygulamaları ilk bayrağı, tarayıcılar ikincisini dinler.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            if let bundleID, Self.enhancedBrowsers.contains(bundleID) {
                AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
            }
            boosted.insert(pid)
        }

        var targets: [CrawlTarget] = []
        var nodes = 0
        var windowRect: CGRect?
        let deadline = start.addingTimeInterval(0.35)

        if let window = Self.element(app, kAXFocusedWindowAttribute) ?? Self.element(app, kAXMainWindowAttribute) {
            windowRect = Self.basics(window)?.rect
            let area = windowRect.map { $0.intersection(clip) } ?? clip
            if !area.isNull {
                nodes += Self.walk(window, clip: area, deadline: deadline, maxNodes: 4000, into: &targets)
            }
        }
        if let dockPid {
            if let menuBar = Self.element(app, kAXMenuBarAttribute) {
                nodes += Self.walk(menuBar, clip: clip, deadline: deadline.addingTimeInterval(0.05), maxNodes: 120, into: &targets)
            }
            let dock = AXUIElementCreateApplication(dockPid)
            AXUIElementSetMessagingTimeout(dock, 0.25)
            nodes += Self.walk(dock, clip: clip, deadline: deadline.addingTimeInterval(0.1), maxNodes: 200, into: &targets)
        }

        return ScanResult(appName: name, window: windowRect, targets: targets, trusted: true,
                          nodes: nodes, duration: Date().timeIntervalSince(start))
    }

    // Genişlik öncelikli dolaşma: önce üst düzey öğeler, süre ya da düğüm sınırı dolunca durur.
    // Ekran dışında kalan alt ağaçlara hiç girilmez.
    private static func walk(_ root: AXUIElement, clip: CGRect, deadline: Date, maxNodes: Int,
                             into out: inout [CrawlTarget]) -> Int {
        var queue: [AXUIElement] = [root]
        var head = 0
        while head < queue.count, head < maxNodes, Date() < deadline {
            let element = queue[head]
            head += 1
            guard let info = basics(element), !skipRoles.contains(info.role) else { continue }
            if let r = info.rect, r.width > 1, r.height > 1, !r.intersects(clip) { continue }

            if atomicRoles.contains(info.role) {
                if let r = info.rect, r.width >= 4, r.height >= 4, r.width <= 900, r.height <= 300 {
                    let (text, url) = details(element, role: info.role, children: info.children)
                    out.append(CrawlTarget(id: CFHash(element), rect: r, text: text, url: url, role: info.role,
                                           markable: r.height <= 48 && r.width <= 700))
                }
                continue
            }
            queue.append(contentsOf: info.children)
        }
        return head
    }

    private struct Basics {
        let role: String
        let rect: CGRect?
        let children: [AXUIElement]
    }

    // Tek bir IPC çağrısında rol, konum, boyut ve çocuklar.
    private static func basics(_ element: AXUIElement) -> Basics? {
        guard let values = copyMultiple(element, basicAttributes) else { return nil }
        var rect: CGRect?
        if let p = axPoint(values[1]), let s = axSize(values[2]) { rect = CGRect(origin: p, size: s) }
        return Basics(role: values[0] as? String ?? "", rect: rect, children: values[3] as? [AXUIElement] ?? [])
    }

    private static func details(_ element: AXUIElement, role: String, children: [AXUIElement]) -> (String, String?) {
        var text = ""
        var url: String?
        if let values = copyMultiple(element, detailAttributes) {
            let candidates = privateValueRoles.contains(role) ? values[0...1] : values[0...2]
            for case let s as String in candidates where !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = s
                break
            }
            url = (values[3] as? URL)?.absoluteString
        }
        if text.isEmpty, role == "AXLink", let first = children.first {
            text = (copy(first, kAXValueAttribute) as? String) ?? (copy(first, kAXTitleAttribute) as? String) ?? ""
        }
        return (clean(text), url)
    }

    private static func clean(_ s: String) -> String {
        let collapsed = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 44 ? String(collapsed.prefix(43)) + "…" : collapsed
    }

    // Erişilebilirlik izni yokken: ön plandaki uygulamanın pencere kenarlarında gezilecek noktalar.
    // Pencere çerçeveleri bu izin olmadan da okunabilir.
    private static func windowEdgeTargets(pid: pid_t, clip: CGRect) -> [CrawlTarget] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        var out: [CrawlTarget] = []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  r.width > 120, r.height > 80 else { continue }
            var points: [CGPoint] = []
            var x = r.minX + 30
            while x < r.maxX - 20 {
                points += [CGPoint(x: x, y: r.minY + 12), CGPoint(x: x, y: r.maxY - 6)]
                x += 140
            }
            var y = r.minY + 60
            while y < r.maxY - 30 {
                points += [CGPoint(x: r.minX + 6, y: y), CGPoint(x: r.maxX - 6, y: y)]
                y += 150
            }
            for p in points where clip.contains(p) {
                let id = UInt(bitPattern: (Int(p.x) << 20) ^ Int(p.y))
                out.append(CrawlTarget(id: id, rect: CGRect(x: p.x - 10, y: p.y - 6, width: 20, height: 12),
                                       text: "", url: nil, role: "AXWindowEdge", markable: false))
            }
        }
        return out
    }

    // MARK: AX yardımcıları

    private static func copyMultiple(_ element: AXUIElement, _ attributes: CFArray) -> [AnyObject]? {
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, attributes, AXCopyMultipleAttributeOptions(rawValue: 0), &values) == .success,
              let array = values as? [AnyObject], array.count == CFArrayGetCount(attributes) else { return nil }
        return array
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func axPoint(_ value: AnyObject) -> CGPoint? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func axSize(_ value: AnyObject) -> CGSize? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &s) ? s : nil
    }
}
