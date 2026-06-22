# Глубокое ревью документов Markdown-парсера

## Главный вывод (meta)

План **не был исправлен** после прошлого ревью. Из 21 проверки регрессии (C1–C8, M1–M13, где M8 отсутствует) — **0 исправлено, 2 частично исправлены, 19 остались как есть**:

- **C1–C8 (критические):** 7 still-present (C1, C2, C4, C5, C6, C8 — критичны; C7 минорен), 1 partially-fixed (C3). **Ни один критический дефект прошлого ревью не устранён.**
- **M1–M13 (мажорные):** 11 still-present (M1, M2, M3, M4, M5, M6, M9, M10, M12, M13), 1 partially-fixed (M7). **Ни один мажорный дефект прошлого ревью не устранён.**

Это означает, что план прошёл ревью, зафиксировал замечания в отдельном файле, но **не внёс ни одной правки в собственный текст задач**. Документ остался в том же состоянии, что и до прошлого ревью, плюс добавились новые, ранее не замеченные дефекты (F1-CRITICAL, L18-C1/C2, F5, F7 и др.). Верdict по мета-уровню: **regression is total** — план не отвечает на ревью вообще.

---

## Доказательная база — критические находки (severity critical)

### K1. Псевдо-двухпроходность: inline-парсинг eager, прямые ссылки не резолвятся
- **ID:** F1-CRITICAL / C1 (regression) / F1 (test-quality) — три линзы сошлись на одном дефекте
- **Где:** Спец §3 строки 133, 149, 151–152; план Task 14 строки 1374–1379; Task 16 строка 1531; Task 14 Interfaces строка 1259; тесты Task 21 строки 1983–1996, Task 25 строки 2221–2226; Self-Review строка 2346
- **Доказательство:** `MarkdownParser.parse` (1374–1379) делает один вызов `BlockParser(defs: defs).parse(lines[...])` и возвращает — никакого второго обхода AST. Task 16 (строка 1531): «In `BlockParser`, wherever content was `[.text(raw)]`, call `InlineParser(defs: defs).parse(raw)`» — inline-парсинг встроен в блок-скан, т.е. в Pass A.
- **Спец:** «This is why a second pass exists — a reference may be defined later in the document» (строка 149). Pass A должен ЗАВЕРШИТЬСЯ до начала Pass B.
- **Почему ломается:** Параграф `[Swift][sw]` флашится на blank line ДО того, как `[sw]: https://swift.org` зарегистрирован в DefinitionStore. `defs.link(for:"sw")` → nil → literal text. Тесты Task 21 (1984: `[Swift][sw]\n\n[sw]: https://swift.org`) и Task 25 (2222: `Text[^1]\n\n[^1]: note`) **заведомо падают** на Step 4 «Run, expect PASS».
- **Fix → микро-задача 16b:** Pass A хранит raw-текст на leaf-блоках; после `BlockParser.parse` и полного `DefinitionStore` — рекурсивный обход дерева с `InlineParser(defs:).parse(raw)`. Убрать eager-вызовы из BlockParser (Task 16). Перенумеровать так, чтобы 16b шёл до Tasks 21/25.

### K2. Диспетчер блоков: list-ветка стоит перед thematic-break — `- - -` становится списком
- **ID:** F3 (algo-block) / F4 (swift-compile) / C6 (regression) / F3 (test-quality)
- **Где:** Task 11 строка 1000 («after block quote, before blank handling»); Task 6 тест строка 526; `listMarker` строки 977–987
- **Доказательство:** `listMarker("- - -")` возвращает non-nil (first='-', rest.first==' ', guard 984 проходит). Финальный порядок: fence → blockQuote → **list** → blank → setext → thematicBreak → atx. Тест Task 6 (526): `#expect(MarkdownParser.parse("- - -").blocks == [.thematicBreak])` — **падает** после реализации Task 11.
- **CommonMark:** §4.1/§5.4 example 42 — `- - -`/`* * *` → `<hr/>`.
- **Fix:** Проверять `thematicBreak(line)` ДО list-ветки, либо guard в list-ветке.

