#!/usr/bin/env python3
"""Generate localized index.html from en/index.html. Guides are in tools/guides/."""
from __future__ import annotations
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EN = ROOT / "en"
GUIDES = Path(__file__).resolve().parent / "guides"

FEATURES_EN = [
    ("Four view modes", "Text only, formatted text, text + preview, or preview only. Switch anytime — your undo history is kept."),
    ("Buttons on the toolbar", "Bold, italic, headings, lists, links, and code — insert with one click if you do not want to remember symbols."),
    ("Table of contents", "A panel lists your headings. Click a line — the document scrolls to that place."),
    ("Formulas and charts", "If you need math or a flowchart in the text — the app can show them in preview (works offline)."),
    ("Light and dark appearance", "Choose a comfortable theme for your eyes — light, dark, or follow the Mac system setting."),
    ("Export", "Save the result as PDF, web page, picture, or Word. Books (EPUB) — if you install the free Pandoc program."),
]

LOCALES = {
    "ru": {
        "html_lang": "ru",
        "lang_btn": "RU",
        "canonical_home": "https://beardy.app/ru/",
        "og_locale": "ru_RU",
        "og_title": "Beardy — простой редактор Markdown для Mac",
        "og_description": "Пишите текст и сразу видьте результат. Для Mac.",
        "json_desc": "Простой редактор Markdown для Mac.",
        "title_home": "Beardy — простой редактор Markdown для Mac",
        "desc_home": "Beardy — понятный редактор Markdown для Mac: пишите текст, смотрите результат, сохраняйте в PDF. Автор: Константин Шкурко.",
        "skip": "Перейти к содержанию",
        "nav_how": "Как начать",
        "nav_features": "Возможности",
        "nav_modes": "Режимы",
        "nav_guide": "Инструкция",
        "nav_download": "Скачать",
        "eyebrow": "Для Mac · Для заметок и документов",
        "h1": "Понятный редактор для файлов Markdown",
        "hero_lead": "<strong>Markdown</strong> — это простой способ оформить текст: заголовки, списки и ссылки помечаются обычными символами (например <code>#</code> — заголовок). Beardy показывает, как текст будет выглядеть — прямо при наборе или в отдельном окне.",
        "cta_primary": "Скачать Beardy",
        "cta_secondary": "Как пользоваться приложением",
        "hero_note": "Файлы хранятся на вашем Mac. Приложение может сохранять изменения само. Просмотр результата работает без интернета.",
        "steps_h2": "Как начать за три шага",
        "steps_p": "Не нужны курсы и сложные настройки — откройте программу и пишите.",
        "step1": "<strong>Установите Beardy</strong> на Mac и откройте. На экране будут кнопки: новый документ, открыть файл или перетащить файл в окно.",
        "step2": "<strong>Пишите текст.</strong> Можно нажимать кнопки на панели (жирный, заголовок, список) или вводить символы Markdown вручную.",
        "step3": "<strong>Выберите, как смотреть текст:</strong> только символы, только красивый вид или оба варианта рядом. Когда готово — сохраните или экспортируйте в PDF.",
        "steps_link": "Полная пошаговая инструкция",
        "audience_h2": "Кому подойдёт Beardy?",
        "audience_p": "Тем, кто на Mac пишет длинные тексты, инструкции или документацию к программам.",
        "dev_h3": "Программистам",
        "dev_li": [
            "Код в тексте подсвечивается цветом",
            "Список заголовков сбоку — нажали и перешли к нужному разделу",
            "Отмена действий работает и после смены режима просмотра",
            "Несколько файлов во вкладках; можно включить автосохранение",
        ],
        "tw_h3": "Авторам статей и инструкций",
        "tw_li": [
            "Редактирование как в обычном редакторе — оформление видно сразу",
            "Сохранение в PDF, веб-страницу, картинку или Word",
            "Формулы и простые схемы в тексте (для просмотра интернет не нужен)",
            "Проверка орфографии при наборе",
        ],
        "feat_h2": "Что умеет Beardy",
        "feat_p": "Главное — простыми словами.",
        "modes_h2": "Четыре способа смотреть один и тот же документ",
        "modes_p": "В программе названия на английском — ниже объяснение каждого.",
        "shots_h2": "Как выглядит программа",
        "shots_p": "Здесь будут скриншоты. Как их сделать — в <a href=\"../SCREENSHOTS.md\">SCREENSHOTS.md</a> (для владельца сайта).",
        "cta_h2": "Попробуйте Beardy на Mac",
        "cta_p": "Создал <strong>Константин Шкурко</strong>. Вопросы по работе — в инструкции на этом сайте.",
        "cta_btn": "Открыть пошаговую инструкцию",
        "footer_tag": "Простой редактор Markdown для Mac. Автор: Константин Шкурко.",
        "footer_site": "Сайт",
        "footer_langs": "Языки",
        "mode_edit": "Только текст с символами",
        "mode_live": "Текст сразу выглядит оформленным",
        "mode_split": "Слева текст, справа результат",
        "mode_preview": "Только готовый вид, без символов",
        "og_title_fix": "Beardy — Simple Markdown Editor for Mac",
        "twitter_desc": "Понятный редактор Markdown: пишите, смотрите результат, сохраняйте в PDF.",
    },
    "de": {
        "html_lang": "de",
        "lang_btn": "DE",
        "canonical_home": "https://beardy.app/de/",
        "og_locale": "de_DE",
        "og_title": "Beardy — Einfacher Markdown-Editor für Mac",
        "og_description": "Text schreiben und das Ergebnis sofort sehen. Für Mac.",
        "json_desc": "Einfacher Markdown-Editor für Mac.",
        "title_home": "Beardy — Einfacher Markdown-Editor für Mac",
        "desc_home": "Beardy ist ein verständlicher Markdown-Editor für Mac. Text schreiben, Ergebnis sehen, als PDF speichern. Von Konstantin Shkurko.",
        "skip": "Zum Inhalt springen",
        "nav_how": "So starten Sie",
        "nav_features": "Funktionen",
        "nav_modes": "Ansichten",
        "nav_guide": "Anleitung",
        "nav_download": "Download",
        "eyebrow": "Für Mac · Für Notizen und Dokumente",
        "h1": "Ein klarer Editor für Markdown-Dateien",
        "hero_lead": "<strong>Markdown</strong> ist eine einfache Art, Text zu schreiben: Überschriften, Listen und Links markieren Sie mit normalen Zeichen (z. B. <code>#</code> für eine Überschrift). Beardy zeigt, wie der Text aussehen wird — beim Tippen oder in einem eigenen Fenster.",
        "cta_primary": "Beardy herunterladen",
        "cta_secondary": "So nutzen Sie die App",
        "hero_note": "Ihre Dateien bleiben auf dem Mac. Die App kann automatisch speichern. Die Vorschau funktioniert ohne Internet.",
        "steps_h2": "In drei Schritten starten",
        "steps_p": "Kein Kurs nötig — App öffnen und schreiben.",
        "step1": "<strong>Beardy installieren</strong> und öffnen. Sie sehen: neues Dokument, Datei öffnen oder Datei ins Fenster ziehen.",
        "step2": "<strong>Text schreiben.</strong> Toolbar für Fett, Überschrift, Liste — oder Markdown-Zeichen selbst tippen.",
        "step3": "<strong>Ansicht wählen:</strong> nur Zeichen, nur formatiert, oder beides nebeneinander. Dann speichern oder als PDF exportieren.",
        "steps_link": "Ausführliche Schritt-für-Schritt-Anleitung",
        "audience_h2": "Für wen ist Beardy?",
        "audience_p": "Für alle, die am Mac lange Texte, Anleitungen oder Programmdokumentation schreiben.",
        "dev_h3": "Programmierer",
        "dev_li": [
            "Code im Text wird farbig hervorgehoben",
            "Liste der Überschriften — Klick springt zur Stelle",
            "Rückgängig funktioniert auch nach Ansichtswechsel",
            "Mehrere Dateien in Tabs; Autospeichern möglich",
        ],
        "tw_h3": "Autoren von Artikeln und Anleitungen",
        "tw_li": [
            "Bearbeiten wie in einem normalen Editor — Formatierung sofort sichtbar",
            "Speichern als PDF, Webseite, Bild oder Word",
            "Formeln und einfache Diagramme (Vorschau ohne Internet)",
            "Rechtschreibprüfung beim Tippen",
        ],
        "feat_h2": "Was Beardy kann",
        "feat_p": "Die wichtigsten Funktionen — in einfachen Worten.",
        "modes_h2": "Vier Ansichten für dasselbe Dokument",
        "modes_p": "In der App heißen die Modi auf Englisch — hier die Bedeutung.",
        "shots_h2": "So sieht die App aus",
        "shots_p": "Screenshots folgen. Anleitung in <a href=\"../SCREENSHOTS.md\">SCREENSHOTS.md</a>.",
        "cta_h2": "Beardy auf dem Mac testen",
        "cta_p": "Von <strong>Konstantin Shkurko</strong>. Hilfe — in der Anleitung auf dieser Seite.",
        "cta_btn": "Schritt-für-Schritt-Anleitung öffnen",
        "footer_tag": "Einfacher Markdown-Editor für Mac. Autor: Konstantin Shkurko.",
        "footer_site": "Seite",
        "footer_langs": "Sprachen",
        "mode_edit": "Nur Text mit Zeichen",
        "mode_live": "Text wirkt sofort formatiert",
        "mode_split": "Links Text, rechts Ergebnis",
        "mode_preview": "Nur fertige Ansicht",
        "og_title_fix": "Beardy — Simple Markdown Editor for Mac",
        "twitter_desc": "Klarer Markdown-Editor: schreiben, Vorschau, PDF speichern.",
    },
    "fr": {
        "html_lang": "fr",
        "lang_btn": "FR",
        "canonical_home": "https://beardy.app/fr/",
        "og_locale": "fr_FR",
        "og_title": "Beardy — Éditeur Markdown simple pour Mac",
        "og_description": "Écrivez et voyez le résultat tout de suite. Pour Mac.",
        "json_desc": "Éditeur Markdown simple pour Mac.",
        "title_home": "Beardy — Éditeur Markdown simple pour Mac",
        "desc_home": "Beardy est un éditeur Markdown clair pour Mac : écrire, voir le résultat, enregistrer en PDF. Par Konstantin Shkurko.",
        "skip": "Aller au contenu",
        "nav_how": "Par où commencer",
        "nav_features": "Fonctions",
        "nav_modes": "Affichages",
        "nav_guide": "Mode d'emploi",
        "nav_download": "Télécharger",
        "eyebrow": "Pour Mac · Notes et documents",
        "h1": "Un éditeur clair pour les fichiers Markdown",
        "hero_lead": "Le <strong>Markdown</strong> est une façon simple d'écrire : titres, listes et liens avec des caractères ordinaires (par ex. <code>#</code> pour un titre). Beardy montre le rendu — pendant la saisie ou dans une fenêtre à part.",
        "cta_primary": "Télécharger Beardy",
        "cta_secondary": "Comment utiliser l'app",
        "hero_note": "Vos fichiers restent sur votre Mac. Sauvegarde automatique possible. L'aperçu fonctionne sans Internet.",
        "steps_h2": "Commencer en trois étapes",
        "steps_p": "Pas besoin de formation — ouvrez l'app et écrivez.",
        "step1": "<strong>Installez Beardy</strong> et ouvrez-le. Boutons : nouveau document, ouvrir un fichier, ou glisser un fichier dans la fenêtre.",
        "step2": "<strong>Écrivez.</strong> Barre d'outils pour gras, titre, liste — ou tapez les symboles Markdown.",
        "step3": "<strong>Choisissez l'affichage :</strong> symboles seuls, rendu seul, ou les deux côte à côte. Puis enregistrez ou exportez en PDF.",
        "steps_link": "Guide détaillé pas à pas",
        "audience_h2": "Pour qui est Beardy ?",
        "audience_p": "Pour ceux qui écrivent de longs textes, des modes d'emploi ou de la doc sur Mac.",
        "dev_h3": "Développeurs",
        "dev_li": [
            "Le code dans le texte est coloré",
            "Liste des titres — clic pour aller à la section",
            "Annuler fonctionne après changement d'affichage",
            "Plusieurs fichiers en onglets ; sauvegarde auto possible",
        ],
        "tw_h3": "Rédacteurs d'articles et guides",
        "tw_li": [
            "Comme un éditeur classique — la mise en forme apparaît tout de suite",
            "PDF, page web, image ou Word",
            "Formules et schémas simples (aperçu hors ligne)",
            "Correction orthographique",
        ],
        "feat_h2": "Ce que fait Beardy",
        "feat_p": "L'essentiel — en langage simple.",
        "modes_h2": "Quatre façons de voir le même document",
        "modes_p": "Les noms dans l'app sont en anglais — voici ce qu'ils signifient.",
        "shots_h2": "À quoi ressemble l'app",
        "shots_p": "Captures à venir. Voir <a href=\"../SCREENSHOTS.md\">SCREENSHOTS.md</a>.",
        "cta_h2": "Essayez Beardy sur Mac",
        "cta_p": "Par <strong>Konstantin Shkurko</strong>. Aide — guide sur ce site.",
        "cta_btn": "Ouvrir le guide pas à pas",
        "footer_tag": "Éditeur Markdown simple pour Mac. Auteur : Konstantin Shkurko.",
        "footer_site": "Site",
        "footer_langs": "Langues",
        "mode_edit": "Texte avec symboles seulement",
        "mode_live": "Texte formaté en direct",
        "mode_split": "Texte à gauche, rendu à droite",
        "mode_preview": "Rendu final seulement",
        "og_title_fix": "Beardy — Simple Markdown Editor for Mac",
        "twitter_desc": "Éditeur Markdown clair : écrire, aperçu, PDF.",
    },
    "es": {
        "html_lang": "es",
        "lang_btn": "ES",
        "canonical_home": "https://beardy.app/es/",
        "og_locale": "es_ES",
        "og_title": "Beardy — Editor Markdown sencillo para Mac",
        "og_description": "Escribe y ve el resultado al momento. Para Mac.",
        "json_desc": "Editor Markdown sencillo para Mac.",
        "title_home": "Beardy — Editor Markdown sencillo para Mac",
        "desc_home": "Beardy es un editor Markdown claro para Mac: escribe, ve el resultado, guarda en PDF. Por Konstantin Shkurko.",
        "skip": "Ir al contenido",
        "nav_how": "Cómo empezar",
        "nav_features": "Funciones",
        "nav_modes": "Vistas",
        "nav_guide": "Instrucciones",
        "nav_download": "Descargar",
        "eyebrow": "Para Mac · Notas y documentos",
        "h1": "Un editor claro para archivos Markdown",
        "hero_lead": "<strong>Markdown</strong> es una forma sencilla de escribir: títulos, listas y enlaces con caracteres normales (por ejemplo <code>#</code> para un título). Beardy muestra cómo se verá el texto — al escribir o en otra ventana.",
        "cta_primary": "Descargar Beardy",
        "cta_secondary": "Cómo usar la aplicación",
        "hero_note": "Tus archivos quedan en tu Mac. La app puede guardar sola. La vista previa funciona sin Internet.",
        "steps_h2": "Empezar en tres pasos",
        "steps_p": "No hace falta curso — abre la app y escribe.",
        "step1": "<strong>Instala Beardy</strong> y ábrelo. Verás: documento nuevo, abrir archivo o arrastrar un archivo a la ventana.",
        "step2": "<strong>Escribe.</strong> Barra de herramientas para negrita, título, lista — o escribe los símbolos Markdown.",
        "step3": "<strong>Elige la vista:</strong> solo símbolos, solo formato, o ambos a la vez. Luego guarda o exporta a PDF.",
        "steps_link": "Guía paso a paso completa",
        "audience_h2": "¿Para quién es Beardy?",
        "audience_p": "Para quien escribe textos largos, instrucciones o documentación en Mac.",
        "dev_h3": "Programadores",
        "dev_li": [
            "El código en el texto se colorea",
            "Lista de títulos — clic para ir a la sección",
            "Deshacer funciona al cambiar de vista",
            "Varios archivos en pestañas; autoguardado",
        ],
        "tw_h3": "Autores de artículos y guías",
        "tw_li": [
            "Como un editor normal — el formato se ve al instante",
            "Guardar en PDF, página web, imagen o Word",
            "Fórmulas y diagramas simples (vista previa sin red)",
            "Corrección ortográfica",
        ],
        "feat_h2": "Qué puede hacer Beardy",
        "feat_p": "Lo principal — en palabras sencillas.",
        "modes_h2": "Cuatro formas de ver el mismo documento",
        "modes_p": "En la app los nombres están en inglés — aquí su significado.",
        "shots_h2": "Cómo se ve la aplicación",
        "shots_p": "Capturas pendientes. Ver <a href=\"../SCREENSHOTS.md\">SCREENSHOTS.md</a>.",
        "cta_h2": "Prueba Beardy en tu Mac",
        "cta_p": "Por <strong>Konstantin Shkurko</strong>. Ayuda — guía en este sitio.",
        "cta_btn": "Abrir guía paso a paso",
        "footer_tag": "Editor Markdown sencillo para Mac. Autor: Konstantin Shkurko.",
        "footer_site": "Sitio",
        "footer_langs": "Idiomas",
        "mode_edit": "Solo texto con símbolos",
        "mode_live": "Texto formateado al escribir",
        "mode_split": "Texto a la izquierda, resultado a la derecha",
        "mode_preview": "Solo aspecto final",
        "og_title_fix": "Beardy — Simple Markdown Editor for Mac",
        "twitter_desc": "Editor Markdown claro: escribir, vista previa, PDF.",
    },
}

