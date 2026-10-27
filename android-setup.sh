#!/usr/bin/env bash
# يُنفَّذ بعد "npx cap add android" لتخصيص المشروع المُولَّد (صلاحيات + أيقونة + شاشة البداية)
set -euo pipefail
M=android/app/src/main/AndroidManifest.xml
RES=android/app/src/main/res

# صلاحيات الحفظ على الأندرويد القديم
if ! grep -q WRITE_EXTERNAL_STORAGE "$M"; then
  sed -i 's#</manifest>#    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />\n    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />\n</manifest>#' "$M"
fi

pip install --quiet pillow
python3 - "$RES" www/icon-512.png <<'PY'
import sys, os, re, glob
from PIL import Image, ImageDraw
res, src = sys.argv[1], sys.argv[2]
icon = Image.open(src).convert("RGBA")
W = icon.size[0]
bg = icon.getpixel((6, 6))[:3]
bg_hex = "#%02x%02x%02x" % bg

# قصّ الدائرة المضيئة (الشعار) كطبقة أمامية
r = int(W * 0.43); c = W // 2
mask = Image.new("L", (W, W), 0); ImageDraw.Draw(mask).ellipse((c-r, c-r, c+r, c+r), fill=255)
logo = Image.new("RGBA", (W, W), (0, 0, 0, 0)); logo.paste(icon, (0, 0), mask)
logo = logo.crop((c-r, c-r, c+r, c+r))

def layer(px, frac):               # طبقة شفافة مربعة بحجم px والشعار في الوسط
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    s = int(px * frac); l = logo.resize((s, s), Image.LANCZOS)
    out.paste(l, ((px - s)//2, (px - s)//2), l); return out

# أيقونة التطبيق: قديمة + متكيّفة
sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for d, s in sizes.items():
    p = f"{res}/mipmap-{d}"; os.makedirs(p, exist_ok=True)
    legacy = Image.new("RGBA", (s, s), bg + (255,)); l = logo.resize((int(s*0.82),)*2, Image.LANCZOS)
    legacy.paste(l, ((s-l.size[0])//2,)*2, l)
    legacy.save(f"{p}/ic_launcher.png"); legacy.save(f"{p}/ic_launcher_round.png")
    layer(int(s*108/48), 0.60).save(f"{p}/ic_launcher_foreground.png")
any26 = f"{res}/mipmap-anydpi-v26"; os.makedirs(any26, exist_ok=True)
xml = '<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/telawat_bg"/>\n    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n</adaptive-icon>\n'
for n in ("ic_launcher.xml", "ic_launcher_round.xml"):
    open(f"{any26}/{n}", "w").write(xml)
os.makedirs(f"{res}/values", exist_ok=True)
open(f"{res}/values/telawat_colors.xml", "w").write(f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="telawat_bg">{bg_hex}</color>\n</resources>\n')

# شاشة البداية: خلفية كحلية + الشعار (للأندرويد القديم)، وللأندرويد 12+ عبر الثيم
for f in glob.glob(f"{res}/drawable*/splash.png"):
    try:
        w, h = Image.open(f).size
        im = Image.new("RGBA", (w, h), bg + (255,)); s = int(min(w, h) * 0.42)
        l = logo.resize((s, s), Image.LANCZOS); im.paste(l, ((w-s)//2, (h-s)//2), l)
        im.convert("RGB").save(f)
    except Exception as e:
        print("splash skip", f, e)
sf = f"{res}/values/styles.xml"
if os.path.exists(sf):
    t = open(sf, encoding="utf-8").read()
    if "windowSplashScreenBackground" not in t:
        t2 = re.sub(r'(<style name="AppTheme\.NoActionBarLaunch"[^>]*>)',
                    r'\1\n        <item name="windowSplashScreenBackground">@color/telawat_bg</item>\n        <item name="windowSplashScreenAnimatedIcon">@mipmap/ic_launcher_foreground</item>', t, count=1)
        print("styles patched" if t2 != t else "WARN: launch style not found")
        open(sf, "w", encoding="utf-8").write(t2)
print("icons + splash done, bg", bg_hex)
PY
echo "setup done"
