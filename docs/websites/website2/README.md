# Beardy marketing website

Static promotional site for **Beardy** (macOS markdown editor). Hosted as plain HTML/CSS/JS — no build step required for deployment.

## Structure

```
website/
  index.html          # Auto-detect language → redirect to /en/, /ru/, …
  en/ ru/ de/ fr/ es/ # Localized landing + guide
  assets/             # CSS, JS, images, i18n registry
  sitemap.xml
  robots.txt
  llms.txt            # Hints for AI crawlers
  humans.txt
  SCREENSHOTS.md      # How to capture real screenshots
  tools/generate-locales.py  # Regenerate non-English pages from en/
```

## Local preview

From this folder:

```bash
python3 -m http.server 8080
```

Open `http://localhost:8080/` — you will be redirected to your browser language.

## Features

- **5 languages**: EN, RU, DE, FR, ES (extensible via `assets/i18n/languages.json` + new `/xx/` folders)
- **Locale detection** on first visit (`assets/js/locale-redirect.js`) with manual override (persisted)
- **Light / dark / system** theme (`assets/js/theme.js`)
- **SEO**: canonical URLs, hreflang, Open Graph, JSON-LD (`SoftwareApplication`, `Person`, `HowTo`)
- **Author indexing**: Konstantin Shkurko / Константин Шкурко in meta, JSON-LD, footer, llms.txt
- **Responsive** layout and reduced-motion support

## Publishing

1. Replace `https://beardy.app/` in `sitemap.xml`, canonical links, and JSON-LD if your domain differs.
2. Add real screenshots per `SCREENSHOTS.md` under `assets/img/screenshots/`.
3. Replace logo placeholder and add `og-image.png` (1200×630).
4. Point your static host (GitHub Pages, Netlify, Cloudflare Pages) at `docs/website/` or copy files to the web root.

## Regenerating translations

After editing `en/index.html` or `en/guide.html`:

```bash
python3 tools/generate-locales.py
```

Then review `ru/`, `de/`, `fr/`, `es/` for any strings that need manual tuning.

## Adding a language

1. Add locale to `assets/i18n/languages.json`.
2. Add code to `SUPPORTED` in `assets/js/locale-redirect.js`.
3. Extend `LOCALES`, `FEATURES`, and `GUIDE_TEXT` in `tools/generate-locales.py`.
4. Run the generator and update `sitemap.xml`, `llms.txt`, and hreflang blocks in `en/index.html`.