### K3. Lazy continuation в списках поглощает headings/fences
- **ID:** F5 (algo-block) / C8 (regression)
- **Где:** Task 11 `parseList` строки 1048–1049
- **Доказательство:** `} else if listMarker(l) == nil { itemLines.append(l); i += 1 // lazy continuation }` — исключает только другие list-маркеры. `- a\n# H` → heading вкладывается в item вместо sibling.
- **CommonMark:** §4.12 — только параграф может лениво продолжаться; block-start прерывает контейнер.
- **Fix:** Добавить `isBlockStart(_ line:) -> Bool` (ATX, setext, fence, thematic break, blockquote, list, table, `:`, link/footnote def); lazy continuation только когда `!isBlockStart(line)`. Зеркало для blockquote (F4, строки 891–893).

### K4. Emphasis resolver: правило тройки — только комментарий, не в коде
- **ID:** L18-C1 (algo-inline) / F7 (swift-compile) / C3 (regression, partially-fixed) / F9 (test-quality)
- **Где:** Task 18 строки 1733–1741; строка 1765 (note); тесты Step 1 строки 1666–1685
- **Доказательство:** Строки 1738–1739: `// rule of 3: if either is both open&close, sum % 3 == 0 only when each %3==0` сразу за `openerPos = j; break` — безусловный break, нет `% 3` арифметики. `a*b**b**b*c`, `foo******bar*baz`, `***a b***c**` парсятся неправильно. Ни одного `%` в теле resolveEmphasis вне комментария.
- **CommonMark:** §6.2/§4.5.2 rule of 3.
- **Fix:** В цикле поиска opener-а пропускать кандидат, когда `(ocount + ccount) % 3 == 0 && ocount % 3 != 0 && ccount % 3 != 0` и delimiter может both open & close. Добавить тесты CM examples 413–427.

### K5. Emphasis resolver: openers_bottom отсутствует — алгоритм неэквивалентен canonical
- **ID:** L18-C2 (algo-inline) / C3 (regression)
- **Где:** Task 18 строки 1710–1762; строка 1713 (`var openers: [Int] = []`); строка 1765 note
- **Доказательство:** Только плоский `openers: [Int]` и `openers.removeAll { $0 > op }` (строка 1757, на успешном матче). На failed closer (строка 1745) `openers.append(i); i += 1` — никакого floor для (char, canOpen, length%3). План сам признаёт (строка 1765): «switch to the canonical CommonMark linked-list process_emphasis (openers_bottom per delimiter type...)» — как fallback, не как primary.
- **Fix:** Сделать canonical `process_emphasis` primary реализацией Task 18.

### K6. Adjacent .text nodes не коалесцируются — тест `unmatchedStarIsLiteral` падает
- **ID:** C2 (regression) / L17-C1 (algo-inline, minor)
- **Где:** Task 18 emit строки 1715–1724; Task 17 parse строки 1583–1612; тест строка 1684
- **Доказательство:** emit добавляет один `.text(...)` на delimiter-run + один `.literal` на literal token. `a * b` → `[.text("a "), .text("*"), .text(" b")]` (три узла). Тест (1684): `#expect(inlines("a * b") == [.text("a * b")])` — **падает**. grep по «coalesc/merge/adjacent» — 0 hits.
- **Fix:** Коалесцирующий pass в конце `InlineParser.parse` (и после resolveEmphasis) — мерджить consecutive `.text`, рекурсивно по детям emphasis/strong/strikethrough/link.

