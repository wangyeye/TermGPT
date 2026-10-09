# TermGPT local SwiftTerm changes

The vendored SwiftTerm code retains its upstream MIT license. The macOS terminal selection implementation is adjusted to:

- Run a weakly captured selection scroll timer in common run-loop modes during drag tracking.
- Scroll downward at the lower viewport edge and upward at the upper edge, with bounded velocity.
- Keep the mouse-down selection anchor and extend the selection as new rows become visible.
- Stop on mouse release, re-entry into the middle of the viewport, view detachment and deallocation.
- Preserve mouse reporting and alternate-screen behavior for terminal applications.

Regression coverage lives in `Tests/TermGPTTests/TerminalSelectionScrollTests.swift`; run `scripts/test-isolated.sh` after checking the documented macOS build environment.
# Terminal search

`Mac/TerminalSearch.swift` adds buffer search and reveal APIs. UTF-16 regex offsets map back to terminal cells, preserving wide-character selection. Search is bounded to 10,000 matches and physical rows; reveal clamps scroll position to the last valid viewport.
