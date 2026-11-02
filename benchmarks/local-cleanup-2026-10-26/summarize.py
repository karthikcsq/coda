import json,pathlib,statistics,math,re
base=pathlib.Path('/tmp/coda-cleanup-benchmark')
cases={c['id']:c for c in json.loads((base/'cases.json').read_text())}
def norm(s): return re.sub(r'\s+',' ',s.strip()).casefold()
def acceptable(row):
 c=cases[row['case']]
 return norm(row['output'])==norm(c['expected']) and not row['capped'] and (row['case']!='paragraph' or '\n\n' in row['output'])
summary=[]
for p in sorted((base/'results').glob('*.json')):
 d=json.loads(p.read_text());rows=[r for r in d['rows'] if r['repeat']>0];first=[r for r in rows if r['repeat']==1];t=sorted(r['seconds'] for r in rows)
 summary.append({'label':d['label'],'prompt_variant':d.get('prompt_variant','base'),'sample_count':len(t),'case_count':len(first),'reference_pass_cases':sum(acceptable(r) for r in first),'passed_cases':[r['case'] for r in first if acceptable(r)],'failed_cases':[r['case'] for r in first if not acceptable(r)],'p50_ms':1000*statistics.median(t),'p95_ms':1000*t[math.ceil(.95*len(t))-1],'cold_first_output_s':d['cold_process_to_first_complete_seconds'],'load_s':d['load_seconds'],'disk_bytes':d['disk_bytes'],'metal_peak_bytes':max(r['metal_peak_bytes'] for r in rows),'rss_max_bytes':max(r['rss_max_bytes'] for r in rows),'capped_generations':sum(r['capped'] for r in rows),'unique_case_outputs':len(set((r['case'],r['output']) for r in rows))})
(base/'summary.json').write_text(json.dumps(summary,indent=2))
for d in summary:
 if d['label'].endswith('corrections'): print(d['label'],d['reference_pass_cases'],'/14',round(d['p50_ms']),round(d['p95_ms']),round(d['cold_first_output_s'],2),round(d['disk_bytes']/1e6),round(d['metal_peak_bytes']/1e9,2),round(d['rss_max_bytes']/1e9,2))
