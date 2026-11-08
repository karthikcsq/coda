"""Voz v0.4.0 decoder projection adaptation, preserving its compiled runtime.
Only the three existing output projection blobs change. Fail closed on layouts
we have not validated. Do not modify the shared generic model directory.
"""
import json
import math
import re
from pathlib import Path


def blob_specs(directory):
    text = (Path(directory) / 'model.mil').read_text()
    specs = {}
    for line in text.splitlines():
        match = re.match(r'\s*tensor<fp16, \[([\d, ]+)\]> (\w+) = (const|constexpr_blockwise_shift_scale)\(', line)
        if match:
            shape = tuple(int(x) for x in match[1].split(','))
            offsets = [int(x) for x in re.findall(r'offset = uint64\((\d+)\)', line)]
            if offsets:
                entry = (shape, offsets, match[3])
                if match[2] in specs and specs[match[2]] != entry:
                    raise ValueError('Voz decoder functions disagree about shared weights.')
                specs[match[2]] = entry
    return specs


def read_weights(directory):
    import numpy as np
    from coremltools.libmilstoragepython import _BlobStorageReader
    specs = blob_specs(directory)
    reader = _BlobStorageReader(str(Path(directory) / 'weights/weight.bin'))
    weights = {}
    for name, (shape, offsets, kind) in specs.items():
        if not name.startswith("joint_out_"): continue
        if kind == 'const':
            weights[name] = np.asarray(reader.read_fp16_data(offsets[0])).view(np.float16).astype('float32').reshape(shape)
        else:
            data = np.asarray(reader.read_int8_data(offsets[0])).reshape(shape).astype('float32')
            scale = np.asarray(reader.read_fp16_data(offsets[1])).view(np.float16).astype('float32').reshape((shape[0],) + (1,) * (len(shape) - 1))
            weights[name] = data * scale
    if weights['joint_out_weight_to_fp16_quantized'].shape != (8198, 640, 1, 1):
        raise ValueError('This Voz decoder layout is not supported by the trainer.')
    return weights


def decoder(directory):
    import torch
    import torch.nn.functional as F
    w = {k: torch.from_numpy(v.astype('float16')).reshape(v.shape[:2] if v.ndim == 4 else v.shape) for k, v in read_weights(directory).items()}

    class Decoder(torch.nn.Module):
        def __init__(self):
            super().__init__()
            self.weight = torch.nn.Parameter(w['joint_out_weight_to_fp16_quantized'].float().clone())
            self.bias = torch.nn.Parameter(w['joint_out_bias_to_fp16'].float().clone())

        def forward(self, hidden):
            return F.linear(hidden, self.weight, self.bias)
    return Decoder()


def patch_projection(directory, weight, bias):
    import numpy as np
    from coremltools.libmilstoragepython import _BlobStorageReader
    directory = Path(directory)
    path = directory / 'weights/weight.bin'
    specs = blob_specs(directory)
    reader = _BlobStorageReader(str(path))
    # Durations stay frozen, including their original quantization.
    old = read_weights(directory)
    weight = weight.copy(); bias = bias.copy()
    weight[-5:] = old['joint_out_weight_to_fp16_quantized'].reshape(8198,640)[-5:]
    bias[-5:] = old['joint_out_bias_to_fp16'][-5:]
    scale = np.maximum(np.max(np.abs(weight), axis=1) / 127, 1e-7).astype(np.float16)
    quant = np.clip(np.rint(weight / scale.astype('float32')[:,None]), -127, 127).astype('int8')
    original_quant = np.asarray(reader.read_int8_data(specs['joint_out_weight_to_fp16_quantized'][1][0])).reshape(8198,640)
    original_scale = np.asarray(reader.read_fp16_data(specs['joint_out_weight_to_fp16_quantized'][1][1])).view(np.float16)
    quant[-5:] = original_quant[-5:]; scale[-5:] = original_scale[-5:]
    raw = bytearray(path.read_bytes())
    items = [(specs['joint_out_weight_to_fp16_quantized'][1][0], quant, 'read_int8_data'),
             (specs['joint_out_weight_to_fp16_quantized'][1][1], scale, 'read_fp16_data'),
             (specs['joint_out_bias_to_fp16'][1][0], bias.astype('float16'), 'read_fp16_data')]
    for offset, value, method in items:
        before = np.asarray(getattr(reader, method)(offset)).tobytes()
        # Blob payload headers are 64 bytes in the pinned format. Verify with
        # Apple's reader before writing; never guess offsets for another format.
        start = offset + 64
        if bytes(raw[start:start+len(before)]) != before or len(value.tobytes()) != len(before):
            raise ValueError('Unsupported Core ML weight storage; current model kept.')
        raw[start:start+len(before)] = value.tobytes()
    path.write_bytes(raw)


