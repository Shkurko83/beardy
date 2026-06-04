#!/usr/bin/env python3
"""Apply pirate BlackBeard translations to localized index.html from en/index.html."""
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
EN_INDEX = ROOT / "en" / "index.html"

# Longest phrases first per locale (order matters)
RU = [
    ('lang="en"', 'lang="ru"'),
    (">EN</button>", ">RU</button>"),
    ("https://beardyeditor.com/en/", "https://beardyeditor.com/ru/"),
    ('hreflang="en" href="https://beardyeditor.com/en/"', 'hreflang="en" href="https://beardyeditor.com/en/"'),
    ('<a href="../en/" data-lang="en" aria-current="page" hreflang="en">', '<a href="../en/" data-lang="en" hreflang="en">'),
    ('<a href="../ru/" data-lang="ru" hreflang="ru">', '<a href="../ru/" data-lang="ru" aria-current="page" hreflang="ru">'),
    ("Skip to content", "Перейти к содержанию"),
    ("Captain's decree", "Указ капитана"),
    ("Boarding plan", "План абордажа"),
    ("Loot", "Добыча"),
    ("How to sail", "Как плавать"),
    ("Plunder", "Захватить"),
    ("Ahoy, Mac · Blackbeard's writing deck", "Эй, Mac · Каюта Чёрной Бороды"),
    ("Write your logbooks like a captain", "Пишите журналы как капитан"),
    (
        "<strong>BlackBeard Editor</strong> is a Markdown editor for Mac — plain text that turns into handsome documents. Notes, README files, ship's articles… feed the parrot later; write now.",
        "<strong>BlackBeard Editor</strong> — редактор Markdown для Mac: обычный текст превращается в аккуратные документы. Заметки, README, корабельные уставы… попугая покормите потом — пишите сейчас.",
    ),
    ("Plunder the app (free)", "Захватить приложение (бесплатно)"),
    ("How to sail the editor", "Как плавать в редакторе"),
    (
        "Files stay on your Mac. Auto-save keeps your treasure from sinking. Preview works offline — no shore connection needed.",
        "Файлы на вашем Mac. Автосохранение не даст сокровищам утонуть. Просмотр без интернета — берег не нужен.",
    ),
    ("The Captain's decree", "Указ капитана"),
    (
        "This application is <em>far too expensive</em> for honest merchants — because the price is <strong>zero doubloons</strong>. You cannot buy what was never sold. So we invite you to do the only sensible thing:",
        "Это приложение <em>слишком дорогое</em> для честных купцов — потому что цена <strong>ноль дублонов</strong>. Купить то, что не продавали, нельзя. Поэтому разумный поступок один:",
    ),
    ("Pirate it here. Legally. For Mac.", "Спиратить его здесь. Законно. Для Mac."),
    ("No pieces of eight. No subscription. No royal tax.", "Ни восьмых. Ни подписки. Ни королевской пошлины."),
    (
        "We are not Blackbeard's ghost — but the logo has a gold tooth. Fair warning.",
        "Мы не призрак Чёрной Бороды — но на лого золотой зуб. Считайте предупреждением.",
    ),
    ("Walk the plank only if you close the app without saving.", "Сойдёте по доске только если закроете приложение без сохранения."),
    ("Steal this editor from us. We insist.", "Украдьте редактор у нас. Мы настаиваем."),
    ("Boarding plan in three steps", "План абордажа в три шага"),
    ("Even a landlubber can hoist sail in minutes.", "И сухопутный матрос поднимет парус за минуты."),
    (
        "<strong>Take the ship.</strong> Install BlackBeard Editor on your Mac and open it — new log, open a file, or drag one aboard.",
        "<strong>Захватите корабль.</strong> Установите BlackBeard Editor на Mac — новый журнал, открыть файл или перетащить в окно.",
    ),
    (
        "<strong>Scratch your charts.</strong> Write with toolbar buttons or Markdown marks — headings, lists, code for the crew.",
        "<strong>Чертите карты.</strong> Пишите кнопками панели или знаками Markdown — заголовки, списки, код для команды.",
    ),
    (
        "<strong>Choose your spyglass.</strong> Text only, pretty view, or split deck — then export to PDF when the voyage is done.",
        "<strong>Выберите подзорную трубу.</strong> Только текст, красивый вид или палуба пополам — потом PDF, когда рейд окончен.",
    ),
    ("Full sailing manual", "Полный морской устав"),
    ("Who sails with us?", "Кто плывёт с нами?"),
    ("Developers, scribes, and anyone who drafts long texts on macOS.", "Разработчики, писцы и все, кто пишет длинные тексты на macOS."),
    ("Code corsairs", "Кодовые корсары"),
    ("Syntax-colored code blocks in your scrolls", "Цветной код в свитках"),
    ("Jump through chapters via the headings list", "Прыжок по разделам в списке заголовков"),
    ("Undo survives when you switch view modes", "Отмена переживает смену режима"),
    ("Many tabs; auto-save like a careful quartermaster", "Много вкладок; автосохранение как у бертольда"),
    ("Scribes &amp; chroniclers", "Писцы и летописцы"),
    ("Live mode — see formatted prose as you type", "Live — оформление видно при наборе"),
    ("Export PDF, web page, image, or Word", "PDF, веб-страница, картинка или Word"),
    ("Formulas and diagrams offline in the hold", "Формулы и схемы в трюме без сети"),
    ('Spell check so “arr” is not the only word spelled right', "Орфография — чтобы не только «арр» было верно"),
    ("What's in the hold", "Что в трюме"),
    ("The loot — explained without navy jargon.", "Добыча — без флотского жаргона."),
    ("Four view modes", "Четыре режима"),
    ("Edit, Live, Split, Preview — same document, different spyglasses. Switch freely; undo stays with you.", "Edit, Live, Split, Preview — один документ, разные трубы. Переключайте; отмена с вами."),
    ("Toolbar cutlasses", "Сабли на панели"),
    ("Bold, headings, lists, links, code — one click each if you do not memorize the runes.", "Жирный, заголовки, списки, ссылки, код — по клику, если руны не зубрите."),
    ("Chart of headings", "Карта заголовков"),
    ("A side panel lists your sections. Click — the scroll jumps there. No treasure map required.", "Сбоку список разделов. Клик — прокрутка туда. Карта сокровищ не нужна."),
    ("Math &amp; sea charts", "Математика и морские карты"),
    ("Formulas and Mermaid diagrams render in preview — still works when you're off the grid.", "Формулы и Mermaid в просмотре — работает без берега."),
    ("Dark &amp; gold themes", "Тёмная и золотая тема"),
    ("Light, dark, or match your Mac — like switching between night raid and noon parley.", "Светлая, тёмная или как у Mac — ночной рейд или полуденная попытка."),
    ("Export scrolls", "Экспорт свитков"),
    ("PDF, HTML, PNG, DOCX — and EPUB if you install Pandoc (free, like this editor).", "PDF, HTML, PNG, DOCX — EPUB, если поставить Pandoc (бесплатно, как редактор)."),
    ("Four ways to read the same log", "Четыре способа читать один журнал"),
    ("Names in the app stay in English — here is the pirate's translation.", "В приложении имена на английском — ниже перевод пирата."),
    ("Raw marks on parchment", "Сырые метки на пергаменте"),
    ("Fancy script while you write", "Красивый текст при наборе"),
    ("Marks port, pretty starboard", "Метки на борту, красота на штирборте"),
    ("Captain's final copy only", "Только финальная копия капитана"),
    ("Sights from the deck", "Виды с палубы"),
    ("App screenshots coming soon. Captain's orders:", "Скриншоты скоро. Приказ капитана:"),
    ("Hoist the colors — download for Mac", "Поднимите флаг — скачать для Mac"),
    (
        "Built by <strong>Konstantin Shkurko</strong> (Константин Шкурко). The real Blackbeard never edited Markdown — but you can.",
        "Создал <strong>Константин Шкурко</strong>. Настоящая Чёрная Борода Markdown не правила — но вы можете.",
    ),
    ("Open the sailing manual", "Открыть морской устав"),
    ("Pirate Markdown editor for Mac · beardyeditor.com · Konstantin Shkurko.", "Пиратский редактор Markdown для Mac · beardyeditor.com · Константин Шкурко."),
    ("Deck", "Палуба"),
    ("View modes", "Режимы"),
    ("Languages", "Языки"),
    ("BlackBeard Editor — Pirate Markdown Editor for Mac", "BlackBeard Editor — пиратский Markdown-редактор для Mac"),
    (
        "BlackBeard Editor: a brutal pirate-themed Markdown editor for Mac. Too expensive to buy? Pirate it here — free. By Konstantin Shkurko (Константин Шкурко).",
        "BlackBeard Editor — брутальный пиратский Markdown-редактор для Mac. Слишком дорого купить? Спиратите здесь — бесплатно. Автор: Константин Шкурко.",
    ),
    ('aria-label="BlackBeard Editor home"', 'aria-label="BlackBeard Editor — главная"'),
    ("alt=\"BlackBeard Editor — pirate skull logo with hat and gold tooth\"", "alt=\"BlackBeard Editor — пиратский череп с шляпой и золотым зубом\""),
]

