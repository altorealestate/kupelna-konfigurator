"""
Visual checks for the bathroom configurator demo (PRAVIDLA.md, steps 2-4). Free: no kie.ai
calls and nothing in the project is changed. Sheets go to vystupy\\kontrola\\<time>\\.

  python demo\\kontrola.py generacia <id> [<id> ...]      (wildcards, or --posledne N)
      A generation against its input: for every checklist area an input | result |
      difference crop with a score. Areas outside the task's category that changed
      are marked "!" and come first.
  python demo\\kontrola.py zostava [-k baterie] [--oblast doplnky-vaza] [--vyber dlazba=dlazba-amani]
      The assembled demo, composed from demo\\img exactly like the page: every option of
      a category on every wall cladding, cropped to each of its areas.
  python demo\\kontrola.py stranka [--url https://...] [--vyber obklad=obklad-graphit]
      Screenshots of the page at desktop and phone width, broken images, console errors,
      and whether every image the page references exists (file) or returns HTTP 200 (url).
"""
import argparse
import fnmatch
import json
import re
import sys
import time
from pathlib import Path
from urllib.parse import urljoin

import cv2
import numpy as np

DEMO = Path(__file__).resolve().parent
ROOT = DEMO.parent
CFG = json.loads((DEMO / 'varianty.json').read_text(encoding='utf-8'))
W, H = int(CFG['sirka']), int(CFG['vyska'])

# Checklist areas (PRAVIDLA.md, step 2): relative rectangles x0, y0, x1, y1 of the base frame.
AREAS = {
    'doplnky-vaza': (0.35, 0.42, 0.445, 0.67),
    'doplnky-mydlo': (0.565, 0.575, 0.64, 0.67),
    'umyvadlo-polica': (0.34, 0.56, 0.66, 0.70),
    'bateria-umyvadlo': (0.46, 0.46, 0.54, 0.66),
    'sifon': (0.46, 0.68, 0.54, 0.78),
    'sprcha': (0.17, 0.20, 0.31, 0.72),
    'vana-baterie': (0.68, 0.57, 0.80, 0.84),
    'prepad-vane': (0.88, 0.75, 0.94, 0.83),
    'zastena-vzpera': (0.06, 0.12, 0.34, 0.165),
    'zlab-pas': (0.14, 0.82, 0.34, 0.90),
    'zrkadlo': (0.37, 0.23, 0.63, 0.57),
    'strop': (0.15, 0.0, 0.85, 0.12),
    'stolicka': (0.52, 0.75, 0.67, 0.98),
}
# An area outside the task's category is flagged above these: % of pixels differing by more
# than 25 (0-255, after a light blur; the mean difference also grows with a mere change of
# tone) and % of the input's edges with no edge in the result within 4 px.
SHARE_LIMIT = 10.0
LOST_LIMIT = 30.0


# --- Images ----------------------------------------------------------------------------
# cv2.imread/imwrite cannot open paths with diacritics on Windows ("Pracovná", "Kupelňa").

def read_img(path):
    img = cv2.imdecode(np.fromfile(str(path), np.uint8), cv2.IMREAD_UNCHANGED)
    if img is None:
        raise SystemExit(f'Cannot read {path}')
    return img


def write_jpg(path, img, quality=88):
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imencode('.jpg', img, [cv2.IMWRITE_JPEG_QUALITY, quality])[1].tofile(str(path))
    return path


def bgr(img):
    if img.ndim == 2:
        return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    return img[:, :, :3]


def load_input(rel):
    """A task input or the base photo, stretched to the base frame (Obr.Nacitaj mode 0)."""
    img = bgr(read_img(ROOT / rel))
    if img.shape[:2] != (H, W):
        img = cv2.resize(img, (W, H), interpolation=cv2.INTER_AREA)
    return img


def load_aligned(rel, t):
    """A result moved into the base frame like Obr.NacitajZarovnane: base pixel u maps to
    (u - W/2) * sx + W/2 + dx in the result stretched to W x H."""
    img = bgr(read_img(ROOT / rel))
    kx, ky = img.shape[1] / W, img.shape[0] / H
    sx, sy, dx, dy = t
    m = np.array([[sx * kx, 0, (W / 2 * (1 - sx) + dx + 0.5 * sx) * kx - 0.5],
                  [0, sy * ky, (H / 2 * (1 - sy) + dy + 0.5 * sy) * ky - 0.5]])
    return cv2.warpAffine(img, m, (W, H), flags=cv2.INTER_CUBIC | cv2.WARP_INVERSE_MAP,
                          borderMode=cv2.BORDER_REFLECT)


