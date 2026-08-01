<div align="center">

# 🪞 herdr-clone-layout

**Every new workspace opens looking like the one you just left.**

No config file, no templates to maintain — the layout you're already
working in *is* the template.

[Install](#install) · [How it works](#how-it-works) ·
[Manual duplicate](#manual-duplicate) ·
[Why geometry, and apps only if you ask](#why-geometry-and-apps-only-if-you-ask) ·
[Reference](#reference)

</div>

herdr-clone-layout is a [herdr](https://herdr.dev) plugin. Create a workspace or
a worktree — from the CLI *or* the herdr TUI — and it opens with the **same tabs**
(labels and order) and the **same pane splits** (directions and ratios) as the
workspace you were just in.

- **Zero configuration.** Nothing to declare. Rearrange your panes today and
  tomorrow's worktrees follow along automatically.
- **Workspaces and worktrees both get a choice.** Whichever you create, if you're
  looking at it you get a popup first — where the panes open, and what the clone
  copies. One built in the background clones silently, since nobody's there to
  answer.
- **The apps come with it.** Each pane reopens whatever it was running — your
  editor, your dev server, your agent. Untick the second box to get bare shells
  instead.
- **A checkbox turns it off, and it stays off.** Untick *clone layouts into new
  workspaces* in the popup and nothing is cloned — into that workspace, or into
  any new workspace or worktree after it, until you tick it again.
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

  <img width="1194" height="702" alt="07-31-2026-12:32:58" src="https://github.com/user-attachments/assets/4aca4a1f-6e62-4107-b3f4-523e094294ae" />

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

## The dialog

Create a workspace (`prefix+shift+n`) or a worktree (`prefix+shift+g`) and, once
you're looking at it, it opens with a popup:

```
  new workspace

  > clone current layout
      the same tabs and splits as ~/Code/herdr-clone-layout

    panes open in
    ~/Code/herdr-clone-layout

    options
    [x] clone layouts into new workspaces
    [x] reopen the apps each pane was running

  ^ v switch    space toggle    enter confirm    esc cancel
```

Two answers and two switches. The **first two rows** decide *where the panes
open* and are what **Enter** confirms; the **two checkboxes** decide *what a
clone is*, and stay ticked the way you leave them.

- **Enter** — clone the layout, exactly as the plugin has always done.
- **Down**, then edit the path and **Enter** — the same tabs and splits, but
  every pane spawned in that directory instead. `~` works, the path must exist,
  and it's pre-filled with the directory of the workspace you came from, so
  confirming it unchanged lands you in the same place as the first option.
- **Space**, on either box — tick or untick it. See below.
- **Esc** — you didn't want this one after all: the new workspace is **closed**,
  not left behind empty. Ctrl-D does the same. See
  [Cancelling](#cancelling).

Typing jumps straight to the path field. **Ctrl-U** clears it, **Ctrl-W** deletes
back a path segment. Space belongs to the row it's standing on: it toggles a box,
types a space in the path field, and does nothing on the top row — with two boxes
there's no one box it could mean.

### A worktree's popup

It's the same popup, titled `new worktree`, minus the directory row:

```
  new worktree

  > clone current layout
      the same tabs and splits as ~/Code/herdr-clone-layout

    options
    [x] clone layouts into new workspaces
    [x] reopen the apps each pane was running

  ^ v switch    enter confirm    esc cancel
```

A worktree is a checkout of its own, made where it was made, and the layout worth
having in it is the one you came from — with its panes in the checkout, like the
branch you just left. Opening them somewhere else is a question about a new
workspace, not about a worktree, so it isn't asked here: **Enter** clones, and the
two boxes are all there is left to decide. Typing a path does nothing, since
there's no field for it to go in.

The other difference is [cancelling](#cancelling): a worktree is never thrown
away.

### Reopening the apps

With the second box ticked, every pane in the clone reopens the command the pane
it was cloned from was running:

```
  source workspace              new workspace
  ┌───────────┬──────────┐      ┌───────────┬──────────┐
  │ nvim .    │ (prompt) │  ──► │ nvim .    │ (prompt) │
  ├───────────┴──────────┤      ├───────────┴──────────┤
  │ pnpm run dev         │      │ pnpm run dev         │
  └──────────────────────┘      └──────────────────────┘
```

herdr can't start a pane *on* a command — `pane split` and `tab create` only take
a directory — so each pane is created as a shell and the command is typed into it
with `herdr pane run`. What gets typed is the pane's real command line, read from
`herdr pane process-info`: the leader of the foreground process group, which is
the command you started rather than the children it went on to fork. A pane
sitting at its shell prompt contributes nothing and is left as a shell.

Source and clone have the same geometry, so their panes pair off by position —
top-to-bottom, then left-to-right. If a tab somehow comes out with a different
number of panes, that tab reopens nothing rather than risk typing a command into
the wrong pane.

**This runs your commands again.** A second dev server will fight the first for
its port, and an agent pane starts a fresh agent. Untick the box for bare shells
— see [Why geometry, and apps only if you ask](#why-geometry-and-apps-only-if-you-ask).

### Turning it off

Go **down** to the first checkbox, **Space** to untick it, then back **up** to
either directory answer and **Enter**:

```
  new workspace

  > clone current layout
      nothing is cloned. enter leaves this workspace empty

    panes open in
    ~/Code/herdr-clone-layout

    options
    [ ] clone layouts into new workspaces
    [x] reopen the apps each pane was running

  ^ v switch    enter confirm    esc cancel
```

The box wins over whichever row you confirm from: **Enter** leaves the new
workspace exactly as herdr opened it — and so does every workspace *and worktree*
created afterwards, silently, without a popup for the ones that would have got
one. It's remembered in the plugin's state dir (`clone-enabled`), so it survives
restarts. (Confirming on a checkbox row itself works too, and clones as-is when
the box is ticked.)

The popup is the one thing an unticked box doesn't suppress: it's where the box
lives, so a plain new workspace still opens it, unticked, and **Space** then
**Enter** puts everything back. `prefix+shift+d`
([manual duplicate](#manual-duplicate)) also keeps working while the box is
unticked — invoking it *is* the answer to the question the box asks. (It does
respect the *apps* box, which is about what a clone copies rather than whether to
make one.)

Only **Enter** writes the answers down, both boxes at once. Toggling a box and
then pressing **Esc** cancels that too.

### Cancelling

**Esc** (or **Ctrl-D**) means you didn't want the new workspace after all, so the
plugin closes it for you instead of leaving an empty workspace lying around.
herdr moves you to another workspace as it goes.

**A worktree is never closed this way.** It's a git checkout on disk with a branch
of its own; a dismissed popup is nowhere near reason enough to remove one, so it
stays with bare shells in it. If you do want it gone, that's herdr's job —
`remove_worktree` (unbound by default) or `herdr worktree remove --workspace <id>`.

Otherwise it only closes the workspace it was asked about, and only while that
workspace is still the empty thing it was asked about. The popup doesn't hold the
keyboard hostage — you can switch away, do something in the new workspace and
come back — so before closing it checks that the workspace still has one tab and
one pane, and that the pane isn't running anything. If any of that has changed
it's kept, and the log says why:

```
dialog: cancelled for w7
dialog: w7 is running nvim ., keeping it
```

Anything that survives being cancelled is recorded as settled, so focusing it
later doesn't ask the same question again — it's still one tab and one pane, which
is all "new" means to the hook.

A popup that ends any other way — killed, or its herdr going away — closes
nothing either. Only an explicit cancel does.

The popup only appears when you're actually looking at the new workspace or
worktree. One created in the background — a scripted `herdr workspace create` or
`herdr worktree create`, or the `apply` action below — clones without asking,
since there's nobody there to answer.

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
5. Decides whether to **ask**. Anything you aren't looking at is cloned right
   away — or skipped entirely, if the popup's first checkbox was left unticked:
   those paths show nothing, so the remembered answer is the only answer there
   is. Whatever *is* on screen opens the popup, which takes over the claim and
   does the cloning itself once you answer — a hook that sat waiting for a
   keypress would be blocking herdr the whole time. A new worktree fires all
   three events within a couple of milliseconds, so whichever handler wins the
   claim gives the focus a moment to settle and re-reads the snapshot before
   deciding; otherwise the popup would appear or not depending on which event
   got there first.
6. Reconstructs the source's split tree from the snapshot's pane/split
   rectangles, linearizes it into ordered split steps, and replays them with
   `herdr tab create` / `herdr pane split`.
7. With the apps box ticked, reads each source tab's pane commands from
   `herdr pane process-info` before rebuilding it, then types them into the
   rebuilt panes with `herdr pane run`, pairing the two tabs' panes by position.

```
 new workspace (CLI or TUI) ──► clone-layout event hook
        ▼
   snapshot ─► new? ─► pick source ─► claim ─► ask? ─► plan.jq ─► replay
        │                                       │                   │
        │                                not focused ──────────────►┤
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

## Why geometry, and apps only if you ask

Tab labels and split geometry are always cloned. Whether the commands come with
them is the second checkbox's call, and it's worth knowing what you're choosing
between.

The panes in a working layout are usually a coding agent, an editor, a dev
server, a log tail. Relaunching those in a brand-new worktree is sometimes
exactly what you want — the same four tools, pointed at the new branch, without
setting them up by hand. It's also sometimes redundant or destructive: a second
dev server fights the first for its port, a log tail follows a file the new
worktree doesn't have yet, and an agent pane starts a *fresh agent* that will
happily begin work you didn't ask for (and spend tokens doing it).

The box is ticked out of the box, so a clone is a working copy of what you had.
Untick it and panes open as bare shells — the layout without the launch — which
is the safer default if your panes tend to hold agents or servers.

Either way, nothing is *re*-attached: a reopened command is a new process, not
the old one moved. And nothing is replayed from a declarative config — if that's
what you want, see
[herdr-plugin-workspace-manager](https://github.com/razajamil/herdr-plugin-workspace-manager).

---

# Reference

## What gets cloned

| Cloned | Not cloned |
| --- | --- |
| Tab labels and their order | Pane titles |
| Pane split directions (`right` / `down`) | Working directories (each pane starts in the new workspace's own cwd, even the ones whose command was running somewhere else) |
| Pane split ratios | Which pane/tab was focused (the first tab is shown) |
| The command each pane was running — *with the second box ticked* | Scrollback, environment, and anything else a process was holding: a reopened command is a new process |

## Environment variables

| Var | Default | Purpose |
| --- | --- | --- |
| `HERDR_CLONE_LAYOUT_LOG` | `1` | Set to `0` to disable the activity log. |
| `HERDR_PLUGIN_STATE_DIR` | set by herdr | Where the focus history, populated-workspace history, claims, the two checkboxes (`clone-enabled`, `reopen-apps`), and the log live. Falls back to `$XDG_STATE_HOME/herdr-clone-layout`. |
| `HERDR_PLUGIN_ROOT` | set by herdr | Plugin checkout root; falls back to the script's own directory. |
| `HERDR_BIN_PATH` | `herdr` | The herdr binary to drive. |

## Troubleshooting

The hook runs headless, so it logs what it decided:

```sh
tail -f ~/.local/state/herdr/plugins/herdr-clone-layout/clone-layout.log
```

Lines look like `clone w1 -> w7 (4 tabs)`, or a reason it did nothing
(`w7 not fresh, skip`, `w7 has held a layout before, skip`, `no source to clone
for w7`, `clone layout is off, leaving w7 alone`). Every command it reopens is
logged as it is typed — `reopen in w9:p3: pnpm run dev` — or `not reopening in
w9:t2: 2 panes for 3 commands` when a tab came out the wrong shape. The dialog
logs its own decision too — `prompt for w7`, then `dialog: clone w1 -> w7 in
/some/dir`, `dialog: clone off, leaving w7 as it is`, or `dialog: cancelled for
w7` followed by either `dialog: closing w7` or the reason it was kept. herdr's
own plugin log is also worth a look:

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
- **"No" is remembered for that workspace too.** Confirming with the first box
  unticked keeps the workspace but settles it, so switching back to it later
  doesn't reopen the popup. Esc settles it the same way whenever the workspace
  survives — a worktree, or one that isn't empty any more.
- **A worktree's popup only appears if herdr put you in it.** The in-app
  `prefix+shift+g` focuses the new worktree, so you get asked. A scripted
  `herdr worktree create` doesn't focus it, so it clones silently on the
  remembered answers, exactly as it did before.
- **A reopened command runs where the pane opens, not where it ran.** Panes start
  in the new workspace's directory (or the one you typed), so a command that was
  running in a subdirectory — `pnpm run dev` in `apps/web` — comes back at the
  top of the new one. The pane's directory isn't cloned; only the command is.
- **The command is the process's, not your keystrokes.** `pnpm run dev` reads
  back from the process table as `node /usr/bin/pnpm run dev`, which re-runs the
  same thing but doesn't look like what you typed. Shell built-ins, aliases and
  functions leave no process behind at all, so a pane running one reopens as a
  bare shell.
- **The commands are read once,** just before each tab is rebuilt — a command
  started in the source workspace after that isn't seen.

## Trust & security

A herdr plugin is ordinary code that runs on your machine with your environment
and can drive the full herdr CLI. This one calls `herdr api snapshot`, `herdr tab
create/rename/focus/close`, `herdr pane split/process-info/run`, `herdr workspace
create/focus/close`, and `herdr plugin pane open` for the popup. The one thing it
closes is a workspace you just cancelled out of, and only while it is still
empty. It's ~800 lines of
POSIX sh plus a jq program; read them.

**With the apps box ticked it does run commands of yours** — the ones your own
panes were already running, read from `herdr pane process-info` and typed back
into the new panes with `herdr pane run`. It never invents a command, and it
never runs anything when the box is unticked. Every command it types is in the
log.

## Development

```sh
./tests/run.sh          # every fixture
./tests/run.sh grid     # fixtures matching "grid"
./tests/known.sh        # the "new workspace or merely emptied?" guard
./tests/prompt.sh       # who gets asked, how paths are read, the remembered box
./tests/keys.sh         # the popup driven by its own keys
./tests/apps.sh         # reading pane commands back, and where they get typed
```

`run.sh` covers `lib/plan.jq` — the snapshot-geometry analysis — against fixtures
in [`tests/fixtures/`](./tests/fixtures), each carrying a snapshot and the plan it
should produce. `keys.sh` runs the real popup with its keys on stdin, and it and
`apps.sh` use a stub herdr in place of a session — one that answers
`pane process-info` from fixtures and records every `pane run`. All five need
nothing but `jq`: no herdr server, no terminal, nothing to clean up, so they run
in CI.

Adding a case is one JSON file with `name`, `ws`, `snapshot`, and `expected`.
To capture a real layout to build one from:

```sh
herdr api snapshot | jq '.result.snapshot | {tabs, layouts}'
```

The repo carries the `herdr-plugin` GitHub topic, which is what lists it in the
herdr marketplace.

## License

[MIT](./LICENSE) © Danilo de Lucas
