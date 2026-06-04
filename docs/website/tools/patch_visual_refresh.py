#!/usr/bin/env python3
"""Visual refresh: masthead, icons, voyage steps, App Store CTA. Does not change copy text."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LOCALES = ("en", "ru", "de", "fr", "es")

FONT_OLD = (
    '<link href="https://fonts.googleapis.com/css2?family=Crimson+Pro:ital,wght@0,400;0,600;0,700;1,400&display=swap" rel="stylesheet">'
)
FONT_NEW = (
    '<link href="https://fonts.googleapis.com/css2?family=Noto+Sans:ital,wght@0,400;0,500;0,600;0,700;1,400&display=swap" rel="stylesheet">'
)

FEATURE_EMOJI = {
    "⚔": "icon-modes.png",
    "☰": "icon-toolbar.png",
    "🗺": "icon-outline.png",
    "⚓": "icon-math.png",
    "☠": "icon-themes.png",
    "📜": "icon-export.png",
}

STEP_ICONS = ("step-chest.png", "step-map.png", "step-scope.png")

APP_STORE_LABEL = {
    "en": "Download on the App Store",
    "ru": "ЗАГРУЗИТЬ ИЗ APP STORE",
    "de": "Im App Store laden",
    "fr": "Télécharger dans l’App Store",
    "es": "Descargar en el App Store",
}

MASTHEAD = """  <header class="site-masthead">
    <div class="masthead-banner" aria-hidden="true">
      <img src="../assets/img/pirate-banner.png" alt="" width="1200" height="280" decoding="async">
    </div>
    <div class="site-header">
      <div class="container header-inner">
        <a class="brand" href="index.html" aria-label="{brand_aria}">
        <img class="brand-logo" src="../assets/img/logo.png" alt="" width="56" height="56">
        <span class="brand-name">BlackBeard Editor</span>
      </a>
      <nav class="nav-desktop masthead-nav" aria-label="{nav_aria}">"""


def patch_file(path: Path, locale: str) -> None:
    text = path.read_text(encoding="utf-8")
    if FONT_OLD in text:
        text = text.replace(FONT_OLD, FONT_NEW)

    # Remove standalone banner strip
    text = re.sub(
        r'\s*<div class="pirate-banner-wrap" aria-hidden="true">\s*'
        r'<img src="\.\./assets/img/pirate-banner\.png" alt="" width="1200" height="72"[^>]*>\s*'
        r"</div>\s*",
        "\n",
        text,
    )

    # Masthead: replace plain site-header opening
    if "site-masthead" not in text and '<header class="site-header">' in text:
        text = text.replace(
            '<header class="site-header">',
            '<header class="site-masthead">\n'
            '    <div class="masthead-banner" aria-hidden="true">\n'
            '      <img src="../assets/img/pirate-banner.png" alt="" width="1200" height="280" decoding="async">\n'
            "    </div>\n"
            '    <div class="site-header">',
            1,
        )
        text = text.replace(
            '<nav class="nav-desktop"',
            '<nav class="nav-desktop masthead-nav"',
            1,
        )
        text = text.replace('width="44" height="44"', 'width="56" height="56"', 1)

    # Close masthead: before mobile nav overlay, add closing div for site-header + masthead
    if "site-masthead" in text and "</header>\n\n  <div class=\"mobile-nav-overlay\"" in text:
        text = text.replace(
            "  </header>\n\n  <div class=\"mobile-nav-overlay\"",
            "    </div>\n  </header>\n\n  <div class=\"mobile-nav-overlay\"",
            1,
        )

    # Hero logo frame
    old_hero = (
        '        <div class="reveal hero-logo-wrap">\n'
        '          <img class="hero-logo"'
    )
    new_hero = (
        '        <div class="reveal hero-logo-wrap">\n'
        '          <div class="hero-logo-frame">\n'
        '            <div class="hero-frame-banner" aria-hidden="true"></div>\n'
        '            <img class="hero-logo"'
    )
    if old_hero in text and "hero-logo-frame" not in text:
        text = text.replace(old_hero, new_hero, 1)
        text = text.replace(
            'height="512">\n        </div>\n      </div>\n    </section>',
            'height="512">\n          </div>\n        </div>\n      </div>\n    </section>',
            1,
        )

    # Compass rose larger
    text = text.replace(
        'class="plank-deco" width="64" height="64"',
        'class="plank-deco" width="120" height="120"',
    )

    # Feature icons
    for emoji, icon in FEATURE_EMOJI.items():
        old = f'<div class="feature-icon" aria-hidden="true">{emoji}</div>'
        new = (
            f'<div class="feature-icon" aria-hidden="true">'
            f'<img src="../assets/img/icons/{icon}" alt="" width="72" height="72" loading="lazy">'
            f"</div>"
        )
        text = text.replace(old, new)

    # Voyage steps (index only)
    if path.name == "index.html" and 'class="steps-list' in text:
        text = text.replace('class="steps-list reveal"', 'class="voyage-steps reveal"')
        lis = re.findall(r"<li><strong>.*?</li>", text, re.DOTALL)
        if len(lis) >= 3:
            new_ol = ['        <ol class="voyage-steps reveal">']
            for i, li in enumerate(lis[:3]):
                inner = li[4:-5]  # strip <li>...</li>
                icon = STEP_ICONS[i]
                new_ol.append(
                    f'          <li class="voyage-step">\n'
                    f'            <div class="voyage-marker" aria-hidden="true">'
                    f'<img src="../assets/img/icons/{icon}" alt="" width="64" height="64"></div>\n'
                    f"            <div class=\"voyage-body\">{inner}</div>\n"
                    f"          </li>"
                )
            new_ol.append("        </ol>")
            text = re.sub(
                r'        <ol class="voyage-steps reveal">.*?</ol>',
                "\n".join(new_ol),
                text,
                count=1,
                flags=re.DOTALL,
            )

    # App Store button in download (index only)
    if path.name == "index.html" and "btn-app-store" not in text:
        label = APP_STORE_LABEL[locale]
        btn = (
            f'          <a class="btn btn-app-store" href="#download" role="button">\n'
            f'            <img class="app-store-icon" src="../assets/img/icons/apple-pirate.png" alt="" width="32" height="32">\n'
            f"            <span>{label}</span>\n"
            f"          </a>\n"
        )
        text = text.replace(
            '          <a class="btn btn-secondary" href="guide.html">',
            btn + '          <a class="btn btn-secondary" href="guide.html">',
            1,
        )

    path.write_text(text, encoding="utf-8")


def main() -> None:
    for loc in LOCALES:
        for name in ("index.html", "guide.html"):
            p = ROOT / loc / name
            if p.exists():
                patch_file(p, loc)
                print("patched", p.relative_to(ROOT))


if __name__ == "__main__":
    main()
