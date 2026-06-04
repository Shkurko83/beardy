#!/usr/bin/env python3
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
GUIDES = Path(__file__).resolve().parent / "guides"

for path in ROOT.rglob("*"):
    if path.suffix not in {".html", ".xml", ".txt", ".md"}:
        continue
    if "tools" in path.parts and path.name.endswith(".py"):
        continue
    text = path.read_text(encoding="utf-8")
    text = text.replace("beardy.app", "beardyeditor.com")
    text = text.replace("Beardy", "BlackBeard Editor")
    text = text.replace("BlackBeard Editor Editor", "BlackBeard Editor")
    path.write_text(text, encoding="utf-8")

for code in ("ru", "de", "fr", "es", "en"):
    src = GUIDES / f"{code}.html"
    if src.is_file():
        shutil.copy(src, ROOT / code / "guide.html")

# Patch guide headers with logo (en template)
GUIDE_HEADER = '''      <a class="brand" href="index.html">
        <img class="brand-logo" src="../assets/img/logo.png" alt="" width="44" height="44">
        <span class="brand-name">BlackBeard Editor</span>
      </a>'''

for code in ("en", "ru", "de", "fr", "es"):
    g = ROOT / code / "guide.html"
    if not g.is_file():
        continue
    t = g.read_text(encoding="utf-8")
    import re
    t = re.sub(
        r'<a class="brand" href="index\.html">.*?</a>',
        GUIDE_HEADER,
        t,
        count=1,
        flags=re.DOTALL,
    )
    t = t.replace('href="../assets/img/favicon.svg"', 'href="../assets/img/logo.png"')
    t = t.replace('type="image/svg+xml"', 'type="image/png"')
    if 'pirate-banner-wrap' not in t:
        t = t.replace(
            "<body>",
            '<body>\n  <div class="pirate-banner-wrap" aria-hidden="true">\n    <img src="../assets/img/pirate-banner.png" alt="" width="1200" height="72">\n  </div>',
            1,
        )
    if "Pirata One" not in t:
        t = t.replace(
            "family=Inter:wght@400",
            "family=Crimson+Pro:ital,wght@0,400;0,600&family=Pirata+One&family=Inter:wght@400",
        )
    g.write_text(t, encoding="utf-8")

print("rebrand complete")
