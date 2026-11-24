#!/usr/bin/env python3
"""Build Muaz's Indexing Report PDF exclusively from saved benchmark evidence."""
import argparse
from collections import defaultdict
import csv
import hashlib
import json
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak, Preformatted

ROOT = Path(__file__).resolve().parents[2]
NAVY = colors.HexColor('#142D46')
TEAL = colors.HexColor('#087F8C')
LIGHT = colors.HexColor('#EDF3F7')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir',type=Path,default=ROOT/'reports/phase3/performance')
    parser.add_argument('--output',type=Path,default=ROOT/'reports/phase3/Indexing_Report.pdf')
    args=parser.parse_args()
    evidence=json.loads((args.evidence_dir/'summary.json').read_text())
    runs=list(csv.DictReader((args.evidence_dir/'runs.csv').open(newline='')))
    if len(runs)!=30 or not all(r['results_unchanged'] for r in evidence['summary']):
        raise SystemExit('Incomplete benchmark evidence; report was not generated')
    for file,expected in evidence['sql_sha256'].items():
        # Evidence produced on Windows may contain backslash-separated paths.
        # Normalize those when rebuilding the same report on Linux/macOS.
        if hashlib.sha256((ROOT/Path(file.replace('\\', '/'))).read_bytes()).hexdigest()!=expected:
            raise SystemExit('Benchmark SQL differs from measured evidence: '+file)
    styles=getSampleStyleSheet()
    styles.add(ParagraphStyle(name='TitlePP',fontName='Helvetica-Bold',fontSize=25,leading=29,textColor=NAVY,spaceAfter=16))
    styles.add(ParagraphStyle(name='BodyPP',fontName='Helvetica',fontSize=9.5,leading=14,spaceAfter=9,textColor=NAVY))
    styles.add(ParagraphStyle(name='SmallPP',fontName='Helvetica',fontSize=8,leading=11,spaceAfter=6,textColor=NAVY))
    styles.add(ParagraphStyle(name='CodePP',fontName='Courier',fontSize=7,leading=10,textColor=NAVY,spaceAfter=9))
    styles['Heading2'].textColor=TEAL
    story=[]
    def p(text,style='BodyPP'):
        return Paragraph(text,styles[style])
    def add(text,style='BodyPP'):
        story.append(p(text,style))
    def table(rows,widths):
        t=Table([[p(escape(str(c)),'SmallPP') for c in row] for row in rows],colWidths=widths,repeatRows=1,hAlign='LEFT')
        t.setStyle(TableStyle([('BACKGROUND',(0,0),(-1,0),LIGHT),('VALIGN',(0,0),(-1,-1),'TOP'),
                               ('LINEBELOW',(0,0),(-1,0),1,TEAL),('BOTTOMPADDING',(0,0),(-1,-1),6),
                               ('TOPPADDING',(0,0),(-1,-1),6),('LINEBELOW',(0,1),(-1,-1),.3,colors.lightgrey)]))
        story.append(t);story.append(Spacer(1,12))
    def heading(text): add(text,'Heading2')
    titles={'demand_authority_month':'Selective authority / month demand',
            'generation_fuel_month':'Selective fuel / month generation',
            'demand_cube_2025':'Broad region / season demand CUBE'}
    add('POWERPULSE / PHASE 3 / MUAZ FAHAD 24L-2563','SmallPP')
    add('Indexing Report','TitlePP')
    add('Covering indexes improve the two selective query cases. The broad CUBE retains its original plan and cost.')
    add('Measured 24 November 2026. Frozen source: five U.S. balancing authorities, operating years 2024-2025. '
        'A fresh disposable warehouse was built using the repository pipeline. No existing user database was modified.')
    table([['Query','Before median ms','After median ms','Time reduction %']]+
          [[titles[r['query']],f"{r['before_median_ms']:.3f}",f"{r['after_median_ms']:.3f}",f"{r['time_improvement_pct']:.2f}"] for r in evidence['summary']],
          [225,90,90,106])
    heading('Measurement method')
    add('For each fixed query: one EXPLAIN warm-up and five measured EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) executions '
        'per arm. Compare median Execution Time. Estimated Total Cost is the root plan cost, in planner units, not milliseconds. '
        'Both candidates are added together in the after arm. All data, query parameters, table statistics and session settings stay fixed.')
    add('VACUUM ANALYZE prepares both facts before measurement; dimensions are ANALYZEd once. The warm-cache policy does not '
        'flush the operating-system cache. Baseline runs precede indexed runs. Results are checked with ordered SHA-256 checksums, '
        'and all three checksums match across arms. Experimental indexes are rolled back after the test.')
    heading('Interpretation')
    add('Recommend the two candidates for the measured selective workload, subject to Emaad reviewing storage/write costs. '
        'The CUBE scans a broad population; neither candidate is selected. Its small timing difference across five samples '
        'does not establish a meaningful speed change. No production latency or concurrent-write benefit is claimed.')
    add('The complete thirty runs, JSON plans, readable plan outlines, index inventory and session metadata accompany this report '
        'in reports/phase3/performance/.', 'SmallPP')

    for s in evidence['summary']:
        story.append(PageBreak())
        name=s['query']
        add(titles[name],'TitlePP')
        filters={'demand_authority_month':'CISO; source operating dates 2025-07-01 through 2025-07-31. Measures: observed/eligible hours and nonnegative demand MWh.',
                 'generation_fuel_month':'Exact source header Natural Gas; all five authorities; source operating July 2025. Signed generation MWh and fuel-observation counts.',
                 'demand_cube_2025':'Source operating year 2025; GROUP BY CUBE(region_name, season). Eligible demand SUM, AVG and counts across all four grouping levels.'}
        add(filters[name])
        table([['Arm','Median ms','Cost','Index selection'],
               ['Before',f"{s['before_median_ms']:.3f}",f"{s['before_cost']:.2f}",'Existing baseline indexes / plan below'],
               ['After',f"{s['after_median_ms']:.3f}",f"{s['after_cost']:.2f}",', '.join(s['candidate_indexes_used']) or 'No candidate selected']],
              [52,70,75,314])
        cost_pct=100*(s['before_cost']-s['after_cost'])/s['before_cost']
        add(f"Median execution reduction: {s['time_improvement_pct']:.2f}%. Estimated cost reduction: {cost_pct:.2f}%. "
            'Improvement = 100 x (before - after) / before.')
        for arm in ['before','after']:
            arm_runs=[r for r in runs if r['query']==name and r['arm']==arm]
            median=s[f'{arm}_median_ms']
            selected=min(arm_runs,key=lambda r:abs(float(r['execution_ms'])-median))
            plan=json.loads((args.evidence_dir/'plans'/f"{name}_{arm}_{selected['run']}.json").read_text())[0]
            heading(arm.title()+' plan: median measured execution')
            lines=[]
            def walk(node,depth=0):
                label=node['Node Type']
                if 'Relation Name' in node: label+=' on '+node['Relation Name']
                if 'Index Name' in node: label+=' ['+node['Index Name']+']'
                # Wrap index label onto a continuation line if needed.
                prefix='  '*depth
                if len(prefix+label)>95:
                    label=label.replace(' [','\n'+prefix+'  [')
                lines.append(prefix+label)
                for child in node.get('Plans',[]): walk(child,depth+1)
            walk(plan['Plan'])
            story.append(Preformatted('\n'.join(lines),styles['CodePP']))
            add(f"Execution {plan['Execution Time']:.3f} ms; planning {plan['Planning Time']:.3f} ms; "
                f"root shared hits {plan['Plan'].get('Shared Hit Blocks',0):,}; reads {plan['Plan'].get('Shared Read Blocks',0):,}.",'SmallPP')
        heading('All five measured execution times (ms)')
        table([['Arm','Run 1','Run 2','Run 3','Run 4','Run 5']]+
              [[arm.title()]+[f"{float(r['execution_ms']):.3f}" for r in runs if r['query']==name and r['arm']==arm] for arm in ['before','after']],
              [76,87,87,87,87,87])
        sample=next(r for r in runs if r['query']==name)
        add(f"Result rows: {sample['result_rows']}. Ordered result SHA-256:", 'SmallPP')
        story.append(Preformatted(sample['result_sha256'],styles['CodePP']))

    story.append(PageBreak())
    add('Environment, costs and reproduction','TitlePP')
    add(escape(evidence['postgresql']),'SmallPP')
    add(escape(evidence['host_platform']+' / '+evidence['cpu'])+f" / {evidence['logical_cpus']} logical CPUs",'SmallPP')
    add('Physical RAM was not recorded; shared_buffers and work_mem are recorded below. No hardware-normalized comparison is claimed.','SmallPP')
    def setting_value(name,value):
        if name in ['shared_buffers','effective_cache_size']:
            return f'{int(value)*8192/1048576:g} MiB ({value} x 8 KiB pages)'
        if name=='work_mem': return f'{int(value)/1024:g} MiB ({value} KiB)'
        return value
    table([['Session / data setting','Recorded value']]+[[k,setting_value(k,v)] for k,v in evidence['settings'].items()]+
          [[k,f'{v:,} rows'] for k,v in evidence['counts'].items()],[235,276])
    heading('Candidate definitions and measured storage')
    story.append(Preformatted('CREATE INDEX idx_p3_demand_authority_date\n  ON project_dw.fact_hourly_demand (authority_key, date_key)\n  INCLUDE (actual_demand_mw);\n\nCREATE INDEX idx_p3_generation_source_date_authority\n  ON project_dw.fact_hourly_generation\n  (energy_source_key, date_key, authority_key) INCLUDE (generation_mw);',styles['CodePP']))
    for name,size in evidence['candidate_storage_bytes'].items():
        add(f'{escape(name)}: {size:,} bytes ({size/1048576:.2f} MiB).','SmallPP')
    add('INCLUDE columns allow covering access for the measured sums; the planner used both candidates in their respective selective queries. '
        'Visibility-map state from VACUUM matters for index-only scans. Each index also consumes disk and adds insert/update/vacuum maintenance; '
        'write overhead was not benchmarked. Existing FK-only indexes may remain useful for other queries. Preserve PK/UNIQUE indexes.')
    add('Baseline commit: '+escape(evidence['commit'])+'. '+escape(evidence['working_tree_note']),'SmallPP')

    story.append(PageBreak())
    add('Baseline index inventory and provenance','TitlePP')
    groups=defaultdict(list)
    for r in evidence['indexes_before']:
        groups[(r['table'],r['definition'].split(' USING ',1)[-1])].append(r['name'])
    duplicates=[(k,v) for k,v in groups.items() if len(v)>1]
    add(f'{len(duplicates)} groups of equivalent baseline indexes were retained during both arms. Cleanup was not mixed into '
        'the experiment. Review usage and constraint dependencies separately before removing a redundant index.')
    table([['Table / indexed field','Equivalent index names']]+
          [[k[0]+' / '+k[1],'; '.join(v)] for k,v in duplicates],[210,301])
    heading('Reproduction and limitations')
    add('Set PG* credentials locally for a disposable benchmark database, load it using etl/run_all.py --phase3, then run '
        'etl/06_run_phase3_muaz.py. Run tests/phase3_muaz_checks.py --disposable before '
        'etl/07_benchmark_phase3_muaz.py --disposable. Rebuild this PDF with reports/phase3/build_indexing_report.py. '
        'For another measurement use an empty --output-dir and pass it as --evidence-dir to this builder.')
    add('Thirty warm-cache samples come from one local session with fixed before/after ordering. Different machines, data volumes, '
        'cache states, concurrent loads and statistics can change results. Raw evidence is retained; no extra testing of alternative '
        'indexes was necessary because each selective candidate was used. The CUBE result supports retaining its broad scan.')
    heading('Exact experiment inputs')
    for file,sha in evidence['sql_sha256'].items():
        add(escape(file),'SmallPP'); story.append(Preformatted(sha,styles['CodePP']))
    add('Benchmark metadata: reports/phase3/performance/summary.json. All runs: runs.csv. '
        'Representative outlines shown in this PDF are taken from the measured JSON plan closest to each median, '
        'rather than from a separately timed EXPLAIN. The plans/ directory contains JSON and readable outlines '
        'for all thirty executions. Result checksums cover the complete ordered query results, including NULL subtotal keys.')
    add('Candidate rollback verified: '+str(evidence['candidates_rolled_back'])+'. '
        'Human review by Emaad, application to the shared warehouse and native Power BI acceptance remain pending.')
    def footer(canvas,doc):
        canvas.setStrokeColor(TEAL);canvas.line(42,37,A4[0]-42,37)
        canvas.setFont('Helvetica',8);canvas.setFillColor(NAVY)
        canvas.drawString(42,24,'PowerPulse | Muaz Fahad | Measured indexing evidence | 24 Nov 2026')
        canvas.drawRightString(A4[0]-42,24,str(doc.page))
    args.output.parent.mkdir(parents=True,exist_ok=True)
    doc=SimpleDocTemplate(str(args.output),pagesize=A4,rightMargin=42,leftMargin=42,topMargin=40,bottomMargin=50,
                         title='PowerPulse Indexing Report - Muaz Fahad',author='Muaz Fahad')
    doc.build(story,onFirstPage=footer,onLaterPages=footer)
    print('Saved '+str(args.output))


if __name__=='__main__':
    main()
