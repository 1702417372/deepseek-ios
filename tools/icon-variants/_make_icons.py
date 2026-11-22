# -*- coding: utf-8 -*-
"""Generate original "little chubby fish" iOS app icons in 3 styles.

Pure Pillow drawing (no external assets, no emoji fonts).
Supersampled 3x, outputs 1024 RGB + 120/60 previews + compare sheet.
"""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

OUT = r"D:\39945\文档\deepseek-harness\default-workspace\deepseek-clone\tools\icon-variants"
SIZE = 1024
SS = 3
W = SIZE * SS

# ---------------------------------------------------------------- helpers
def S(v):
    return int(round(v * SS))

def B(box):
    return tuple(S(v) for v in box)

def P(pts):
    return [(S(x), S(y)) for x, y in pts]

def rgba(hexstr, a=255):
    hexstr = hexstr.lstrip('#')
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16), a)

def mix(c1, c2, t):
    return tuple(int(round(c1[i] * (1 - t) + c2[i] * t)) for i in range(3))

def vertical_gradient(top, bottom, xmix=0.0):
    yy, xx = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32)
    t = yy / (SIZE - 1)
    if xmix:
        t = (1 - xmix) * t + xmix * (xx / (SIZE - 1))
    top = np.array(top, dtype=np.float32)
    bottom = np.array(bottom, dtype=np.float32)
    arr = top[None, None, :] * (1 - t[..., None]) + bottom[None, None, :] * t[..., None]
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), 'RGB')
    return im.resize((W, W), Image.BICUBIC).convert('RGBA')

def new_layer():
    return Image.new('RGBA', (W, W), (0, 0, 0, 0))

def soft_ellipse(img, box, color, blur):
    # Blur the alpha mask only; blurring straight RGBA creates gray fringes
    # because the transparent pixels are black and un-premultiplied.
    mask = Image.new('L', (W, W), 0)
    ImageDraw.Draw(mask).ellipse(B(box), fill=color[3])
    mask = mask.filter(ImageFilter.GaussianBlur(S(blur)))
    layer = Image.new('RGBA', (W, W), (color[0], color[1], color[2], 0))
    layer.putalpha(mask)
    img.alpha_composite(layer)

def ellipse(d, box, fill=None, outline=None, width=0):
    d.ellipse(B(box), fill=fill, outline=outline, width=S(width) if width else 0)