### K7. Intraword underscore rule отсутствует — `a_b_c` парсится как emphasis
- **ID:** C4 (regression) / L18-C3 (algo-inline, major) / F4 (test-quality, major)
- **Где:** Task 18 `classifyFlanking` строки 1700–1708; тест строка 1680
- **Доказательство:** `classifyFlanking` возвращает только (left, right) без char-specific branch для `_`. Для `a_b_c` оба `_` — left-flanking AND right-flanking → canOpen=canClose=true → резолвер образует emphasis на `b`. Тест (1680): `#expect(inlines("a_b_c") == [.text("a_b_c")])` — **падает**.
- **CommonMark:** §4.5 — `_` can open только если left-flanking AND (!right-flanking OR preceded by punctuation).
- **Fix:** Передать delimiter char в classifyFlanking; для `_` добавить intraword-условие.

### K8. Loose-list detection сломан — blank lines внутри item не сбрасывают isTight
- **ID:** C5 (regression) / F10 (algo-block, major) / F6 (test-quality, major)
- **Где:** Task 11 `parseList` строки 1034, 1044, 1052
- **Доказательство:** Внутренний цикл (1044) проглатывает blank line в `itemLines.append("")` без `isTight = false`. `sawBlank` (1034) — только во внешнем цикле, недостижим для intra-item blanks. `isTight = isTight && true` (1052) — no-op. `- a\n\n  b` → isTight==true (CM: loose). Тест `looseListWhenBlankBetweenItems` (955–959) — **падает** для inter-item case тоже (blank проглатывается внутренним циклом).
- **CommonMark:** §5.2.2.
- **Fix:** `isTight = false` при blank внутри item; трекать blanks на границах items.

### K9. `normalizeHTML` используется, но нигде не определён — test target не компилируется
- **ID:** F2 (swift-compile) / L2 (task-sequence) / M12 (regression) / F10 (spec-coverage)
- **Где:** Task 26 строка 2302; Step 1 строка 2263 (только `astToHTML`)
- **Доказательство:** Строка 2302: `if normalizeHTML(produced) != normalizeHTML(c.html) { failures.append(c.example) }`. grep по всему плану — ровно 1 hit, определений 0. `ConformanceTests.swift` не компилируется → `swift test` не запускается.
- **Fix:** Определить `normalizeHTML(_:)` в ConformanceHTML.swift (collapse whitespace, sort attributes) либо перейти на curated-AST подход (строка 2259 рекомендует именно его, но Step 1 всё равно строит HTML-рендерер — внутреннее противоречие, F13).

### K10. Task 1 не компилируется standalone (ссылается на типы из Task 2)
- **ID:** L1 (task-sequence) / D1 (decomposition)
- **Где:** Task 1 строки 78–88, 105–108
- **Доказательство:** `MarkdownDocument` (78–85) использует `[MarkdownBlock]` и `[FootnoteDefinition]`, определённые только в Task 2. Строка 88: «Do Task 2's Step 1 file creation together with this step so the module compiles». Step 5 (105): «Expected: PASS (after the AST model from Task 2 exists)». Нарушает per-task green invariant.
- **Fix:** Слить Task 2 Step 1 в Task 1.

---

## Мажорные

