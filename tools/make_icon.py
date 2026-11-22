import sys
from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S), (77, 107, 254))

# 垂直渐变（带缓动）
top = (86, 118, 255)
bottom = (27, 38, 168)
pix = img.load()
for y in range(S):
    t = y / (S - 1)
    tt = t * t * (3 - 2 * t)
    r = int(top[0] + (bottom[0] - top[0]) * tt)
    g = int(top[1] + (bottom[1] - top[1]) * tt)
    b = int(top[2] + (bottom[2] - top[2]) * tt)
    for x in range(S):
        pix[x, y] = (r, g, b)

# 左上柔和光晕
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse([-260, -330, 720, 560], fill=(255, 255, 255, 52))
glow = glow.filter(ImageFilter.GaussianBlur(130))
img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")

d = ImageDraw.Draw(img)

# 圆角气泡主体
d.rounded_rectangle([238, 296, 786, 692], radius=104, fill=(255, 255, 255))
# 气泡尾巴
d.polygon([(356, 676), (474, 676), (388, 806)], fill=(255, 255, 255))

# 三个蓝点 = 正在对话
for cx in (404, 512, 620):
    r = 40
    d.ellipse([cx - r, 454 - r, cx + r, 454 + r], fill=(46, 62, 196))

# 轻微高光让它不那么"平"
hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.ellipse([300, 320, 720, 560], fill=(255, 255, 255, 34))
hl = hl.filter(ImageFilter.GaussianBlur(60))
img = Image.alpha_composite(img.convert("RGBA"), hl).convert("RGB")

img.save(sys.argv[1], "PNG")
print("saved", sys.argv[1], img.size)
