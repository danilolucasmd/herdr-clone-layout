# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.2]

### Fixed

- **The layout was sometimes cloned before you answered the popup.** Claims for
  workspaces that no longer exist are swept on every pass, but "no longer exists"
  was decided from the snapshot the sweeping hook happened to be carrying. Hooks
  run concurrently and each reads its own, so a workspace created a moment ago is
  missing from the snapshot a hook that started first is holding — and it dropped
  a claim that was very much alive. That handed the same new workspace to a
  second hook, whose `plugin pane open` failed because the first one's popup was
  already up, so it fell through to cloning directly: the layout appeared behind
  the popup before you had answered it, and cancelling could no longer undo it
  ("is not empty any more, keeping it"). A claim is now only swept once it is old
  enough that no build could still be behind it, so a live one is never taken
  away.

## [0.5.1]

### Fixed

- Shellcheck failure in CI. `tests/apps.sh` piped `cat` into `tr`, which is
  SC2002 — a style warning that shellcheck 0.9.0 (what the runner installs)
  reports and newer versions no longer do by default, so it passed locally and
  failed on push. The file is read with a redirect now.

## [0.5.0]

### Added

- **New worktrees get the popup too.** Creating one with `prefix+shift+g` now
  asks the same question a new workspace does, titled `new worktree`, with the
  directory row already on the worktree's checkout — so confirming it unchanged
  does exactly what a worktree did when it was never asked. The point is the two
  checkboxes: a worktree's directory was settled when you created it, but what
  the clone copies wasn't, and the popup is the only place to change it. A
  worktree created in the background still clones silently on the remembered
  answers, since herdr doesn't focus one and there's nobody to answer.

### Changed

- Cancelling never removes a worktree. It's a git checkout on disk with a branch
  of its own, so unlike an empty new workspace it stays, with bare shells in it.
  Anything that survives a cancel is now recorded as settled, so focusing it
  later doesn't ask the same question again.

### Fixed

- Stop the activity log from being truncated by its own trimming. Three hooks
  fire at once for a new worktree and all trimmed through one shared temp path,
  so their writes interleaved and the winner of the race moved a truncated log
  into place — with `mv: cannot stat` from the losers in herdr's plugin log.
- Decide whether to ask about a new worktree only after its focus has settled.
  Its three events arrive within a couple of milliseconds of each other, so
  whichever won the claim could read a snapshot from before the focus landed and
  clone silently instead of asking.

## [0.4.1]

### Changed

- **Esc closes the new workspace** instead of leaving it behind empty: cancelling
  the popup now undoes the whole thing, and herdr moves you to another workspace
  as it goes. Ctrl-D does the same. It only closes the workspace it was asked
  about, and only while that workspace still has the one tab and one pane it was
  asked about and nothing running in it — the popup doesn't hold the keyboard,
  so anything you put in there in the meantime keeps it alive, with the reason
  logged.

### Fixed

- Drop claims left behind by a workspace that no longer exists. A popup whose
  workspace is closed from somewhere else is orphaned rather than signalled, so
  its trap never runs and its claim stayed forever; since herdr recycles short
  workspace ids, that claim would silently stop the next workspace given the same
  id from ever being cloned into.

## [0.4.0]

### Added

- A **second checkbox** below the first — `[x] reopen the apps each pane was
  running` — and with it the end of geometry-only cloning. Ticked, every pane in
  the clone reopens the command the pane it was cloned from was running: herdr
  cannot start a pane *on* a command, so the pane is created as a shell and the
  command is typed into it with `herdr pane run`. The command is the pane's real
  one, read from `herdr pane process-info` — the foreground process group leader,
  not the children it forked — and a pane at its shell prompt stays a shell.
  Source and clone have the same geometry, so their panes pair off by position; a
  tab that comes out with a different number of panes reopens nothing rather than
  type a command into the wrong pane. Remembered like the first box, and it
  applies to worktrees and `prefix+shift+d` too.
- **This box starts ticked**, so out of the box a clone now re-runs your
  commands: a second dev server will fight the first for its port, and an agent
  pane starts a fresh agent. Untick it for the old bare-shell behaviour.
- `tests/apps.sh`, covering the command reading and the pane pairing against a
  stub herdr that answers `pane process-info` from fixtures and records every
  `pane run`.

## [0.3.0]

### Added

- A **checkbox** on the popup's last row — `[x] clone layouts into new
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

## [0.2.0]

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

[0.5.2]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.5.2
[0.5.1]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.5.1
[0.5.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.5.0
[0.4.1]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.4.1
[0.4.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.4.0
[0.3.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.3.0
[0.2.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.2.0
[0.1.0]: https://github.com/danilolucasmd/herdr-clone-layout/releases/tag/v0.1.0