FEATURES = {
    "ru": [
        ("Четыре режима просмотра", "Только текст, только оформление, оба рядом или только результат. Можно переключать — история «отменить» сохраняется."),
        ("Кнопки на панели", "Жирный, курсив, заголовки, списки, ссылки и код — одним нажатием, если не хотите запоминать символы."),
        ("Содержание по заголовкам", "Сбоку список разделов. Нажали на строку — документ прокрутился к этому месту."),
        ("Формулы и схемы", "Если нужны формулы или блок-схема в тексте — приложение покажет их в просмотре (без интернета)."),
        ("Светлая и тёмная тема", "Выберите удобный вид — светлый, тёмный или как в системе Mac."),
        ("Экспорт", "Сохранить в PDF, веб-страницу, картинку или Word. Книга EPUB — если установить бесплатную программу Pandoc."),
    ],
    "de": [
        ("Vier Ansichten", "Nur Text, nur Format, beides nebeneinander oder nur Ergebnis. Wechseln jederzeit — Rückgängig bleibt."),
        ("Toolbar-Tasten", "Fett, Kursiv, Überschriften, Listen, Links, Code — ein Klick, ohne Symbole auswendig."),
        ("Inhaltsverzeichnis", "Überschriftenliste — Klick scrollt zur Stelle."),
        ("Formeln und Diagramme", "Mathe oder Flussdiagramm in der Vorschau (offline)."),
        ("Hell und dunkel", "Helles, dunkles Design oder wie am Mac eingestellt."),
        ("Export", "PDF, Webseite, Bild oder Word. EPUB mit kostenlosem Pandoc."),
    ],
    "fr": [
        ("Quatre affichages", "Texte seul, rendu seul, côte à côte, ou résultat seul. L'annulation est conservée."),
        ("Boutons de la barre", "Gras, italique, titres, listes, liens, code — un clic."),
        ("Sommaire", "Liste des titres — clic pour y aller."),
        ("Formules et schémas", "Maths ou diagramme en aperçu (hors ligne)."),
        ("Clair et sombre", "Thème clair, sombre ou comme le Mac."),
        ("Export", "PDF, page web, image ou Word. EPUB avec Pandoc gratuit."),
    ],
    "es": [
        ("Cuatro vistas", "Solo texto, solo formato, ambos, o solo resultado. Deshacer se mantiene."),
        ("Botones de la barra", "Negrita, cursiva, títulos, listas, enlaces, código — un clic."),
        ("Índice de títulos", "Lista de secciones — clic para ir allí."),
        ("Fórmulas y diagramas", "Mates o diagrama en vista previa (sin red)."),
        ("Claro y oscuro", "Tema claro, oscuro o como el Mac."),
        ("Exportar", "PDF, web, imagen o Word. EPUB con Pandoc gratis."),
    ],
}


