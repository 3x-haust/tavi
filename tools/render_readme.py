# Renders the README artwork in the DMG installer's style: .github/readme/
# hero-{light,dark}.png and install-{light,dark}.png. Run with Pillow; the outputs
# are committed.
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, '.github', 'readme')
LOGO = os.path.join(ROOT, 'Resources', 'TaviLogo.png')
S = 2
W = 880 * S
BLUE = (61, 108, 225)

THEMES = {
    'light': dict(paper=(250, 248, 244), dot=(232, 228, 220), ink=(35, 35, 35), mute=(138, 133, 125),
                  faint=(214, 209, 200), pill=(255, 255, 255), edge=(234, 230, 222), badge=(35, 35, 35),
                  badge_ink=(255, 255, 255)),
    'dark': dict(paper=(24, 24, 26), dot=(44, 44, 47), ink=(236, 234, 229), mute=(150, 147, 140),
                 faint=(70, 70, 74), pill=(36, 36, 39), edge=(56, 56, 60), badge=(236, 234, 229),
                 badge_ink=(24, 24, 26)),
}

FONT_DIRS = [os.path.expanduser('~/Library/Fonts'), '/Library/Fonts', '/System/Library/Fonts']


def font(name, size):
    for directory in FONT_DIRS:
        path = os.path.join(directory, name)
        if os.path.exists(path):
            return ImageFont.truetype(path, size * S)
    return ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', size * S)


title = font('Pretendard-Bold.otf', 34)
body = font('Pretendard-Medium.otf', 16)
strong = font('Pretendard-Bold.otf', 16)
step = font('Pretendard-SemiBold.otf', 15)
keys = font('SFNSMono.ttf', 17)
word = font('Pretendard-Bold.otf', 19)


def canvas(height, t):
    """Paper with the installer's quiet dot grid, rounded so it sits as a card."""
    image = Image.new('RGBA', (W, height), t['paper'] + (255,))
    d = ImageDraw.Draw(image)
    for y in range(12 * S, height, 16 * S):
        for x in range(8 * S, W, 16 * S):
            d.ellipse((x - S, y - S, x + S, y + S), fill=t['dot'])
    mask = Image.new('L', (W, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, height - 1), radius=20 * S, fill=255)
    image.putalpha(mask)
    return image, d


def centered(d, y, runs):
    width = sum(d.textlength(text, font=f) for text, f, _ in runs)
    x = (W - width) / 2
    for text, f, fill in runs:
        d.text((x, y), text, font=f, fill=fill)
        x += d.textlength(text, font=f)


def chevrons(d, left, right, cy, t):
    """The installer's trail: fading in from the keys, ending in the logo's blue."""
    count, half = 5, 6 * S
    for i in range(count):
        x = left + (right - left) * (i + 0.5) / count
        share = i / (count - 1)
        color = BLUE if i == count - 1 else tuple(round(t['faint'][c] + (t['ink'][c] - t['faint'][c]) * share) for c in range(3))
        d.line([(x - half * 0.6, cy - half), (x + half * 0.6, cy), (x - half * 0.6, cy + half)],
               fill=color, width=3 * S, joint='curve')


def pill(d, cx, y, number, label, width, t):
    badge, pad, gap, height = 22 * S, 12 * S, 10 * S, 38 * S
    x = cx - width / 2
    d.rounded_rectangle((x, y, x + width, y + height), radius=height / 2, fill=t['pill'], outline=t['edge'], width=S)
    bx, by = x + pad, y + (height - badge) / 2
    d.ellipse((bx, by, bx + badge, by + badge), fill=t['badge'])
    d.text((bx + badge / 2, by + badge / 2), str(number), font=step, fill=t['badge_ink'], anchor='mm')
    d.text((bx + badge + gap, y + height / 2), label, font=step, fill=t['ink'], anchor='lm')


def hero(t):
    image, d = canvas(470 * S, t)
    logo = Image.open(LOGO).convert('RGBA').resize((104 * S, 104 * S), Image.LANCZOS)
    corner = Image.new('L', logo.size, 0)
    ImageDraw.Draw(corner).rounded_rectangle((0, 0, logo.width - 1, logo.height - 1), radius=24 * S, fill=255)
    logo.putalpha(Image.composite(logo.getchannel('A'), corner, corner))
    origin = ((W - logo.width) // 2, 40 * S)
    # The icon's cream tile nearly matches the paper, so it gets the soft lift of a Dock icon.
    shadow = Image.new('RGBA', image.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (origin[0], origin[1] + 4 * S, origin[0] + logo.width, origin[1] + logo.height + 4 * S),
        radius=24 * S, fill=(0, 0, 0, 70 if t['paper'][0] > 128 else 160))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(10 * S)))
    image.alpha_composite(logo, origin)
    centered(d, 166 * S, [('한영 전환 없이, 쓰던 흐름 그대로.', title, t['ink'])])
    centered(d, 216 * S, [('그냥 치면 ', body, t['mute']), ('Tavi', strong, t['ink']),
                          ('가 단어마다 한국어인지 영어인지 알아서 정해요', body, t['mute'])])

    examples = [('dkssudgktpdy', '안녕하세요'), ('APIfmf', 'API를'), ('gksdudwjsghks', '한영전환')]
    key_right, word_left = W / 2 - 70 * S, W / 2 + 70 * S
    for row, (typed, result) in enumerate(examples):
        cy = 290 * S + row * 50 * S
        d.text((key_right, cy), typed, font=keys, fill=t['mute'], anchor='rm')
        chevrons(d, key_right + 18 * S, word_left - 18 * S, cy, t)
        d.text((word_left, cy), result, font=word, fill=t['ink'], anchor='lm')
    return image


def install(t):
    image, d = canvas(250 * S, t)
    centered(d, 32 * S, [('설치는 세 번이면 끝', title, t['ink'])])
    steps = ['DMG를 받아 Tavi를 Applications로', 'Tavi를 열고 ‘키보드 설정 열기’', '영상대로 + → 한국어 → Tavi → 추가']
    width = max(d.textlength(label, font=step) for label in steps) + 72 * S
    for index, label in enumerate(steps):
        pill(d, W / 2, 92 * S + index * 50 * S, index + 1, label, width, t)
    return image


os.makedirs(OUT, exist_ok=True)
for name, theme in THEMES.items():
    hero(theme).save(os.path.join(OUT, f'hero-{name}.png'), optimize=True)
    install(theme).save(os.path.join(OUT, f'install-{name}.png'), optimize=True)
print('Rendered', OUT)