| ID | Где | Суть | CommonMark | Fix → задача |
|---|---|---|---|---|
| F1 (algo-block) | Task 3 строки 288–310; все indentation checks (461, 540, 819, 885, 978, 743, 1332) | Tabs не раскрываются в 4-колоночные stops; `\t# H` misclassified | §2.1 | expandTabs pass в Task 3 |
| F2 (algo-block) / M3 | Task 5 (461), 6 (540), 7 (605), 8 (743), 10 (880), 14 (1332), 15 (1437) | `drop(while: { $0 == " " })` без ≤3 bound; `    # H` → heading вместо code | §5.1/5.3/5.4/5.5/6.1 | `stripUpTo3Spaces` helper |
| F4 (algo-block) | Task 10 строки 891–893 | Block-quote lazy continuation поглощает headings/fences | §4.12 | `isBlockStart` guard (см. K3) |
| F6 (algo-block) / M4 | Task 11 строки 1003–1009 | Нет canInterruptParagraph: `foo\n2. bar` → параграф + список start=2 | §5.2 | guard: bullet OR ordered==1 AND non-empty item |
| F7 (algo-block) | Task 13 строки 1220–1224 | Table прерывает параграф без `paragraph.isEmpty` guard | GFM §4.1 | guard `paragraph.isEmpty` |
| F8 (algo-block) / M6 | Task 8 строки 707–716, 740 | Fence indent не записан, content не strip; `   ```\n   code` → code с 3 пробелами | §5.5 | хранить indent в Fence, strip content |
| F9 (algo-block) / M6 | Task 8 строки 753–757 | isFenceCloser: `allSatisfy` запрещает trailing spaces; `drop(while spaces)` без ≤3 | §5.5 | strip trailing whitespace, cap leading ≤3 |
| F10 (algo-block) / C5 | Task 11 строки 1034, 1044, 1052 | Loose-list: blank внутри item не сбрасывает isTight (см. K8) | §5.2.2 | — |
| F11 (algo-block) | Task 14 строки 1331–1350; guard 1321 | Link-ref-def: нет multi-line titles, нет `<dest>`, нет escapes, нет trailing-junk validation, не прерывает параграф | §6.1 | переписать helper, убрать `paragraph.isEmpty` guard |
| F12 (algo-block) / M13 | Task 14 строки 1362–1366 | Footnote body обрезается на первой blank line; multi-paragraph невозможны | Pandoc | peek-ahead через blank к indented line |
| F13 (algo-block) / M5 | Task 15 строки 1437–1454 | Definition list: все `:` lines мерджатся в один detail; `details: [[MarkdownBlock]]` всегда 1 элемент | PHP Markdown Extra | каждый `:` — отдельный detail |
| F2-MAJOR (spec-coverage) | Task 23 строки 2114–2115, 2143, 2130–2138 | GFM bare EMAIL autolinks не реализованы, не протестированы | GFM §6.9 | +test, +email detection |
| F3-MAJOR (spec-coverage) | Task 26 строка 2272 | GFM fixtures hand-authored (~15), не official | спец §6 строка 184 | скачать official GFM fixtures |
| L24-C1 / M1 | Task 24 строки 2155–2200 vs Task 4 (357), Task 7 (593), Task 9 (797) | softBreak ломает multi-line `.text` тесты Tasks 4/7/9; план не обновляет их | §6.7 | обновить 3 теста в Task 24 |
| L20-C1 | Task 20 строки 1891–1892, 2020 | image alt = raw bracket text, не stripped text content | §6.5 | parse interior, reduce to text |
| L20-C2 / M7 | Task 20 строки 1938–1944 | extractTitle не валидирует leftover после title; нет escape handling | §5.3/6.3 | reject on non-ws leftover, handle `\\` |
| L20-C3 / M7 | Task 20 строки 1923–1936, 1903–1921 | `<dest>` без whitespace-separation; нет `\>` escapes; code spans не opaque для bracket matching | §5.3/6.3 | ws-requirement, escapes, backtick opacity |
| L14-C1 | Task 14 строки 1331–1350 | linkReferenceDefinition: нет `<dest>`, нет `(...)` title, нет multi-line | §5.3 | rewrite helper |
| L23-C1 / M9 | Task 23 строки 2108–2151 | GFM autolink trailing-punctuation: только `.,!?)`, нет `*_~?:`, нет balanced-paren | GFM §6.9 | full punctuation set + paren balance |
| F1 (swift-compile) | Task 22 строка 2071 | `indexOf` used but never defined — compile error | — | inline scan или helper |
| F3 (swift-compile) | Task 26 строки 2263, 2301 | `astToHTML` referenced, no implementation snippet | — | предоставить реализацию |
| F4 (swift-compile) | Task 11 / Task 6 тест | = K2 | — | — |
| L3 (task-sequence) | Task 18 строки 1710–1762, 1765 | resolveEmphasis acknowledged-fiddly, per-task green нарушен для riskiest unit | §6.2 | canonical process_emphasis primary |
| L5 (task-sequence) | L331, L1151, L1259, L1467/L1538 | Interface text врёт про "Pass B" — скрывает K1 | — | выровнять prose после fix K1 |
| F2 (test-quality) | Task 26 строки 2263, 2279–2281, 2302 | conformance harness: normalizeHTML undefined, astToHTML no impl, knownSkippedExamples empty | — | см. K9 |
| F3 (test-quality) | Task 6 (526) / Task 11 (1000) | = K2 | — | — |
| F4 (test-quality) | Task 18 (1680) / classifyFlanking (1700–1708) | = K7 | — | — |
| F5 (test-quality) | Task 4 (357), 7 (593), 9 (797) vs 2178 | = L24-C1 / M1 | — | — |
| F9 (test-quality) | Task 18 строки 1683–1685, 1765 | `a * b` (один `*`) не различает flanking-correct от broken; rule-of-3 cases только в prose note, не в Step 1 | §6.2 | +`a * b * c`, +`***a***`, +`*a**b**c*`, +`**a*b*c**` |

---

## Минорные / nit

- **F4-MINOR:** Conformance test — loop внутри одного `@Test`, не parameterized (`@Test(arguments:)`) (Task 26 строки 2297–2305; спец §6 строка 185).
- **F5-MINOR:** known-skips как `Set<Int>` без per-case reason (Task 26 строка 2280; спец §6 строка 187).
- **F6-MINOR:** SwiftLint success criterion условный; нет `.swiftlint.yml` (Task 27 строка 2331; спец строка 199).
- **F7-MINOR:** HTML pass-through — explicit spec decision, но нет implementing task и нет теста (спец строки 37–39, 129, 191–192).
- **F8-MINOR:** Footnote reference conditional на definition existence — спец §5 строка 171 unconditional; план Task 25 строка 2211 добавляет условие (тест 2229–2232 кодирует deviation).
- **F9-MINOR:** `DefinitionStore` как `final class` в напряжении с «value types only, no classes» (спец §1 строки 54–55; план Task 14 строка 1291). Это internal, не AST — но constraint не scoped.
- **F11-MINOR:** Multi-line link reference definitions не обработаны (single-line only) (Task 14 строки 1331–1350).
- **F14-MINOR:** listMarkerWidth не cap-ит spaces-after-marker на 4 (≥5 diverges) (Task 11 строки 985–986, 994–996).
- **F15-MINOR:** setext/thematic trailing-whitespace: drops spaces but not tabs (Task 7 строка 608, Task 6 строка 540).
- **L22-C1 (minor):** Autolink URI: пустой after-colon принимается (`<mailto:` → autolink); email validation слишком loose (Task 22 строки 2083–2096).
- **L18-C4 (minor):** Flanking punctuation использует Swift Unicode categories, не CommonMark punctuation set (Task 18 строки 1702, 1706).
- **F8 (test-quality, minor):** `inlines()` helper читает только `.blocks.first`, возвращает `[]` для multi-block — silent-pass для stray-block регрессий (9 копий: 1485, 1560, 1661, 1796, 1842, 1978, 2052, 2125, 2172).
- **F11 (test-quality, minor):** Email autolink хранит raw `a@b.com` без `mailto:` — divergence от cmark не документирована (Task 22 строка 2062).
- **F12 (test-quality, minor):** Task 26 нет GFM conformance test; `SpecCase` без `section` (строки 2253, 2272, 2290).
- **F14 (test-quality, minor):** Несколько CommonMark edge cases без Step 1 теста: `#nope`, setext после non-paragraph, unmatched backticks, indented-code blank-line interior.
- **F15 (test-quality, minor):** linkReferenceDefinition title только `"`/`'`, нет `(...)`; multi-line unsupported (Task 14 строки 1345–1348).
- **AST-2..AST-11:** серия minor/nit по AST API — footnote ordinal не хранится, footnote id exact vs link normalize (асимметрия недокументирована), image alt String vs link content, MarkdownTable alignment count не type-enforced, ordered list per-item number не хранится, codeBlock info string обрезается до первого слова, hardBreak/softBreak bare cases sufficient, definitionList empty-details edge.
- **swift-compile nits:** F10 (`extractTitle` dead `s.isEmpty ? nil : nil`), F11 (`!paragraph.isEmpty == false` → `paragraph.isEmpty`), F12 (`isTight = isTight && true` no-op), F13 (`isIndentedCode` redundant ternary), F5 (parseList без `extension BlockParser`), F6 (`hasFootnote` в API но без impl), F8 (DefinitionStore final class tension), F9 (`import Foundation` parenthetical only).

