# Build a geometry-only clone plan for workspace $ws from a herdr snapshot.
#
#   jq -n --argjson snap <.result.snapshot> --arg ws <workspace_id> -f plan.jq
#
# Output: a JSON array of tabs in tab-bar display order, each:
#   { "label": <string>, "steps": [ {parent,dir,ratio,child}, ... ] }
#
# Replay contract: a fresh tab starts as one pane = handle 0. For each step, in
# order, split handle[parent] along <dir> ("right"|"down") at <ratio>; the pane
# thereby created becomes handle[child]. herdr's ratio is the fraction the
# ORIGINAL (left/top) pane keeps, which is exactly what the snapshot reports, so
# it is passed through untouched. Panes carry no commands (geometry only).

def rect_eq($a; $b):
  ($a.x == $b.x) and ($a.y == $b.y) and ($a.width == $b.width) and ($a.height == $b.height);

# Bounding box of a tab's panes = the whole tab area.
def bbox($panes):
  ($panes | map(.rect)) as $rs
  | ($rs | map(.x) | min) as $x
  | ($rs | map(.y) | min) as $y
  | {x: $x, y: $y,
     width: (($rs | map(.x + .width) | max) - $x),
     height: (($rs | map(.y + .height) | max) - $y)};

# The first (left for "right" splits, top for "down") immediate child rect of
# $area. Among every pane/split rect that shares $area's top-left corner and its
# cross-axis extent, the immediate child is the largest along the split axis
# (deeper nested splits are strictly smaller). Returns null if none.
def child_a($L; $area; $dir):
  ([$L.panes[].rect] + [$L.splits[].rect]) as $rs
  | if $dir == "right"
    then [$rs[] | select(.x == $area.x and .y == $area.y and .height == $area.height and .width > 0 and .width < $area.width)]
         | (if length == 0 then null else max_by(.width) end)
    else [$rs[] | select(.x == $area.x and .y == $area.y and .width == $area.width and .height > 0 and .height < $area.height)]
         | (if length == 0 then null else max_by(.height) end)
    end;

# The complementary (right/bottom) child rect, derived from $area and child A.
def child_b($area; $dir; $ca):
  if $dir == "right"
  then {x: ($area.x + $ca.width), y: $area.y, width: ($area.width - $ca.width), height: $area.height}
  else {x: $area.x, y: ($area.y + $ca.height), width: $area.width, height: ($area.height - $ca.height)}
  end;

# Recursively resolve $area into a binary tree of leaves ({leaf: pane_id}) and
# internal splits ({dir, ratio, a, b}).
def node($L; $area):
  (first($L.panes[] | select(.rect | rect_eq(.; $area))) // null) as $leaf
  | if $leaf != null then {leaf: $leaf.pane_id}
    else
      (first($L.splits[] | select(.rect | rect_eq(.; $area))) // null) as $sp
      | if $sp == null then {leaf: null}                       # defensive: untiled
        else
          child_a($L; $area; $sp.direction) as $ca
          | if $ca == null then {leaf: null}
            else
              {dir: $sp.direction, ratio: $sp.ratio,
               a: node($L; $ca),
               b: node($L; child_b($area; $sp.direction; $ca))}
            end
        end
    end;

# Linearize the tree into ordered split steps with integer pane handles.
# $h is the handle of this node's area; $next is the next free handle.
def lin($n; $h; $next):
  if ($n | has("leaf")) then {steps: [], next: $next}
  else
    $next as $cb
    | lin($n.a; $h; ($next + 1)) as $la          # child A keeps this node's handle
    | lin($n.b; $cb; $la.next) as $lb            # child B is the newly split pane
    | {steps: ([{parent: $h, dir: $n.dir, ratio: $n.ratio, child: $cb}] + $la.steps + $lb.steps),
       next: $lb.next}
  end;

# Snapshot array order is the tab *display* order — the order herdr paints the
# tab bar in. `.number` is a per-tab identity that stays glued to its tab when
# the user drags tabs around (reordering w1's tabs to t1,t2,t4,t3 leaves the
# numbers 1,2,4,3), so sorting by it would replay the pre-reorder order.
[$snap.tabs[] | select(.workspace_id == $ws)]
| map(
    .label as $label
    | .tab_id as $tid
    | ([$snap.layouts[] | select(.tab_id == $tid)] | first) as $L
    | if ($L == null) or (($L.panes | length) == 0)
      then {label: $label, steps: []}
      else {label: $label, steps: lin(node($L; bbox($L.panes)); 0; 1).steps}
      end
  )
