#!/usr/bin/env python3
"""Source-oracle and rolled-back fixture checks for Muaz's installed views.

Run on a disposable database only: --disposable and PGDATABASE containing
benchmark or scratch are required because fixtures update real demand facts.
The frozen CSVs are read independently using Python Decimal arithmetic.
"""
import argparse
import csv
from collections import defaultdict
from datetime import datetime
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path

import psycopg
from psycopg.rows import dict_row
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parents[1]
FIELDS = ['observed_authority_hours','eligible_forecast_pairs','excluded_forecast_pairs',
          'eligible_actual_sum_mw','eligible_forecast_sum_mw','signed_error_sum_mw',
          'abs_error_sum_mw','underforecast_pairs','equal_forecast_pairs','overforecast_pairs']


def source_oracle():
    def group():
        return [0,0,0,Decimal(0),Decimal(0),Decimal(0),Decimal(0),0,0,0]
    groups = [defaultdict(group) for _ in range(3)]
    manifest = json.loads((ROOT/'data_acquisition/data/source_manifest.json').read_text())
    hashes = {}
    for file in manifest['files']:
        path = ROOT/'data_acquisition/data'/file['subset_file']
        hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        if hashes[path.name] != file['subset_sha256']:
            raise AssertionError(f'Source hash mismatch: {path.name}')
        with path.open(newline='', encoding='utf-8-sig') as stream:
            for r in csv.DictReader(stream):
                a = r['Balancing Authority']
                d = datetime.strptime(r['Data Date'], '%m/%d/%Y').date()
                h = datetime.strptime(r['Local Time at End of Hour'], '%m/%d/%Y %I:%M:%S %p').hour
                season = ['Winter','Winter','Spring','Spring','Spring','Summer',
                          'Summer','Summer','Autumn','Autumn','Autumn','Winter'][d.month-1]
                actual = Decimal(r['Demand (MW)']) if r['Demand (MW)'].strip() else None
                forecast = Decimal(r['Demand Forecast (MW)']) if r['Demand Forecast (MW)'].strip() else None
                eligible = actual is not None and actual > 0 and forecast is not None and forecast >= 0
                for mapping, key in zip(groups, [(a,d.replace(day=1)),(a,d.year,season,h),
                                                  (a,d.replace(day=1),h)]):
                    g = mapping[key]; g[0] += 1; g[1] += eligible; g[2] += not eligible
                    if eligible:
                        error = actual-forecast
                        for i, value in [(3,actual),(4,forecast),(5,error),(6,abs(error))]:
                            g[i] += value
                        g[7] += error>0; g[8] += error==0; g[9] += error<0
    for mapping in groups:
        for g in mapping.values():
            if g[1] == 0: g[3:7] = [None]*4
    return groups, hashes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disposable', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT/'reports/phase3/muaz/validation.json')
    args = parser.parse_args()
    load_dotenv(ROOT/'.env')
    dbname = os.getenv('PGDATABASE','powerpulse_dw')
    if not args.disposable or not any(s in dbname.lower() for s in ['benchmark','scratch']):
        parser.error('Use a dedicated benchmark/scratch database and --disposable')
    checks = []
    def check(name, condition, detail=None):
        if not condition: raise AssertionError(name)
        checks.append({'name':name,'passed':True,'detail':detail})
        print('PASS '+name, flush=True)
    groups, hashes = source_oracle()
    config = {k:os.getenv(env,default) for k,env,default in [
        ('host','PGHOST','localhost'),('port','PGPORT','5432'),
        ('user','PGUSER','postgres'),('dbname','PGDATABASE','powerpulse_dw')]}
    if os.getenv('PGPASSWORD'): config['password']=os.environ['PGPASSWORD']
    with psycopg.connect(**config, connect_timeout=10, row_factory=dict_row) as conn:
        runtime = conn.execute('SELECT version() AS v').fetchone()['v']
        views = [
            ('vw_q05_forecast_accuracy',['authority_code','month_start']),
            ('vw_q06_underforecast_pattern',['authority_code','calendar_year','season','hour_ending']),
            ('vw_forecast_month_hour_components',['authority_code','month_start','hour_ending'])]
        for (view,keys), oracle in zip(views,groups):
            rows = conn.execute('SELECT * FROM project_reporting.'+view).fetchall()
            seen = set()
            for row in rows:
                key=tuple(row[k] for k in keys); seen.add(key)
                assert key in oracle and [row[k] for k in FIELDS]==oracle[key], (view,key)
                if 'forecast_bias_mw' in row:
                    g=oracle[key]
                    for field,expected in [
                        ('forecast_bias_mw',g[5]/g[1] if g[1] else None),
                        ('forecast_mae_mw',g[6]/g[1] if g[1] else None),
                        ('forecast_wape_pct',100*g[6]/g[3] if g[1] else None),
                        ('underforecast_pct',Decimal(100)*g[7]/g[1] if g[1] else None)]:
                        assert row[field] is None if expected is None else abs(row[field]-expected)<Decimal('1e-10'), (view,key,field)
            check(view+' all components and rates match independent CSV',seen==oracle.keys(),{'groups':len(rows)})
        check('baseline forecast population',sum(g[1] for g in groups[0].values())==87399)
        before = {view:conn.execute('SELECT * FROM project_reporting.'+view+' ORDER BY '+', '.join(keys)).fetchall() for view,keys in views}
        conn.commit()
        with conn.transaction(force_rollback=True):
            target=conn.execute('SELECT authority_key,month_start FROM project_reporting.vw_q05_forecast_accuracy ORDER BY 1,2 LIMIT 1').fetchone()
            params=tuple(target.values())
            keys=conn.execute("SELECT f.demand_key FROM project_dw.fact_hourly_demand f JOIN project_dw.dim_date d USING(date_key) WHERE authority_key=%s AND date_trunc('month',d.calendar_date)::date=%s ORDER BY utc_hour_end LIMIT 9",params).fetchall()
            conn.execute("UPDATE project_dw.fact_hourly_demand f SET actual_demand_mw=NULL,forecast_demand_mw=NULL FROM project_dw.dim_date d WHERE f.date_key=d.date_key AND authority_key=%s AND date_trunc('month',d.calendar_date)::date=%s",params)
            fixture=[(100,90),(100,100),(100,110),(0,0),(-1,0),(100,-1),(None,100),(100,None),(50,0)]
            for key,(actual,forecast) in zip(keys,fixture):
                conn.execute('UPDATE project_dw.fact_hourly_demand SET actual_demand_mw=%s,forecast_demand_mw=%s WHERE demand_key=%s',(actual,forecast,key['demand_key']))
            row=conn.execute('SELECT * FROM project_reporting.vw_q05_forecast_accuracy WHERE authority_key=%s AND month_start=%s',params).fetchone()
            check('real view handles null/zero/negative/equal/over/under forecast fixture',
                  (row['eligible_forecast_pairs'],row['underforecast_pairs'],row['equal_forecast_pairs'],row['overforecast_pairs'],row['forecast_bias_mw'],row['forecast_mae_mw'],row['forecast_wape_pct'],row['underforecast_pct'])==(4,2,1,1,Decimal('12.5'),Decimal('17.5'),Decimal('20'),Decimal('50')))
            conn.execute("UPDATE project_dw.fact_hourly_demand f SET actual_demand_mw=0 FROM project_dw.dim_date d WHERE f.date_key=d.date_key AND authority_key=%s AND date_trunc('month',d.calendar_date)::date=%s",params)
            row=conn.execute('SELECT * FROM project_reporting.vw_q05_forecast_accuracy WHERE authority_key=%s AND month_start=%s',params).fetchone()
            check('no eligible pairs produces NULL rates and sums',row['eligible_forecast_pairs']==0 and all(row[k] is None for k in ['eligible_actual_sum_mw','abs_error_sum_mw','forecast_bias_mw','forecast_mae_mw','forecast_wape_pct','underforecast_pct']))
            # Remove an internal month: the Q01 spine must preserve a no-data Q05 row.
            conn.execute("DELETE FROM project_dw.fact_hourly_demand f USING project_dw.dim_date d WHERE f.date_key=d.date_key AND authority_key=%s AND d.calendar_date>=DATE '2024-02-01' AND d.calendar_date<DATE '2024-03-01'",(target['authority_key'],))
            row=conn.execute("SELECT * FROM project_reporting.vw_q05_forecast_accuracy WHERE authority_key=%s AND month_start=DATE '2024-02-01'",(target['authority_key'],)).fetchone()
            check('missing internal month retains zero counts and NULL rates',row is not None and row['observed_authority_hours']==0 and row['eligible_forecast_pairs']==0 and row['forecast_wape_pct'] is None)
            conn.execute((ROOT/'sql/07_phase3_analytics/p3_validate.sql').read_text())
            check('SQL validation passes with edge fixtures',True)
        check('rolled-back fixtures restore all baseline view rows',all(before[v]==conn.execute('SELECT * FROM project_reporting.'+v+' ORDER BY '+', '.join(k)).fetchall() for v,k in views))
        conn.execute((ROOT/'sql/06_reporting/p3_forecast_views.sql').read_text())
        conn.execute((ROOT/'sql/07_phase3_analytics/p3_validate.sql').read_text())
        check('reinstall preserves all view rows',all(before[v]==conn.execute('SELECT * FROM project_reporting.'+v+' ORDER BY '+', '.join(k)).fetchall() for v,k in views))
        conn.commit()
        cur=conn.execute((ROOT/'sql/07_phase3_analytics/p3_q05_q06.sql').read_text())
        sizes=[]
        while True:
            if cur.description: sizes.append(len(cur.fetchall()))
            if not cur.nextset(): break
        check('analytical submission SQL executes',True,{'result_set_rows':sizes})
        result={'date':'2026-11-24','runtime':runtime,'checks':checks,'source_sha256':hashes,
                'sql_sha256':{f:hashlib.sha256((ROOT/f).read_bytes()).hexdigest() for f in [
                    'sql/06_reporting/p3_forecast_views.sql',
                    'sql/07_phase3_analytics/p3_validate.sql',
                    'sql/07_phase3_analytics/p3_q05_q06.sql']},
                'scope':'Forecast SQL validated on the full clean disposable warehouse. No production database changes; no human reviewer sign-off.',
                'summary':conn.execute('SELECT sum(observed_authority_hours) observed_hours,sum(eligible_forecast_pairs) eligible_pairs,sum(excluded_forecast_pairs) excluded_pairs,sum(abs_error_sum_mw) abs_error_sum_mw,sum(eligible_actual_sum_mw) eligible_actual_sum_mw,100*sum(abs_error_sum_mw)/sum(eligible_actual_sum_mw) wape_pct FROM project_reporting.vw_q05_forecast_accuracy').fetchone()}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,default=str)+'\n')


if __name__=='__main__':
    main()
