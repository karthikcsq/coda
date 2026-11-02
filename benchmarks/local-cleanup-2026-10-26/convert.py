import sys,time,json,pathlib
from mlx_lm.convert import convert
base=pathlib.Path('/tmp/coda-cleanup-benchmark'); slug=sys.argv[1];t=time.perf_counter()
convert(str(base/'models'/slug),mlx_path=str(base/'quantized'/slug),quantize=True,q_bits=4,q_group_size=64,trust_remote_code=False)
print(json.dumps({'conversion_seconds':time.perf_counter()-t,'slug':slug}))
