# Remove individual recent emoji

```sh
python3 -I tools/tests/remove-recent-emoji/run.py \
  --signal-kit /path/to/telegram-ios/submodules/SSignalKit \
  --compatibility-ref upstream/pr117
```

The compatibility ref used during development is `592446a5f9833ec24c84844b571d9caf6f06dec9` from the existing recent-emoji deduplication PR #117. Fetch that ref separately if needed, or pass its available local ref. This feature does not import that PR into its branch.

The runner creates a temporary Swift package and removes it on exit. It executes the complete production `RecentUsedEmoji` model and `Strings.swift` with real Cocoa/CoreText and SwiftSignalKit. It also extracts the ordinary emoji menu, the custom-emoji removal branch, the segment renderer and both coordinate lookup helpers.

On 2026-10-29, all 21 cases passed both against this feature and against a temporary composition with PR #117's model, string helpers and Recent rendering policy. Checks cover:

- Removing all variation-selector variants without rewriting or reordering surviving entries.
- Separate skin tones, legacy default-tone rendering, ZWJ sequences, flags and keycaps.
- Original source identity retained through display normalization, including reused visual layers.
- Exact custom-emoji namespace/file identity and immediate equality-driven updates.
- Custom Recent remains reachable when the last ordinary recent emoji is removed; other picker modes are unchanged.
- Idempotent removal, empty lists, JSON round trips and transaction-time reads of the latest preferences.
- Menu availability only with the explicit Recent callback; no removal for search/category rows, no accidental send, and menu identity unaffected by later pointer movement.

A bounded send/reload check reproduces the reported duplicate growth for both ✅ and 😁: four cycles produce counts `[1, 2, 3, 4]` with the current base's persistence logic and `[1, 1, 1, 1]` with PR #117. The removal operation clears the selected symbol's variants in both versions. This does not claim exhaustive verification of the separate PR.

## Boundaries

Postbox/PreferencesEntry, MediaId, row/layer/menu state and the font factory are adapters. JSON encoding/decoding is checked separately from the lazy in-memory transactional adapter. Custom-emoji menu coverage executes only its removal branch. Wiring checks inspect source rather than executing the full controller. These tests do not claim real AppKit mouse dispatch, live account database mutation, server behavior or complete application validation.

The normal context menu should be checked in the running app: Recent ordinary/custom emoji offers Remove From Recent; search, categories, installed packs and unrelated picker modes do not. Removing an item does not uninstall its pack, delete messages or prevent it being added to Recent on its next use.
