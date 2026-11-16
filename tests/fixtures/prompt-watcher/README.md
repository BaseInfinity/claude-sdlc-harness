# prompt-watcher fixtures

Buffers replayed, one per pane id in `sessions.txt`, by a stub `it2api` in `tests/test-conduct.sh`.

| File | Source |
|---|---|
| `AAAAAAAA-…01.txt` | Real AskUserQuestion pane, captured 2026-11-15, content replaced, structure kept |
| `BBBBBBBB-…02.txt` | Real idle Codex pane, captured 2026-11-15, content replaced |
| `CCCCCCCC-…03.txt` | Real pane whose transcript quotes the dialog strings inline |
| `DDDDDDDD-…04.txt` | Built from strings in Claude Code 2.1.321's binary; layout not captured live |
| `EEEEEEEE-…05.txt` | Built from strings in Codex 0.167.0's binary; layout not captured live |
| `11111111`, `22222222`, `33333333`, `44444444`, `55555555` | Prose quoting one half of a dialog each, so every line anchor is load-bearing |
| `FFFFFFFF-…06.txt` | `DDDDDDDD-…04.txt`'s dialog, answered and scrolled up under later output |
