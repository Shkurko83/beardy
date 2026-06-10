# Как создать новую тему оформления в Black Beard Editor

Подробная инструкция для начинающих. Black Beard Editor использует **две связанные, но разные** системы оформления:

| Система | За что отвечает | Где настраивается в приложении |
|--------|------------------|--------------------------------|
| **Editor Theme** (`ThemeFamily`) | Фон, текст, заголовки, ссылки, таблицы, цитаты, inline-код, панели Edit/Live/Preview | **Settings → Editor Theme** |
| **Code Theme** (`CodeTheme`) | Подсветка синтаксиса внутри блоков ` ``` ` (highlight.js) | **Settings → Code blocks** |

Обычно вы создаёте **Editor Theme** (семейство цветов). **Code Theme** добавляют отдельно, если нужна своя подсветка кода или вы отключили «Match code blocks to editor theme».

---

## Часть 0. Что нужно перед началом

### Инструменты

- **Xcode** (та же версия, что для сборки Black Beard Editor)
- **Cursor** или любой редактор текста
- По желанию: [SF Symbols](https://developer.apple.com/sf-symbols/) не нужен для тем; полезен **Digital Color Meter** (macOS) — снять HEX с экрана

### Базовые понятия

- **Светлая / тёмная вариация** — у каждого `ThemeFamily` есть **два набора цветов**: `isDark: false` и `isDark: true`. В настройках переключатель «Dark appearance» выбирает между ними.
- **HEX-цвет** — строка вида `#0d1117` (6 символов после `#`). В коде используется `Color(hex: "#0d1117")`.
- **rawValue** — технический идентификатор темы латиницей без пробелов, например `ocean`, `rosePine`. По нему тема сохраняется в настройках пользователя.

### Главные файлы (запомните пути)

```
Black Beard Editor/
├── Black Beard Editor/Services/ThemeService.swift    ← Editor Theme + Code Theme (главный файл)
├── Black Beard Editor/Services/BundledHighlightJS.swift
├── Black Beard Editor/Services/EditorAppearanceSync.swift
├── Black Beard Editor/SettingsView.swift             ← UI настроек тем
├── Black Beard Editor/Utilities/Extensions/Color+Extensions.swift
├── HighlightJS/styles/*.min.css           ← CSS подсветки кода
└── codemirror-editor.html                 ← редактор (получает CSS из ThemeService)
```

---

## Часть 1. Создание новой Editor Theme (семейство, например «Ocean»)

Это то, что пользователь видит как **GitHub**, **Nord**, **Dracula** в списке **Editor Theme**.

### Шаг 1. Придумайте идентификатор и название

| Поле | Пример | Правила |
|------|--------|---------|
| `rawValue` (enum case) | `ocean` | camelCase, латиница, уникальный среди `ThemeFamily` |
| `displayName` | `Ocean` | Как показывать в UI |

### Шаг 2. Откройте `ThemeService.swift`

Файл: `Black Beard Editor/Services/ThemeService.swift`

Найдите enum **`ThemeFamily`** (примерно строка 97):

```swift
enum ThemeFamily: String, CaseIterable, Identifiable {
    case github = "github"
    case minimal = "minimal"
    // ...
}
```

**Добавьте новый case** (в конец списка, перед закрывающей `}`):

```swift
    case ocean = "ocean"
```

Значение справа от `=` **должно совпадать** с именем case, если вы не уверены — копируйте стиль существующих тем (`"github"`, `"nord"`).

### Шаг 3. Добавьте отображаемое имя

В том же файле найдите `var displayName: String` у `ThemeFamily` и ветку `switch self`:

```swift
        case .ocean: return "Ocean"
```

### Шаг 4. Задайте цвета (самый важный шаг)

В `ThemeFamily` найдите функцию **`func colors(isDark: Bool) -> ThemeColors`**.

Для **каждой** новой темы нужно **два блока** `ThemeColors(...)`:

1. `return isDark ? ThemeColors(...)` — **тёмная** версия (первый блок внутри `case .ocean:`)
2. `: ThemeColors(...)` — **светлая** версия (второй блок)

Скопируйте ближайшую по стилю существующую тему (например `.nord` или `.github`) и замените HEX-значения.

#### Что означает каждое поле `ThemeColors`

| Поле | Где видно в редакторе |
|------|------------------------|
| `background` | Фон страницы, Edit/Live/Preview |
| `text` | Основной текст абзацев |
| `secondaryText` | Второстепенный текст, номера строк (в паре с code theme), подписи |
| `heading` | Заголовки H1–H6 |
| `link` | Ссылки |
| `code` | Фон **inline**-кода `` `так` `` и подложка блоков кода (если включено «Match code blocks») |
| `codeText` | Цвет текста inline-кода |
| `selection` | Фон выделения текста |
| `border` | Рамки, разделители, цитаты (левая полоса), границы таблиц |
| `tableHeader` | Фон шапки таблицы |
| `tableStripe` | Фон чётных строк таблицы |

**Пример** (сокращённо — подставьте свои цвета):

