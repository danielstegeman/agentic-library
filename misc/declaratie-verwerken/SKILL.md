---
name: declaratie-verwerken
description: Process expense receipts for monthly declarations. Use this skill whenever the user wants to process receipts from the bonnetjes folder, fill in or update the declaration spreadsheet (declaratieformulier), scan receipts for date and amount, move or rename receipt files to month folders, or handle anything related to expense declarations. Always use this skill for any task involving a declaraties folder, bonnetjes, or declaratieformulier.
---

# Declaratie Verwerken

Process receipts from `bonnetjes/` into monthly Excel declaration files.

## Paths

```
BASE_DIR  = current working directory
BONNETJES = <BASE_DIR>/bonnetjes/
TEMPLATE  = ~/.claude/skills/declaratie-verwerken/Declaratieformulier template.xlsx
SCRIPT    = ~/.claude/skills/declaratie-verwerken/scripts/process_expense.py
```

## Folder structure

```
<project>/
├── bonnetjes/                              ← incoming receipts (process these)
├── declaratie-config.json                  ← user config (name, expense types)
└── <YYYY>/                                 ← year folder, e.g. 2026/
    └── <MM-maand>/                         ← e.g. 04-april/
        ├── Declaratieformulier <naam> MM-YY.xlsx
        └── <receipt files>
```

Dutch month names: `januari februari maart april mei juni juli augustus september oktober november december`
Month folder format: `MM-maand` (e.g. `01-januari`, `04-april`, `12-december`)
Excel filename format: `Declaratieformulier <naam> MM-YY.xlsx`

## Expense subjects

Use the most specific label that fits:

| Subject | When to use |
|---------|-------------|
| `hotel` | Hotel overnight stay |
| `eten` | Meal — restaurant, lunch, dinner |
| `ontbijt` | Breakfast (if separate from hotel) |
| `trein` | Train ticket (NS or international) |
| `taxi` | Taxi, Uber, Bolt |
| `ov` | Other public transport (bus, tram, metro) |
| `parking` | Parking garage or lot |
| `brandstof` | Fuel |
| `vliegtuig` | Flight |
| `representatie` | Client entertainment |
| `kantoor` | Office supplies |
| `software` | Software, license, subscription |
| `cursus` | Training, course, conference |
| `telefoon` | Phone or internet costs |
| `overig` | Anything that doesn't fit above |

---

## Step 0 — Setup (first time or unknown user)

Before processing, check whether `declaratie-config.json` exists in BASE_DIR.

**If it does not exist:**
1. Ask: *"Wat is je volledige naam?"* (full name for the Excel filename)
2. Ask: *"Wat voor soort declaraties verwacht je? (bijv. hotel, eten, trein, parking)"*
3. Create `declaratie-config.json`:
```json
{
  "name": "<full name>",
  "expected_expenses": ["hotel", "eten", "..."]
}
```
4. Create `bonnetjes/` folder if it doesn't exist.

**If it exists:** read `name` and `expected_expenses` from it.

---

## Step 1 — List receipts in bonnetjes/

Use Glob pattern `bonnetjes/*` (relative to BASE_DIR) to find all files.
Skip hidden files and non-receipt files.

---

## Step 2 — Read each receipt

Use the Read tool on each file. Claude has vision for images (JPEG, PNG) and can read PDFs.

Extract:
- **date** — date of purchase or stay (format: YYYY-MM-DD)
  - Hotel bookings: use check-in date
  - Bank statements: use the transaction date
  - WhatsApp images: the filename often contains the send date as a fallback
- **amount** — total in EUR (look for "Totaal", "Total", "Te betalen", the largest prominent number, or the debit amount on bank statements)
- **subject** — pick the best match from the subjects table above

### When to ask for clarification

**Ask the user before processing** if any of the following is true:
- The date cannot be determined from the receipt or filename
- The amount is ambiguous (multiple totals, foreign currency without clear rate)
- The category is genuinely unclear (e.g. a generic store name with no visible items)
- The receipt is for an amount significantly higher or lower than what `expected_expenses` would suggest

Ask concisely: *"Bon [filename]: kan je me helpen? [specific question]"*

Do **not** ask if you can make a confident best guess — just note it in the summary.

---

## Step 3 — Run the processing script for each receipt

```bash
python "$HOME/.claude/skills/declaratie-verwerken/scripts/process_expense.py" \
  "<BASE_DIR>" \
  "<full_path_to_receipt>" \
  "<YYYY-MM-DD>" \
  "<subject>" \
  "<amount>" \
  "<name>"
```

The script will automatically:
- Find or create the `<YYYY>/<MM-maand>/` folder
- Copy the template to create `Declaratieformulier <naam> MM-YY.xlsx` if it doesn't exist yet
  - Template is looked up in: skill folder → BASE_DIR → created from scratch
- Rename the receipt to `YYYY-MM-DD-subject.ext` and move it to the month folder
- Add a row: Datum | Omschrijving | Bijlage/Bon nr. | Bedrag | Door werknemer betaald
- Sort all rows by date, then filename

Process all receipts before reporting. If unsure about a detail, ask first (see Step 2).

---

## Step 4 — Report

```
Verwerkt:
  2026-04-14-hotel.pdf   →  2026/04-april/  |  hotel  |  EUR 95.55
  2026-04-14-eten.jpeg   →  2026/04-april/  |  eten   |  EUR 27.20
  ...

Excel bijgewerkt:
  Declaratieformulier Jan Jansen 04-26.xlsx  (2 rijen toegevoegd)
```

Note any receipts where you guessed the date, amount, or category.

---

## Excel structure (for reference)

Sheet **Blad1**:

| Column | Field | Notes |
|--------|-------|-------|
| A | Datum | Date of expense |
| B | Omschrijving | Subject label |
| C | Bijlage/Bon nr. | Receipt filename |
| D | Bedrag | Amount in EUR |
| E | Door werknemer betaald | Same as Bedrag |

- B4: employee name
- B5: month/year
- Data rows start at row 9
- SUM formula in column E (auto-extended by script)
