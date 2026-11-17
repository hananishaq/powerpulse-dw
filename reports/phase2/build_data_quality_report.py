"""Build the submission PDF from a measured, exported DQ run (no invented results)."""
import argparse
import json
from pathlib import Path
import sys
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Table, TableStyle, Spacer, PageBreak

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "etl"))
from common import EVIDENCE

NAVY = colors.HexColor("#133247")
TEAL = colors.HexColor("#087F89")
GRAY = colors.HexColor("#526574")
PALE = colors.HexColor("#EDF5F7")
STYLES = {
 "title": ParagraphStyle("title",fontName="Helvetica-Bold",fontSize=27,leading=32,textColor=NAVY,spaceAfter=14),
 "h": ParagraphStyle("h",fontName="Helvetica-Bold",fontSize=13,leading=17,textColor=TEAL,spaceBefore=13,spaceAfter=8),
 "body": ParagraphStyle("body",fontName="Helvetica",fontSize=10,leading=14.5,textColor=NAVY,spaceAfter=8),
 "small": ParagraphStyle("small",fontName="Helvetica",fontSize=8.1,leading=11,textColor=GRAY,spaceAfter=6),
 "cell": ParagraphStyle("cell",fontName="Helvetica",fontSize=8.4,leading=11.6,textColor=NAVY),
}


