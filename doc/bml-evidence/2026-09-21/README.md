# BML migration evidence — 2026-09-21 checkpoint

Captured headlessly in the isolated development container using seeded accounts.
These are development fixtures, not production data. The baseline is d9ea4bea6;
completed implementation and characterization commits end at 65e502439.

- `access-before` / `access-after`: BML and TT access-filter states, including mobile.
- `image-preview-before` / `image-preview-after`: preview iframe migration.
- `image-dialog-before` / `image-dialog-after`: parent dialog migration.
- `customize-before.png` and `customize-baseline`: still-BML customization states;
  `results.json` records browser exceptions and widget IDs (not full acceptance).

See [the progress log](../../BML-PROGRESS.md) for tests, limitations and observed
baseline defects. The failed intermediate access-filter screenshot is excluded.
