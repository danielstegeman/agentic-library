#!/usr/bin/env python3
"""
Process a single expense receipt: move it to the correct month folder and add a row
to the monthly declaration Excel file.

Usage:
    python process_expense.py <base_dir> <receipt_path> <date_YYYY-MM-DD> <subject> <amount> <name>

Arguments:
    base_dir      Root declaraties directory
    receipt_path  Full path to the receipt file (in bonnetjes/)
    date          Receipt date in YYYY-MM-DD format
    subject       Short description: hotel, eten, trein, taxi, parking, etc.
    amount        Amount in EUR as a decimal (e.g. 95.55)
    name          Full name of the employee (e.g. "Jan Jansen")

Example:
    python process_expense.py "/path/to/declaraties" "bonnetjes/receipt.jpg" "2026-04-14" "hotel" "95.55" "Jan Jansen"
"""

import sys
import os
import shutil
from datetime import datetime
import openpyxl
from openpyxl.styles import Font, Alignment, PatternFill

MONTHS = {
    1: 'januari', 2: 'februari', 3: 'maart', 4: 'april',
    5: 'mei', 6: 'juni', 7: 'juli', 8: 'augustus',
    9: 'september', 10: 'oktober', 11: 'november', 12: 'december',
}

SKILL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_START_ROW = 9


def month_folder_name(month: int) -> str:
    return f"{month:02d}-{MONTHS[month]}"


def get_excel_filename(year: int, month: int, name: str) -> str:
    return f"Declaratieformulier {name} {month:02d}-{str(year)[2:]}.xlsx"


def find_template(base_dir: str) -> str | None:
    """Look for a .xlsx template in skill folder, then base_dir."""
    # Skill folder first: any .xlsx starting with "Declaratieformulier"
    for f in os.listdir(SKILL_DIR):
        if f.lower().startswith('declaratieformulier') and f.endswith('.xlsx'):
            return os.path.join(SKILL_DIR, f)
    # Fall back to base_dir
    for f in os.listdir(base_dir):
        if f.lower().startswith('declaratieformulier') and 'template' in f.lower() and f.endswith('.xlsx'):
            return os.path.join(base_dir, f)
    return None


def find_totaal_row(ws) -> int:
    """Find the row containing 'Totaal' in column A, or return a default."""
    for row in range(DATA_START_ROW, 200):
        val = ws.cell(row=row, column=1).value
        if isinstance(val, str) and val.strip().lower() == 'totaal':
            return row
    return None


def find_name_cell(ws) -> str:
    """Detect which cell holds the employee name (look for 'Naam:' label)."""
    for row in range(1, 10):
        for col in range(1, 4):
            val = ws.cell(row=row, column=col).value
            if isinstance(val, str) and 'naam' in val.lower():
                return f"{chr(64 + col + 1)}{row}"  # cell to the right of label
    return 'B2'  # default


def find_month_cell(ws) -> str:
    """Detect which cell holds the month/year (look for 'Maand' label)."""
    for row in range(1, 10):
        for col in range(1, 4):
            val = ws.cell(row=row, column=col).value
            if isinstance(val, str) and 'maand' in val.lower():
                return f"{chr(64 + col + 1)}{row}"
    return 'B4'  # default


def ensure_sum_formulas(ws, totaal_row: int, last_data_row: int):
    """Add or extend SUM formulas at the totaal row for columns D and E."""
    for col in [4, 5]:  # D and E
        cell = ws.cell(row=totaal_row, column=col)
        formula = f'=SUM({chr(64+col)}{DATA_START_ROW}:{chr(64+col)}{last_data_row})'
        if cell.value is None or (isinstance(cell.value, str) and 'SUM' in cell.value.upper()):
            cell.value = formula


def create_blank_declaration(excel_path: str, year: int, month: int, name: str):
    """Create a fresh Info Support declaration .xlsx from scratch."""
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = 'Blad1'

    ws['A1'] = 'Declaratieformulier'
    ws['A1'].font = Font(bold=True, size=14)
    ws['A2'] = 'Naam:'
    ws['A2'].font = Font(bold=True)
    ws['B2'] = name
    ws['A4'] = 'Maand/Jaar:'
    ws['A4'].font = Font(bold=True)
    ws['B4'] = datetime(year, month, 1)
    ws['B4'].number_format = 'MMMM YYYY'

    header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')
    header_font = Font(bold=True, color='FFFFFF')
    headers = ['Datum', 'Omschrijving', 'Bijlage/Bon nr.', 'Bedrag', 'Door werknemer betaald']
    for col, header in enumerate(headers, start=1):
        cell = ws.cell(row=7, column=col, value=header)
        cell.font = header_font
        cell.fill = header_fill

    ws.column_dimensions['A'].width = 14
    ws.column_dimensions['B'].width = 22
    ws.column_dimensions['C'].width = 35
    ws.column_dimensions['D'].width = 12
    ws.column_dimensions['E'].width = 24

    totaal_row = DATA_START_ROW + 15
    ws.cell(row=totaal_row, column=1).value = 'Totaal'
    ws.cell(row=totaal_row, column=1).font = Font(bold=True)
    ensure_sum_formulas(ws, totaal_row, totaal_row - 1)

    wb.save(excel_path)


