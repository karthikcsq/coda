"""Opt-in validation against the installed Voz decoder, without user recordings.
CODA_VOZ_BASE=/path/to/voz/v0.4.0 python -m unittest discover -s scripts/personal-audio
"""
import os
from pathlib import Path
import tempfile
import shutil
import unittest

@unittest.skipUnless(os.environ.get('CODA_VOZ_BASE'), 'Requires a local Voz model and Core ML runtime')
class NativeVozTests(unittest.TestCase):
    def test_projection_round_trip_updates_native_voz_and_preserves_generic(self):
        import numpy as np
        import coremltools as ct
        from voz import decoder, patch_projection
        source = Path(os.environ['CODA_VOZ_BASE']) / 'decoder.mlmodelc'
        original = (source / 'weights/weight.bin').read_bytes()
        model = decoder(source)
        inputs = {'embed': np.zeros((1,640,1,1),dtype='float16'),
                  'h_in': np.zeros((1,1280,1,1),dtype='float16'),
                  'c_in': np.zeros((1,1280,1,1),dtype='float16'),
                  'enc_step': np.zeros((1,640,1,8),dtype='float16')}
        native = ct.models.CompiledMLModel(str(source), compute_units=ct.ComputeUnit.CPU_ONLY, function_name='decoder_1')
        baseline = native.predict(dict(inputs))['logits']
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)/'decoder.mlmodelc'
            shutil.copytree(source,target)
            bias = model.bias.detach().numpy().copy()
            bias[:10] += .125
            patch_projection(target,model.weight.detach().numpy(),bias)
            candidate = ct.models.CompiledMLModel(str(target),compute_units=ct.ComputeUnit.CPU_ONLY,function_name='decoder_1')
            result = candidate.predict(dict(inputs))['logits']
            self.assertAlmostEqual(float(np.mean(result[:,:10]-baseline[:,:10])),.125,delta=.02)
            self.assertEqual(float(np.max(np.abs(result[:,-5:]-baseline[:,-5:]))),0)
        self.assertEqual(original,(source/'weights/weight.bin').read_bytes())