def px(rect, pad=0.0):
    x0, y0, x1, y1 = rect
    return (max(0, int((x0 - pad) * W)), max(0, int((y0 - pad) * H)),
            min(W, round((x1 + pad) * W)), min(H, round((y1 + pad) * H)))


def crop(img, rect, pad=0.0):
    x0, y0, x1, y1 = px(rect, pad)
    return img[y0:y1, x0:x1]


def quads(roi):
    return [tuple(roi[i:i + 4]) for i in range(0, len(roi), 4)]


def overlaps(a, b):
    return min(a[2], b[2]) > max(a[0], b[0]) and min(a[3], b[3]) > max(a[1], b[1])


# --- Sheets ----------------------------------------------------------------------------

def tile(img, text, tw, th):
    """img fitted into tw x th (upscaled when small, so details are visible) under a label."""
    s = min(tw / img.shape[1], th / img.shape[0])
    size = (max(1, round(img.shape[1] * s)), max(1, round(img.shape[0] * s)))
    fit = cv2.resize(img, size, interpolation=cv2.INTER_AREA if s < 1 else cv2.INTER_CUBIC)
    canvas = np.full((th + 24, tw, 3), 255, np.uint8)
    y, x = 24 + (th - size[1]) // 2, (tw - size[0]) // 2
    canvas[y:y + size[1], x:x + size[0]] = fit
    cv2.putText(canvas, text, (4, 17), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 0), 1, cv2.LINE_AA)
    return canvas


def tile_size(rect, area, max_w, max_h):
    """A tile of about `area` pixels with the rectangle's aspect, at most max_w x max_h."""
    aspect = (rect[2] - rect[0]) * W / ((rect[3] - rect[1]) * H)
    tw = min(max_w, (area * aspect) ** 0.5, max_h * aspect)
    return int(tw), int(tw / aspect)


def join(images, axis, gap=8):
    """Stacks images side by side (axis 1) or below each other (axis 0) on white."""
    other = 1 - axis
    size = max(i.shape[other] for i in images)
    out = []
    for i in images:
        pad = [(0, 0), (0, 0), (0, 0)]
        pad[other] = (0, size - i.shape[other])
        out.append(np.pad(i, pad, constant_values=255))
        gap_shape = [0, 0, 3]
        gap_shape[axis], gap_shape[other] = gap, size
        out.append(np.full(gap_shape, 255, np.uint8))
    return np.concatenate(out[:-1], axis=axis)


def heat(d):
    return cv2.applyColorMap(np.clip(d.astype(np.float32) * 4, 0, 255).astype(np.uint8), cv2.COLORMAP_INFERNO)


def out_dir():
    d = ROOT / 'vystupy' / 'kontrola' / time.strftime('%Y%m%d-%H%M%S')
    d.mkdir(parents=True, exist_ok=True)
    return d


def safe(name):
    return re.sub(r'[^\w.@-]', '_', name)


def rel(path):
    return str(Path(path).relative_to(ROOT))


# --- generacia -------------------------------------------------------------------------

def changed_rects(tid):
    """ROI rectangles the task is meant to change, or None for the whole image (claddings)."""
    base = re.split('[@#]', tid)[0]
    acc = CFG.get('doplnky') or {}
    if base in (acc.get('prazdny'), acc.get('kluc')):
        return quads(acc['roi'])
    item = next((v for v in CFG['varianty'] + CFG.get('pomocne', []) if v['id'] == base), {})
    for k in CFG['kategorie']:
        if k['id'] == item.get('kategoria') or base in (k.get('prazdny'), k.get('kluc'), k.get('stary')):
            return quads(k['roi']) if k.get('roi') else None
    return None


