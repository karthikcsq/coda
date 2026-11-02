"""One-time local 0.4.10 installation after normal quit; no permissions/audio/UI."""
import hashlib, json, pathlib, plistlib, subprocess

repo=pathlib.Path(__file__).resolve().parents[2]
stage=repo/'build-staged'
candidate=stage/'Coda-0.4.10-candidate.app'
canonical=repo/'build/Coda.app'
rollback=stage/'Coda-0.4.9-build8-rollback.app'
evidence=pathlib.Path(__file__).parent
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def info(app): return plistlib.loads((app/'Contents/Info.plist').read_bytes())
def verify(app):
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    result=subprocess.run(['codesign','-d','-r-',str(app)],capture_output=True,text=True,check=True)
    requirement=result.stderr+result.stdout
    assert 'certificate leaf = H"22571b293ddeed6b20db834884a208bfdaddedd7"' in requirement,requirement
    return requirement.strip()
def history():
    base=pathlib.Path.home()/'Library/Application Support/Coda'
    return {folder:{p.name:digest(p) for p in sorted((base/folder).glob('*.json'))} for folder in ['Meetings','Dictations']}
def preferences():
    return {key:subprocess.check_output(['defaults','read','app.coda.notebook',key],text=True).strip() for key in ['dictationCleanupMode','dictationMode','dictationModifierShortcut']}
assert info(candidate)['CFBundleShortVersionString']=='0.4.10' and info(candidate)['CFBundleVersion']=='9'
assert info(canonical)['CFBundleShortVersionString']=='0.4.9' and info(canonical)['CFBundleVersion']=='8'
assert not rollback.exists(), 'Never overwrite rollback'
requirement=verify(candidate)
scripts={'worker.py':'smart_cleanup_worker.py','cleanup_rules.py':'cleanup_rules.py','punctuation.py':'punctuation.py'}
hashes={}
for source,destination in scripts.items():
    a=repo/'scripts/smart-cleanup'/source; b=candidate/'Contents/Resources'/destination
    assert digest(a)==digest(b),(a,b)
    hashes[destination]=digest(b)
assert not list(candidate.rglob('__pycache__'))
saved=history(); prefs=preferences()
for name,value in [('history-hashes',saved),('settings',prefs)]:
    path=stage/('pre-0.4.10-'+name+'.json')
    assert not path.exists(),path
    path.write_text(json.dumps(value,indent=2)+'\n')
canonical.rename(rollback)
try: candidate.rename(canonical)
except BaseException:
    rollback.rename(canonical)
    raise
verify(canonical)
diagnostic=subprocess.check_output([str(canonical/'Contents/MacOS/Coda'),'--insertion-diagnostics'],text=True)
assert 'Accessibility trusted: true' in diagnostic,diagnostic
assert saved==history(), 'Saved JSON changed'
assert prefs==preferences(), 'Preferences changed'
subprocess.run(['open',str(canonical)],check=True)
result=dict(installed_version='0.4.10',build='9',script_sha256=hashes,signing_requirement=requirement,strict_signature_verified=True,diagnostic=diagnostic.strip().splitlines(),preferences=prefs,saved_json_preserved={k:len(v) for k,v in saved.items()},rollback=str(rollback.relative_to(repo)),normal_quit=True,live_audio_clipboard_or_computer_use=False)
(evidence/'installation.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
