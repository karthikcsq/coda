# Coda speaker count extension

Source: Desert-Ant-Labs/desert-ant-core 4.1.0, revision
`86b9b55fe8c61ec1c27c5b6383f545c6df1d6ceb`, `Sources/Who`.
The original source-available license and copyright apply; see LICENSE.md.
Native cross-language bindings are omitted. The remaining twelve Swift files are
built as CodaWho against the unchanged DesertAnt and AudioIO products and numerics.

Coda adds an optional 1–4 speaker count to the audio and sample APIs. With no
count, the original segmentation and threshold clustering paths are unchanged.
With a count, voice embeddings are used even for one-piece recordings and
average-linkage merges to the requested number of available voice clusters.
Lanes without enough solo speech fold into the nearest voiced lane, matching the
upstream temporal fallback instead of creating extra speakers. No usable voice
embeddings produce an actionable error rather than ignoring the requested count.
One speaker combines detected speech lanes without adding speech in silence.
Counts do not manufacture silent participants when fewer voices are available.
No model weights, download behavior, or licensing/reporting code are changed.
