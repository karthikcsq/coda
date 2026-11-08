# Main workflow and worktree consolidation

The dev/prod workflow was already on main at 8041c9a. Merged the correction
editor branch (68d4f8b and 646ee72) into main with merge commit e373405.
Correction defaults are Control–Option–C for Production and Shift–Control–Option–C
for Development. The editor window identifies Development.

Verification: CODA_RENDER_DOCS=1 ./scripts/test.sh passed 226 tests
(5 supporting, 90 UI, 131 core). After channel integration, the filtered
CorrectionEditor run passed 6 tests including the native render suite.
python3 -m unittest discover -s scripts/tests passed all 7 workflow tests.
Native correction renders refreshed for Development; original text remains
visible above the editable correction. No live hotkey or audio test performed.

Removed four clean secondary checkouts: speed-dictation-capture,
correct-last-dictation, personal-dictation-finetuning, and coda-soundalike.
Deleted the three merged t3 feature branches. Retained sound-alike-corrections
because it has older distinct commits, with feature equivalents already on main;
also retained the preexisting backup/before-scrub ref. No source was discarded.
Ignored contents were build outputs, dependency checkouts and Python caches.
Production and Development processes were left running without replacement.
No push, GitHub Release, or app installation was performed.
