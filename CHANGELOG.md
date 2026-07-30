# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A popup when you create a plain workspace, offering either the layout as-is or
  the same layout with every pane opened in a directory you type. It starts on
  "clone current layout", and the directory field is pre-filled with the
  directory of the workspace you came from, so Enter either way gives you what
  the plugin did before. Esc leaves the new workspace bare.
- Worktrees are unaffected: a new worktree already had its directory chosen when
  it was created, so it still clones straight away with no dialog. Workspaces
  built in the background (scripted `herdr workspace create`) also clone without
  asking, since there's nobody at the keyboard to answer.
- A **checkbox** on that popup's last row — `[x] clone layouts into new
  workspaces` — turning the plugin off. The two rows above it still decide where
  the panes open; the box decides whether anything is cloned at all. Go down to
  it, Space to untick, back up to either directory answer, and Enter now leaves
  the new workspace exactly as herdr opened it. The answer is remembered in the
  state dir (`clone-enabled`), so it outlives the popup and a restart: while it
  is unticked nothing is cloned into any new workspace or worktree, including the
  paths that never showed a popup. The popup still opens for a plain new
  workspace, since that is where the box is; Space and Enter put everything back.
  `prefix+shift+d` is unaffected either way — invoking it is itself the answer.
  Only Enter writes the answer down, so toggling the box and pressing Esc cancels
  that too.
- `tests/keys.sh`, driving the popup through its own key handling — the keys
  arrive on stdin and a stub herdr stands in for the session, so it needs no
  terminal and runs in CI alongside the rest.

### Fixed

- Clone tabs in tab-bar display order instead of `.number` order. A tab keeps
  its `.number` when you drag it to a new position, so manually reordering the
  tabs in a workspace had no effect on the clone — the new workspace came out in
  the order the tabs were originally created in.
- Stop re-cloning a workspace whose tabs you have just closed. "1 tab and 1
  pane" was the test for a brand-new workspace, but a workspace you have emptied
  out looks identical, so closing tabs down to the last one put the whole layout
  straight back. Workspaces that have held a layout are now remembered and never
  cloned into again.
- `apply` no longer risks stacking a second copy of the layout on top of the one
  the `workspace.created` / `workspace.focused` hooks build for the same new
  workspace.
- A failed or empty snapshot is no longer read as "every workspace was closed".

## [0.1.0] — Unreleased

First public release.

### Added

- Clone the tab layout (labels + order) and pane-split geometry (directions +
  ratios) of the previously-focused workspace into every newly created
  workspace or worktree.
- Covers both creation paths: the CLI (`worktree.created` / `workspace.created`)
  and the herdr TUI (`workspace.focused` only), deduped with an atomic claim so
  a layout is built exactly once.
- `apply` action and a `prefix+shift+d` keybinding to duplicate the current
  workspace's layout into a new workspace on demand.
- Activity log with a 500-line cap, silenced with `HERDR_CLONE_LAYOUT_LOG=0`.
- Offline fixture tests for the snapshot-geometry analysis (`./tests/run.sh`).

[0.1.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.1.0
