"""Walk every screen at phone width and in dark mode.

Checks the three things that make a beta look unfinished: sideways scroll on a
phone, text that fails WCAG contrast against what is actually behind it, and
tap targets under 44px. Contrast is measured in the browser against computed
backgrounds — a guess from the stylesheet is not a measurement.
"""
import json, os, sys, time

# Drives a real browser over CDP. Start one first:
#   /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
#     --headless=new --remote-debugging-port=9222 --user-data-dir=/tmp/audit-profile
# and the app with ./scripts/start.sh --no-ios.
import urllib.request
from websocket import create_connection

WEB = os.environ.get("FISHERS_WEB", "http://127.0.0.1:7311")


class Tab:
    def __init__(self):
        pages = json.load(urllib.request.urlopen("http://127.0.0.1:9222/json"))
        page = next(t for t in pages if t["type"] == "page")
        self.ws = create_connection(page["webSocketDebuggerUrl"], timeout=30,
                                    suppress_origin=True)
        self.i = 0
        self.send("Runtime.enable")
        self.send("Page.enable")

    def send(self, method, **params):
        self.i += 1
        self.ws.send(json.dumps({"id": self.i, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.i:
                return msg.get("result", {})

    def js(self, expr):
        r = self.send("Runtime.evaluate", expression=expr, awaitPromise=True,
                      returnByValue=True)
        if "exceptionDetails" in r:
            return None
        return r.get("result", {}).get("value")

    def goto(self, path):
        self.send("Page.navigate", url=WEB + path)
        time.sleep(2.5)

PROBE = r"""
(() => {
  const lum = (c) => {
    const [r,g,b] = c.map(v => { v /= 255; return v <= 0.03928 ? v/12.92 : ((v+0.055)/1.055) ** 2.4; });
    return 0.2126*r + 0.7152*g + 0.0722*b;
  };
  const parse = (s) => (s.match(/[\d.]+/g) || []).slice(0,3).map(Number);
  // Walk up for the first non-transparent background — that is what the text
  // is really sitting on.
  const behind = (el) => {
    for (let n = el; n; n = n.parentElement) {
      const cs = getComputedStyle(n);
      // A gradient cannot be reduced to one colour, so stop rather than walk
      // past it and measure against something that is not there.
      if (cs.backgroundImage && cs.backgroundImage !== 'none') return null;
      const bg = cs.backgroundColor;
      const a = (bg.match(/[\d.]+/g) || [])[3];
      if (bg && bg !== 'transparent' && a !== '0') return parse(bg);
    }
    return [255,255,255];
  };
  const ratio = (a,b) => { const [x,y] = [lum(a), lum(b)].sort((m,n)=>n-m); return (x+0.05)/(y+0.05); };

  const bad = [], small = [];
  for (const el of document.querySelectorAll('main *, .topbar *')) {
    const text = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
    if (!text) continue;
    const cs = getComputedStyle(el);
    if (cs.visibility === 'hidden' || cs.display === 'none' || cs.opacity === '0') continue;
    const box = el.getBoundingClientRect();
    if (!box.width || !box.height) continue;
    const size = parseFloat(cs.fontSize);
    const heavy = parseInt(cs.fontWeight, 10) >= 700;
    const need = (size >= 24 || (size >= 18.66 && heavy)) ? 3 : 4.5;
    const bg = behind(el);
    if (!bg) continue;
    const r = ratio(parse(cs.color), bg);
    if (r < need) bad.push({ t: el.textContent.trim().slice(0,32), r: +r.toFixed(2), need, size });
  }
  for (const el of document.querySelectorAll('main button, main a, main input, main select, .topbar button, .topbar a')) {
    const b = el.getBoundingClientRect();
    if (b.width && b.height < 44 && b.height > 0) small.push({ t: (el.textContent||el.getAttribute('aria-label')||'').trim().slice(0,24), h: Math.round(b.height) });
  }
  return JSON.stringify({
    overflow: document.documentElement.scrollWidth > window.innerWidth + 1,
    scrollW: document.documentElement.scrollWidth,
    innerW: window.innerWidth,
    bad: bad.slice(0, 6),
    small: small.slice(0, 6),
  });
})()
"""

# Paths to walk, one per line. Ids are local, so this is not committed with
# any: pass a file, or pipe them in.
paths = [p.strip() for p in open(sys.argv[1]) if p.strip() and not p.startswith("#")]
EMAIL = os.environ.get("FISHERS_EMAIL", "demo@fishers.test")
PASSWORD = os.environ.get("FISHERS_PASSWORD", "password123")
API = os.environ.get("FISHERS_API", "http://localhost:7312")

t = Tab()
t.goto("/login")
t.js(f"const API={API!r}, EMAIL={EMAIL!r}, PASSWORD={PASSWORD!r};")
t.js("""(async () => {
  const r = await fetch(API + '/api/v1/auth/login', {method:'POST',
    headers:{'content-type':'application/json'},
    body: JSON.stringify({email: EMAIL, password: PASSWORD})});
  const d = await r.json();
  localStorage.setItem('fishers_access_token', d.access_token);
  localStorage.setItem('fishers_refresh_token', d.refresh_token);
  localStorage.setItem('fishers_user', JSON.stringify(d.user));})()""")
time.sleep(1.5)

for theme, w, h, mobile in (("light", 390, 844, True), ("dark", 390, 844, True), ("dark", 1280, 900, False)):
    t.js(f"localStorage.setItem('fishers_theme','{theme}')")
    t.send("Emulation.setDeviceMetricsOverride", width=w, height=h, deviceScaleFactor=2, mobile=mobile)
    # `pointer: coarse` only matches with touch emulation on, and the 44px
    # minimums are written behind that query — without this the audit checks a
    # phone-sized mouse.
    t.send("Emulation.setTouchEmulationEnabled", enabled=mobile, maxTouchPoints=5 if mobile else 0)
    print(f"\n=== {theme} @ {w}px ===")
    for path in paths:
        t.goto(path)
        time.sleep(2.2)
        try:
            out = json.loads(t.js(PROBE) or "{}")
        except Exception as e:
            print(f"  {path:52} PROBE FAILED {e}")
            continue
        flags = []
        if out.get("overflow"):
            flags.append(f"OVERFLOW {out['scrollW']}>{out['innerW']}")
        if out.get("bad"):
            flags.append("CONTRAST " + "; ".join(f"{b['t']!r} {b['r']}<{b['need']}" for b in out["bad"]))
        if out.get("small"):
            flags.append("TAP " + "; ".join(f"{s['t']!r} {s['h']}px" for s in out["small"]))
        print(f"  {path:52} {' | '.join(flags) if flags else 'ok'}")
