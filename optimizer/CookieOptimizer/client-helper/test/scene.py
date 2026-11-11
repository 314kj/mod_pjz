# a simple PZ-like test picture (day / night) for checking the looks
from PIL import Image, ImageDraw, ImageFilter
import random
def scene(night=False, W=960, H=540):
    random.seed(4)
    im = Image.new('RGB', (W, H), (74, 96, 58))
    d = ImageDraw.Draw(im)
    # grass noise
    for i in range(4000):
        x, y = random.randrange(W), random.randrange(H)
        g = random.randint(-14, 14)
        d.point((x, y), fill=(74 + g, 100 + g, 56 + g // 2))
    # diagonal road
    d.polygon([(0, 330), (420, 120), (560, 190), (140, 400)], fill=(92, 92, 96))
    d.polygon([(380, 540), (960, 250), (960, 330), (520, 540)], fill=(92, 92, 96))
    for k in range(8):
        x = 40 + k * 55; y = 330 - k * 27
        d.line([(x, y), (x + 22, y - 11)], fill=(210, 200, 120), width=3)
    # houses (isometric blocks)
    def house(x, y, w, h, wall, roof):
        d.polygon([(x, y), (x + w, y - w // 2), (x + w, y - w // 2 - h), (x, y - h)], fill=wall)
        d.polygon([(x, y), (x - w, y - w // 2), (x - w, y - w // 2 - h), (x, y - h)], fill=tuple(int(v * 0.75) for v in wall))
        d.polygon([(x, y - h), (x + w, y - w // 2 - h), (x, y - w - h), (x - w, y - w // 2 - h)], fill=roof)
        for j in range(2):
            wx = x + 18 + j * 30; wy = y - 30 - j * 15
            d.polygon([(wx, wy), (wx + 14, wy - 7), (wx + 14, wy - 27), (wx, wy - 20)], fill=(255, 214, 120) if night else (120, 150, 170))
    house(700, 200, 90, 70, (176, 150, 120), (120, 60, 50))
    house(250, 470, 110, 80, (150, 160, 170), (70, 70, 80))
    house(820, 470, 80, 60, (190, 170, 140), (90, 50, 40))
    # trees
    for (x, y) in [(120, 120), (180, 160), (600, 420), (650, 460), (900, 120), (480, 60)]:
        d.ellipse([x - 28, y - 40, x + 28, y + 10], fill=(46, 80, 40))
        d.ellipse([x - 18, y - 52, x + 14, y - 14], fill=(58, 98, 50))
    # zombies / player (small figures)
    for (x, y, c) in [(330, 260, (150, 60, 60)), (360, 280, (110, 120, 90)), (520, 300, (60, 90, 160))]:
        d.rectangle([x - 5, y - 26, x + 5, y], fill=c); d.ellipse([x - 5, y - 36, x + 5, y - 26], fill=(220, 190, 160))
    # street lamp
    d.line([(560, 330), (560, 250)], fill=(50, 50, 50), width=4)
    if night:
        im = Image.eval(im, lambda v: int(v * 0.22))
        glow = Image.new('RGB', (W, H), (0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.ellipse([470, 240, 650, 380], fill=(150, 120, 60))
        gd.ellipse([660, 120, 760, 190], fill=(90, 70, 30))
        glow = glow.filter(ImageFilter.GaussianBlur(40))
        im = Image.fromarray(__import__('numpy').clip(__import__('numpy').asarray(im).astype(int) + __import__('numpy').asarray(glow).astype(int), 0, 255).astype('uint8'))
        d = ImageDraw.Draw(im)
        d.ellipse([552, 242, 568, 258], fill=(255, 240, 190))
        for (wx, wy) in [(718, 170), (748, 155), (268, 440), (298, 425), (838, 440), (868, 425)]:
            d.polygon([(wx, wy), (wx + 14, wy - 7), (wx + 14, wy - 27), (wx, wy - 20)], fill=(255, 210, 120))
    else:
        d.ellipse([552, 242, 568, 258], fill=(200, 200, 190))
    return im
if __name__ == '__main__':
    scene().save('day.png'); scene(True).save('night.png')