DE = [
    ('lang="en"', 'lang="de"'),
    (">EN</button>", ">DE</button>"),
    ("https://beardyeditor.com/en/", "https://beardyeditor.com/de/"),
    ('<a href="../en/" data-lang="en" aria-current="page" hreflang="en">', '<a href="../en/" data-lang="en" hreflang="en">'),
    ('<a href="../de/" data-lang="de" hreflang="de">', '<a href="../de/" data-lang="de" aria-current="page" hreflang="de">'),
    ("Skip to content", "Zum Inhalt springen"),
    ("Captain's decree", "Befehl des Kapitäns"),
    ("Boarding plan", "Enterplan"),
    ("Loot", "Beute"),
    ("How to sail", "Bedienung"),
    ("Plunder", "Plündern"),
    ("Ahoy, Mac · Blackbeard's writing deck", "Ahoy, Mac · Schreibdeck der Schwarzen Bart"),
    ("Write your logbooks like a captain", "Schreiben Sie Logbücher wie ein Kapitän"),
    ("Plunder the app (free)", "App plündern (kostenlos)"),
    ("How to sail the editor", "So steuern Sie den Editor"),
    ("Pirate it here. Legally. For Mac.", "Hier piraten. Legal. Für Mac."),
    ("The Captain's decree", "Befehl des Kapitäns"),
    ("Boarding plan in three steps", "Enterplan in drei Schritten"),
    ("Who sails with us?", "Wer segelt mit?"),
    ("What's in the hold", "Was im Laderaum liegt"),
    ("Hoist the colors — download for Mac", "Flagge hissen — Download für Mac"),
    ("BlackBeard Editor — Pirate Markdown Editor for Mac", "BlackBeard Editor — Piraten-Markdown-Editor für Mac"),
]