---

## Разбивка на микро-задачи для параллельных агентов

### Wave 0 (один агент, один коммит) — foundation
- **W0-T1:** Слить Task 1 + Task 2 Step 1 — module scaffold + полный AST model + smoke + model tests. **blockedBy:** ничего. **Scope:** `Sources/MarkdownAST/{MarkdownParser.swift,MarkdownBlock.swift,MarkdownInline.swift}`, `Package.swift`, smoke test. Один компилируемый green коммит.

### Wave 1 (после W0) — fan-out
- **W1-T3:** `splitIntoLines` + **expandTabs** (4-col stops). blockedBy: W0. Scope: `Line.swift`.
- **W1-T26a:** AST→HTML renderer `astToHTML(MarkdownDocument)->String`. blockedBy: **только W0** (не зависит от парсера). Scope: `ConformanceHTML.swift`.
- **W1-T26b:** `normalizeHTML(_:)` helper. blockedBy: ничего. Scope: pure string function.
- **W1-T26c:** fixture download + `.copy("Resources")` в Package.swift + `loadSpec` decoder. blockedBy: ничего. Scope: механика.
- **W1-T14store:** `DefinitionStore` class (normalize/addLink/link(for:)/addFootnote/hasFootnote). blockedBy: **только W0** (нужен `FootnoteDefinition`). Scope: `DefinitionStore.swift`, unit-test в изоляции.

