<div align="center">

# 🪞 herdr-clone-layout

**Every new workspace opens looking like the one you just left.**

No config file, no templates to maintain — the layout you're already
working in *is* the template.

[Install](#install) · [How it works](#how-it-works) ·
[Manual duplicate](#manual-duplicate) · [Why geometry only](#why-geometry-only) ·
[Reference](#reference)

</div>

herdr-clone-layout is a [herdr](https://herdr.dev) plugin. Create a workspace or
a worktree — from the CLI *or* the herdr TUI — and it opens with the **same tabs**
(labels and order) and the **same pane splits** (directions and ratios) as the
workspace you were just in.

- **Zero configuration.** Nothing to declare. Rearrange your panes today and
  tomorrow's worktrees follow along automatically.
- **Worktrees just work; workspaces get a choice.** A new worktree clones
  silently — its directory was settled when you created it. A new workspace
  opens a popup first, so you can send all its panes somewhere else.
- **CLI and TUI both covered.** The two creation paths emit different events;
  the plugin subscribes to all of them and dedupes, so a layout is built exactly
  once.
- **New workspaces only.** It builds into a brand-new workspace and never
  touches one you've already arranged — including one you've since closed the
  tabs in. Emptying a workspace out doesn't make it a clone target again.
- **Never steals focus.** A workspace created in the background is built in the
  background.
- **Just the herdr CLI underneath.** The result is ordinary tabs and panes —
  nothing proprietary to unwind.

## Install

Requires **herdr ≥ 0.7.0** and **[jq](https://jqlang.github.io/jq/)** on your `PATH`.

```sh
herdr plugin install danilolucasmd/herdr-clone-layout
```

<details>
<summary>Local development / pinning / non-interactive</summary>

```sh
# live edits from a clone
git clone https://github.com/danilolucasmd/herdr-clone-layout.git
herdr plugin link ./herdr-clone-layout

# pin a release with --ref, or install non-interactively with --yes
herdr plugin install danilolucasmd/herdr-clone-layout --ref <tag> --yes
```

`herdr plugin link` talks to a **running** herdr server, so launch herdr first.

</details>

That's the whole setup. Arrange a workspace the way you like it, then create a
worktree — the new one comes up already arranged.

## The workspace dialog

A new **worktree** clones straight away: you chose its directory when you created
it, so there's nothing left to ask.

A new **workspace** has no directory of its own, so it gets a popup first:

```
  new workspace

  > clone current layout
      the same tabs and splits as ~/Code/herdr-clone-layout

    panes open in
    ~/Code/herdr-clone-layout

  ^ v switch    enter confirm    esc cancel
```

- **Enter** — clone the layout, exactly as the plugin has always done.
- **Down**, then edit the path and **Enter** — the same tabs and splits, but
  every pane spawned in that directory instead. `~` works, the path must exist,
  and it's pre-filled with the directory of the workspace you came from, so
  confirming it unchanged lands you in the same place as the first option.
- **Esc** — leave the new workspace bare.

Typing jumps straight to the path field. **Ctrl-U** clears it, **Ctrl-W** deletes
back a path segment.

The popup only appears when you're actually looking at the new workspace. A
workspace created in the background — a scripted `herdr workspace create`, or the
`apply` action below — clones without asking, since there's nobody there to
answer.

## How it works

herdr creates workspaces two different ways, and they emit different events:

| You create a workspace via… | herdr emits to plugins |
| --- | --- |
| `herdr worktree create` / `herdr workspace create` (CLI) | `worktree.created` **and** `workspace.created` |
| the **TUI** "new worktree / workspace" (in-app) | **only** `workspace.focused` (it focuses the new one on creation) |

So the hook listens for all three. On any of them it:

1. Reads the live session snapshot (`herdr api snapshot`).
2. Bails unless the workspace is **new**. Two things have to hold: it must be
   *fresh* — exactly 1 tab and 1 pane — and it must never have held a layout
   before. Freshness alone isn't enough, because a workspace you've closed all
   your tabs in looks exactly like one herdr just made; without the second test,
   closing tabs down to the last one would put the whole layout straight back.
   So every workspace seen holding more than one tab or pane is remembered, and
   is never cloned into again. Ids of closed workspaces are forgotten, so a
   recycled workspace id counts as new.
3. Picks the **source**: the currently-focused workspace, or — when the new one
   already has focus (the TUI path) — the most recent *other* workspace from a
   short focus history. Only a workspace with more than one tab or pane
   qualifies.
4. Takes an **atomic claim** on the new workspace id, so overlapping events
   can't clone it twice.
5. Decides whether to **ask**. A linked git worktree, or a workspace that isn't
   focused, is cloned right away. Anything else opens the popup, which takes
   over the claim and does the cloning itself once you answer — a hook that sat
   waiting for a keypress would be blocking herdr the whole time.
6. Reconstructs the source's split tree from the snapshot's pane/split
   rectangles, linearizes it into ordered split steps, and replays them with
   `herdr tab create` / `herdr pane split`.

```
 new workspace (CLI or TUI) ──► clone-layout event hook
        ▼
   snapshot ─► new? ─► pick source ─► claim ─► ask? ─► plan.jq ─► replay
        │                                       │                   │
        │                            worktree, or not focused ──────┤
        └── not new / no source / already claimed ─► no-op          ▼
                                            tab 0  → reuse + rename the root tab
                                            tab N  → herdr tab create --label
                                            step   → herdr pane split --direction --ratio
```

With a directory chosen, tab 0 is created fresh like the rest and the
workspace's original root tab is closed — that pane is already running in the
workspace's own directory and can't be respawned somewhere else.

The geometry analysis lives in [`lib/plan.jq`](./lib/plan.jq): herdr reports each
pane and split as a rectangle, and the plan rebuilds the binary split tree from
those rectangles, then flattens it into steps like *"split handle 0 to the right
at 0.65; the pane that creates becomes handle 1"*. It's the part with real logic,
so it has [tests](#development).

## Manual duplicate

`prefix+shift+d` creates a new workspace and duplicates the current one's layout
into it. Same thing from the CLI:

```sh
herdr plugin action invoke apply --plugin herdr-clone-layout
```

Rebind or drop the key by editing `[[keys.command]]` in
[`herdr-plugin.toml`](./herdr-plugin.toml).

## Why geometry only

Panes open as **bare shells**. Tab labels and split geometry are cloned; the
commands that were running are not re-run.

That's deliberate. The panes in a working layout are usually a coding agent, an
editor, a dev server, a log tail — relaunching those in a brand-new worktree is
at best redundant and at worst destructive (a second dev server fighting for the
port, an agent starting work you didn't ask for). Cloning the *shape* gives you
the working view you expect and lets you start what you actually want in it.

If you want commands re-run from a declarative config, that's a different tool —
see [herdr-plugin-workspace-manager](https://github.com/razajamil/herdr-plugin-workspace-manager).

---

# Reference

## What gets cloned

| Cloned | Not cloned |
| --- | --- |
| Tab labels and their order | Pane commands / running processes |
| Pane split directions (`right` / `down`) | Pane titles |
| Pane split ratios | Working directories (each pane starts in the new workspace's own cwd) |
| | Which pane/tab was focused (the first tab is shown) |

## Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `HERDR_CLONE_LAYOUT_LOG` | `1` | Set to `0` to disable the activity log. |
| `HERDR_PLUGIN_STATE_DIR` | set by herdr | Where the focus history, populated-workspace history, claims, and log live. Falls back to `$XDG_STATE_HOME/herdr-clone-layout`. |
| `HERDR_PLUGIN_ROOT` | set by herdr | Plugin checkout root; falls back to the script's own directory. |
| `HERDR_BIN_PATH` | `herdr` | The herdr binary to drive. |

## Troubleshooting

The hook runs headless, so it logs what it decided:

```sh
tail -f ~/.local/state/herdr/plugins/herdr-clone-layout/clone-layout.log
```

Lines look like `clone w1 -> w7 (4 tabs)`, or a reason it did nothing
(`w7 not fresh, skip`, `w7 has held a layout before, skip`, `no source to clone
for w7`). The dialog logs its own decision too — `prompt for w7`, then
`dialog: clone w1 -> w7 in /some/dir` or `dialog: cancelled for w7`. herdr's own
plugin log is also worth a look:

```sh
herdr plugin log list --plugin herdr-clone-layout
```

The log is trimmed to its last 500 lines on each run.

## Notes & limitations

- **Only genuinely new workspaces are populated.** A workspace that already has
  more than one tab or pane is left alone — including after a restart that
  restores your session — and so is one that used to, however few tabs you've
  left in it since.
- **A zoomed tab clones as a single pane.** herdr reports the zoomed pane as
  filling the tab, so that's the geometry the plugin sees. Unzoom before cloning
  if you want the full split arrangement.
- **Splits are rebuilt, not pixel-copied.** Ratios come back exactly as reported,
  but herdr rounds to whole cells, so a rebuilt pane can land a cell off in a
  differently-sized window.
- **Additive.** The plugin builds panes and never tears them down. The one
  exception is the workspace's original root tab, closed when you pick a
  directory, because its pane can't be moved there.
- **The dialog edits at the end of the line.** Backspace, Ctrl-W by path
  segment, and Ctrl-U to start over; there's no cursor to move mid-path.
- **The panes are bare shells.** Choosing a directory changes where they start,
  not what runs in them — no commands are replayed, in either mode.

## Trust & security

A herdr plugin is ordinary code that runs on your machine with your environment
and can drive the full herdr CLI. This one runs no commands of yours — it only
calls `herdr api snapshot`, `herdr tab create/rename/focus`, `herdr pane split`,
and `herdr workspace create/focus`. It's ~200 lines of POSIX sh plus a jq
program; read them.

## Development

```sh
./tests/run.sh          # every fixture
./tests/run.sh grid     # fixtures matching "grid"
```

The tests cover `lib/plan.jq` — the snapshot-geometry analysis — against
fixtures in [`tests/fixtures/`](./tests/fixtures), each carrying a snapshot and
the plan it should produce. They're pure jq: no herdr server, no terminal,
nothing to clean up, so they run in CI.

Adding a case is one JSON file with `name`, `ws`, `snapshot`, and `expected`.
To capture a real layout to build one from:

```sh
herdr api snapshot | jq '.result.snapshot | {tabs, layouts}'
```

The repo carries the `herdr-plugin` GitHub topic, which is what lists it in the
herdr marketplace.

## License

[MIT](./LICENSE) © Danilo de Lucas
