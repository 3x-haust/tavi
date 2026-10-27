# Renders the DMG window background: Resources/dmg/background.png (640x400)
# and background@2x.png. Run with Pillow; the outputs are committed so packaging
# only needs dmgbuild.
#
# Finder draws the real app and Applications icons on top, so they are never
# painted here. A background forces light-mode (black) file names, so the paper
# stays light. Finder's path/status bars, when the user has them on, cover the
# bottom ~90pt; everything that must be read sits above 300pt.
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'Resources', 'dmg')
S = 2
W, H = 640 * S, 400 * S
APP, DIR = (160 * S, 160 * S), (480 * S, 160 * S)  # icon centres; keep in sync with dmg-settings.py
ICON = 112 * S

PAPER = (250, 248, 244)
DOT = (232, 228, 220)
INK = (35, 35, 35)
MUTE = (138, 133, 125)
FAINT = (214, 209, 200)
BLUE = (61, 108, 225)

FONT_DIRS = [
    os.path.expanduser('~/Library/Fonts'), '/Library/Fonts', '/System/Library/Fonts',
    '/System/Applications/Utilities/Terminal.app/Contents/Resources/Fonts',
]


def font(names, size):
    for name in names:
        for directory in FONT_DIRS:
            path = os.path.join(directory, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, size * S)
    return ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', size * S)


title = font(['Pretendard-Bold.otf'], 22)
body = font(['Pretendard-Medium.otf'], 13)
strong = font(['Pretendard-Bold.otf'], 13)
step = font(['Pretendard-SemiBold.otf'], 12)
mono = font(['SF-Mono-Medium.otf', 'SFNSMono.ttf'], 11)
mono_strong = font(['Pretendard-Bold.otf'], 12)

bg = Image.new('RGB', (W, H), PAPER)
d = ImageDraw.Draw(bg)

# Quiet dot grid, cleared around the icons and their Finder labels.
for y in range(12 * S, H, 16 * S):
    for x in range(8 * S, W, 16 * S):
        if any(abs(x - cx) < 84 * S and -80 * S < y - cy < 92 * S for cx, cy in (APP, DIR)):
            continue
        d.ellipse((x - S, y - S, x + S, y + S), fill=DOT)


def centered(y, runs):
    width = sum(d.textlength(text, font=f) for text, f, _ in runs)
    x = (W - width) / 2
    for text, f, fill in runs:
        d.text((x, y), text, font=f, fill=fill)
        x += d.textlength(text, font=f)


centered(26 * S, [('한영 전환 없이, 쓰던 흐름 그대로.', title, INK)])
centered(60 * S, [('Tavi', strong, INK), ('를 ', body, MUTE), ('Applications', strong, INK), (' 폴더로 끌어다 놓으세요', body, MUTE)])

# Chevron trail from app to folder, darkening toward the target; the last one
# takes the blue of the logo's bar.
left, right = APP[0] + ICON // 2 + 26 * S, DIR[0] - ICON // 2 - 26 * S
count, half = 5, 7 * S
cy = APP[1]
for i in range(count):
    x = left + (right - left) * (i + 0.5) / count
    t = i / (count - 1)
    color = BLUE if i == count - 1 else tuple(round(FAINT[c] + (INK[c] - FAINT[c]) * t) for c in range(3))
    d.line([(x - half * 0.6, cy - half), (x + half * 0.6, cy), (x - half * 0.6, cy + half)],
           fill=color, width=3 * S, joint='curve')

# What the app does, in one line: raw keys in, Korean out.
keys, arrow, word = 'dkssud', '  →  ', '안녕'
y = cy + 22 * S
width = d.textlength(keys, font=mono) + d.textlength(arrow, font=mono) + d.textlength(word, font=mono_strong)
x = (left + right - width) / 2
for text, f, fill in [(keys, mono, MUTE), (arrow, mono, FAINT), (word, mono_strong, INK)]:
    d.text((x, y), text, font=f, fill=fill)
    x += d.textlength(text, font=f)

# Second step, on a pill so it reads as an instruction rather than decoration.
label = '그다음 Tavi를 열고 영상대로 추가하면 끝'
badge = 18 * S
pad = 12 * S
gap = 8 * S
text_w = d.textlength(label, font=step)
pill_w = pad + badge + gap + text_w + pad + 4 * S
pill_h = 30 * S
px, py = (W - pill_w) / 2, 262 * S
d.rounded_rectangle((px, py, px + pill_w, py + pill_h), radius=pill_h / 2, fill=(255, 255, 255), outline=(234, 230, 222), width=S)
bx, by = px + pad, py + (pill_h - badge) / 2
d.ellipse((bx, by, bx + badge, by + badge), fill=INK)
d.text((bx + badge / 2, by + badge / 2), '2', font=step, fill=(255, 255, 255), anchor='mm')
d.text((bx + badge + gap, py + pill_h / 2), label, font=step, fill=INK, anchor='lm')

os.makedirs(OUT, exist_ok=True)
bg.save(os.path.join(OUT, 'background@2x.png'), optimize=True)
bg.resize((W // S, H // S), Image.LANCZOS).save(os.path.join(OUT, 'background.png'), optimize=True)
print('Rendered', OUT)