→ **6 параллельных агентов** сразу после W0.

### Wave 2 (после W1-T3) — block dispatcher skeleton
- **W2-T4:** BlockParser skeleton + paragraph accumulation + **trim per-line whitespace** (M10). blockedBy: W1-T3. Scope: `BlockParser.swift` dispatcher + paragraph flush. Это последовательный gate для block-side.

### Wave 3 (после W2-T4, с per-file split из D2) — блок-конструкции, fan-out
- **W3-T5:** ATX heading (со `stripUpTo3Spaces`). blockedBy: W2-T4.
- **W3-T6:** Thematic break (с ≤3 indent). blockedBy: W2-T4.
- **W3-T8:** Fenced code (indent recording, content strip, closer rules — M6). blockedBy: W2-T4.
- **W3-T10:** Block quote (с `isBlockStart` lazy guard — K3/F4). blockedBy: W2-T4.
- **W3-T13:** Table (с `paragraph.isEmpty` guard — F7). blockedBy: W2-T4.
- **W3-T15:** Definition list (каждый `:` — отдельный detail — M5/F13). blockedBy: W2-T4.
- **W3-T14wire:** BlockParser wiring DefinitionStore + link/footnote def collection. blockedBy: W1-T14store, W2-T4.

→ **7 параллельных** (при per-file decomposition из D2).

### Wave 4 (после Wave 3) — зависимые блоки
- **W4-T7:** Setext heading. blockedBy: W3-T6 (ordering vs thematic).
- **W4-T9:** Indented code. blockedBy: W3-T8 (index loop).
- **W4-T11a:** `listMarker` recognizer. blockedBy: W2-T4.
- **W4-T11e:** dispatch ordering fix — thematicBreak ПЕРЕД list (K2). blockedBy: W3-T6, W4-T11a.