def ensure_month_folder(base_dir: str, year: int, month: int, name: str) -> tuple:
    """Create <year>/<MM-month>/ folder if needed. Returns (month_dir, excel_path)."""
    year_dir = os.path.join(base_dir, str(year))
    month_dir = os.path.join(year_dir, month_folder_name(month))
    os.makedirs(month_dir, exist_ok=True)

    excel_filename = get_excel_filename(year, month, name)
    excel_path = os.path.join(month_dir, excel_filename)

    if not os.path.exists(excel_path):
        template_path = find_template(base_dir)
        if template_path:
            shutil.copy2(template_path, excel_path)
            wb = openpyxl.load_workbook(excel_path)
            ws = wb['Blad1']
            ws[find_name_cell(ws)] = name
            ws[find_month_cell(ws)] = datetime(year, month, 1)
            # Ensure SUM formulas exist at the totaal row
            totaal_row = find_totaal_row(ws)
            if totaal_row:
                ensure_sum_formulas(ws, totaal_row, totaal_row - 1)
            wb.save(excel_path)
            print(f"Created from template: {excel_path}")
        else:
            create_blank_declaration(excel_path, year, month, name)
            print(f"Created (blank): {excel_path}")

    return month_dir, excel_path


def add_expense_row(excel_path: str, date: datetime, description: str, filename: str, amount: float):
    """Append an expense row to Blad1, pushing the totaal row down if needed."""
    wb = openpyxl.load_workbook(excel_path)
    ws = wb['Blad1']

    totaal_row = find_totaal_row(ws)

    # Find first empty data row
    target_row = None
    for row in range(DATA_START_ROW, 500):
        val = ws.cell(row=row, column=1).value
        if val is None or (isinstance(val, str) and val.strip().lower() == 'totaal'):
            target_row = row
            break

    if target_row is None:
        print("ERROR: Could not find an empty row in Blad1", file=sys.stderr)
        sys.exit(1)

    # If we've hit the totaal row, insert a row to push it down
    if totaal_row and target_row == totaal_row:
        ws.insert_rows(totaal_row)
        totaal_row += 1

    ws.cell(row=target_row, column=1).value = date
    ws.cell(row=target_row, column=2).value = description
    ws.cell(row=target_row, column=3).value = filename
    ws.cell(row=target_row, column=4).value = amount
    ws.cell(row=target_row, column=5).value = amount

    # Update SUM formulas to cover the new last data row
    if totaal_row:
        ensure_sum_formulas(ws, totaal_row, target_row)

    wb.save(excel_path)
    print(f"Row {target_row}: {date.strftime('%Y-%m-%d')} | {description} | {filename} | EUR {amount:.2f}")


def sort_expense_rows(excel_path: str):
    """Sort all data rows (DATA_START_ROW to totaal-1) by date, then filename."""
    wb = openpyxl.load_workbook(excel_path)
    ws = wb['Blad1']

    totaal_row = find_totaal_row(ws)
    end_row = (totaal_row - 1) if totaal_row else None

    rows = []
    for row in range(DATA_START_ROW, end_row + 1 if end_row else 500):
        val = ws.cell(row=row, column=1).value
        if val is None:
            break
        rows.append([ws.cell(row=row, column=col).value for col in range(1, 6)])

    if not rows:
        return

    rows.sort(key=lambda r: (r[0] if r[0] else datetime.min, r[2] or ''))

    for i, row_data in enumerate(rows):
        for col, val in enumerate(row_data, start=1):
            ws.cell(row=DATA_START_ROW + i, column=col).value = val

    # Refresh SUM to cover actual last data row
    if totaal_row:
        last_data = DATA_START_ROW + len(rows) - 1
        ensure_sum_formulas(ws, totaal_row, last_data)

    wb.save(excel_path)


def move_receipt(receipt_path: str, month_dir: str, date: datetime, subject: str) -> str:
    """Move receipt to month folder with standardized name. Returns new filename."""
    ext = os.path.splitext(receipt_path)[1].lower()
    new_filename = f"{date.strftime('%Y-%m-%d')}-{subject}{ext}"
    target_path = os.path.join(month_dir, new_filename)

    if os.path.exists(target_path):
        base = f"{date.strftime('%Y-%m-%d')}-{subject}"
        counter = 2
        while os.path.exists(os.path.join(month_dir, f"{base}-{counter}{ext}")):
            counter += 1
        new_filename = f"{base}-{counter}{ext}"
        target_path = os.path.join(month_dir, new_filename)

    shutil.move(receipt_path, target_path)
    print(f"Moved: {os.path.basename(receipt_path)} -> {new_filename}")
    return new_filename


def main():
    if len(sys.argv) != 7:
        print(__doc__)
        sys.exit(1)

    base_dir, receipt_path, date_str, subject, amount_str, name = sys.argv[1:]

    try:
        date = datetime.strptime(date_str, '%Y-%m-%d')
    except ValueError:
        print(f"ERROR: Invalid date '{date_str}', expected YYYY-MM-DD", file=sys.stderr)
        sys.exit(1)

    try:
        amount = float(amount_str)
    except ValueError:
        print(f"ERROR: Invalid amount '{amount_str}'", file=sys.stderr)
        sys.exit(1)

    if not os.path.exists(receipt_path):
        print(f"ERROR: File not found: {receipt_path}", file=sys.stderr)
        sys.exit(1)

    month_dir, excel_path = ensure_month_folder(base_dir, date.year, date.month, name)
    new_filename = move_receipt(receipt_path, month_dir, date, subject)
    add_expense_row(excel_path, date, subject, new_filename, amount)
    sort_expense_rows(excel_path)

    print(f"Done -> {excel_path}")


if __name__ == '__main__':
    main()
