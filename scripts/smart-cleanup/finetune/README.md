# Fine-tuning Smart cleanup

LoRA fine-tuning of spokenly/cleanup-1 on the user's speaking mistakes. Tooling lives here; all data lives in the private folder `~/Library/Application Support/Coda/SmartCleanup/finetune/` and is never committed (it contains or paraphrases the user's dictations).

| Private path | Contents |
| --- | --- |
| `labeled.jsonl` | The user's saved dictations with gold cleaned text |
| `sources/synthetic.jsonl`, `sources/synthetic_keep2.jsonl` | Written examples (fixes, plus keep-traps where nothing may be cut) and their generator scripts |
| `data/` | train / valid (MLX chat format) and `heldout.jsonl` (fixed test set) |
| `base-bf16/` | Upstream spokenly/cleanup-1 weights, revision `cd95b502…` |
| `adapters-r*/`, `cleanup-r*-8bit/` | Trained adapters and fused 8-bit candidates |

Labels follow [POLICY.md](POLICY.md); every label must pass the runtime guard.

```bash
F=~/Library/Application\ Support/Coda/SmartCleanup/finetune; P=~/Library/Application\ Support/Coda/SmartCleanup/v1/runtime/bin/python
python3 check_labels.py "$F"/sources/*.jsonl "$F/labeled.jsonl"
python3 split.py "$F/sources/synthetic.jsonl" "$F/labeled.jsonl" "$F/data" --edit-repeat 2 "$F/sources/synthetic_keep2.jsonl"
"$P" -m mlx_lm lora -c lora-r2.yaml --train --model "$F/base-bf16" --data "$F/data" --adapter-path "$F/adapters-r2"
"$P" -m mlx_lm fuse --model "$F/base-bf16" --adapter-path "$F/adapters-r2" --save-path "$F/fused-r2-bf16"
"$P" -m mlx_lm convert --hf-path "$F/fused-r2-bf16" --mlx-path "$F/cleanup-r2-8bit" -q --q-bits 8 --q-group-size 64
"$P" score.py "$F/cleanup-r2-8bit" "$F/data/heldout.jsonl"
```

## Results on the fixed held-out set (103 examples: 50 dictations, 53 written)

| Model (8-bit, current guard) | Exact | Words missed | Words wrongly cut (examples) | Guard rejects | Avg ms |
| --- | --- | --- | --- | --- | --- |
| spokenly/cleanup-1, installed in 0.4.14 | 75.7% | 40 | 25 (14) | 4 | 79 |
| Round 1: lr 5e-5, 150 iters, 367 rows | 82.5%* | 28 | 28 (11) | 2 | — |
| Round 2: lr 3e-5, 120 iters, 520 rows incl. 164 keep-traps | 93.2% | 30 | 3 (3) | 2 | 78 |

*Round 1 was scored unfused at bf16, before the 12-word gap limit. It over-cut ("6 by 6 by 12" → "8 by 16", dropped "I think"); round 2 added keep-traps for those patterns. Extra training rows that nearly copy a held-out example are dropped by `split.py`.

Known gaps in round 2: "my manager asked would ask" (held out, never trained on) and "change the change how" are still missed; it once dropped a 16-word instruction, which the 12-word gap limit now rejects.
