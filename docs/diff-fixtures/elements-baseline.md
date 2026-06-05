# Markdown Elements — Baseline

Reference document with common Markdown / GFM elements supported in Beardy2.

## Headings

### Third level

#### Fourth level

##### Fifth level

###### Sixth level

## Inline text

Plain paragraph with **bold**, *italic*, ~~strikethrough~~, ***bold italic***, `inline code`, and a [link to Apple](https://www.apple.com "Apple home").

Autolink test: <https://example.com>

Line with explicit break (two trailing spaces):  
Second line after soft break.

## Blockquote

> Blockquote line one.
> Blockquote line two with **bold** and `code` inside.

## Thematic break

---

## Unordered list

- North item
- Center item
  - Nested alpha
  - Nested beta
- South item

## Ordered list

1. Prepare
2. Execute
  1. Sub-step A
  2. Sub-step B
3. Review

## Task list

- [x] Completed task
- [ ] Open task
- [ ] Another open task

## Fenced code (Swift)

```swift
struct Article {
    let title: String
    let wordCount: Int
}
```

## Fenced code (plain)

```
plain text block
no language tag
```

## Mermaid diagram

```mermaid
flowchart LR
    A[Start] --> B{Choice}
    B -->|Yes| C[Done]
    B -->|No| D[Retry]
```

## Table

| Feature     | Status | Notes        |
|-------------|--------|--------------|
| Headings    | OK     | H1–H6        |
| Tables      | OK     | GFM style    |
| Code blocks | OK     | Highlighting |
| Images      | OK     | Local paths  |

## Image

![Sample diagram](assets/sample-diagram.png "Diagram title")

## Math

Inline: $E = mc^2$

Display:

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

## Raw HTML snippet

<kbd>Cmd</kbd> + <kbd>S</kbd> to save.

## Closing

Final paragraph. Fixture label: **baseline**.
