import json, pathlib, sys, time
from huggingface_hub import HfApi, snapshot_download
base=pathlib.Path('/tmp/coda-cleanup-benchmark')
repo=sys.argv[1]; slug=repo.replace('/','--')
api=HfApi(token=False); info=api.model_info(repo,revision=sys.argv[2] if len(sys.argv)>2 else None,files_metadata=True)
card=info.card_data.to_dict() if info.card_data else {}
assert card.get('license')=='apache-2.0',card.get('license')
assert not info.gated,'Gated model; stop for review'
manifest={'repo':repo,'revision':info.sha,'license':card.get('license'),'started':time.time(),'files':[{'name':s.rfilename,'size':s.size} for s in info.siblings],'data_only':True,'token':False}
(base/'manifests').mkdir(exist_ok=True)
(base/'manifests'/f'{slug}.json').write_text(json.dumps(manifest,indent=2))
path=snapshot_download(repo,revision=info.sha,token=False,local_dir=base/'models'/slug,
 allow_patterns=['*.json','*.safetensors','*.txt','*.model','*.jinja','*.tiktoken','LICENSE*','README.md'],max_workers=3)
manifest['local_path']=path;manifest['download_seconds']=time.time()-manifest['started'];manifest['actual_bytes']=sum(p.stat().st_size for p in pathlib.Path(path).rglob('*') if p.is_file())
(base/'manifests'/f'{slug}.json').write_text(json.dumps(manifest,indent=2))
print(json.dumps({k:manifest[k] for k in ['repo','revision','license','actual_bytes','download_seconds']}))
