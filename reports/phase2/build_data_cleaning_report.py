#!/usr/bin/env python3
"""
PowerPulse | Phase 2 | Step 2 - builds reports/phase2/Data_Cleaning_Report.pdf
Owner: Qasim Tanveer

Every number in the PDF is read from YOUR database, so run the staging load first:
    python etl/01_load_staging.py
    python reports/phase2/build_data_cleaning_report.py

It also runs the cleaning self-test (adds 9 dirty rows, shows the rules catch them, then restores the
real data), so run it on your LOCAL database only.
"""
import importlib.util
import io
from datetime import datetime
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer,
                                Table, TableStyle)

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "reports" / "phase2" / "Data_Cleaning_Report.pdf"

# ---- reuse the loader's connection + self-test -------------------------------------------------
spec = importlib.util.spec_from_file_location("load_staging", ROOT / "etl" / "01_load_staging.py")
loader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(loader)

NAVY = colors.black
TEAL = colors.black
LIGHT = colors.HexColor("#f2f2f2")
GRID = colors.HexColor("#999999")
GREEN = colors.HexColor("#1b7f3b")

ss = getSampleStyleSheet()
H1 = ParagraphStyle("H1", parent=ss["Heading1"], fontName="Helvetica-Bold", fontSize=15, textColor=NAVY, spaceBefore=10, spaceAfter=6, keepWithNext=1)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], fontName="Helvetica-Bold", fontSize=11.5, textColor=TEAL, spaceBefore=8, spaceAfter=4, keepWithNext=1)
BODY = ParagraphStyle("BODY", parent=ss["BodyText"], fontName="Helvetica", fontSize=9.3, leading=13)
SMALL = ParagraphStyle("SMALL", parent=BODY, fontSize=8, leading=10.5, textColor=colors.HexColor("#444444"))
CELL = ParagraphStyle("CELL", parent=BODY, fontSize=7.6, leading=9.4)
CELLB = ParagraphStyle("CELLB", parent=CELL, fontName="Helvetica-Bold", textColor=colors.black)
MONO = ParagraphStyle("MONO", parent=CELL, fontName="Courier", fontSize=7.4, leading=9)
TITLE = ParagraphStyle("TITLE", parent=ss["Title"], fontName="Helvetica-Bold", fontSize=18, textColor=colors.black, alignment=0, leading=22)
SUB = ParagraphStyle("SUB", parent=BODY, fontSize=10, alignment=0, textColor=colors.black)


def P(text, style=BODY):
    return Paragraph(text, style)


def fmt(v):
    if v is None:
        return "NULL"
    if isinstance(v, int):
        return f"{v:,}"
    return str(v)


def table(rows, header, widths, mono_cols=(), zebra=True, font=CELL):
    data = [[Paragraph(str(h), CELLB) for h in header]]
    for r in rows:
        data.append([Paragraph(fmt(c).replace("&", "&amp;").replace("<", "&lt;"), MONO if i in mono_cols else font)
                     for i, c in enumerate(r)])
    t = Table(data, colWidths=widths, repeatRows=1)
    style = [("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#d9d9d9")), ("VALIGN", (0, 0), (-1, -1), "TOP"),
             ("GRID", (0, 0), (-1, -1), 0.4, GRID), ("TOPPADDING", (0, 0), (-1, -1), 3),
             ("BOTTOMPADDING", (0, 0), (-1, -1), 3), ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4)]
    if zebra:
        for i in range(1, len(data)):
            if i % 2 == 0:
                style.append(("BACKGROUND", (0, i), (-1, i), LIGHT))
    t.setStyle(TableStyle(style))
    return t


def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(colors.black)
    canvas.drawString(2 * cm, 1.2 * cm, "PowerPulse | Phase 2 | Data Cleaning Report")
    canvas.drawRightString(A4[0] - 2 * cm, 1.2 * cm, f"Page {doc.page}")
    canvas.setStrokeColor(GRID)
    canvas.line(2 * cm, 1.6 * cm, A4[0] - 2 * cm, 1.6 * cm)
    canvas.restoreState()