def metrics(a, b):
    ga, gb = cv2.GaussianBlur(a, (0, 0), 1.5), cv2.GaussianBlur(b, (0, 0), 1.5)
    d = cv2.absdiff(ga, gb).max(axis=2)
    ea = cv2.Canny(cv2.cvtColor(ga, cv2.COLOR_BGR2GRAY), 40, 100) > 0
    eb = cv2.dilate(cv2.Canny(cv2.cvtColor(gb, cv2.COLOR_BGR2GRAY), 40, 100), np.ones((9, 9), np.uint8)) > 0
    n = int(ea.sum())
    lost = float((ea & ~eb).sum() / n * 100) if n > 50 else 0.0
    return d, float(d.mean()), float((d > 25).mean() * 100), lost


def cmd_generacia(args):
    results = json.loads((DEMO / 'vysledky.json').read_text(encoding='utf-8'))
    ids = []
    if args.posledne:
        ids = sorted(results, key=lambda k: Path(results[k]['subor']).name, reverse=True)[:args.posledne]
    for pat in args.ids:
        hits = [k for k in results if fnmatch.fnmatchcase(k, pat)]
        if not hits:
            print(f'No result matches {pat}')
        ids += [h for h in hits if h not in ids]
    if not ids:
        raise SystemExit('Nothing to check: give result ids (wildcards ok) or --posledne N.')
    names = args.oblast or list(AREAS)
    out = out_dir()
    print('Legend: ! changed outside the task area, ~ inside it (change expected), '
          'diff = mean difference 0-255, edges = input edges missing in the result')
    for tid in ids:
        r = results[tid]
        ref_rel = CFG['podklad'] if args.voci_povodnemu else r['vstup']
        ref = load_input(ref_rel)
        img = load_aligned(r['subor'], r['zarovnanie'])
        task_rects = changed_rects(tid)
        rows = []
        for name in names:
            a, b = crop(ref, AREAS[name]), crop(img, AREAS[name])
            d, mean, share, lost = metrics(a, b)
            expected = task_rects is None or any(overlaps(AREAS[name], q) for q in task_rects)
            flag = not expected and (share > SHARE_LIMIT or lost > LOST_LIMIT)
            rows.append(dict(name=name, a=a, b=b, d=d, mean=mean, share=share, lost=lost,
                             mark='!' if flag else '~' if expected else ' '))
        rows.sort(key=lambda x: ('!~ '.index(x['mark']), -x['lost']))

        print(f"\n{tid}: {r['subor']}  (against {ref_rel}, match {r.get('zhoda')})")
        print(f"    {'area':<16} {'diff':>5} {'>25':>5} {'edges':>6}")
        for x in rows:
            print(f"  {x['mark']} {x['name']:<16} {x['mean']:5.1f} {x['share']:4.0f}% {x['lost']:5.0f}%")
        sheets = []
        for p in range(0, len(rows), args.na_stranu):
            lines = []
            for x in rows[p:p + args.na_stranu]:
                tw, th = tile_size(AREAS[x['name']], 210000, 560, 600)
                lines.append(join([
                    tile(x['a'], f"{x['mark']} {x['name']}  input", tw, th),
                    tile(x['b'], f"result  diff {x['mean']:.1f}  edges -{x['lost']:.0f}%", tw, th),
                    tile(heat(x['d']), 'difference x4', tw, th)], 1))
            sheets.append(write_jpg(out / f'{safe(tid)}-{p // args.na_stranu + 1}.jpg', join(lines, 0, 14)))
        print('  sheets: ' + ', '.join(rel(s) for s in sheets))


# --- zostava ---------------------------------------------------------------------------

def page_data():
    html = (DEMO / 'index.html').read_text(encoding='utf-8')
    m = re.search(r'/\*DATA\*/window\.KUPELNA = (.*?);/\*/DATA\*/', html, re.S)
    if not m:
        raise SystemExit('index.html has no data block, run demo\\zostav.ps1 first.')
    return json.loads(m.group(1))


def as_list(v):
    return [v] if isinstance(v, dict) else v


