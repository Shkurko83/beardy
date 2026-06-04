# BlackBeard Editor — marketing site

**Domain:** [beardyeditor.com](https://beardyeditor.com)  
**Product:** BlackBeard Editor (pirate-themed Markdown editor for macOS)

## Preview locally

```bash
cd docs/website
python3 -m http.server 8080
```

Open `http://localhost:8080/ru/` or `/en/`.

## Assets

| File | Purpose |
|------|---------|
| `assets/img/logo.png` | App icon (your Blackbeard skull) |
| `assets/img/pirate-texture.png` | Page background texture |
| `assets/img/pirate-banner.png` | Masthead banner (full width, not cropped) |
| `assets/img/icons/*.png` | Feature icons, voyage step markers, App Store apple |
| `assets/img/compass-rose.png` | Decoration in “Captain's decree” block |

## Regenerate translations after editing `en/index.html`

```bash
python3 tools/apply_pirate_i18n.py   # ru, de, fr, es home pages
python3 tools/rebrand_all.py         # domain + guides (if needed)
```

## Deploy

Upload the contents of `docs/website/` to the root of **beardyeditor.com**. Ensure `logo.png` and textures are served (files are large — consider compressing PNGs before production).