def patch_index(html: str, code: str, t: dict) -> str:
    html = html.replace('lang="en"', f'lang="{t["html_lang"]}"', 1)
    html = re.sub(r"<title>.*?</title>", f"<title>{t['title_home']}</title>", html, count=1)
    html = re.sub(
        r'<meta name="description" content="[^"]*"',
        f'<meta name="description" content="{t["desc_home"]}"',
        html,
        count=1,
    )
    html = re.sub(r'<link rel="canonical" href="[^"]*"', f'<link rel="canonical" href="{t["canonical_home"]}"', html, 1)
    html = re.sub(r'<meta property="og:url" content="[^"]*"', f'<meta property="og:url" content="{t["canonical_home"]}"', html, 1)
    html = re.sub(r'"url": "https://beardy\.app/en/"', f'"url": "{t["canonical_home"]}"', html, 1)
    html = re.sub(
        rf'<link rel="alternate" hreflang="{code}" href="[^"]*"',
        f'<link rel="alternate" hreflang="{code}" href="{t["canonical_home"]}"',
        html,
        1,
    )
    html = html.replace('<meta property="og:locale" content="en_US">', f'<meta property="og:locale" content="{t["og_locale"]}">')
    html = html.replace('<meta property="og:title" content="Beardy — Simple Markdown Editor for Mac">', f'<meta property="og:title" content="{t["og_title"]}">')
    html = html.replace(
        'content="Write in Markdown and see the formatted result. For Mac. Easy to start."',
        f'content="{t["og_description"]}"',
    )
    html = html.replace('"description": "Simple Markdown editor for Mac."', f'"description": "{t["json_desc"]}"', 1)
    html = html.replace(
        'content="A clear Markdown editor: write, preview, export to PDF."',
        f'content="{t["twitter_desc"]}"',
    )
    html = html.replace('"inLanguage": "en"', f'"inLanguage": "{t["html_lang"]}"')
    html = html.replace(">EN</button>", ">" + t["lang_btn"] + "</button>", 1)
    html = re.sub(r'<a href="\.\./en/" data-lang="en" aria-current="page"', '<a href="../en/" data-lang="en"', html)
    html = html.replace(f'<a href="../{code}/" data-lang="{code}"', f'<a href="../{code}/" data-lang="{code}" aria-current="page"', 1)

    nav_map = [
        (">How it works</a>", "nav_how"),
        (">What it does</a>", "nav_features"),
        (">View modes</a>", "nav_modes"),
        (">How to use</a>", "nav_guide"),
        (">Download</a>", "nav_download"),
    ]
    for en, key in nav_map:
        html = html.replace(en, ">" + t[key] + "</a>")

    reps = [
        ("Skip to content", t["skip"]),
        ("For Mac · For notes and documents", t["eyebrow"]),
        ("A clear editor for Markdown files", t["h1"]),
        (
            "<strong>Markdown</strong> is a simple way to write text: headings, lists, and links are marked with ordinary characters (for example <code>#</code> for a heading). Beardy shows how your text will look — while you type or in a separate window.",
            t["hero_lead"],
        ),
        ("Download Beardy", t["cta_primary"]),
        ("How to use the app", t["cta_secondary"]),
        (
            "Your files stay on your Mac. The app can save changes automatically. Preview works without the internet.",
            t["hero_note"],
        ),
        ("How to start in three steps", t["steps_h2"]),
        ("No manual or special training needed — open the app and write.", t["steps_p"]),
        (
            "<strong>Install Beardy</strong> on your Mac and open it. You will see buttons: create a new document, open a file, or drag a file into the window.",
            t["step1"],
        ),
        (
            "<strong>Write your text.</strong> Use the toolbar for bold, headings, and lists — or type Markdown symbols yourself.",
            t["step2"],
        ),
        (
            "<strong>Choose how to view:</strong> text only, formatted text only, or text and preview side by side. Save or export to PDF when ready.",
            t["step3"],
        ),
        ("Full step-by-step guide", t["steps_link"]),
        ("Who is Beardy for?", t["audience_h2"]),
        ("For anyone who writes long texts, instructions, or code documentation on a Mac.", t["audience_p"]),
        ("Programmers", t["dev_h3"]),
        ("Authors of articles and guides", t["tw_h3"]),
        ("What Beardy can do", t["feat_h2"]),
        ("The main features — in plain language.", t["feat_p"]),
        ("Four ways to view the same document", t["modes_h2"]),
        ("The names in the app are in English — here is what each one means.", t["modes_p"]),
        ("What the app looks like", t["shots_h2"]),
        (
            'Screenshots will be added here. How to take them — in <a href="../SCREENSHOTS.md">SCREENSHOTS.md</a> (for the site owner).',
            t["shots_p"],
        ),
        ("Try Beardy on your Mac", t["cta_h2"]),
        (
            "Created by <strong>Konstantin Shkurko</strong> (Константин Шкурко). Questions about the app — see the guide on this site.",
            t["cta_p"],
        ),
        ("Open step-by-step guide", t["cta_btn"]),
        (
            "A simple Markdown editor for Mac. Author: Konstantin Shkurko (Константин Шкурко).",
            t["footer_tag"],
        ),
        (">Site</h4>", ">" + t["footer_site"] + "</h4>"),
        (">Languages</h4>", ">" + t["footer_langs"] + "</h4>"),
        ("<strong>Edit</strong><span>Only your text, with symbols</span>", f'<strong>Edit</strong><span>{t["mode_edit"]}</span>'),
        ("<strong>Live</strong><span>Text looks formatted as you type</span>", f'<strong>Live</strong><span>{t["mode_live"]}</span>'),
        ("<strong>Split</strong><span>Text on the left, result on the right</span>", f'<strong>Split</strong><span>{t["mode_split"]}</span>'),
        ("<strong>Preview</strong><span>Only the finished look, no symbols</span>", f'<strong>Preview</strong><span>{t["mode_preview"]}</span>'),
    ]
    for a, b in reps:
        html = html.replace(a, b)

    dev_old = [
        "<li>Code in documents is highlighted in color</li>",
        "<li>A list of headings on the side — click to jump to a section</li>",
        "<li>Undo works even if you switch the view mode</li>",
        "<li>Several files open in tabs; auto-save available</li>",
    ]
    tw_old = [
        "<li>Edit like in a normal editor — formatting appears right away</li>",
        "<li>Save as PDF, web page, image, or Word file</li>",
        "<li>Formulas and simple charts in the text (no internet needed for preview)</li>",
        "<li>Spell check while typing</li>",
    ]
    for o, n in zip(dev_old, [f"<li>{x}</li>" for x in t["dev_li"]]):
        html = html.replace(o, n)
    for o, n in zip(tw_old, [f"<li>{x}</li>" for x in t["tw_li"]]):
        html = html.replace(o, n)

    for (etitle, edesc), (ntitle, ndesc) in zip(FEATURES_EN, FEATURES[code]):
        html = html.replace(f"<h3>{etitle}</h3>\n            <p>{edesc}</p>", f"<h3>{ntitle}</h3>\n            <p>{ndesc}</p>")

    return html


def main():
    en_index = (EN / "index.html").read_text(encoding="utf-8")
    for code, t in LOCALES.items():
        out = ROOT / code
        out.mkdir(exist_ok=True)
        (out / "index.html").write_text(patch_index(en_index, code, t), encoding="utf-8")
        guide_src = GUIDES / f"{code}.html"
        if guide_src.is_file():
            shutil.copy(guide_src, out / "guide.html")
            print("wrote", code, "(index + guide)")
        else:
            print("wrote", code, "(index only — missing guides/" + code + ".html)")


if __name__ == "__main__":
    main()