class Composer:
    """Composes a selection from demo\\img exactly like index.html does."""

    def __init__(self, data):
        self.data = data
        self.cats = data['kategorie']
        self.plate_cat = next(c for c in self.cats if c['typ'] == 'podklad')
        self.layer_cats = sorted((c for c in self.cats if c['typ'] != 'podklad'), key=lambda c: c['z'])
        self.cache = {}

    def image(self, src):
        if src not in self.cache:
            self.cache[src] = read_img(DEMO / src)
        return self.cache[src]

    @staticmethod
    def option(cat, oid):
        return next(o for o in cat['moznosti'] if o['id'] == oid)

    def compose(self, sel):
        plate = sel.get(self.plate_cat['id'], 'povodny')
        o = self.option(self.plate_cat, plate)
        out = bgr(self.image(self.data['povodny'] if plate == 'povodny' else o['obrazok'])).astype(np.float32)
        for c in self.layer_cats:
            layers = self.option(c, sel.get(c['id'], 'povodny')).get('vrstvy') or {}
            # Like the page: o.vrstvy[plate] || o.vrstvy['*'] || [] (an empty list counts).
            pieces = layers.get(plate)
            if pieces is None:
                pieces = layers.get('*') or []
            for p in as_list(pieces):
                img = self.image(p['src'])
                x, y, w, h = int(p['x']), int(p['y']), int(p['w']), int(p['h'])
                if img.shape[:2] != (h, w):
                    img = cv2.resize(img, (w, h), interpolation=cv2.INTER_AREA)
                a = img[:, :, 3:4].astype(np.float32) / 255 if img.shape[2] == 4 else 1.0
                region = out[y:y + h, x:x + w]
                region[:] = region * (1 - a) + img[:, :, :3] * a
        return out.astype(np.uint8)


def parse_sel(items):
    sel = {}
    for item in items or []:
        for part in item.split(','):
            if part:
                k, _, v = part.partition('=')
                sel[k.strip()] = v.strip()
    return sel


def short(oid):
    return oid.split('-', 1)[1] if '-' in oid else oid


def cmd_zostava(args):
    comp = Composer(page_data())
    sel = parse_sel(args.vyber)
    plate_id = comp.plate_cat['id']
    plates = [o['id'] for o in comp.plate_cat['moznosti']]
    kats = args.k or [c['id'] for c in comp.layer_cats]
    out = out_dir()
    for kid in kats:
        cat = next((c for c in comp.cats if c['id'] == kid), None)
        if cat is None:
            raise SystemExit(f'Unknown category {kid}')
        if cat['typ'] == 'podklad':
            # Rows = checklist areas, columns = claddings.
            names = args.oblast or list(AREAS)
            full = {pl: comp.compose({**sel, plate_id: pl}) for pl in plates}
            lines = []
            for name in names:
                tw, th = tile_size(AREAS[name], 120000, 400, 480)
                lines.append(join([tile(crop(full[pl], AREAS[name], 0.01), f'{name} | {short(pl)}', tw, th)
                                   for pl in plates], 1))
            for p in range(0, len(lines), 4):
                f = write_jpg(out / f'zostava-{kid}-{p // 4 + 1}.jpg', join(lines[p:p + 4], 0, 14))
                print(rel(f))
            continue
        # Rows = options of the category, columns = claddings; one sheet per area.
        src_cat = next(k for k in CFG['kategorie'] if k['id'] == kid)
        regions = [(n, AREAS[n]) for n in args.oblast] if args.oblast else \
            [(f'{kid}-{i}', q) for i, q in enumerate(quads(src_cat['roi']))]
        crops = {}
        for o in cat['moznosti']:
            for pl in plates:
                full = comp.compose({**sel, kid: o['id'], plate_id: pl})
                for name, q in regions:
                    crops[name, o['id'], pl] = crop(full, q, 0.01)
        for name, q in regions:
            tw, th = tile_size(q, 120000, 400, 480)
            lines = [join([tile(crops[name, o['id'], pl], f"{short(o['id'])} | {short(pl)}", tw, th)
                           for pl in plates], 1) for o in cat['moznosti']]
            f = write_jpg(out / f'zostava-{safe(name)}.jpg', join(lines, 0, 14))
            print(rel(f))


# --- stranka ---------------------------------------------------------------------------

# Shown stage images and swatches (made eager first) have finished loading.
JS_READY = """() => [...document.images].filter(i => i.getAttribute('src') &&
  (!i.closest('#stage') || i.classList.contains('on') || i.classList.contains('base'))).every(i => i.complete)"""
JS_BROKEN = """() => [...document.images].filter(i => i.getAttribute('src') && i.complete && i.naturalWidth === 0)
  .map(i => i.getAttribute('src'))"""
