#!/usr/bin/env python3
"""Measure the same three queries before/after candidate indexes on a disposable DB.

Requires --disposable and a database name containing 'benchmark' or 'scratch'.
Preserves every existing index; refuses a baseline that already has a candidate
name or equivalent definition. Candidate DDL is rolled back after measurement.
"""
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
from datetime import datetime, timezone

import psycopg
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]


def digest(value):
    return hashlib.sha256(json.dumps(value, default=str, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disposable', action='store_true')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'reports/phase3/performance')
    args = parser.parse_args()
    load_dotenv(ROOT / '.env')
    dbname = os.getenv('PGDATABASE', 'powerpulse_dw')
    if not args.disposable or not any(word in dbname.lower() for word in ['benchmark', 'scratch']):
        parser.error('Use --disposable with a dedicated database named with benchmark or scratch')
    config = {k: os.getenv(env, default) for k, env, default in [
        ('host', 'PGHOST', 'localhost'), ('port', 'PGPORT', '5432'),
        ('dbname', 'PGDATABASE', 'powerpulse_dw'), ('user', 'PGUSER', 'postgres')]}
    if os.getenv('PGPASSWORD'):
        config['password'] = os.environ['PGPASSWORD']
    sql_path = ROOT / 'sql/09_phase3_performance/01_benchmarks.sql'
    ddl_path = ROOT / 'sql/09_phase3_performance/02_candidate_indexes.sql'
    parts = re.split(r'^-- benchmark: (\w+)\s*$', sql_path.read_text(), flags=re.M)
    queries = {parts[i]: parts[i+1].strip() for i in range(1, len(parts), 2)}
    out = args.output_dir
    if out.exists() and any(out.iterdir()):
        parser.error('Output directory must be empty; preserve previous raw measurements')
    out.mkdir(parents=True, exist_ok=True)
    plans = out / 'plans'
    plans.mkdir()
    runs, summary = [], []
    with psycopg.connect(**config, connect_timeout=10, autocommit=True) as conn:
        conn.execute("SET statement_timeout='120s'")
        conn.execute('SET max_parallel_workers_per_gather=0')
        conn.execute('SET jit=off')
        conn.execute("SET work_mem='32MB'")
        inventory = conn.execute("SELECT tablename,indexname,indexdef FROM pg_indexes "
                                 "WHERE schemaname='project_dw' ORDER BY tablename,indexname").fetchall()
        candidate_names = ['idx_p3_demand_authority_date', 'idx_p3_generation_source_date_authority']
        if any(row[1] in candidate_names for row in inventory):
            raise SystemExit('Candidate index already exists; use a fresh disposable baseline')
        # Refuse equivalent definitions, even under another name.
        definitions = [row[2].split(' USING ', 1)[-1] for row in inventory]
        for definition in ['btree (authority_key, date_key) INCLUDE (actual_demand_mw)',
                           'btree (energy_source_key, date_key, authority_key) INCLUDE (generation_mw)']:
            if definition in definitions:
                raise SystemExit('An equivalent candidate index exists; use a fresh baseline')
        for table in ['fact_hourly_demand', 'fact_hourly_generation']:
            conn.execute('VACUUM (ANALYZE) project_dw.' + table)
        for table in ['dim_date','dim_balancing_authority','dim_energy_source']:
            conn.execute('ANALYZE project_dw.' + table)
        environment = {
            'created_at_utc': datetime.now(timezone.utc).isoformat(),
            'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
            'working_tree_note': 'Muaz files are working-tree additions; exact SQL hashes recorded below.',
            'postgresql': conn.execute('SELECT version()').fetchone()[0],
            'host_platform': platform.platform(), 'cpu': platform.processor(),
            'logical_cpus': os.cpu_count(),
            'cache_policy': 'Warm cache; one unrecorded warm-up and five measured executions per query per arm; no OS cache flushing.',
            'settings': dict(conn.execute("SELECT name,setting FROM pg_settings WHERE name=ANY(%s) ORDER BY name",
                                         (['work_mem','shared_buffers','effective_cache_size','jit',
                                           'max_parallel_workers_per_gather','random_page_cost',
                                           'seq_page_cost','default_statistics_target'],)).fetchall()),
            'counts': {table: conn.execute('SELECT count(*) FROM project_dw.'+table).fetchone()[0]
                       for table in ['fact_hourly_demand','fact_hourly_generation','dim_date','dim_energy_source']},
            'indexes_before': [{'table':r[0],'name':r[1],'definition':r[2]} for r in inventory],
            'sql_sha256': {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest()
                           for p in [sql_path,ddl_path]},
            'candidate_storage_bytes': {}, 'measurements': [],
        }
        # All experimental CREATE INDEX operations are transactional and rolled back.
        with conn.transaction(force_rollback=True):
            baseline_results = {}
            for arm in ['before', 'after']:
                if arm == 'after':
                    conn.execute(ddl_path.read_text())
                    for name in candidate_names:
                        environment['candidate_storage_bytes'][name] = conn.execute(
                            'SELECT pg_relation_size(%s::regclass)', ('project_dw.'+name,)).fetchone()[0]
                for name, sql in queries.items():
                    rows = conn.execute(sql).fetchall()
                    result_hash = digest(rows)
                    if arm == 'before':
                        baseline_results[name] = result_hash
                    elif result_hash != baseline_results[name]:
                        raise RuntimeError(f'Results changed after candidate DDL: {name}')
                    # Explicit warm-up under EXPLAIN, matching the measured command.
                    conn.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+sql).fetchone()
                    for run in range(1,6):
                        plan = conn.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+sql).fetchone()[0]
                        p = plan[0]
                        stem = f'{name}_{arm}_{run}'
                        (plans / f'{stem}.json').write_text(json.dumps(plan,indent=2)+'\n')
                        # Readable plan represents the SAME measured JSON execution.
                        def readable(node, depth=0):
                            lines = ['  '*depth + json.dumps({k:v for k,v in node.items() if k!='Plans'},default=str)]
                            for child in node.get('Plans',[]): lines.extend(readable(child,depth+1))
                            return lines
                        (plans / f'{stem}.txt').write_text('\n'.join(readable(p['Plan']))+
                            f"\nPlanning Time: {p['Planning Time']} ms\nExecution Time: {p['Execution Time']} ms\n")
                        used=[]
                        def collect(node):
                            if 'Index Name' in node: used.append(node['Index Name'])
                            for child in node.get('Plans',[]): collect(child)
                        collect(p['Plan'])
                        runs.append({'query':name,'arm':arm,'run':run,
                                     'execution_ms':p['Execution Time'], 'planning_ms':p['Planning Time'],
                                     'estimated_total_cost':p['Plan']['Total Cost'],
                                     'shared_hit_blocks':p['Plan'].get('Shared Hit Blocks',0),
                                     'shared_read_blocks':p['Plan'].get('Shared Read Blocks',0),
                                     'result_rows':len(rows),'result_sha256':result_hash,
                                     'indexes_used':';'.join(sorted(set(used)))})
                    print(f'PASS {name} {arm}: five measured runs, unchanged result {result_hash[:12]}',flush=True)
            for name in queries:
                before=[r for r in runs if r['query']==name and r['arm']=='before']
                after=[r for r in runs if r['query']==name and r['arm']=='after']
                b=statistics.median(r['execution_ms'] for r in before)
                a=statistics.median(r['execution_ms'] for r in after)
                summary.append({'query':name,'before_median_ms':b,'after_median_ms':a,
                                'time_improvement_pct':100*(b-a)/b if b else None,
                                'before_cost':before[0]['estimated_total_cost'],
                                'after_cost':after[0]['estimated_total_cost'],
                                'candidate_indexes_used':sorted(set(i for r in after for i in r['indexes_used'].split(';') if i in candidate_names)),
                                'results_unchanged':True})
        environment['candidates_rolled_back'] = not conn.execute(
            "SELECT 1 FROM pg_indexes WHERE schemaname='project_dw' AND indexname=ANY(%s)",
            (candidate_names,)).fetchone()
        environment['summary']=summary
    with (out/'runs.csv').open('w',newline='',encoding='utf-8') as f:
        writer=csv.DictWriter(f,fieldnames=list(runs[0])); writer.writeheader();writer.writerows(runs)
    (out/'summary.json').write_text(json.dumps(environment,indent=2)+'\n')
    print(json.dumps(summary,indent=2))


if __name__ == '__main__':
    main()
