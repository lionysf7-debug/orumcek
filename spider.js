/*
  Crawler Örümceği
  ----------------
  Sayfadaki bağlantıları bir web crawler gibi "tarayan" prosedürel örümcek.
  Herhangi bir sayfada çalışır: index.html içinde, konsola yapıştırarak ya da
  bookmarklet olarak. Tekrar çalıştırılırsa örümceği kaldırır (aç/kapa).

  Ayarlar, betikten önce tanımlanırsa window.CRAWLER_SPIDER_CONFIG üzerinden okunur:
    { spiders: 1, speed: 150, size: 1, direction: -1 (yukarı) | 1 (aşağı), follow: true, hud: true }

  Not: Bookmarklet'e dönüştürülebilmesi için bu dosyada yalnızca blok yorum kullanılır.
*/
(() => {
  'use strict';

  if (window.__crawlerSpider) {
    window.__crawlerSpider.destroy();
    return;
  }

  const CFG = Object.assign({
    spiders: 1,
    speed: 150,
    size: 1,
    direction: -1,
    follow: true,
    hud: true,
    root: null
  }, window.CRAWLER_SPIDER_CONFIG || {});

  const PALETTE = ['#38d6ff', '#ff3fb4', '#7a5cff', '#7ee08a', '#ff8a5c', '#4f7dff', '#f2e35b'];
  const FONTS = [
    '"Courier New", Courier, monospace',
    'Georgia, "Times New Roman", serif',
    '"Helvetica Neue", Arial, sans-serif',
    'Menlo, Consolas, monospace',
    '"Times New Roman", Times, serif'
  ];
  const DRESS_CLASSES = ['wcs-touch', 'wcs-fill', 'wcs-mono', 'wcs-serif', 'wcs-ink', 'wcs-big'];

  /* Bacak düzeni (sol taraf; sağ taraf aynalanır).
     a: gövde yönüne göre açı (derece), reach: uzanma çarpanı */
  const LEG_LAYOUT = [
    { a: 36, reach: 1.08 },
    { a: 74, reach: 0.92 },
    { a: 110, reach: 0.88 },
    { a: 146, reach: 1.02 }
  ];
  const BASE_REACH = 92;
  const MAX_SPIDERS = 12;

  const rand = (a, b) => a + Math.random() * (b - a);
  const pick = arr => arr[(Math.random() * arr.length) | 0];
  const clamp = (v, lo, hi) => (v < lo ? lo : v > hi ? hi : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const angleDiff = (to, from) => Math.atan2(Math.sin(to - from), Math.cos(to - from));
  const smoothstep = t => t * t * (3 - 2 * t);

  /* ---------- Tema: koyu sayfada açık çizgi, açık sayfada koyu çizgi ---------- */

  function pageIsDark() {
    let el = document.elementFromPoint(innerWidth / 2, innerHeight / 2) || document.body;
    for (; el; el = el.parentElement) {
      const m = getComputedStyle(el).backgroundColor.match(/[\d.]+/g);
      if (!m) continue;
      const [r, g, b, a = 1] = m.map(Number);
      if (a < 0.5) continue;
      return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255 < 0.45;
    }
    return false;
  }

  const DARK = pageIsDark();
  const INK = DARK ? 'rgba(178, 205, 255, 0.92)' : 'rgba(30, 44, 80, 0.9)';
  const BODY_FILL = DARK ? 'rgba(10, 12, 20, 0.85)' : 'rgba(255, 255, 255, 0.85)';
  const JOINT_A = '#ff4f9a';
  const JOINT_B = DARK ? '#6f9bff' : '#2f5bd6';
  const THREAD_COLORS = DARK
    ? ['#ff4f9a', '#9fb8ff', '#ffffff', '#38d6ff']
    : ['#ff2f8a', '#3c5bd6', '#222222', '#0aa6d6'];

  /* ---------- Sayfaya eklenen katmanlar ---------- */

  const style = document.createElement('style');
  style.textContent = [
    '.wcs-touch{outline:1px solid var(--wcs-c)!important;outline-offset:1px}',
    '.wcs-ink{color:var(--wcs-c)!important}',
    '.wcs-fill{background:var(--wcs-c)!important;color:#0a0a12!important;text-decoration:none!important}',
    '.wcs-mono{font-family:"Courier New",Courier,monospace!important;letter-spacing:.04em}',
    '.wcs-serif{font-family:Georgia,"Times New Roman",serif!important;font-style:italic!important}',
    '.wcs-big{font-size:var(--wcs-s,1.5em)!important;line-height:1.05!important}'
  ].join('');
  document.head.appendChild(style);

  const canvas = document.createElement('canvas');
  canvas.style.cssText = 'position:fixed;left:0;top:0;pointer-events:none;z-index:2147483646';
  const ctx = canvas.getContext('2d');
  let W = 0, H = 0, DPR = 1;

  function resize() {
    DPR = Math.min(2, window.devicePixelRatio || 1);
    W = document.documentElement.clientWidth;
    H = window.innerHeight;
    canvas.width = Math.round(W * DPR);
    canvas.height = Math.round(H * DPR);
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
  }
  resize();
  document.body.appendChild(canvas);

  const hud = document.createElement('div');
  hud.style.cssText = [
    'position:fixed', 'left:12px', 'bottom:12px', 'z-index:2147483647',
    'max-width:calc(100vw - 24px)', 'padding:8px 10px', 'border-radius:6px',
    'background:rgba(8,10,16,.8)', 'color:#cfe0ff', 'font:11px/1.45 Menlo,Consolas,monospace',
    'pointer-events:none', 'white-space:pre', 'overflow:hidden'
  ].join(';');
  if (!CFG.hud) hud.style.display = 'none';
  document.body.appendChild(hud);

  /* ---------- Bağlantı haritası (crawler'ın "gördüğü" sayfa) ---------- */

  const root = (CFG.root && document.querySelector(CFG.root))
    || document.querySelector('#mw-content-text, main, article, [role="main"]')
    || document.body;

  let links = [];
  let linksAt = -Infinity;
  const visited = new WeakMap();  /* bağlantı -> son ziyaret zamanı (sn) */
  const dressed = new Set();      /* kapanışta temizlenecek öğeler */
  let visitedCount = 0;

  function refreshLinks(now) {
    const sx = window.scrollX, sy = window.scrollY;
    links = [];
    for (const el of root.querySelectorAll('a[href]')) {
      const r = el.getClientRects()[0];
      if (!r || r.width < 3 || r.height < 3) continue;
      links.push({ el, x: r.left + sx, y: r.top + sy, w: r.width, h: r.height });
    }
    linksAt = now;
  }

  function liveRect(el) {
    const r = el.getClientRects()[0];
    return r ? { x: r.left + window.scrollX, y: r.top + window.scrollY, w: r.width, h: r.height } : null;
  }

  function nearestLink(x, y, maxD) {
    let best = null, bestD = maxD;
    for (const L of links) {
      if (L.y > y + maxD || L.y + L.h < y - maxD) continue;
      const cx = clamp(x, L.x + 1, L.x + L.w - 1);
      const cy = clamp(y, L.y + 1, L.y + L.h - 1);
      const d = Math.hypot(cx - x, cy - y);
      if (d < bestD) { bestD = d; best = { el: L.el, x: cx, y: cy }; }
    }
    return best;
  }

  function linkText(el) {
    const t = (el.textContent || '').replace(/\s+/g, ' ').trim();
    return t.length > 44 ? t.slice(0, 43) + '…' : t;
  }

  /* Dokunulan bağlantıyı "işaretle": renkli kutu, yazı tipi, boyut */
  function dress(el, strong) {
    if (!el.isConnected) return;
    el.style.setProperty('--wcs-c', pick(PALETTE));
    el.classList.add('wcs-touch');
    dressed.add(el);
    if (!strong) return;
    const r = Math.random();
    if (r < 0.32) el.classList.add('wcs-fill');
    else if (r < 0.52) el.classList.add('wcs-mono', 'wcs-ink');
    else if (r < 0.7) el.classList.add('wcs-serif', 'wcs-ink');
    else el.classList.add('wcs-ink');
    if (Math.random() < 0.3 && linkText(el).length < 36) {
      el.style.setProperty('--wcs-s', rand(1.25, 1.9).toFixed(2) + 'em');
      el.classList.add('wcs-big');
    }
  }

  /* ---------- Canvas üzerindeki efektler ---------- */

  const ghosts = [];  /* sayfada bırakılan, yavaşça sönen etiket kopyaları */
  const rings = [];   /* temas halkaları */
  const log = [];     /* HUD: son "istekler" */

  function makeLabel(text, x, y) {
    const px = Math.round(rand(11, 22));
    const font = (Math.random() < 0.3 ? 'italic ' : '') + px + 'px ' + pick(FONTS);
    ctx.font = font;
    const color = pick(PALETTE);
    const filled = Math.random() < 0.6;
    return {
      text, font, x, y, vx: 0, vy: 0, ang: 0, tilt: 0, len: 0,
      w: ctx.measureText(text).width + 8,
      h: px + 6,
      bg: filled ? color : null,
      fg: filled ? '#0a0a12' : color
    };
  }

  function dropLabel(L, now) {
    L.born = now;
    L.life = rand(4, 8);
    ghosts.push(L);
    if (ghosts.length > 40) ghosts.shift();
  }

  function drawLabel(L, alpha) {
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(L.x, L.y);
    ctx.rotate(L.ang);
    if (L.bg) {
      ctx.fillStyle = L.bg;
      ctx.fillRect(-L.w / 2, -L.h / 2, L.w, L.h);
    } else {
      ctx.strokeStyle = L.fg;
      ctx.lineWidth = 1;
      ctx.strokeRect(-L.w / 2, -L.h / 2, L.w, L.h);
    }
    ctx.fillStyle = L.fg;
    ctx.font = L.font;
    ctx.textBaseline = 'middle';
    ctx.fillText(L.text, -L.w / 2 + 4, 0.5);
    ctx.restore();
  }

  function line(x1, y1, x2, y2) {
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();
  }

  function dot(x, y, r, color) {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.fill();
  }

  function pushLog(el) {
    let s;
    try {
      const u = new URL(el.href);
      s = (u.host + u.pathname + u.hash).replace(/^www\./, '');
    } catch (e) {
      s = el.getAttribute('href') || '';
    }
    log.push('GET ' + (s.length > 52 ? s.slice(0, 51) + '…' : s));
    if (log.length > 6) log.shift();
  }

  /* İki parçalı ters kinematik: kalça (h), ayak (p), femur a, tibia b.
     Diz, iki olası çözümden (bx, by) yönüne daha yakın olanıdır. */
  function solveKnee(hx, hy, px, py, a, b, bx, by) {
    const dx = px - hx, dy = py - hy;
    const d = clamp(Math.hypot(dx, dy), Math.abs(a - b) + 0.5, a + b - 0.5);
    const base = Math.atan2(dy, dx);
    const off = Math.acos(clamp((a * a + d * d - b * b) / (2 * a * d), -1, 1));
    const k1x = hx + Math.cos(base + off) * a, k1y = hy + Math.sin(base + off) * a;
    const k2x = hx + Math.cos(base - off) * a, k2y = hy + Math.sin(base - off) * a;
    return (k1x - hx) * bx + (k1y - hy) * by >= (k2x - hx) * bx + (k2y - hy) * by
      ? { x: k1x, y: k1y }
      : { x: k2x, y: k2y };
  }

  /* ---------- Örümcek ---------- */

  class Spider {
    constructor(x, y, dir) {
      this.x = x;
      this.y = y;
      this.vx = 0;
      this.vy = 0;
      this.dir = dir;
      this.h = dir < 0 ? -Math.PI / 2 : Math.PI / 2;
      this.size = CFG.size * rand(0.9, 1.1);
      this.phase = rand(0, 100);
      this.target = null;
      this.pause = 0.5;
      this.burst = 1;
      this.misses = 0;
      this.threads = [];
      this.carried = [];
      this.legs = [];
      for (let i = 0; i < 8; i++) {
        const k = i % 4;
        const reach = BASE_REACH * LEG_LAYOUT[k].reach * this.size;
        const leg = {
          i, k, reach,
          side: i < 4 ? -1 : 1,
          ang: LEG_LAYOUT[k].a * Math.PI / 180,
          femur: reach * 0.6,
          tibia: reach * 0.62,
          fx: 0, fy: 0, sx: 0, sy: 0, tx: 0, ty: 0,
          t: 1,
          link: null
        };
        const p = this.restFoot(leg, 0);
        leg.fx = leg.tx = p.x;
        leg.fy = leg.ty = p.y;
        this.legs.push(leg);
      }
    }

    hip(leg) {
      const a = this.h + leg.side * leg.ang;
      const r = 6 * this.size;
      return { x: this.x + Math.cos(a) * r, y: this.y + Math.sin(a) * r };
    }

    /* Bacağın gövdeye göre "olması gereken" ayak noktası; lead > 0 ise hız yönünde ileri atar */
    restFoot(leg, lead) {
      const a = this.h + leg.side * leg.ang;
      return {
        x: this.x + Math.cos(a) * leg.reach + this.vx * lead,
        y: this.y + Math.sin(a) * leg.reach + this.vy * lead
      };
    }

    update(dt, now) {
      if (this.pause > 0) {
        this.pause -= dt;
        const k = Math.pow(0.001, dt);
        this.vx *= k;
        this.vy *= k;
      } else {
        const T = this.target;
        if (!T || (T.el && !T.el.isConnected) || now - T.since > 6) this.pickTarget(now);
        this.steer(dt, now);
      }

      const doc = document.documentElement;
      this.x = clamp(this.x + this.vx * dt, 20, doc.scrollWidth - 20);
      this.y = clamp(this.y + this.vy * dt, 20, doc.scrollHeight - 20);

      const sp = Math.hypot(this.vx, this.vy);
      if (sp > 10) this.h += angleDiff(Math.atan2(this.vy, this.vx), this.h) * Math.min(1, dt * 7);

      this.updateLegs(dt, now, sp);
      this.updateCarried(dt);
      this.threads = this.threads.filter(t => now - t.born < t.life);
    }

    /* Crawler'ın sıradaki hedefi: ilerleme yönünde, ziyaret edilmemiş, makul uzaklıkta bir bağlantı */
    pickTarget(now) {
      let best = null, bestScore = Infinity;
      for (const L of links) {
        const last = visited.get(L.el);
        if (last !== undefined && now - last < 30) continue;
        const cx = L.x + L.w / 2, cy = L.y + L.h / 2;
        const ahead = (cy - this.y) * this.dir;
        if (ahead < 12 || ahead > 320) continue;
        const dx = cx - this.x;
        const score = Math.abs(Math.hypot(dx, ahead) - 120) + Math.abs(dx) * 0.35 + Math.random() * 160;
        if (score < bestScore) {
          bestScore = score;
          best = L;
        }
      }
      if (best) {
        this.misses = 0;
        this.target = { el: best.el, u: rand(0.15, 0.85), x: 0, y: 0, since: now };
        return;
      }
      /* Bu yönde taranacak bağlantı kalmadı: geri dön; yine yoksa rastgele dolaş */
      this.misses++;
      this.dir *= -1;
      this.target = this.misses > 2
        ? { el: null, x: this.x + rand(-200, 200), y: this.y + rand(-200, 200), since: now }
        : null;
    }

    steer(dt, now) {
      const T = this.target;
      if (!T) return;
      let tx = T.x, ty = T.y;
      if (T.el) {
        const r = liveRect(T.el);
        if (!r) { this.target = null; return; }
        tx = r.x + r.w * T.u;
        ty = r.y + r.h / 2;
      }
      const dx = tx - this.x, dy = ty - this.y;
      const d = Math.hypot(dx, dy);
      if (d < 14) {
        if (T.el) this.bite(T.el, tx, ty, now);
        this.target = null;
        this.pause = Math.random() < 0.25 ? rand(0.5, 1.1) : rand(0.08, 0.35);
        this.burst = rand(0.7, 1.45);
        return;
      }
      /* Düz çizgi yerine hafif kıvrılan, böceğimsi bir rota */
      const wander = (Math.sin(now * 1.7 + this.phase) * 0.45 + Math.sin(now * 3.1 + this.phase * 2) * 0.2)
        * clamp((d - 40) / 120, 0, 1);
      const a = Math.atan2(dy, dx) + wander;
      const speed = CFG.speed * this.burst * clamp(d / 70, 0.3, 1);
      const k = Math.min(1, dt * 4);
      this.vx += (Math.cos(a) * speed - this.vx) * k;
      this.vy += (Math.sin(a) * speed - this.vy) * k;
    }

    /* Hedefe ulaşınca: bağlantıyı "indir", işaretle, bazen kopar ve sürükle */
    bite(el, x, y, now) {
      if (!visited.has(el)) visitedCount++;
      visited.set(el, now);
      dress(el, true);
      pushLog(el);
      rings.push({ x, y, born: now, r: 22, color: pick(PALETTE) });
      this.threads.push({ x, y, born: now, life: rand(2.5, 5), color: pick(THREAD_COLORS) });
      if (this.threads.length > 8) this.threads.shift();

      const text = linkText(el);
      if (!text) return;
      if (Math.random() < 0.4) {
        const L = makeLabel(text, x, y);
        L.len = rand(30, 120);
        L.tilt = rand(-0.35, 0.35);
        this.carried.push(L);
        if (this.carried.length > 5) dropLabel(this.carried.shift(), now);
      } else if (Math.random() < 0.4) {
        const L = makeLabel(text, x + rand(-70, 70), y + rand(-8, 8));
        if (Math.random() < 0.25) L.ang = rand(-0.5, 0.5);
        dropLabel(L, now);
      }
    }

    updateLegs(dt, now, sp) {
      const stepDist = BASE_REACH * 0.34 * this.size;
      const stepTime = clamp(0.2 - sp / 1800, 0.09, 0.2);

      for (const leg of this.legs) {
        if (leg.t >= 1) continue;
        leg.t = Math.min(1, leg.t + dt / stepTime);
        const e = smoothstep(leg.t);
        leg.fx = lerp(leg.sx, leg.tx, e);
        leg.fy = lerp(leg.sy, leg.ty, e);
        if (leg.t >= 1 && leg.link) {
          dress(leg.link, Math.random() < 0.15);
          rings.push({ x: leg.fx, y: leg.fy, born: now, r: 10, color: pick(PALETTE) });
        }
      }

      /* En çok geride kalan bacak önce adım atar; komşusu havadaysa bekler (dalga yürüyüşü) */
      const order = this.legs
        .map(leg => {
          const p = this.restFoot(leg, 0);
          return { leg, err: Math.hypot(leg.fx - p.x, leg.fy - p.y) };
        })
        .sort((a, b) => b.err - a.err);
      for (const { leg, err } of order) {
        if (leg.t < 1 || err < stepDist) continue;
        if (err < stepDist * 2.2 && this.neighborStepping(leg)) continue;
        this.startStep(leg);
      }
    }

    neighborStepping(leg) {
      const base = leg.side < 0 ? 0 : 4;
      const ids = [(leg.i + 4) % 8];
      if (leg.k > 0) ids.push(base + leg.k - 1);
      if (leg.k < 3) ids.push(base + leg.k + 1);
      return ids.some(j => this.legs[j].t < 1);
    }

    startStep(leg) {
      const p = this.restFoot(leg, 0.22);
      p.x += rand(-6, 6);
      p.y += rand(-6, 6);
      /* Ayak yakınında bağlantı varsa ona "tutun" */
      const hit = nearestLink(p.x, p.y, 26 * this.size);
      leg.link = hit ? hit.el : null;
      if (hit) {
        p.x = hit.x;
        p.y = hit.y;
      }
      leg.sx = leg.fx;
      leg.sy = leg.fy;
      leg.tx = p.x;
      leg.ty = p.y;
      leg.t = 0;
    }

    /* Koparılan etiketler ipe bağlıymış gibi gövdeyi takip eder */
    updateCarried(dt) {
      const drag = Math.pow(0.05, dt);
      for (const c of this.carried) {
        const dx = c.x - this.x, dy = c.y - this.y;
        const d = Math.hypot(dx, dy) || 1;
        if (d > c.len) {
          const pull = (d - c.len) * 22 * dt;
          c.vx -= (dx / d) * pull;
          c.vy -= (dy / d) * pull;
        }
        for (const o of this.carried) {
          if (o === c) continue;
          const ox = c.x - o.x, oy = c.y - o.y, od = Math.hypot(ox, oy);
          if (od > 0.01 && od < 24) {
            c.vx += (ox / od) * 140 * dt;
            c.vy += (oy / od) * 140 * dt;
          }
        }
        c.vx *= drag;
        c.vy *= drag;
        c.x += c.vx * dt;
        c.y += c.vy * dt;
        let a = Math.atan2(dy, dx);
        if (a > Math.PI / 2) a -= Math.PI;
        else if (a < -Math.PI / 2) a += Math.PI;
        c.ang += angleDiff(a + c.tilt, c.ang) * Math.min(1, dt * 5);
      }
    }

    draw(now) {
      const s = this.size;

      ctx.lineWidth = 1;
      for (const t of this.threads) {
        ctx.globalAlpha = (1 - (now - t.born) / t.life) * 0.8;
        ctx.strokeStyle = t.color;
        line(this.x, this.y, t.x, t.y);
      }
      ctx.globalAlpha = 0.55;
      ctx.strokeStyle = INK;
      for (const c of this.carried) line(this.x, this.y, c.x, c.y);
      ctx.globalAlpha = 1;
      for (const c of this.carried) drawLabel(c, 0.95);

      /* Bacaklar */
      const joints = [];
      ctx.lineWidth = 1.3 * s;
      ctx.strokeStyle = INK;
      ctx.beginPath();
      for (const leg of this.legs) {
        const hp = this.hip(leg);
        let px = leg.fx, py = leg.fy;
        if (leg.t < 1) {
          /* Kalkan ayak, yukarıdan bakınca kalçaya biraz yaklaşır */
          const lift = Math.sin(Math.PI * leg.t) * 0.16;
          px = lerp(px, hp.x, lift);
          py = lerp(py, hp.y, lift);
        }
        /* Dizler dışa doğru: ön bacaklar geriye, arka bacaklar öne kıvrılır */
        const kAng = this.h + leg.side * (leg.ang + (leg.k < 2 ? 0.5 : -0.5));
        const K = solveKnee(hp.x, hp.y, px, py, leg.femur, leg.tibia, Math.cos(kAng), Math.sin(kAng));
        ctx.moveTo(hp.x, hp.y);
        ctx.lineTo(K.x, K.y);
        ctx.lineTo(px, py);
        joints.push([K.x, K.y, px, py, leg.link && leg.t >= 1]);
      }
      ctx.stroke();
      for (const [kx, ky, px, py, gripping] of joints) {
        dot(kx, ky, 1.9 * s, JOINT_A);
        dot(px, py, (gripping ? 2.6 : 1.5) * s, gripping ? JOINT_A : JOINT_B);
      }

      /* Gövde: karın + baş-göğüs */
      ctx.save();
      ctx.translate(this.x, this.y);
      ctx.rotate(this.h);
      ctx.fillStyle = BODY_FILL;
      ctx.strokeStyle = INK;
      ctx.lineWidth = 1.2;
      ctx.beginPath();
      ctx.ellipse(-13 * s, 0, 11 * s, 8 * s, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      ctx.ellipse(0, 0, 6.5 * s, 5.5 * s, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(-5 * s, 0);
      ctx.lineTo(-22 * s, 0);
      ctx.moveTo(-13 * s, -6 * s);
      ctx.lineTo(-13 * s, 6 * s);
      ctx.stroke();
      dot(4.2 * s, -2 * s, 1.2 * s, JOINT_A);
      dot(4.2 * s, 2 * s, 1.2 * s, JOINT_A);
      if (this.pause > 0) dot(0, 0, (1.5 + Math.sin(now * 20) * 0.8) * s, JOINT_B);
      ctx.restore();
    }
  }

  /* ---------- Kamera, çizim, HUD ---------- */

  const spiders = [];
  let clock = 0;
  let paused = false;
  let camY = window.scrollY;
  let userScrollUntil = 0;

  function addSpider(x, y, dir) {
    if (spiders.length >= MAX_SPIDERS) return;
    spiders.push(new Spider(x, y, dir === undefined ? pick([-1, 1]) : dir));
  }

  function updateCamera(dt) {
    const s = spiders[0];
    if (!CFG.follow || !s) return;
    if (clock < userScrollUntil) {
      camY = window.scrollY;
      return;
    }
    const maxY = Math.max(0, document.documentElement.scrollHeight - H);
    const goal = clamp(s.y - H * 0.52, 0, maxY);
    camY += (goal - camY) * (1 - Math.pow(0.08, dt));
    window.scrollTo({ left: window.scrollX, top: Math.round(camY), behavior: 'instant' });
  }

  function draw(now) {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.clearRect(0, 0, W, H);
    ctx.translate(-window.scrollX, -window.scrollY);

    for (let i = ghosts.length - 1; i >= 0; i--) {
      if (now - ghosts[i].born > ghosts[i].life) ghosts.splice(i, 1);
    }
    for (const g of ghosts) drawLabel(g, Math.min(1, (g.life - (now - g.born)) / 1.2) * 0.9);

    for (const s of spiders) s.draw(now);

    ctx.lineWidth = 1.2;
    for (let i = rings.length - 1; i >= 0; i--) {
      const r = rings[i], t = (now - r.born) / 0.45;
      if (t >= 1) { rings.splice(i, 1); continue; }
      ctx.globalAlpha = 1 - t;
      ctx.strokeStyle = r.color;
      ctx.beginPath();
      ctx.arc(r.x, r.y, lerp(2, r.r, t), 0, Math.PI * 2);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  let hudAt = -1;
  function renderHud(now) {
    if (!CFG.hud || (now - hudAt < 0.12 && !paused)) return;
    hudAt = now;
    let frontier = 0;
    for (const L of links) if (!visited.has(L.el)) frontier++;
    hud.textContent =
      'CRAWLER  ziyaret: ' + visitedCount + '  kuyruk: ' + frontier + '  örümcek: ' + spiders.length +
      (paused ? '  [duraklatıldı]' : '') + '\n' +
      (log.length ? log.join('\n') + '\n' : '') +
      'boşluk: duraklat · N: örümcek ekle · F: takip · H: gizle · Esc: kapat';
  }

  let raf = 0;
  let last = performance.now();
  function frame(ms) {
    raf = requestAnimationFrame(frame);
    const dt = Math.min(0.05, Math.max(0, (ms - last) / 1000));
    last = ms;
    if (!paused) {
      clock += dt;
      if (clock - linksAt > 0.6) refreshLinks(clock);
      for (const s of spiders) s.update(dt, clock);
      updateCamera(dt);
    }
    draw(clock);
    renderHud(clock);
  }

  /* ---------- Girdiler ve kapanış ---------- */

  function onUserScroll() {
    userScrollUntil = clock + 2.5;
  }

  function onKey(e) {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    const k = e.key.toLowerCase();
    if (k === ' ') paused = !paused;
    else if (k === 'n') addSpider(window.scrollX + W * rand(0.3, 0.7), window.scrollY + H * rand(0.3, 0.7));
    else if (k === 'f') { CFG.follow = !CFG.follow; camY = window.scrollY; }
    else if (k === 'h') { CFG.hud = !CFG.hud; hud.style.display = CFG.hud ? '' : 'none'; }
    else if (k === 'escape') destroy();
    else return;
    e.preventDefault();
    e.stopPropagation();
  }

  function destroy() {
    cancelAnimationFrame(raf);
    window.removeEventListener('keydown', onKey, true);
    window.removeEventListener('resize', resize);
    window.removeEventListener('wheel', onUserScroll);
    window.removeEventListener('touchmove', onUserScroll);
    for (const el of dressed) {
      el.classList.remove(...DRESS_CLASSES);
      el.style.removeProperty('--wcs-c');
      el.style.removeProperty('--wcs-s');
    }
    canvas.remove();
    hud.remove();
    style.remove();
    delete window.__crawlerSpider;
  }

  window.addEventListener('keydown', onKey, true);
  window.addEventListener('resize', resize);
  window.addEventListener('wheel', onUserScroll, { passive: true });
  window.addEventListener('touchmove', onUserScroll, { passive: true });

  refreshLinks(0);
  for (let i = 0; i < Math.min(CFG.spiders, MAX_SPIDERS); i++) {
    addSpider(
      window.scrollX + W * rand(0.35, 0.65),
      window.scrollY + H * rand(0.5, 0.7),
      i === 0 ? CFG.direction : undefined
    );
  }
  raf = requestAnimationFrame(frame);

  window.__crawlerSpider = { destroy, addSpider, config: CFG };
})();
