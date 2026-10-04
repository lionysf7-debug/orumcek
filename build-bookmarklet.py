"""spider.js dosyasından sürüklenebilir bir bookmarklet sayfası üretir.

Kullanım:  python3 build-bookmarklet.py   ->  bookmarklet.html
spider.js her değiştiğinde yeniden çalıştırın.
"""
import html
from pathlib import Path
from urllib.parse import quote

here = Path(__file__).resolve().parent
source = (here / "spider.js").read_text(encoding="utf-8")
href = "javascript:" + quote(source, safe="")

page = f"""<!doctype html>
<html lang="tr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Crawler Örümceği Bookmarklet</title>
<style>
  body {{ margin: 0; min-height: 100vh; display: grid; place-items: center; background: #101418; color: #d8dce2;
         font: 15px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
  .box {{ max-width: 520px; padding: 24px; }}
  .bm {{ display: inline-block; margin: 12px 0 20px; padding: 10px 18px; border-radius: 8px; background: #ff3fb4;
         color: #0a0a12; font-weight: 600; text-decoration: none; cursor: grab; }}
  code {{ background: #202226; padding: 1px 5px; border-radius: 4px; }}
</style>
</head>
<body>
<div class="box">
  <h1>Crawler Örümceği</h1>
  <p>Aşağıdaki düğmeyi tarayıcının yer imleri çubuğuna <b>sürükleyip bırakın</b>.</p>
  <a class="bm" href="{html.escape(href, quote=True)}">🕷 Crawler Örümceği</a>
  <p>Sonra herhangi bir sayfada (ör. Wikipedia'da karanlık modda bir makalenin <i>Kaynakça</i> bölümü)
     yer imine tıklayın. Tekrar tıklamak örümceği kaldırır.</p>
  <p>Kısayollar: <code>boşluk</code> duraklat · <code>N</code> örümcek ekle · <code>F</code> takip ·
     <code>H</code> paneli gizle · <code>Esc</code> kapat</p>
</div>
</body>
</html>
"""

(here / "bookmarklet.html").write_text(page, encoding="utf-8")
print(f"bookmarklet.html yazıldı ({len(href):,} karakterlik bağlantı)")