### Wave 5 (после W4-T11a)
- **W5-T11b:** flat `parseList` (bullet only, single-level). blockedBy: W4-T11a.
- **W5-T11c:** nested lists (recursive `BlockParser().parse`). blockedBy: W5-T11b.
- **W5-T11d:** tight/loose rework (K8/C5 — blank tracking внутри item и на границах). blockedBy: W5-T11b.
- **W5-T12:** list item content continuation. blockedBy: W5-T11b.

### Wave 6 (после W3-T14wire, W2-T4) — inline-side gate
- **W6-T16:** InlineParser scaffold (text, escapes) — БЕЗ eager wiring в BlockParser. blockedBy: W3-T14wire, W2-T4.
- **W6-T16b:** **Pass B deferred inline walk** (K1 — скрытая prerequisite задача). blockedBy: W6-T16, W1-T14store. Scope: raw-payload representation на leaves + рекурсивный обход дерева после Pass A. **Это gates Tasks 21/25.**
- **W6-T17:** Code spans (tokenized scan). blockedBy: W6-T16.

### Wave 7 (после W6-T17) — emphasis split (D4)
- **W7-T18a:** `InlineToken` model + tokenizer. blockedBy: W6-T17.
- **W7-T18b:** `classifyFlanking` (pure). blockedBy: ничего (м.б. параллельно с 18a).
- **W7-T18e:** coalescing pass (K6/C2). blockedBy: ничего.

### Wave 8 (после W7-T18a + 18b)
- **W8-T18c:** `resolveEmphasis` core для `*` — canonical `process_emphasis` с openers_bottom + rule of 3 (K4/K5). blockedBy: W7-T18a, W7-T18b.
- **W8-T20a:** `matchBracket`/`matchParen`. blockedBy: W6-T16.
- **W8-T20b:** `splitDestinationAndTitle` + `extractTitle` (M7 fix). blockedBy: W6-T16.

### Wave 9 (после W8-T18c)
- **W9-T18d:** `_` intraword rules (K7/C4). blockedBy: W8-T18c.
- **W9-T20c:** inline link `parseInlineLinkOrImage`. blockedBy: W8-T20a, W8-T20b.
- **W9-T19:** Strikethrough. blockedBy: W8-T18c.
- **W9-T22:** Autolinks (URI + email, fix `indexOf`, fix validation). blockedBy: W8-T18c.

### Wave 10 (после W9)
- **W10-T20d:** image form `![alt](src)` (alt = stripped text content — L20-C1). blockedBy: W9-T20c.
- **W10-T20e:** wire links/images в tokenization. blockedBy: W9-T20c, W10-T20d, W8-T18c.
- **W10-T21:** Reference links (full/collapsed/shortcut) — **теперь работает** благодаря W6-T16b. blockedBy: W10-T20e, W6-T16b.
- **W10-T23:** GFM extended autolinks (bare URLs + **email** — F2-MAJOR; full trailing-punct set — M9). blockedBy: W9-T22.
- **W10-T24:** Soft/hard breaks — **с обновлением тестов Tasks 4/7/9** (L24-C1/M1). blockedBy: W8-T18c.
- **W10-T25:** Footnote references/definitions (multi-paragraph body — M13/F12; unconditional mapping — F8-MINOR). blockedBy: W10-T20e, W6-T16b, W3-T14wire.

### Wave 11 (после всего)
- **W11-T26d:** ConformanceTests.swift parameterized scaffold + KnownSkips с per-case reasons. blockedBy: W1-T26a/b/c + все feature tasks 5–25.
- **W11-T26e:** triage run + populate known-skips + official GFM fixtures (F3-MAJOR). blockedBy: W11-T26d.
- **W11-T27:** Final gate — `swift build`, `swift test`, SwiftLint (с `.swiftlint.yml` — F6-MINOR); HTML pass-through тесты (F7-MINOR); doc comments для limitations.

**Строго последовательные цепи:** W0 → W2-T4 → W6-T16 → W6-T17 → W7-T18a → W8-T18c → (W9-T18d | W9-T20c | W9-T22). Всё остальное — fan-out.

