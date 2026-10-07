"""Placeholder Mod-Browser preview (1920x1080 _metadata/0.png).
Replace with a real screenshot before publishing on mod.io.
Run with the imgvenv python (PIL).
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080
GREEN = (46, 204, 113)
WHITE = (245, 245, 245)
GRAY = (140, 140, 140)
BG_TOP = (24, 28, 36)
BG_BOT = (10, 12, 18)


def vgrad(draw):
    for y in range(H):
        t = y / H
        draw.line([(0, y), (W, y)],
                  fill=tuple(int(BG_TOP[i] + (BG_BOT[i] - BG_TOP[i]) * t) for i in range(3)))


def main():
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    vgrad(d)
    # road
    d.rectangle([0, 800, W, H], fill=(34, 38, 46))
    for x in range(0, W, 160):
        d.rectangle([x, 934, x + 80, 946], fill=(200, 200, 200))

    # stylized bus, side view, in line green
    bx, by, bw, bh = 620, 420, 760, 300
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=36, fill=GREEN)
    d.rounded_rectangle([bx + bw - 40, by + 60, bx + bw + 110, by + 260], radius=24, fill=GREEN)  # front
    d.rectangle([bx + 60, by + 50, bx + bw - 100, by + 150], fill=(18, 22, 30))  # windows
    d.polygon([(bx + bw - 20, by + 260), (bx + bw + 110, by + 260),
               (bx + bw + 110, by + 110), (bx + bw + 30, by + 110)], fill=(18, 22, 30))  # windshield
    for cx in (bx + 170, bx + 590):
        d.ellipse([cx - 70, by + bh - 40, cx + 70, by + bh + 100], fill=(15, 17, 22))
        d.ellipse([cx - 28, by + bh + 2, cx + 28, by + bh + 58], fill=(120, 120, 120))
    # line-color swatches -> bus arrow
    for i, col in enumerate([(231, 76, 60), (241, 196, 15), (52, 152, 219), (46, 204, 113)]):
        x = 180 + i * 110
        d.rounded_rectangle([x, 480, x + 76, 570], radius=14, fill=col)
    ax = 180 + 4 * 110
    d.polygon([(ax, 505), (ax + 90, 505), (ax + 90, 485), (ax + 140, 525),
               (ax + 90, 565), (ax + 90, 545), (ax, 545)], fill=WHITE)

    try:
        title = ImageFont.truetype("/Library/Fonts/Arial Unicode.ttf", 120)
        sub = ImageFont.truetype("/Library/Fonts/Arial Unicode.ttf", 48)
    except OSError:
        title = sub = ImageFont.load_default()
    d.text((W / 2, 150), "AUTO VEHICLE COLOR", font=title, fill=WHITE, anchor="mm")
    d.text((W / 2, 250), "vehicle color follows the line color", font=sub, fill=GRAY, anchor="mm")

    img.save("/Users/florianreisinger/dev/tf3-auto-vehicle-color/_metadata/0.png")
    print("wrote _metadata/0.png")


if __name__ == "__main__":
    main()
