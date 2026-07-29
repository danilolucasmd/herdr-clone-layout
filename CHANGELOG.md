# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Clone tabs in tab-bar display order instead of `.number` order. A tab keeps
  its `.number` when you drag it to a new position, so manually reordering the
  tabs in a workspace had no effect on the clone — the new workspace came out in
  the order the tabs were originally created in.

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
