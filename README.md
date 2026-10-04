# Örümcek — Crawler Spider

A spider that physically *crawls* the links on your screen. It turns the
abstract idea of a web crawler into an animation: a procedurally-walked spider
targets the real `<a href>` elements on a page, tags the links it touches, tears
some off and drags them behind on a thread, while the camera follows along.

Two builds from one codebase:

- **Browser** — a self-contained `spider.js` / bookmarklet that runs on any live
  page (e.g. a real Wikipedia article), reading the DOM's links as its terrain.
- **Native macOS menu-bar app** (`mac/`) — a transparent, click-through overlay
  that walks the links, buttons and text of *any* foreground app (Chrome, Finder,
  System Settings, the menu bar, the Dock) by reading the macOS **accessibility
  tree**. Ships Xcode-free via `./build.sh`, requests Accessibility permission,
  and politely enables/restores browsers' web-content a11y only while it runs.

**Skills demonstrated:** two-bone inverse kinematics (cosine-rule leg solver),
gait generation, `<canvas>` rendering, live DOM introspection, the macOS
Accessibility (AX) API, transparent click-through `NSWindow` overlays, and
Xcode-free Swift builds with ad-hoc signing.

---

## Türkçe

Web crawler'ları bağlantıdan bağlantıya gezen örümcekler olarak gösteren animasyon.
Ekrandaki örümcek gerçek `<a href>` öğelerini hedef alır. Değdiği bağlantıları renkli kutularla işaretler, bazılarını koparıp ipe bağlı olarak peşinden sürükler. Kamera da onu takip eder.

## macOS uygulaması (tüm uygulamalarda)

`mac/` klasöründe, menü çubuğunda çalışan **Örümcek** uygulaması var. Ekranın üstünde şeffaf, tıklamaları geçiren bir katman açar. Örümcek, ön plandaki uygulamanın bağlantılarında, düğmelerinde ve yazılarında gezer: Chrome'daki web sayfaları, Finder, Ayarlar, menü çubuğu ve Dock dahil.

```bash
cd mac && ./build.sh --install
```

- İlk açılışta **Erişilebilirlik izni** ister: Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik > Örümcek. İzin yokken örümcek yalnızca pencere kenarlarında gezer.
- Menü çubuğundaki örümcek simgesinden şunları ayarlayabilirsin: göster/gizle, örümcek sayısı, hız, boyut, renkli efektler, web sayfalarını tarama, menü çubuğu/Dock, tarama günlüğü ve açılışta başlatma.
- Chrome, Edge, Brave ve Firefox web içeriğinin erişilebilirlik ağacını ancak istenince kurar. Örümcek bunu açar, kapanırken de geri alır. "Web sayfalarını da tara" seçeneği kapatılırsa bu hemen geri alınır.
- Ad-hoc imza her derlemede değişir. Yeniden derledikten sonra örümcek öğeleri göremezse Erişilebilirlik listesinde Örümcek'i silip (−) yeniden ekle.

## Tarayıcıda çalıştırma

**1. Demo sayfası.** `index.html` dosyasını tarayıcıda açın. Kaynakçası kurgusal, karanlık temalı bir ansiklopedi sayfası gelir. Örümcek sayfanın en altından başlar ve yukarı tırmanır.

```bash
open index.html
```

URL parametreleri: `?n=3` (örümcek sayısı), `?speed=220`, `?size=1.3`, `?dir=down`, `?title=0` (başlığı gizler), `?hud=0` (paneli gizler), `?seed=42` (farklı sayfa üretir).

**2. Gerçek Wikipedia'da (videodaki gibi).**
1. `bookmarklet.html` sayfasını açın ve pembe düğmeyi yer imleri çubuğuna sürükleyin.
2. Wikipedia'da bir makale açın, örneğin *Spider* ya da *Örümcek*.
3. Sağ menüden görünümü **Koyu** yapın ve *References / Kaynakça* bölümüne inin.
4. Yer imine tıklayın. Tekrar tıklarsanız örümcek kaldırılır.

Bookmarklet çalışmazsa `spider.js` içeriğini geliştirici konsoluna (Cmd+Option+J) yapıştırın.

## Kısayollar

| Tuş | İşlev |
|---|---|
| Boşluk | Duraklat / devam |
| N | Yeni örümcek ekle (en fazla 12) |
| F | Kamera takibini aç/kapa |
| H | Alt paneli gizle |
| T | Başlığı gizle (yalnızca demo sayfasında) |
| Esc | Örümceği tamamen kaldır |

## Reels videosu kaydetmek için

1. Chrome'da sayfayı açın. Cmd+Option+I ile geliştirici araçlarını, Cmd+Shift+M ile cihaz görünümünü açın ve **1080×1920** gibi dikey bir boyut seçin.
2. `H` ile paneli gizleyin.
3. Cmd+Shift+5 ile ekranın o bölgesini kaydedin.

## Nasıl çalışıyor

- **Crawler mantığı:** Sayfadaki bağlantıların konumları düzenli aralıklarla okunur. Örümcek ilerleme yönünde, henüz ziyaret etmediği ve makul uzaklıktaki bir bağlantıyı hedef seçer. Ziyaret edilenler `visited` kümesine girer, kalanlar "kuyruk" (frontier) sayılır.
- **Yürüyüş:** Her ayak yere sabittir. Gövde ilerledikçe ayak ideal noktasından fazla uzaklaşırsa o bacak tek adım atar. Komşu bacak havadayken bekler, bu da dalga şeklinde bir yürüyüş üretir. Adım hedefinin yakınında bir bağlantı varsa ayak ona tutunur.
- **Bacaklar:** Diz noktası iki parçalı ters kinematikle (kosinüs teoremi) hesaplanır.
- **Efektler:** Sayfadaki bağlantılara CSS sınıfları eklenir: renk, yazı tipi ve boyut. Koparılan etiketler, iplikler ve temas halkaları sayfanın üstündeki tek bir `<canvas>` katmanına çizilir.

`spider.js` dosyasını değiştirirseniz bookmarklet'i yeniden üretin:

```bash
python3 build-bookmarklet.py
```

## Lisans

MIT — bkz. [LICENSE](LICENSE).
