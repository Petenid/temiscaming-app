"""Turns the MRC de Témiscamingue's printed collection calendar (PDF) into data.

Run once a year, when the MRC publishes the new calendar (spec D4):

    pip install pymupdf
    python tools/mrc_calendar.py path/to/calendar.pdf 2027

It writes functions/data/mrc-2027.json and prints a readable table. Before
committing, check that table against the printed calendar by eye.

How the PDF is drawn (2026 edition): each month is a grid of day cells. A day
with one bin is a filled rectangle (green, blue or black). A week with two bins
is drawn as small split-cell images (two diagonal halves). Days without a
coloured cell have no pickup.

Témiscaming town is collected on Tuesdays and Lumsden/Letang on Wednesdays. If
a sector's day has no pickup but the next day is coloured, the pickup moved one
day later (as on 24-25 June 2026); every such shift is printed for review.
"""

import datetime
import json
import pathlib
import re
import sys

import pymupdf

MONTHS = ("Janvier Février Mars Avril Mai Juin Juillet Août Septembre "
          "Octobre Novembre Décembre").split()
SECTOR_WEEKDAY = {"town": 1, "lumsden": 2}  # Monday = 0
BIN_TO_MATERIAL = {"green": "compost", "blue": "recycling", "black": "garbage"}
ZOOM = 6  # render scale for reading split-cell images


def colour_name(rgb):
    """Names a fill colour (0-1 floats or 0-255 ints); None if not a bin colour."""
    r, g, b = [v / 255 if v > 1 else v for v in rgb]
    if max(r, g, b) < 0.25:
        return "black"
    if g > 0.45 and g > r + 0.2 and g > b + 0.15:
        return "green"
    if b > 0.45 and b > r + 0.3 and b > g + 0.1:
        return "blue"
    return None


def is_cell(rect):
    return 15 < rect.width < 22 and 11 < rect.height < 17


def read_days(pdf_path, year):
    """Returns {date: set of bin colours} for every day printed in the grid."""
    page = pymupdf.open(pdf_path)[0]
    pixmap = page.get_pixmap(matrix=pymupdf.Matrix(ZOOM, ZOOM))
    words = page.get_text("words")

    plain_cells = []
    for drawing in page.get_drawings():
        if drawing.get("fill") is None:
            continue
        for item in drawing["items"]:
            if item[0] == "re" and is_cell(item[1]):
                plain_cells.append((item[1], colour_name(drawing["fill"])))
    split_cells = [pymupdf.Rect(info["bbox"]) for info in page.get_image_info()
                   if is_cell(pymupdf.Rect(info["bbox"]))]

    def pixel(x, y):
        return pixmap.pixel(int(x * ZOOM), int(y * ZOOM))

    days = {}
    for header in (w for w in words if w[4] in MONTHS):
        month = MONTHS.index(header[4]) + 1
        for w in words:
            in_grid = (header[0] - 60 < w[0] < header[0] + 170
                       and header[1] + 25 < w[1] < header[1] + 150)
            if not in_grid or not re.fullmatch(r"\d{1,2}", w[4]):
                continue
            try:
                date = datetime.date(year, month, int(w[4]))
            except ValueError:
                continue
            centre = pymupdf.Point((w[0] + w[2]) / 2, (w[1] + w[3]) / 2)
            bins = {name for rect, name in plain_cells
                    if name and rect.contains(centre)}
            for rect in split_cells:
                if rect.contains(centre):
                    # Sample the two diagonal halves, away from the printed number.
                    for fx, fy in ((0.12, 0.15), (0.2, 0.12), (0.88, 0.85), (0.8, 0.88)):
                        name = colour_name(pixel(rect.x0 + fx * rect.width,
                                                 rect.y0 + fy * rect.height))
                        if name:
                            bins.add(name)
            days[date] = bins
    return days


def sector_pickups(days, year):
    """Per sector: list of {date, materials}; plus the one-day shifts found."""
    result = {sector: [] for sector in SECTOR_WEEKDAY}
    shifts = []
    monday = datetime.date(year, 1, 1)
    monday -= datetime.timedelta(days=monday.weekday())
    while monday.year <= year:
        for sector, weekday in SECTOR_WEEKDAY.items():
            day = monday + datetime.timedelta(days=weekday)
            if day.year != year:
                continue
            bins = days.get(day, set())
            if not bins:
                next_day = day + datetime.timedelta(days=1)
                if days.get(next_day):
                    shifts.append((sector, day, next_day))
                    day, bins = next_day, days[next_day]
            if bins:
                materials = sorted(BIN_TO_MATERIAL[b] for b in bins)
                result[sector].append({"date": day.isoformat(), "materials": materials})
        monday += datetime.timedelta(days=7)
    return result, shifts


def main():
    pdf_path, year = sys.argv[1], int(sys.argv[2])
    days = read_days(pdf_path, year)
    pickups, shifts = sector_pickups(days, year)

    out = pathlib.Path(__file__).resolve().parent.parent / "functions" / "data" / f"mrc-{year}.json"
    out.parent.mkdir(exist_ok=True)
    data = {
        "source": "MRC de Témiscamingue, Calendrier de collecte sélective",
        "year": year,
        "note": f"Generated by tools/mrc_calendar.py from the printed PDF; checked by eye before commit.",
        "sectors": pickups,
    }
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"wrote {out}")
    print("one-day shifts (check these):", *(f"{s} {a} → {b}" for s, a, b in shifts) or ["none"])
    names = {"compost": "vert", "recycling": "bleu", "garbage": "noir"}
    by_date = {s: {p["date"]: p["materials"] for p in pickups[s]} for s in pickups}
    print(f"\n{'week of':<12} {'town (Tue)':<26} lumsden (Wed)")
    monday = datetime.date(year, 1, 1) - datetime.timedelta(days=datetime.date(year, 1, 1).weekday())
    while monday.year <= year:
        cols = []
        for sector in ("town", "lumsden"):
            week = [d for d in by_date[sector]
                    if 0 <= (datetime.date.fromisoformat(d) - monday).days < 7]
            cols.append(" ".join(f"{d[5:]} {'+'.join(names[m] for m in by_date[sector][d])}"
                                 for d in week) or "—")
        print(f"{monday.isoformat():<12} {cols[0]:<26} {cols[1]}")
        monday += datetime.timedelta(days=7)


if __name__ == "__main__":
    main()