```swift
        case .ocean:
            return isDark
                ? ThemeColors(
                    background: Color(hex: "#0b1e2d"),
                    text: Color(hex: "#e8f4fc"),
                    secondaryText: Color(hex: "#7eb8d4"),
                    heading: Color(hex: "#5ec8e8"),
                    link: Color(hex: "#5ec8e8"),
                    code: Color(hex: "#132a3d"),
                    codeText: Color(hex: "#f78c6c"),
                    selection: Color(hex: "#1a3a52"),
                    border: Color(hex: "#2a4a62"),
                    tableHeader: Color(hex: "#132a3d"),
                    tableStripe: Color(hex: "#0b1e2d")
                )
                : ThemeColors(
                    background: Color(hex: "#f0f9ff"),
                    text: Color(hex: "#0c4a6e"),
                    secondaryText: Color(hex: "#0369a1"),
                    heading: Color(hex: "#0284c7"),
                    link: Color(hex: "#0284c7"),
                    code: Color(hex: "#e0f2fe"),
                    codeText: Color(hex: "#c2410c"),
                    selection: Color(hex: "#bae6fd"),
                    border: Color(hex: "#7dd3fc"),
                    tableHeader: Color(hex: "#e0f2fe"),
                    tableStripe: Color(hex: "#f0f9ff")
                )
```

**Совет:** сначала настройте `background`, `text`, `heading`, `link`, проверьте в приложении, потом остальное.

### Шаг 5. Свяжите тему с подсветкой кода (по умолчанию)

Найдите **`func pairedCodeTheme(isDark: Bool) -> CodeTheme`** в `ThemeFamily`.

Для новой темы добавьте:

```swift
        case .ocean:
            return isDark ? .githubDark : .github   // или .atomOneDark / .solarizedDark и т.д.
```

Это тема highlight.js, которая подставится, когда включено **«Match code blocks to editor theme»**.

| Если ваша Editor Theme… | Часто подходящий CodeTheme |
|-------------------------|----------------------------|
| Светлая, нейтральная | `.github`, `.atomOneLight`, `.xcode` |
| Тёмная, нейтральная | `.githubDark`, `.atomOneDark`, `.vs2015` |
| Solarized-стиль | `.solarizedLight` / `.solarizedDark` |
| Dracula-стиль | `.dracula` |

### Шаг 6. (Опционально) Миграция старых настроек

Если у вас когда-то были пользователи с legacy-именем в `previewTheme`, добавьте case в **`migrateLegacyTheme`**:

```swift
        case "Ocean": themeFamily = .ocean; isDarkMode = false
        case "Ocean Dark": themeFamily = .ocean; isDarkMode = true
```

Новичкам можно пропустить, если тема новая с нуля.

### Шаг 7. Сборка и проверка Editor Theme

1. В Xcode: **Product → Clean Build Folder** (⇧⌘K)
2. **Product → Run** (⌘R)
3. Откройте **Black Beard Editor → Settings** (⌘,)
4. Раздел с **Editor Theme** — должна появиться **Ocean**
5. Выберите тему, переключите **Dark appearance**
6. Откройте документ, проверьте режимы **Edit**, **Live**, **Split**, **Preview**

**Где ещё применяется Editor Theme:**

- Оболочка приложения (боковая панель, вкладки) — через `NSApp.appearance` и `themeService.colors`
- WebView-редактор — CSS генерируется в `ThemeService.generateCSS()` и отправляется через `EditorAppearanceSync`

Менять `codemirror-editor.html` для обычной Editor Theme **не нужно**, если хватает полей `ThemeColors`.

---

## Часть 2. Создание новой Code Theme (подсветка в блоках кода)

Нужна, если:

- хотите отдельную подсветку, не совпадающую с Editor Theme;
- пользователь выключил **Match code blocks to editor theme** и выбирает тему вручную.

### Шаг 1. Получите CSS-файл highlight.js

Официальные стили: https://github.com/highlightjs/highlight.js/tree/main/src/styles  

Скачайте нужный `.css` (например `stackoverflow-light.css`).

### Шаг 2. Положите файл в проект

Папка в репозитории:

```
HighlightJS/styles/
```

Имя файла **строго**:

```
<rawValue>.min.css
```

Пример: для темы `stackoverflowLight` файл должен называться:

```
HighlightJS/styles/stackoverflow-light.min.css
```

если `rawValue = "stackoverflow-light"`.

> Папка `HighlightJS` уже подключена к Xcode как **folder reference** в Resources. Новые `.css` внутри `HighlightJS/styles/` обычно попадают в сборку автоматически после Clean Build.

**Минификация (рекомендуется):** переименуйте в `.min.css` или минифицируйте вручную — в проекте лежат именно `*.min.css`.

### Шаг 3. Добавьте case в `CodeTheme`

В `ThemeService.swift`, enum **`CodeTheme`**:

```swift
    case stackoverflowLight = "stackoverflow-light"
```

`rawValue` **должен совпадать** с именем файла без `.min.css`.

### Шаг 4. Укажите, светлая тема или тёмная

В `var isDark: Bool` у `CodeTheme`:

