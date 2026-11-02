import pathlib,json,hashlib,time
base=pathlib.Path('/tmp/coda-cleanup-benchmark')
files=[];totals={};logical=allocated=0
for p in base.rglob('*'):
 if p.is_symlink() or not p.is_file():continue
 st=p.stat();logical+=st.st_size;allocated+=st.st_blocks*512
 top=p.relative_to(base).parts[0];totals[top]=totals.get(top,0)+st.st_size
 if top in ['models','quantized'] and '.cache' not in p.parts:
  files.append({'path':str(p.relative_to(base)),'bytes':st.st_size,'sha256':hashlib.file_digest(p.open('rb'),'sha256').hexdigest()})
manifest={'scratch_root':str(base),'created_for':'Coda synthetic text cleanup benchmark 2026-10-26','hardware':{'model':'Mac17,8','chip':'Apple M5 Pro','ram_bytes':25769803776},'preexisting_resources_used_readonly':['/opt/homebrew/bin/python3.13'],'preexisting_caches':'No preexisting model/runtime caches used or removed. HF_HOME/HF_HUB_CACHE/XDG_CACHE_HOME/MPLCONFIGDIR redirected to scratch; pip --no-cache-dir. OS file/Metal caches not flushed or removed.','remote_code':False,'credentials':'HF token=False; implicit tokens disabled; inference offline; no API keys accessed','logical_bytes_before_cleanup':logical,'allocated_bytes_before_cleanup':allocated,'top_level_logical_bytes':totals,'model_and_quantized_files':files,'dependencies':'requirements.lock.txt','installed_coda':'untouched throughout benchmark'}
(base/'inventory.json').write_text(json.dumps(manifest,indent=2))
print('logical_bytes',logical,'allocated_bytes',allocated,'files_hashed',len(files))