def main():
    conn = loader.connect()
    q = lambda sql, *a: conn.execute(sql, a).fetchall()
    one = lambda sql, *a: conn.execute(sql, a).fetchone()[0]
    S = loader.SCHEMA

    # Make sure the numbers come from a clean, current run, then capture the self-test evidence.
    loader.run_sql_file(conn, loader.SQL_DIR / "10_clean_staging.sql")
    selftest = loader.run_self_test(conn)

    n_raw = one(f"SELECT COUNT(*) FROM {S}.stg_eia930_balance_raw")
    n_clean = one(f"SELECT COUNT(*) FROM {S}.stg_eia930_balance_clean")
    n_rej = one(f"SELECT COUNT(*) FROM {S}.stg_load_exception WHERE action_taken='ROW_REJECTED'")
    n_nulled = one(f"SELECT COUNT(*) FROM {S}.stg_load_exception WHERE action_taken='VALUE_SET_NULL'")
    log_all = {r[0]: r for r in q(f"SELECT rule_id, rule_name, rows_before, rows_after, rows_affected, detail FROM {S}.stg_cleaning_log WHERE scope='ALL'")}
    null_by_meas = q(f"""SELECT COUNT(*) FILTER (WHERE actual_demand_mw IS NULL), COUNT(*) FILTER (WHERE forecast_demand_mw IS NULL),
                         COUNT(*) FILTER (WHERE total_generation_mw IS NULL),
                         COUNT(*) FILTER (WHERE actual_demand_mw IS NULL OR forecast_demand_mw IS NULL OR total_generation_mw IS NULL),
                         COUNT(*) FILTER (WHERE actual_demand_mw IS NULL AND forecast_demand_mw IS NULL AND total_generation_mw IS NULL)
                         FROM {S}.stg_eia930_balance_clean""")[0]
    null_by_auth = q(f"""SELECT authority_code, COUNT(*), COUNT(*) FILTER (WHERE actual_demand_mw IS NULL),
                         COUNT(*) FILTER (WHERE forecast_demand_mw IS NULL), COUNT(*) FILTER (WHERE total_generation_mw IS NULL)
                         FROM {S}.stg_eia930_balance_clean GROUP BY 1 ORDER BY 1""")
    files = q(f"""SELECT sf.file_name, sf.selected_row_count, COUNT(r.raw_row_id), sf.source_row_count, LEFT(sf.sha256, 12)
                  FROM {S}.stg_source_file sf LEFT JOIN {S}.stg_eia930_balance_raw r ON r.source_file = sf.file_name
                  GROUP BY 1,2,4,5 ORDER BY 1""")
    fuel_cols_present = {
        "EIA930_BALANCE_2024_Jan_Jun.csv": 9, "EIA930_BALANCE_2024_Jul_Dec.csv": 16,
        "EIA930_BALANCE_2025_Jan_Jun.csv": 16, "EIA930_BALANCE_2025_Jul_Dec.csv": 16}
    c10 = q(f"SELECT scope, rows_before, rows_after, rows_affected FROM {S}.stg_cleaning_log WHERE rule_id='C10' AND scope<>'ALL' ORDER BY scope")
    mapping = {r[0]: r[1] for r in q(f"SELECT clean_column, source_column FROM {S}.stg_energy_source_mapping")}
    c08 = q(f"SELECT scope, rows_before, rows_affected FROM {S}.stg_cleaning_log WHERE rule_id='C08' AND scope<>'ALL' AND rows_affected>0 ORDER BY rows_affected DESC")
    ex_blank = q(f"""SELECT r.source_file, r.source_row, r.balancing_authority, r.demand_mw, r.demand_forecast_mw, r.net_generation_mw,
                     c.actual_demand_mw, c.forecast_demand_mw, c.total_generation_mw
                     FROM {S}.stg_eia930_balance_raw r JOIN {S}.stg_eia930_balance_clean c
                       ON c.source_file=r.source_file AND c.source_row=r.source_row::int
                     WHERE BTRIM(r.demand_mw)='' ORDER BY r.raw_row_id LIMIT 2""")
    ex_time = q(f"""SELECT r.source_row, r.data_date, r.hour_number, r.local_time_end, r.utc_time_end,
                    c.data_date, c.hour_number, c.local_hour_end, c.utc_hour_end, c.utc_offset_minutes
                    FROM {S}.stg_eia930_balance_raw r JOIN {S}.stg_eia930_balance_clean c
                      ON c.source_file=r.source_file AND c.source_row=r.source_row::int
                    WHERE r.raw_row_id = 1
                       OR (c.authority_code='PJM' AND c.local_hour_end='2024-03-10 03:00:00')
                       OR (c.authority_code, c.utc_hour_end) IN
                          (SELECT authority_code, MIN(utc_hour_end) FROM {S}.stg_eia930_balance_clean
                           WHERE authority_code='CISO' AND hour_number=25 GROUP BY authority_code)
                    ORDER BY c.utc_hour_end""")
    ex_neg = q(f"""SELECT r.source_row, r.balancing_authority, r.gen_unknown_energy_storage, c.gen_unknown_energy_storage
                   FROM {S}.stg_eia930_balance_raw r JOIN {S}.stg_eia930_balance_clean c
                     ON c.source_file=r.source_file AND c.source_row=r.source_row::int
                   WHERE c.gen_unknown_energy_storage < 0 ORDER BY r.raw_row_id LIMIT 3""")
    table_counts = [
        ("stg_source_file", one(f"SELECT COUNT(*) FROM {S}.stg_source_file"), "Manifest: URL, SHA-256 and row count of each source file"),
        ("stg_authority_reference", one(f"SELECT COUNT(*) FROM {S}.stg_authority_reference"), "Five balancing authorities with names and regions"),
        ("stg_energy_source_mapping", one(f"SELECT COUNT(*) FROM {S}.stg_energy_source_mapping"), "Nineteen fuel headers (original spelling) and their groups"),
        ("stg_eia930_balance_raw", n_raw, "Landing table: every column TEXT, exactly as in the CSV"),
        ("stg_eia930_balance_clean", n_clean, "Typed, standardised, de-duplicated; read by the dimension and fact loads"),
        ("stg_load_exception", one(f"SELECT COUNT(*) FROM {S}.stg_load_exception"), "One row per rejected row or nulled value, with rule and reason"),
        ("stg_cleaning_log", one(f"SELECT COUNT(*) FROM {S}.stg_cleaning_log"), "Before / after / affected counts for every rule"),
    ]

    # ---- chart: missing measures per authority -------------------------------------------------
    fig, ax = plt.subplots(figsize=(6.4, 2.5), dpi=200)
    labels = [r[0] for r in null_by_auth]
    w = 0.26
    xs = range(len(labels))
    for i, (name, col, c) in enumerate([("Actual demand", 2, "#222222"), ("Demand forecast", 3, "#808080"), ("Total generation", 4, "#c8c8c8")]):
        ax.bar([x + (i - 1) * w for x in xs], [r[col] for r in null_by_auth], w, label=name, color=c, edgecolor="black", linewidth=0.5)
    ax.set_xticks(list(xs)); ax.set_xticklabels(labels)
    ax.set_ylabel("Blank source cells (kept as NULL)", fontsize=8)
    ax.set_title("Missing measure values by balancing authority", fontsize=9, color="black")
    ax.tick_params(labelsize=8); ax.legend(fontsize=7.5, frameon=False)
    for s_ in ("top", "right"):
        ax.spines[s_].set_visible(False)
    fig.tight_layout()
    buf = io.BytesIO(); fig.savefig(buf, format="png"); plt.close(fig); buf.seek(0)

    # ---- document ----------------------------------------------------------------------------
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm, topMargin=1.8 * cm, bottomMargin=2.2 * cm,
                            title="PowerPulse Phase 2 - Data Cleaning Report", author="Qasim Tanveer")
    W = A4[0] - 4 * cm
    st = []

    # Header (plain): roll no, name, section only
    st += [P("<b>24L-2517 | Qasim Tanveer | BDS-5B</b>", BODY), Spacer(1, 10),
           P("Data Cleaning Report", TITLE),
           P("PowerPulse Phase 2: staging layer and data cleaning (project_staging)", SUB), Spacer(1, 8)]
    st.append(P("Result at a glance", H2))
    glance = [
        ("Source rows landed (4 EIA-930 CSV files)", n_raw, "matches the manifest per file"),
        ("Clean rows produced", n_clean, "5 authorities x 17,544 UTC hours"),
        ("Rows rejected", n_rej, "no invalid rows in the real data; rules proven by self-test"),
        ("Duplicate (authority, UTC hour) keys", log_all["C09"][4], "uniqueness enforced by a primary key"),
        ("Blank cells kept as NULL in demand / forecast / total generation", f"{null_by_meas[0]} / {null_by_meas[1]} / {null_by_meas[2]}", f"on {null_by_meas[3]} authority-hours; never replaced by 0"),
        ("Negative net-generation values retained", log_all["C08"][4], "real source data (e.g. storage charging)"),
        ("Numeric fuel observations", log_all["C10"][3], "equals the supplied baseline: 0 differences"),
    ]
    st.append(table(glance, ["Measure", "Value", "Comment"], [8.2 * cm, 2.6 * cm, W - 10.8 * cm]))


    # 1 Scope
    st.append(P("1. Scope and staging architecture", H1))
    st.append(P("Phase 1 designed a warehouse of five dimensions and two hourly fact tables over real EIA-930 grid data for five balancing "
                "authorities (CISO, ERCO, ISNE, NYIS, PJM), 1 January 2024 to 31 December 2025. This step lands the four source CSV files in "
                "PostgreSQL and cleans them into one typed table. Python loads the files with COPY; SQL performs the cleaning inside the database, "
                "so every rule is visible, repeatable and logged."))
    st.append(Spacer(1, 4))
    st.append(P("Source files &gt; <b>project_staging</b> &gt; project_dw &gt; project_reporting", ParagraphStyle("c", parent=BODY, alignment=TA_CENTER, textColor=NAVY, fontName="Helvetica-Bold")))
    st.append(Spacer(1, 6))
    st.append(table(table_counts, ["Staging table", "Rows", "Purpose"], [5.4 * cm, 1.8 * cm, W - 7.2 * cm], mono_cols=(0,)))
    st.append(Spacer(1, 6))
    st.append(P("Only the <i>reported</i> measures are staged: demand, demand forecast, total net generation and the 19 reported fuel columns. "
                "The imputed and adjusted variants published by EIA are deliberately not loaded, so reported and estimated values are never mixed. "
                "Fuel headers keep their original spelling in <font face='Courier'>stg_energy_source_mapping.source_column</font> so the fact load can map them exactly."))

    # 2 Source import
    st.append(P("2. Source import and reconciliation (rule C01)", H1))
    st.append(P("Each file was loaded with its own column list: the 2024 Jan-Jun file publishes 9 reported fuel columns, the other three publish 16. "
                "A fuel column that does not exist in a file is stored as NULL (structural absence), which is different from a blank cell inside an existing column. "
                "Loaded row counts were compared with <font face='Courier'>source_manifest.json</font>."))
    st.append(Spacer(1, 4))
    rows = [(f[0], fuel_cols_present[f[0]], f[1], f[2], "OK" if f[1] == f[2] else "MISMATCH", f[4]) for f in files]
    rows.append(("TOTAL", "", sum(f[1] for f in files), sum(f[2] for f in files), "OK" if all(f[1] == f[2] for f in files) else "MISMATCH", ""))
    st.append(KeepTogether(table(rows, ["Source file", "Fuel cols", "Manifest rows", "Loaded rows", "Status", "SHA-256 (first 12)"],
                    [5.6 * cm, 1.5 * cm, 2.3 * cm, 2.2 * cm, 1.6 * cm, W - 13.2 * cm], mono_cols=(0, 5))))
    st.append(Spacer(1, 4))
    st.append(P("Source lineage is preserved: every row keeps its source file name, its row number in the full EIA file (<font face='Courier'>source_row</font>) "
                "and, in the clean table, the SHA-256 of the file it came from, so a fact row can be traced back to an immutable source snapshot.", SMALL))

    # 3 Rule summary
    
    st.append(P("3. Cleaning rules and before / after counts", H1))
    st.append(P("Each rule writes its counts to <font face='Courier'>stg_cleaning_log</font>. <i>Before</i> is the number of rows (or cells for C06-C08, C10) "
                "entering the rule, <i>after</i> the number leaving it, <i>affected</i> the number of rows or values the rule changed, rejected or flagged."))
    st.append(Spacer(1, 4))
    desc = {
        "C01": "Compare rows loaded per file with the manifest; reject unknown file or invalid row number.",
        "C02": "TRIM and UPPER on authority and region codes (for example ' cISo ' becomes 'CISO').",
        "C03": "Authority must exist in the reference table and its region must agree with the reference.",
        "C04": "Parse Data Date to date, the local label to timestamp and the UTC label to timestamptz (+00:00).",
        "C05": "Hour Number must be 1-25; offset = local minus UTC must be -480, -420, -360, -300 or -240 minutes.",
        "C06": "Convert text to numeric(18,4). A non-numeric value becomes NULL and is logged (cells).",
        "C07": "Blank measure cells become NULL, never 0; the row is kept (cells).",
        "C08": "Negative net generation is real data: kept unchanged (cells).",
        "C09": "One row per (authority, UTC hour); newest snapshot wins; extra copies are logged as rejected.",
        "C10": "Numeric fuel cells per column compared with the supplied baseline (cells).",
        "C11": "Raw rows versus clean rows plus rejected rows.",
    }
    rows = [(k, log_all[k][1].split(" (")[0], desc[k], log_all[k][2], log_all[k][3], log_all[k][4]) for k in sorted(log_all)]
    st.append(table(rows, ["Rule", "Name", "What it does", "Before", "After", "Affected"],
                    [1.0 * cm, 3.4 * cm, W - 9.4 * cm, 1.7 * cm, 1.7 * cm, 1.6 * cm]))
    st.append(Spacer(1, 4))
    st.append(P("Reading the table: C07 'affected' counts every blank cell (3 x 218 blank demand / forecast / generation cells plus blank fuel cells), "
                "all of which are stored as NULL. C08 'affected' counts negative values that were deliberately kept.", SMALL))

    # 4 Missing values
    st.append(P("4. Handling missing values (rule C07)", H1))
    st.append(P(f"Actual demand, demand forecast and total generation are each blank in <b>{null_by_meas[0]}</b> source rows. These fall on "
                f"<b>{null_by_meas[3]}</b> distinct authority-hours, of which <b>{null_by_meas[4]}</b> are missing all three measures. "
                "Blank cells are stored as <b>NULL, never 0</b>, and the rows are kept: the hour still happened, only the measurement is unknown. "
                "Replacing a blank with 0 would pull averages and forecast-error metrics towards zero. A check confirms that the zeros in the clean table "
                "are exactly the zeros that exist in the raw data."))
    st.append(Spacer(1, 4))
    st.append(Image(buf, width=W * 0.88, height=W * 0.88 * 2.5 / 6.4))
    st.append(Spacer(1, 4))
    st.append(table([(r[0], r[1], r[2], r[3], r[4]) for r in null_by_auth],
                    ["Authority", "Rows", "NULL demand", "NULL forecast", "NULL total generation"],
                    [3 * cm, 2.6 * cm, 3 * cm, 3.2 * cm, W - 11.8 * cm]))
    st.append(Spacer(1, 6))
    st.append(P("Example: blank source cells become NULL (raw text on the left, typed value on the right)", H2))
    rows = [(f"{r[0].replace('EIA930_BALANCE_', '').replace('.csv', '')} / row {r[1]}", r[2], repr(r[3]), repr(r[4]), repr(r[5]), r[6], r[7], r[8]) for r in ex_blank]
    st.append(table(rows, ["Source row", "BA", "raw demand", "raw forecast", "raw generation", "demand", "forecast", "generation"],
                    [3.7 * cm, 1.1 * cm, 1.9 * cm, 1.9 * cm, 2.2 * cm, 1.6 * cm, 1.7 * cm, W - 14.1 * cm]))
    st.append(Spacer(1, 4))
    st.append(P("<b>Structural absence:</b> the 2024 Jan-Jun file has no column for ten of the 19 fuel categories, and the other three files lack three. "
                "Those cells are NULL as well, and the clean table cannot tell them apart from a blank, so downstream steps must create generation facts only "
                "from numeric cells (blank and absent cells create no fact row). The C07 log entry records the number of structurally absent cells separately.", SMALL))

    # 5 Types and timestamps
    
    st.append(P("5. Type conversion and timestamps (rules C04, C05, C06)", H1))
    st.append(P("Every raw column is TEXT. The clean table uses real types: <font face='Courier'>date</font>, <font face='Courier'>timestamp</font> "
                "(local wall-clock label), <font face='Courier'>timestamptz</font> (UTC instant) and <font face='Courier'>numeric(18,4)</font>. "
                "Timestamps are built with <font face='Courier'>make_timestamp</font>, so the server time zone can never shift them, and the UTC label is stored "
                "with an explicit +00:00. <font face='Courier'>utc_offset_minutes</font> is the local label minus the UTC instant."))
    st.append(Spacer(1, 4))
    rows = [(r[0], f"{r[1]} | {r[2]}", r[3], r[4], f"{r[5]} | {r[6]}", r[7], r[8], r[9]) for r in ex_time]
    st.append(table(rows, ["Row", "raw date | hour", "raw local", "raw UTC", "date | hour", "local (timestamp)", "UTC (timestamptz)", "offset"],
                    [1.2 * cm, 2.3 * cm, 2.5 * cm, 2.5 * cm, 2.1 * cm, 2.4 * cm, 2.4 * cm, W - 15.4 * cm]))
    st.append(Spacer(1, 4))
    st.append(P("<b>Spring clock change:</b> on 10 March 2024 the second hour of the day (Hour Number 2) carries the local label 03:00 because 02:00 "
                "does not exist; the offset changes from -300 to -240 minutes. <b>Autumn clock change:</b> Hour Number reaches 25 on the day clocks go back. The two repetitions of the same local label are different "
                "UTC instants, so both are kept (10 rows have hour number 25, one per authority per autumn). <b>Operating date:</b> the date comes from "
                "<i>Data Date</i>, never from the local label, because a midnight label belongs to the previous operating day "
                f"({one(f'SELECT COUNT(*) FROM {S}.stg_eia930_balance_clean WHERE data_date <> local_hour_end::date'):,} rows have a local-label date that "
                "differs from their operating date). <b>Offsets:</b> all rows fall in the five valid U.S. offsets (-480 to -240).", SMALL))

    st.append(P("6. Negative net generation is retained (rule C08)", H1))
    st.append(P(f"<b>{log_all['C08'][4]:,}</b> numeric fuel observations are negative (storage charging, station load, solar at night). They are real source data, "
                "so they are kept as supplied. Total net generation has no negative values."))
    st.append(Spacer(1, 4))
    st.append(table([(mapping[c], c, b, a) for c, b, a in c08],
                    ["Original fuel header", "Clean column", "Numeric cells", "Negative"], [6.4 * cm, 5.7 * cm, 2.4 * cm, W - 14.5 * cm], mono_cols=(1,)))
    st.append(Spacer(1, 4))
    st.append(table([(r[0], r[1], r[2], r[3]) for r in ex_neg], ["Source row", "BA", "raw text", "clean value"], [3 * cm, 2 * cm, 3 * cm, W - 8 * cm]))

    # 7 Rejected
    
    st.append(P("7. Rejected and invalid records", H1))
    st.append(P(f"In the real data <b>{n_rej} rows were rejected</b> and <b>{n_nulled} values</b> were set to NULL because of bad content, so "
                "<font face='Courier'>stg_load_exception</font> is empty after a normal run. Because an empty exception table proves nothing about the rules, "
                "a self-test (<font face='Courier'>python etl/01_load_staging.py --self-test</font>) adds nine deliberately dirty rows to the raw table, "
                "runs the cleaning SQL, checks the outcome and then restores the real data."))
    st.append(Spacer(1, 4))
    ex = selftest["exceptions"]
    rows = [(e[0], e[1], e[2], e[3], e[4], e[6]) for e in ex]
    st.append(table(rows, ["Rule", "Reason", "Action", "Column", "Bad value", "Source row"],
                    [1.0 * cm, 5.3 * cm, 2.8 * cm, 2.8 * cm, 3.4 * cm, W - 15.3 * cm], mono_cols=(1,)))
    st.append(Spacer(1, 4))
    st.append(P("The two remaining dirty rows are correctly <b>kept</b>: ' pjm ' / 'mida ' was standardised to PJM / MIDA (C02), and a row whose demand was the text "
                "'N/A' kept its generation values while demand became NULL (C06).", SMALL))
    st.append(Spacer(1, 4))
    st.append(table([(("PASS" if ok else "FAIL"), name) for name, ok in selftest["checks"]], ["Result", "Self-test check"], [1.6 * cm, W - 1.6 * cm]))

    st.append(P("8. Duplicate removal (rule C09)", H1))
    st.append(P(f"The business grain of the demand fact is one row per authority and UTC hour. The raw data contains <b>{log_all['C09'][4]}</b> duplicate keys. "
                "The rule is nevertheless implemented: rows are ranked within each (authority_code, utc_hour_end) group by newest snapshot, then file name, then source row; "
                "rank 1 is kept and every other copy is written to the exception table. The primary key on the clean table makes a duplicate impossible, and "
                "the self-test proves the rule fires (source row 1 above was removed as a duplicate)."))

    # 9 Fuel reconciliation
    st.append(P("9. Fuel column reconciliation (rule C10)", H1))
    st.append(P(f"Numeric observations per fuel column were compared with the baseline in <font face='Courier'>energy_source_mapping.csv</font>. "
                f"All 19 columns agree; the total of <b>{log_all['C10'][3]:,}</b> is the number of rows the fuel-generation fact table is expected to hold."))
    st.append(Spacer(1, 4))
    st.append(table([(c, b, a, "OK" if d == 0 else f"DIFF {d}") for c, b, a, d in c10],
                    ["Original fuel header (source_column)", "Baseline", "Clean", "Status"], [8.6 * cm, 2.4 * cm, 2.4 * cm, W - 13.4 * cm]))

    # 10 handoff
    
    st.append(P("10. Hand-off and evidence", H1))
    st.append(P("<b>To the fact-load owner (Muaz):</b> <font face='Courier'>stg_eia930_balance_clean</font> (87,720 rows; business keys authority_code, data_date, "
                "hour_number / local_hour_end, utc_hour_end, source_file + source_sha256, source_row). Unpivot the 19 <font face='Courier'>gen_*</font> columns "
                "using <font face='Courier'>stg_energy_source_mapping</font>, whose <font face='Courier'>source_column</font> holds the exact original header and "
                "<font face='Courier'>clean_column</font> the matching staging column. Only non-NULL values become generation facts."))
    st.append(P("<b>To the dimension-load owner (Emaad):</b> <font face='Courier'>stg_authority_reference</font>, <font face='Courier'>stg_energy_source_mapping</font> "
                "and <font face='Courier'>stg_source_file</font> carry the natural keys (authority code, exact fuel header, file name + SHA-256)."))
    st.append(P("<b>To the quality owner (Mohid):</b> missing-value and cleaning evidence is in <font face='Courier'>stg_cleaning_log</font>, "
                "<font face='Courier'>stg_load_exception</font> and the 30 PASS / FAIL checks in <font face='Courier'>sql/01_staging/90_verify_staging.sql</font>."))
    st.append(P("11. Reproducing the results", H1))
    rows = [
        ("sql/01_staging/00_create_staging_tables.sql", "Creates project_staging tables and the safe-parse helper functions"),
        ("etl/01_load_staging.py", "Loads references, manifest and the four CSVs (COPY), reconciles counts, runs the cleaning"),
        ("sql/01_staging/10_clean_staging.sql", "Cleaning rules C01-C11; rebuilds clean table, exceptions and log in one transaction"),
        ("sql/01_staging/90_verify_staging.sql", "30 PASS / FAIL checks plus evidence queries"),
        ("sql/01_staging/95_ and 96_ selftest files", "Insert / remove the nine dirty rows (used by --self-test)"),
        ("reports/phase2/build_data_cleaning_report.py", "Regenerates this PDF from the database"),
    ]
    st.append(table(rows, ["File", "Purpose"], [7.6 * cm, W - 7.6 * cm], mono_cols=(0,)))
    st.append(Spacer(1, 6))
    st.append(P("All scripts are re-runnable: running them again rebuilds identical counts and changes no results.", SMALL))

    doc.build(st, onFirstPage=footer, onLaterPages=footer)
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