```swift
        case .stackoverflowLight:
            return false   // светлая
```

### Шаг 5. Фон блока кода `blockBackgroundHex`

В `var blockBackgroundHex: String`:

```swift
        case .stackoverflowLight: return "#f6f6f6"
```

Откройте ваш CSS, найдите фон у `.hljs` — используйте тот же HEX, иначе рамка блока и подсветка будут «плыть».

### Шаг 6. (Если создавали Editor Theme) Обновите `pairedCodeTheme`

```swift
        case .ocean:
            return isDark ? .githubDark : .stackoverflowLight
```

### Шаг 7. Проверка Code Theme

1. Clean Build (⇧⌘K), Run
2. Settings → отключите **Match code blocks to editor theme**
3. В списке **Code blocks** выберите новую тему
4. Вставьте в документ:

````markdown
```javascript
function hello() {
  const msg = "test";
  return msg;
}
```
````

5. Проверьте в **Live** и **Split** (превью)

---

## Часть 3. Как тема попадает в редактор (для понимания)

Цепочка без магии:

```
ThemeService.colors
    → generateCSS()  // CSS-переменные --md-bg, --md-text, …
    → EditorAppearanceSync.pushToEditor()
    → window.cmEditor.applyAppearance({ themeCSS, codeThemeURL, … })
    → codemirror-editor.html вставляет <style id="custom-theme-style">
```

Подсветка кода:

```
CodeTheme.bundledThemeURL
    → file:///.../HighlightJS/styles/github-dark.min.css
    → <link id="highlight-theme" href="...">
```

Если Editor Theme «не меняется» — смотрите консоль WebView (Safari → Develop → ваш Mac → Black Beard Editor).

---

## Часть 4. Расширенная настройка (необязательно)

### Изменить только CSS редактора, не трогая Swift-цвета

Можно дописать правила в конец `generateCSS(colors:)` в `ThemeService.swift` (внутри многострочной строки `return """ ... """`).

Используйте переменные:

- `var(--md-bg)`, `var(--md-text)`, `var(--md-heading)`, …

Селекторы уже заданы для `#preview-content`, `#live-editor`, `#markdown-textarea` — копируйте стиль из существующих блоков.

### Список в `AppConstants.Themes`

Файл `AppConstants.swift` содержит `struct Themes` с массивом `availableThemes` — это **устаревший справочник**. Реальный список тем в UI берётся из **`ThemeFamily.allCases`**. Обновлять `AppConstants` не обязательно, но можно для документации.

---

## Часть 5. Чеклист перед коммитом

- [ ] Новый `case` в `ThemeFamily` / `CodeTheme`
- [ ] `displayName` для Editor Theme
- [ ] Два набора `ThemeColors` (light + dark)
- [ ] `pairedCodeTheme` для нового семейства
- [ ] CSS-файл в `HighlightJS/styles/` с правильным именем (для Code Theme)
- [ ] `isDark` и `blockBackgroundHex` для Code Theme
- [ ] Clean Build + ручная проверка Settings
- [ ] Проверка Edit, Live, Split, Preview
- [ ] Блок кода с несколькими языками (js, python, plain text)
- [ ] Таблица, цитата, ссылка, inline-код

---

## Часть 6. Частые ошибки

| Симптом | Причина | Решение |
|---------|---------|---------|
| Темы нет в Settings | Забыли `case` или не пересобрали | Добавить в `ThemeFamily`, ⇧⌘K, Run |
| Тема в списке, но цвета как у GitHub | Скопировали case, не заменили `ThemeColors` | Проверить `case .вашаТема:` |
| Светлая/тёмная перепутаны | Перепутаны два блока в `colors(isDark:)` | Первый блок — `isDark ?` (тёмный), второй — светлый |
| Подсветка кода не работает | Нет файла или неверное имя | `rawValue` = имя файла без `.min.css` |
| Белый блок кода на тёмном фоне | Неверный `blockBackgroundHex` | Взять фон из `.hljs` в CSS |
| После смены темы «залипает» старое | Кэш WebView | Перезапустить приложение |
| HEX не применяется | Опечатка | Формат `#RRGGBB`, кавычки в `Color(hex: "#...")` |

---

## Краткая шпаргалка: только Editor Theme «Ocean»

1. `ThemeService.swift` → `ThemeFamily` → `case ocean = "ocean"`
2. `displayName` → `case .ocean: return "Ocean"`
3. `colors(isDark:)` → два блока `ThemeColors` для `.ocean`
4. `pairedCodeTheme` → `case .ocean: return isDark ? .githubDark : .github`
5. ⇧⌘K → Run → Settings → Ocean

---

## Краткая шпаргалка: только Code Theme

1. Положить `HighlightJS/styles/my-theme.min.css`
2. `CodeTheme` → `case myTheme = "my-theme"`
3. `isDark` + `blockBackgroundHex`
4. ⇧⌘K → Run → Settings → Code blocks

---

*Документ актуален для структуры репозитория Black Beard Editor с `ThemeService.swift` и офлайн-папкой `HighlightJS/`.*
