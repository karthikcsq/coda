# Third-party notices

## Optional Smart formatter

The optional punctuation classifier is [Horizon-Labs/punctuation-restoration-small](https://huggingface.co/Horizon-Labs/punctuation-restoration-small), revision `ee31fdfc5304f876ea3b0dd72d30eda7e940b2b1`, under Apache License 2.0. Its int8 ONNX weights, tokenizer, model card, license and checksummed manifest are installed separately at `Coda/SmartCleanup/v1/punctuation` under Application Support. Coda's own renderer only inserts finite punctuation labels at source offsets; no publisher helper code is used. The isolated official ONNX Runtime 1.31.0 macOS arm64 wheel supplies unmodified inference files and its MIT license/ThirdPartyNotices. `ORT_DISABLE_TELEMETRY=1` is set before loading that library, and telemetry is also disabled through its API. Licenses and reproducible synthetic evidence are retained in `benchmarks/cleanup-reuse-2026-10-26/punctuation-tagger/`. No model/runtime weights are bundled in the app.

The separately installed Smart formatter uses [Qwen/Qwen3.5-2B](https://huggingface.co/Qwen/Qwen3.5-2B), revision `15852e8c16360a2fea060d615a32b45270f8a8fc`, under Apache License 2.0. Coda uses a locally converted text-only 4-bit/group64 artifact, not a modified upstream checkpoint release. The upstream license is retained at `benchmarks/local-cleanup-2026-10-26/licenses/Qwen--Qwen3.5-2B-LICENSE`. The isolated MLX runtime is installed separately under Application Support, with its package metadata; requirements are pinned in the benchmark folder. App bundles contain Coda's formatter worker, not model weights or Python packages. This open-weight formatter does not change the separate Voz/Who licensing described below.

Smart cleanup first runs [spokenly/cleanup-1](https://huggingface.co/spokenly/cleanup-1), revision `cd95b5028cefd3a8cee4cefb4cdf159c88676f91`, under Apache License 2.0 (fine-tuned from Qwen/Qwen3-0.6B-Base). Coda uses a locally converted 8-bit/group64 MLX artifact installed separately under `Application Support/Coda/SmartCleanup/v1/cleanup`, with the upstream LICENSE, NOTICE and a SOURCE.json recording the source and converted weight hashes. App bundles do not contain these weights. Since 0.4.15 the installed artifact is a local LoRA fine-tune of that checkpoint (a modified version under Apache-2.0 section 4), with the untuned conversion kept as a rollback.

**Powered by Desert Ant Labs** — https://desertant.com

Coda integrates the official [desert-ant-core Swift SDK](https://github.com/Desert-Ant-Labs/desert-ant-core), pinned to **4.1.0** (`v4.1.0`, revision `86b9b55fe8c61ec1c27c5b6383f545c6df1d6ceb`). Voz and Who run inference locally. No model weights are vendored in Coda's Git repository. Modified Who Swift sources from that revision are included in `Vendor/Who` as the `CodaWho` target to support an optional speaker count. They retain the Desert Ant Labs Source-Available License and copyright; see [the preserved license notice](Vendor/Who/LICENSE.md) and [modification record](Vendor/Who/CODA-PATCH.md). Other Desert Ant SDK sources are resolved through Swift Package Manager.

The SDK **and** models are licensed under the [Desert Ant Labs Source-Available License v1.0](https://license.desertant.com/1.0), copyright 2026 Desert Ant Labs B.V. They are **not open source** and are not covered by Coda's MIT license. Read the authoritative license before using or distributing them, including its active-device thresholds, required attribution, competing-model restrictions, and licensing metadata provisions. The in-app Settings screen preserves visible attribution and asks the user to accept the model terms before any model initialization, downloading, or inference. Coda does not modify or disable SDK licensing reporting.

The SDK dependency includes Apple [swift-numerics](https://github.com/apple/swift-numerics), resolved to 1.1.1, under Apache License 2.0 with Runtime Library Exception. Consult its checked-out LICENSE.txt and NOTICE.txt when distributing dependencies. Swift and Apple system frameworks are subject to their respective licenses.

OpenAI is an optional hosted service governed by its own terms and data policies. Coda sends transcript text only after explicit action or an informed automatic-summary opt-in. Coda is independent of OpenAI and Desert Ant Labs.

## KeyboardShortcuts

[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts), version **2.4.0**, revision `1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27`, is vendored under MIT. Compatibility changes are documented in `Vendor/KeyboardShortcuts/CODA-PATCH.md`. No VoiceInk or Whispering source is included.

MIT License

Copyright (c) Sindre Sorhus <sindresorhus@gmail.com> (https://sindresorhus.com)

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Handy behavioral reference

The guarded paste transaction follows the promised-data receipt and change-count ownership pattern in [Handy](https://github.com/cjpais/Handy), commit `5a9451e70aedc90648ce2befd9d7e0304746f9c1`, `src-tauri/src/paste_tx/macos.rs`, `paste_tx/mod.rs`, and `input.rs`. The Swift adapter ports the explicit Command/V/100ms/release sequence and post-injection receipt timing; it retains stricter target checks, all-format clipboard restoration, and never ports auto-submit. Coda uses its own Swift implementation and keeps its native UI. Handy is MIT licensed.

MIT License

Copyright (c) 2025 CJ Pais

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