---

## Рекомендация: готов ли план к реализации?

**Verdict: NEEDS-REVISION.** Не rewrite (архитектура AST model и block/leaf dispatch в основе здравые), но до начала кодирования **обязательно** внести минимальный набор правок в текст плана:

### Блокирующее (must-fix перед coding):

1. **K1 — двухпроходность.** Добавить задачу 16b (Pass B deferred inline walk); убрать eager `InlineParser.parse` из BlockParser (Task 16 строка 1531); обновить `MarkdownParser.parse` (Task 14 строки 1374–1379). Без этого Tasks 21/25 заведомо красные.
2. **K2 — dispatch order.** Task 11 строка 1000: переместить thematic-break ПЕРЕД list-веткой. Без этого падает тест Task 6 (строка 526).
3. **K4/K5 — emphasis resolver.** Task 18: сделать canonical `process_emphasis` с `openers_bottom` и реальным rule-of-3 guard primary реализацией, не prose fallback.
4. **K6 — coalescing.** Task 18: добавить коалесцирующий pass. Без этого падает `unmatchedStarIsLiteral` (строка 1684).
5. **K7 — intraword `_`.** Task 18 `classifyFlanking`: добавить `_`-specific canOpen/canClose. Без этого падает `intrawordUnderscoreNotEmphasis` (строка 1680).
6. **K8 — loose-list.** Task 11: `isTight = false` на blank внутри item; убрать no-op `isTight = isTight && true`. Без этого падает `looseListWhenBlankBetweenItems` (строка 958).
7. **K3 — lazy continuation.** Tasks 10/11: `isBlockStart` guard. Без этого `> para\n# H` → неправильный AST.
8. **K9 — `normalizeHTML`/`astToHTML`.** Task 26: предоставить реализации либо перейти на curated-AST (строка 2259). Без этого test target не компилируется.
9. **K10 — Task 1 standalone.** Слить Task 2 Step 1 в Task 1.

### Настоятельно рекомендуется (до coding, недорого):

10. **F1/M2 — tabs.** expandTabs в Task 3.
11. **F2/M3 — ≤3 indent.** `stripUpTo3Spaces` helper во все openers.
12. **M4 — paragraph interruption.** canInterruptParagraph guard.
13. **M5 — definition list details.** Каждый `:` → отдельный detail.
14. **M6 — fence indent/closer.** Записать opening indent, strip content, closer rules.
15. **M7 — link dest/title.** Balanced parens, leftover rejection, escapes, code-span opacity.
16. **M9 — GFM autolink punct.** Full set `?!.,:*_~` + paren balance + bare email (F2-MAJOR).
17. **M10 — paragraph line trim.** Trim leading/trailing ws per line.
18. **M12 — normalizeHTML** (см. K9).
19. **M13 — footnote multi-paragraph.** Peek-ahead через blank.
20. **L24-C1/M1 — soft break regression.** Обновить тесты Tasks 4/7/9 в Task 24.
21. **L20-C1 — image alt.** Parse interior, strip markup.
22. **F3-MAJOR — GFM fixtures.** Скачать official, не hand-author.
23. **F1 (swift-compile) — `indexOf`.** Inline scan.
24. **L1/L3 — Task 18 risk.** Разбить на 18a–18e (D4).

### Может быть отложено (track, fix opportunistically):
- F4–F8 MINOR, F11, F14, F15, L18-C4, L22-C1, все AST-* nits, swift-compile nits, decomposition D2/D7 (per-file split exploitable только при параллельной диспетчеризации).

**Итог:** план содержит **9 критических дефектов**, каждый из которых либо ломает компиляцию test target, либо гарантированно падает на Step 4 «expect PASS» тестах самого плана, либо нарушает core-архитектурное обещание спецификации. Ни один дефект прошлого ревью не устранён. План **не готов к реализации в текущем виде**; после внесения 9 блокирующих правок (плюс желательно 24 настоятельных) — готов.