def encode(directory, audio):
    import numpy as np
    import coremltools as ct
    meta = json.loads((Path(directory)/'meta.json').read_text())
    n = len(audio)
    if n > 240000 or n == 0:
        raise ValueError('Voz training clips must contain speech and be at most 15 seconds.')
    padded = np.zeros(meta['n_rows'] * 160, dtype='float32')
    padded[256:256+n] = audio
    if n == 240000:
        tail = len(padded) - 256 - n
        padded[256+n:] = audio[-1] * np.power(.97, np.arange(1,tail+1))
    rows = padded.reshape(-1,160).T[None,:,None,:].astype('float16')
    valid = min(1500,n//160+1)
    mask = np.zeros((1,1,1,1500),dtype='float16');mask[:,:,:,:valid]=1
    attended = min(188,max(1,math.ceil(n/1280)))
    key = np.full((1,188,1,1),-40000,dtype='float16');key[:,:attended]=0
    mel = ct.models.CompiledMLModel(str(Path(directory)/'mel.mlmodelc'),compute_units=ct.ComputeUnit.CPU_ONLY)
    enc = ct.models.CompiledMLModel(str(Path(directory)/'encoder.mlmodelc'),compute_units=ct.ComputeUnit.CPU_AND_NE)
    features = mel.predict({'audio_rows':rows,'mel_mask':mask})['mel']
    result = enc.predict({'mel':features,'key_bias':key,'pad_mask':np.ones((1,1,1,188),dtype='float16')})['enc_proj']
    return result[0,:,0,:min(188,(valid+7)//8)].T.astype('float32')


def tokenize(text, vocab):
    # The public Voz sidecar contains pieces but no SentencePiece scores. Use
    # exact representable pieces; fail instead of training unknown characters.
    text = '▁' + '▁'.join(text.strip().split())
    pieces = {piece:i for i,piece in enumerate(vocab[:8192]) if piece and not piece.startswith('<')}
    result = []
    while text:
        match = next((text[:n] for n in range(min(len(text), max(map(len,pieces))),0,-1) if text[:n] in pieces),None)
        if match is None:
            raise ValueError('A reviewed transcript contains characters unavailable in the Voz vocabulary.')
        result.append(pieces[match]);text=text[len(match):]
    if len(result)>64:
        raise ValueError('Use a shorter reviewed transcript (at most 64 Voz pieces).')
    return result


def aligned_features(directory, audio, tokens, model):
    import numpy as np
    import torch
    import coremltools as ct
    enc = encode(directory,audio)
    embedding = np.fromfile(Path(directory)/'embedding.f16',dtype='float16').reshape(8193,640)
    native = ct.models.CompiledMLModel(str(Path(directory)/'decoder.mlmodelc'), compute_units=ct.ComputeUnit.CPU_ONLY, function_name='decoder_1')
    T,U=len(enc),len(tokens)+1
    lattice=np.empty((T,U,8198),dtype='float16')
    h=np.zeros((1,1280,1,1),dtype='float16');c=h.copy()
    embed=np.zeros((1,640,1,1),dtype='float16')
    for u in range(U):
        next_state=None
        for start in range(0,T,8):
            frames=np.zeros((1,640,1,8),dtype='float16')
            count=min(8,T-start)
            frames[0,:,0,:count]=enc[start:start+count].T
            result=native.predict({'embed':embed.copy(),'h_in':h.copy(),'c_in':c.copy(),'enc_step':frames})
            lattice[start:start+count,u,:]=result['logits'][0,:,0,:count].T
            if next_state is None: next_state=(result['h_out'],result['c_out'])
        h,c=next_state
        if u<len(tokens):embed=embedding[tokens[u]][None,:,None,None].copy()
    logits=torch.from_numpy(lattice.astype('float32'))
    lp=logits[:,:,:8193].log_softmax(-1).numpy()
    blanks=lp[:,:,8192]
    labels=np.full((T,U),-np.inf)
    for u,token in enumerate(tokens):labels[:,u]=lp[:,u,token]
    durations=logits[:,:,8193:].log_softmax(-1).numpy()
    del logits,lp
    best=np.full((T+1,U),-np.inf);best[0,0]=0
    back={}
    for t in range(T):
        for u in range(U):
            if not np.isfinite(best[t,u]):continue
            for d in range(5):
                for emit in (False,True):
                    if emit and u==U-1:continue
                    step=d if emit else max(1,d)
                    nt=min(T,t+step);nu=u+int(emit)
                    value=best[t,u]+(labels[t,u] if emit else blanks[t,u])+durations[t,u,d]
                    if value>best[nt,nu]:
                        best[nt,nu]=value;back[nt,nu]=(t,u,tokens[u] if emit else 8192)
    cursor=(T,U-1);xs=[];ys=[]
    if cursor not in back:raise ValueError('Could not align a reviewed transcript to its Voz audio.')
    while cursor!=(0,0):
        t,u,label=back[cursor];xs.append(lattice[t,u].astype("float32"));ys.append(label);cursor=(t,u)
    # Recover the frozen head's input from its native logits. Quantized CPU
    # execution has small rounding differences; preserve the exact native
    # starting logits as a detached residual while learning projection deltas.
    native_logits=np.stack(xs)
    weight=model.weight.detach().numpy()
    inverse=np.linalg.solve(weight.T@weight+np.eye(640,dtype='float32')*1e-3,weight.T).T
    hidden=torch.from_numpy((native_logits-model.bias.detach().numpy())@inverse)
    with torch.no_grad():residual=torch.from_numpy(native_logits)-model(hidden)
    return hidden,torch.tensor(ys),residual