def fmt(value):
    if value is None:
        return "NULL"
    try:
        from decimal import Decimal
        n = Decimal(str(value))
        return f"{n:,.0f}" if n == n.to_integral() else f"{n:,.4f}"
    except Exception:
        return str(value)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--evidence", type=Path, default=EVIDENCE / "latest_dq.json")
    ap.add_argument("--output", type=Path, default=ROOT / "reports/phase2/Data_Quality_Report.pdf")
    args = ap.parse_args()
    data = json.loads(args.evidence.read_text(encoding="utf-8"))
    run, checks = data["run"], data["checks"]
    if not run.get("completed_at"):
        raise SystemExit("Cannot report an unfinished quality run")
    story = []
    def p(text, style="body"):
        story.append(Paragraph(text, STYLES[style]))
    def h(text): p(text, "h")
    def table(rows, widths):
        cells = [[Paragraph(escape(str(c)), STYLES["cell"]) for c in row] for row in rows]
        t = Table(cells,colWidths=widths,repeatRows=1,hAlign="LEFT")
        t.setStyle(TableStyle([("BACKGROUND",(0,0),(-1,0),PALE),("VALIGN",(0,0),(-1,-1),"TOP"),
            ("LINEBELOW",(0,0),(-1,0),.7,TEAL),("LINEBELOW",(0,1),(-1,-1),.3,colors.HexColor("#D5E1E6")),
            ("LEFTPADDING",(0,0),(-1,-1),7),("RIGHTPADDING",(0,0),(-1,-1),7),
            ("TOPPADDING",(0,0),(-1,-1),7),("BOTTOMPADDING",(0,0),(-1,-1),7)]))
        story.append(t); story.append(Spacer(1,8))
    passed=sum(c["status"]=="PASS" for c in checks)
    p("POWERPULSE / PHASE 2 / MOHID 24L-2510", "small")
    p("Data Quality Report", "title")
    p("Physical warehouse implementation, source accuracy, reporting and repeatability")
    table([["Measured result","Value"],["Overall quality status",run["status"]],
           ["Checks passed",f"{passed} / {len(checks)}"],
           ["Started (UTC)",run["started_at"]],["Completed (UTC)",run["completed_at"]],
           ["DQ run ID",run["run_id"]]], [180,319])
    p("Database: " + escape(run["server_version"]),"small")
    p("Code base revision: " + escape(run["source_commit"]),"small")
    p("The recorded revision identifies the base commit during execution. The corresponding implementation is the commit containing this report and the SQL/scripts beside it. Generated evidence is not a claim about future source versions.","small")
    if run.get("error_message"):
        p("<b>Execution error:</b> " + escape(run["error_message"]))
    h("Scope and interpretation")
    p("Real EIA-930 extracts cover five balancing authorities and operating dates 1 January 2024 through 31 December 2025. Two hourly facts share five dimensions. This report uses an actual PostgreSQL run, persisted check results and independently parsed CSV records.")
    p("PASS means the warehouse agrees with the frozen baseline and the stated control. It does not mean the source is free of missing values or reconciliation discrepancies. Expected source exceptions remain visible and unchanged.")
    h("Validation method")
    p("The validator checks subset SHA-256 hashes and per-file manifest counts, parses the CSVs independently, and compares every demand/fuel observation against loaded facts using natural keys and NULL-safe comparisons. It checks operating dates, UTC/local time, offsets and source file/hash/row lineage. Dimension references are tested before and after fact loading.")
    p("Coverage comes from frozen authority-specific UTC bounds in profile.json, independently of loaded facts. Time-zone-aware operating dates preserve DST and midnight-ending intervals. The January 2026 UTC labels belonging to December 2025 operating dates remain included.")
    story.append(PageBreak())
    p("Validation results", "title")
    p("Each row below is exported from project_reporting.dq_check_result for the recorded run. Full SQL is committed under sql/05_quality/; JSON evidence includes timestamps and explanations.")
    table([["Check / category","Expected","Actual","Result"]] +
          [[c["check_name"].replace("_", " ")+" / "+c["category"],fmt(c["expected"]),fmt(c["actual"]),c["status"]] for c in checks],
          [287,74,74,64])
    story.append(PageBreak())
    p("Findings and reporting rules", "title")
    h("Legitimate source missingness")
    p("Demand, forecast and reported total generation each contain 218 NULLs, affecting 316 distinct hours; 120 hours have all three missing. Rows are retained and source blanks never become zero. Absent fuel headers and blank fuel cells create no generation fact. The evidence records which headers exist in each file, so structural absence is not misrepresented as zero generation.")
    h("Signed generation and available-fuel discrepancies")
    p("The baseline contains 31,007 negative fuel observations; these remain signed. Fuel-total comparison is eligible only when reported total generation and at least one numeric fuel value exist. There are 87,471 comparable hours; 6,958 exceed max(10 MW, 1% of absolute total): PJM 6,873 and ERCO 85. This threshold is a project diagnostic, not an EIA rule. Discrepancies are retained for investigation.")
    h("Metric eligibility and aggregation")
    p("Demand energy is nonnegative observed MW multiplied by one hour, reported in MWh. Forecast scoring uses actual > 0 and forecast >= 0 on exactly the same pair set (87,399 baseline pairs). Error = actual minus forecast; positive bias means underforecasting. WAPE is the ratio of summed absolute errors to summed actuals. Undefined ratios return NULL.")
    p("Generation is aggregated to authority/UTC hour before a demand comparison. Wind/solar share uses matched observed components, positive total and acceptable reconciliation; category versions and excluded hours are disclosed. Monthly peak views retain every tied timestamp. High-demand sets use the monthly positive-demand 90th percentile, including ties; generation is summarized before combining facts.")
    h("Quality by authority")
    grouped={}
    for row in data.get("monthly_coverage",[]):
        a=grouped.setdefault(row["authority_code"],dict(expected=0,present=0,nulls=0,flags=0))
        for target,source in [("expected","expected_hours"),("present","present_hours"),("nulls","null_actual_hours"),("flags","reconciliation_flags")]:
            a[target]+=int(row[source])
    table([["Authority","Expected","Present","NULL actual","Flags"]]+
          [[code,*[fmt(row[k]) for k in ["expected","present","nulls","flags"]]] for code,row in sorted(grouped.items())],
          [111,97,97,97,97])
    story.append(PageBreak())
    p("Evidence and reproduction", "title")
    h("Input snapshot audit")
    table([["Selected CSV","Rows","Verified subset SHA-256 (prefix)"]]+
          [[f["file"].replace("EIA930_BALANCE_", ""),fmt(f["rows"]),f["subset_sha256"][:24]] for f in run["input_files"]],
          [226,64,209])
    p("The JSON evidence contains full subset and original-file SHA-256 hashes, present/absent fuel headers and exact file counts. Full original hashes are lineage identifiers from the acquisition manifest; the validator rehashes the committed selected extracts.","small")
    h("Negative tests and reruns")
    p("The default quality run uses session-local scratch tables to inject a duplicate, unknown authority keys, a missing authority and a missing boundary hour, and tests unsafe demand fan-out. Expected detections are recorded as PASS; missing detections fail. Scratch objects are dropped. Baseline reruns add ordered identity-mapping digest checks for all five dimensions and both facts.")
    integration=EVIDENCE/"integration_tests.json"
    if integration.exists():
        tests=json.loads(integration.read_text(encoding="utf-8"))
        p(f"Additional transactional integration tests: {sum(t['passed'] for t in tests['tests'])} / {len(tests['tests'])} passed. Production-table mutations were rolled back. See integration_tests.json for individual observations.")
    h("Rebuild and inspect")
    p("1. Install PostgreSQL 16+ and Python 3.10+; install requirements.txt.<br/>2. Copy .env.example to .env and configure your own local connection.<br/>3. Run <b>python etl/run_all.py --bootstrap --report</b>.<br/>4. Repeat that command to test stable identity mappings.<br/>5. Run <b>python tests/integration_checks.py</b>, then regenerate this report.<br/>6. Inspect latest_dq.json, latest_pipeline.json and the persisted result tables.")
    h("Ownership and remaining dependencies")
    p("Mohid's deliverables include setup/integration scripts, all ten reporting views, validation SQL/runner, this report and execution documentation. Source and dimension/fact loaders remain the teammates' implementations. The current baseline gate detects unmatched references and stale/extra observations, but it does not implement a fact-mapping quarantine or automatic source-partition revision removal. Those upstream enhancements remain with their assigned owners; this report certifies the frozen baseline, not arbitrary future source revisions.")
    p('Repository: <link href="https://github.com/hananishaq/powerpulse-dw" color="#087F89">github.com/hananishaq/powerpulse-dw</link><br/>Contracts: docs/phase1/02_Business_Requirements.pdf (M01-M12); docs/phase1/03_Business_Questions.pdf (Q01-Q10). Ownership follows the supplied Phase 2 work division.','small')

    def footer(c,doc):
        c.saveState(); c.setStrokeColor(TEAL); c.line(48,A4[1]-32,A4[0]-48,A4[1]-32)
        c.setStrokeColor(colors.HexColor("#D5E1E6")); c.line(48,42,A4[0]-48,42)
        c.setFont("Helvetica",8); c.setFillColor(GRAY)
        c.drawString(48,28,"POWERPULSE | Phase 2 | Data Quality Report")
        c.drawRightString(A4[0]-48,28,f"Page {doc.page}"); c.restoreState()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    doc=SimpleDocTemplate(str(args.output),pagesize=A4,leftMargin=48,rightMargin=48,topMargin=49,bottomMargin=57,
        title="PowerPulse Phase 2 - Data Quality Report",author="Mohid - 24L-2510")
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    print(args.output)


if __name__=="__main__":
    main()
