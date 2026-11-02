"""Recreate only the pinned trial assets in fresh dedicated scratch. Python3.12+."""
import hashlib,pathlib,tarfile,urllib.request
ROOT=pathlib.Path('/tmp/coda-cleanup-reuse-2026-10-26')
FILES=[
 ('quill-0.8b-Q4_K_M.gguf','https://huggingface.co/Quobi/Quill/resolve/4cc2cc3c8e7ea9ee69126becd55be23a3a949899/quill-0.8b-Q4_K_M.gguf','aa54d6f6108d66e4b60a57bdc04ecca6e84e073504918a64b41ac4a0f816f16d'),
 ('llama-b11901-bin-macos-arm64.tar.gz','https://github.com/ggml-org/llama.cpp/releases/download/b11901/llama-b11901-bin-macos-arm64.tar.gz','dde35fc01722157f31af2c3a6e859e971427deb8e65b9e038606fcc9c44ce79c'),
]
def main():
 if ROOT.exists():raise SystemExit('Scratch destination already exists; inspect it rather than overwrite it.')
 ROOT.mkdir()
 for name,url,digest in FILES:
  path=ROOT/name;request=urllib.request.Request(url,headers={'User-Agent':'Coda-synthetic-evaluation'})
  with urllib.request.urlopen(request,timeout=90) as response,path.open('wb') as out:
   while chunk:=response.read(1024*1024):out.write(chunk)
  if hashlib.sha256(path.read_bytes()).hexdigest()!=digest:raise ValueError('Checksum mismatch: '+name)
 runner=ROOT/'runner';runner.mkdir()
 with tarfile.open(ROOT/FILES[1][0]) as archive:
  for member in archive.getmembers():
   if not (runner/member.name).resolve().is_relative_to(runner.resolve()):raise ValueError('Unsafe archive path')
  archive.extractall(runner,filter='data')
 print('Pinned data and official runner ready. Run trial_quill.py; it is synthetic-only and offline.')
if __name__=='__main__':main()