JS_ALL_SRCS = """() => { const D = window.KUPELNA, s = new Set([D.povodny]);
  for (const c of D.kategorie) for (const o of c.moznosti) {
    if (o.obrazok) s.add(o.obrazok); if (o.nahlad) s.add(o.nahlad);
    for (const l of Object.values(o.vrstvy || {})) for (const p of [].concat(l)) s.add(p.src); }
  return [...s]; }"""


def cmd_stranka(args):
    from playwright.sync_api import sync_playwright
    url = args.url or (DEMO / 'index.html').as_uri()
    sel = parse_sel(args.vyber)
    out = out_dir()
    problems = []
    with sync_playwright() as p:
        browser = p.chromium.launch(channel='msedge')
        srcs, final_url = [], url
        for width in args.sirky:
            page = browser.new_page(viewport={'width': width, 'height': 900 if width > 700 else 844})
            errors = []
            page.on('console', lambda m: m.type == 'error' and errors.append(f'console: {m.text}'))
            page.on('pageerror', lambda e: errors.append(f'page error: {e}'))
            page.on('requestfailed', lambda r: errors.append(f'request failed: {r.url} ({r.failure})'))
            page.on('response', lambda r: r.status >= 400 and errors.append(f'HTTP {r.status}: {r.url}'))
            page.goto(url, wait_until='load')
            # The site root redirects to demo/ only after it has loaded.
            page.wait_for_selector('#board .chip', timeout=60000)
            page.wait_for_load_state('load')
            page.evaluate("() => document.querySelectorAll('img[loading=lazy]').forEach(i => i.loading = 'eager')")
            for cat, oid in sel.items():
                page.click(f'label[for="o-{cat}-{oid}"]')
            page.wait_for_function(JS_READY, timeout=120000)
            page.wait_for_timeout(300)
            shot = out / f'stranka-{width}.png'
            page.screenshot(path=str(shot), full_page=True)
            broken = page.evaluate(JS_BROKEN)
            if not srcs:
                srcs, final_url = page.evaluate(JS_ALL_SRCS), page.url
            print(f'{width} px: {rel(shot)}')
            for e in errors + [f'broken image: {b}' for b in broken]:
                print(f'  {e}')
                problems.append(e)
            page.close()
        # Every image the page may show, not only the ones the screenshots loaded.
        missing = []
        if final_url.startswith('http'):
            ctx = browser.new_context()
            for s in srcs:
                status = ctx.request.head(urljoin(final_url, s)).status
                if status != 200:
                    missing.append(f'HTTP {status}: {s}')
            ctx.close()
        else:
            missing = [f'missing file: {s}' for s in srcs if not (DEMO / s).is_file()]
        browser.close()
    for m in missing:
        print(f'  {m}')
    print(f'{len(srcs)} referenced images checked, {len(missing)} missing; {len(problems)} page problem(s).')
    if missing or problems:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('generacia', help='a generation against its input, per checklist area')
    g.add_argument('ids', nargs='*', help='result ids from vysledky.json, wildcards ok')
    g.add_argument('--posledne', type=int, default=0, help='the N most recent results')
    g.add_argument('--oblast', nargs='+', choices=list(AREAS), help='only these areas')
    g.add_argument('--voci-povodnemu', action='store_true', help='compare with the base photo, not the task input')
    g.add_argument('--na-stranu', type=int, default=4, help='areas per sheet')
    z = sub.add_parser('zostava', help='every option of a category on every cladding, like the page')
    z.add_argument('-k', nargs='+', help='categories (default: all layer categories; obklad = areas x claddings)')
    z.add_argument('--oblast', nargs='+', choices=list(AREAS), help='crop these areas instead of the category ROI')
    z.add_argument('--vyber', nargs='+', help='fixed options of other categories, e.g. dlazba=dlazba-amani')
    s = sub.add_parser('stranka', help='screenshots, broken images, HTTP status of every image')
    s.add_argument('--url', help='default: demo\\index.html as a file')
    s.add_argument('--vyber', nargs='+', help='options to select, e.g. obklad=obklad-graphit baterie=baterie-black')
    s.add_argument('--sirky', nargs='+', type=int, default=[1440, 390], help='viewport widths')
    args = ap.parse_args()
    {'generacia': cmd_generacia, 'zostava': cmd_zostava, 'stranka': cmd_stranka}[args.cmd](args)


if __name__ == '__main__':
    main()