FR = [
    ('lang="en"', 'lang="fr"'),
    (">EN</button>", ">FR</button>"),
    ("https://beardyeditor.com/en/", "https://beardyeditor.com/fr/"),
    ('<a href="../en/" data-lang="en" aria-current="page" hreflang="en">', '<a href="../en/" data-lang="en" hreflang="en">'),
    ('<a href="../fr/" data-lang="fr" hreflang="fr">', '<a href="../fr/" data-lang="fr" aria-current="page" hreflang="fr">'),
    ("Skip to content", "Aller au contenu"),
    ("Captain's decree", "Décret du capitaine"),
    ("Boarding plan", "Plan d'abordage"),
    ("Loot", "Butin"),
    ("How to sail", "Mode d'emploi"),
    ("Plunder", "Piller"),
    ("Pirate it here. Legally. For Mac.", "Piratez ici. Légalement. Pour Mac."),
    ("The Captain's decree", "Décret du capitaine"),
    ("BlackBeard Editor — Pirate Markdown Editor for Mac", "BlackBeard Editor — éditeur Markdown pirate pour Mac"),
]

ES = [
    ('lang="en"', 'lang="es"'),
    (">EN</button>", ">ES</button>"),
    ("https://beardyeditor.com/en/", "https://beardyeditor.com/es/"),
    ('<a href="../en/" data-lang="en" aria-current="page" hreflang="en">', '<a href="../en/" data-lang="en" hreflang="en">'),
    ('<a href="../es/" data-lang="es" hreflang="es">', '<a href="../es/" data-lang="es" aria-current="page" hreflang="es">'),
    ("Skip to content", "Ir al contenido"),
    ("Captain's decree", "Decreto del capitán"),
    ("Boarding plan", "Plan de abordaje"),
    ("Loot", "Botín"),
    ("How to sail", "Cómo usar"),
    ("Plunder", "Saquear"),
    ("Pirate it here. Legally. For Mac.", "Piratéalo aquí. Legal. Para Mac."),
    ("The Captain's decree", "Decreto del capitán"),
    ("BlackBeard Editor — Pirate Markdown Editor for Mac", "BlackBeard Editor — editor Markdown pirata para Mac"),
]

LOCALES = {"ru": RU, "de": DE, "fr": FR, "es": ES}


def apply(code: str, pairs: list[tuple[str, str]]) -> None:
    text = EN_INDEX.read_text(encoding="utf-8")
    for a, b in pairs:
        text = text.replace(a, b)
    out = ROOT / code / "index.html"
    out.write_text(text, encoding="utf-8")
    print("wrote", out)


def main():
    for code, pairs in LOCALES.items():
        apply(code, pairs)


if __name__ == "__main__":
    main()