def qbez(p0, c, p1, n=30):
    out = []
    for i in range(1, n + 1):
        t = i / n
        out.append((
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t * t * p1[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t * t * p1[1],
        ))
    return out

def path_points(segs, n=30):
    pts = []
    cur = None
    for seg in segs:
        if seg[0] == 'M':
            cur = seg[1]
            pts.append(cur)
        elif seg[0] == 'Q':
            c, p = seg[1], seg[2]
            pts.extend(qbez(cur, c, p, n))
            cur = p
        elif seg[0] == 'L':
            cur = seg[1]
            pts.append(cur)
    return pts

def draw_closed_path(layer, segs, fill, outline, width, n=30):
    pts = path_points(segs, n)
    d = ImageDraw.Draw(layer)
    d.polygon(P(pts), fill=fill)
    if outline and width:
        d.line(P(pts + [pts[0]]), fill=outline, width=S(width), joint='curve')

def clipped_paint(base, mask, paint):
    layer = new_layer()
    paint(ImageDraw.Draw(layer))
    a = ImageChops.multiply(layer.getchannel('A'), mask)
    layer.putalpha(a)
    base.alpha_composite(layer)

# ---------------------------------------------------------------- fish geometry (1024 space)
BODY = (165, 270, 805, 805)
BODY_C = ((BODY[0] + BODY[2]) / 2, (BODY[1] + BODY[3]) / 2)
TAIL = [
    ('M', (768, 520)),
    ('Q', (820, 456), (880, 424)),
    ('Q', (906, 446), (895, 502)),
    ('Q', (884, 534), (858, 552)),
    ('Q', (886, 582), (898, 637)),
    ('Q', (902, 682), (872, 688)),
    ('Q', (812, 680), (762, 628)),
]
DORSAL = [
    ('M', (570, 318)),
    ('Q', (600, 250), (646, 216)),
    ('Q', (694, 224), (726, 320)),
    ('L', (726, 332)),
    ('L', (570, 332)),
]
PECTORAL = [
    ('M', (250, 680)),
    ('Q', (188, 700), (150, 740)),
    ('Q', (134, 762), (154, 780)),
    ('Q', (192, 792), (246, 775)),
    ('Q', (300, 757), (332, 735)),
    ('Q', (292, 706), (250, 680)),
]
EYE = (308, 402, 436, 542)          # ellipse box
EYE_C = (372, 472)
IRIS_C = (366, 482)
IRIS_R = 50
BLUSH = (244, 548, 344, 612)
MOUTH = (300, 590, 388, 654)

# ---------------------------------------------------------------- style definitions
STYLES = {
    'A': dict(
        title='Brand Blue',
        bg_top=(42, 62, 177), bg_bottom=(77, 107, 254), bg_xmix=0.22,
        body=rgba('FFF2D8'), body_hi=(255, 255, 255, 30), body_sh=(28, 43, 120, 26),
        belly=rgba('FFFBF0'), belly_top=560,
        outline=rgba('16245F'), fin=rgba('F7E1B9'), fin_outline=rgba('16245F'),
        eye_sclera=rgba('FFFDF6'), eye=rgba('13205C'), eye_rim=None,
        eye_hl=rgba('FFFFFF'), blush=rgba('F28F80', 238), blush_hi=(255, 210, 196, 100),
        mouth=rgba('16245F'), bubble_outline=rgba('FFF4DC', 235), bubble_fill=(255, 250, 235, 26),
        glow=None, eye_glow=None, body_shade=0.35,
    ),
    'B': dict(
        title='Cream Blue',
        bg_top=(234, 242, 255), bg_bottom=(214, 230, 255), bg_xmix=0.05,
        body=rgba('4D9BFF'), body_hi=(255, 255, 255, 46), body_sh=(24, 66, 160, 32),
        belly=rgba('FFFFFF'), belly_top=545,
        outline=rgba('123475'), fin=rgba('FF9A3D'), fin_outline=rgba('123475'),
        eye_sclera=rgba('FFFFFF'), eye=rgba('12306B'), eye_rim=None,
        eye_hl=rgba('FFFFFF'), blush=rgba('FF8A78', 240), blush_hi=(255, 205, 190, 120),
        mouth=rgba('12306B'), bubble_outline=rgba('8FB8FF', 245), bubble_fill=(255, 255, 255, 120),
        glow=None, eye_glow=None, body_shade=0.55,
    ),
    'C': dict(
        title='Deep Glow',
        bg_top=(11, 18, 48), bg_bottom=(18, 32, 74), bg_xmix=0.08,
        body=rgba('2FC9D6'), body_hi=(190, 255, 255, 40), body_sh=(6, 45, 70, 46),
        belly=rgba('C8FAF2'), belly_top=558,
        outline=rgba('06303F'), fin=rgba('51DCDD'), fin_outline=rgba('06303F'),
        eye_sclera=rgba('DFFFFA'), eye=rgba('063845'), eye_rim=rgba('71EEF5'),
        eye_hl=rgba('FFFFFF'), blush=rgba('FF8FA6', 235), blush_hi=(255, 205, 214, 120),
        mouth=rgba('052A37'), bubble_outline=rgba('7FF7FF', 240), bubble_fill=(90, 235, 245, 42),
        glow=rgba('39E5F0'), eye_glow=rgba('6FF4FF'), body_shade=0.48,
    ),
}

# ---------------------------------------------------------------- background
def make_background(key):
    st = STYLES[key]
    img = vertical_gradient(st['bg_top'], st['bg_bottom'], st['bg_xmix'])
    if key == 'A':
        soft_ellipse(img, (30, -80, 560, 470), (122, 152, 255, 58), 110)
        soft_ellipse(img, (560, 650, 1090, 1160), (20, 38, 135, 42), 130)
        soft_ellipse(img, (400, 80, 960, 560), (116, 164, 255, 26), 150)
    elif key == 'B':
        soft_ellipse(img, (-130, -170, 420, 330), (255, 255, 255, 95), 110)
        soft_ellipse(img, (680, 650, 1180, 1120), (255, 255, 255, 78), 120)
        soft_ellipse(img, (620, -180, 1160, 300), (255, 255, 255, 66), 120)
        soft_ellipse(img, (-180, 690, 320, 1180), (255, 255, 255, 66), 120)
        layer = new_layer()
        d = ImageDraw.Draw(layer)
        for x, y, r in ((120, 720, 3), (896, 166, 4), (930, 620, 3), (80, 390, 3), (760, 920, 3), (105, 130, 2)):
            d.ellipse(B((x - r, y - r, x + r, y + r)), fill=(255, 255, 255, 190))
        img.alpha_composite(layer)
    else:
        soft_ellipse(img, (210, 180, 810, 880), (44, 226, 238, 62), 120)
        soft_ellipse(img, (600, 120, 1000, 520), (36, 130, 220, 26), 130)
        layer = new_layer()
        d = ImageDraw.Draw(layer)
        stars = [(134, 186, 2.6, 180), (858, 158, 2.2, 170), (918, 336, 2.0, 140),
                 (150, 760, 2.2, 150), (84, 500, 1.8, 120), (878, 760, 2.6, 160),
                 (760, 112, 1.8, 130), (404, 104, 1.8, 120), (956, 626, 1.8, 120),
                 (72, 268, 1.8, 130), (822, 884, 2.0, 140), (112, 906, 2.0, 130),
                 (932, 458, 1.6, 105), (558, 94, 1.6, 110)]
        for x, y, r, a in stars:
            d.ellipse(B((x - r, y - r, x + r, y + r)), fill=(180, 245, 255, a))
        d.ellipse(B((250, 110, 286, 146)), outline=(140, 240, 255, 90), width=S(2))
        img.alpha_composite(layer)
    return img

# ---------------------------------------------------------------- drawing
def build_fish(key):
    st = STYLES[key]
    img = make_background(key)
    body_mask = Image.new('L', (W, W), 0)
    ImageDraw.Draw(body_mask).ellipse(B(BODY), fill=255)

    # C: soft aura around whole silhouette
    if st['glow']:
        sil = Image.new('L', (W, W), 0)
        sd = ImageDraw.Draw(sil)
        sd.polygon(P(path_points(TAIL)), fill=255)
        sd.polygon(P(path_points(DORSAL)), fill=255)
        sd.ellipse(B(BODY), fill=255)
        sd.polygon(P(path_points(PECTORAL)), fill=255)
        glow = st['glow']
        aura = Image.new('RGBA', (W, W), (glow[0], glow[1], glow[2], 0))
        blurred = sil.filter(ImageFilter.GaussianBlur(S(24)))
        aura.putalpha(blurred.point(lambda v: int(v * 0.43)))
        img.alpha_composite(aura)
        aura2 = Image.new('RGBA', (W, W), (glow[0], glow[1], glow[2], 0))
        b2 = sil.filter(ImageFilter.GaussianBlur(S(8)))
        aura2.putalpha(b2.point(lambda v: int(v * 0.20)))
        img.alpha_composite(aura2)

    # tail + fins behind body (fin attaches under the body silhouette)
    draw_closed_path(img, TAIL, st['fin'], st['fin_outline'], 16)
    draw_closed_path(img, DORSAL, st['fin'], st['fin_outline'], 15)
    draw_closed_path(img, PECTORAL, st['fin'], st['fin_outline'], 13)

    # body
    d = ImageDraw.Draw(img)
    ellipse(d, BODY, fill=st['body'])
    # clipped body shading
    def shade(dd):
        dd.ellipse(B((150, 360, 820, 950)), fill=st['body_sh'])
        dd.ellipse(B((150, 230, 720, 560)), fill=st['body_hi'])
    clipped_paint(img, body_mask, shade)
    # belly
    belly = (242, st['belly_top'], 790, 930)
    def paint_belly(dd):
        dd.ellipse(B(belly), fill=st['belly'])
    clipped_paint(img, body_mask, paint_belly)
    # body outline last, over belly
    d = ImageDraw.Draw(img)
    ellipse(d, BODY, outline=st['outline'], width=18)

    # C eye aura
    if st['eye_glow']:
        soft_ellipse(img, (282, 374, 466, 570), (st['eye_glow'][0], st['eye_glow'][1], st['eye_glow'][2], 78), 20)

    # blush
    blush_layer = new_layer()
    bd = ImageDraw.Draw(blush_layer)
    bd.ellipse(B(BLUSH), fill=st['blush'])
    img.alpha_composite(blush_layer)
    # blush highlight
    hl = new_layer()
    hd = ImageDraw.Draw(hl)
    hd.ellipse(B((258, 558, 310, 588)), fill=st['blush_hi'])
    img.alpha_composite(hl)

    # eye
    eye_layer = new_layer()
    ed = ImageDraw.Draw(eye_layer)
    ellipse(ed, EYE, fill=st['eye_sclera'])
    if st['eye_rim']:
        ellipse(ed, EYE, outline=st['eye_rim'], width=3)
    ellipse(ed, EYE, outline=st['outline'], width=8)
    iris_box = (IRIS_C[0] - IRIS_R, IRIS_C[1] - IRIS_R, IRIS_C[0] + IRIS_R, IRIS_C[1] + IRIS_R)
    ellipse(ed, iris_box, fill=st['eye'])
    if st['eye_rim']:
        ellipse(ed, iris_box, outline=st['eye_rim'], width=4)
    # highlights
    ed.ellipse(B((331, 442, 365, 476)), fill=st['eye_hl'])
    ed.ellipse(B((381, 502, 395, 516)), fill=st['eye_hl'])
    ed.ellipse(B((374, 450, 384, 460)), fill=(255, 255, 255, 220))
    img.alpha_composite(eye_layer)

    # smile: simple smooth U with round caps
    mouth_layer = new_layer()
    md = ImageDraw.Draw(mouth_layer)
    m0, mc, m1 = (304, 618), (348, 663), (392, 618)
    mpts = [(m0[0], m0[1])] + qbez(m0, mc, m1, 36) + [(m1[0], m1[1])]
    md.line(P(mpts), fill=st['mouth'], width=S(12), joint='curve')
    for cx, cy in (m0, m1):
        md.ellipse(B((cx - 6, cy - 6, cx + 6, cy + 6)), fill=st['mouth'])
    img.alpha_composite(mouth_layer)

    # bubbles
    bubble_layer = new_layer()
    bd = ImageDraw.Draw(bubble_layer)
    for (x, y, r) in ((252, 242, 26), (176, 330, 15), (306, 170, 9)):
        bd.ellipse(B((x - r, y - r, x + r, y + r)), fill=st['bubble_fill'], outline=st['bubble_outline'], width=S(max(2.5, r * 0.18)))
        # shine
        bd.arc(B((x - r * 0.62, y - r * 0.62, x + r * 0.30, y + r * 0.30)), start=150, end=260,
               fill=(255, 255, 255, 225), width=S(3))
    img.alpha_composite(bubble_layer)

    return img.convert('RGB')

def downsample(img):
    return img.resize((SIZE, SIZE), Image.LANCZOS)

def make_compare(paths, outpath):
    tw = 320
    gap = 22
    margin = 30
    label_h = 58
    cw = margin * 2 + tw * 3 + gap * 2
    ch = margin + tw + label_h
    canvas = Image.new('RGB', (cw, ch), (247, 249, 253))
    d = ImageDraw.Draw(canvas)
    try:
        font = ImageFont.truetype('C:/Windows/Fonts/arialbd.ttf', 34)
    except Exception:
        font = ImageFont.load_default()
    for i, (p, lab) in enumerate(zip(paths, ['A', 'B', 'C'])):
        im = Image.open(p).convert('RGB').resize((tw, tw), Image.LANCZOS)
        x = margin + i * (tw + gap)
        y = margin
        # soft shadow
        sh = Image.new('RGBA', (tw + 30, tw + 30), (0, 0, 0, 0))
        ImageDraw.Draw(sh).rounded_rectangle((12, 12, tw + 18, tw + 18), radius=20, fill=(25, 40, 80, 45))
        sh = sh.filter(ImageFilter.GaussianBlur(8))
        canvas.paste(sh, (x - 15, y - 10), sh)
        canvas.paste(im, (x, y))
        d.rectangle((x, y, x + tw - 1, y + tw - 1), outline=(205, 214, 230), width=1)
        bbox = d.textbbox((0, 0), lab, font=font)
        d.text((x + (tw - (bbox[2] - bbox[0])) / 2, y + tw + 10), lab, fill=(39, 56, 96), font=font)
    canvas.save(outpath)

def main():
    os.makedirs(OUT, exist_ok=True)
    paths = []
    for key, fname in (('A', 'icon-a-brandfish.png'), ('B', 'icon-b-creamfish.png'), ('C', 'icon-c-deepfish.png')):
        print('drawing', key)
        master = downsample(build_fish(key))
        p = os.path.join(OUT, fname)
        master.save(p)
        for small in (120, 60):
            q = os.path.join(OUT, fname.replace('.png', '-%d.png' % small))
            master.resize((small, small), Image.LANCZOS).save(q)
        paths.append(p)
    make_compare(paths, os.path.join(OUT, 'icon-compare.png'))
    print('done')

if __name__ == '__main__':
    main()
