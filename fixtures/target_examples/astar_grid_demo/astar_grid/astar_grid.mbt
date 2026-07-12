///|
/// Weighted grid search with obstacle avoidance (Boss 战一's MVP prompt,
/// see `两个挑战.txt`). This is a zero-heuristic A* — equivalently plain
/// Dijkstra — rather than a full admissible-heuristic A*: the challenge
/// only requires proving termination and obstacle-free paths, not
/// optimality, so `search` never needs a heuristic function at all (see
/// the scope note in this fixture's accompanying plan). `find_min_open`
/// scans linearly for the cheapest open cell instead of using a priority
/// queue — with at most 100x100 = 10000 cells this stays within the
/// challenge's own bound, and a linear scan needs no pointer-swap/alias
/// reasoning, avoiding the "array permutation" SMT trap this project's
/// research notes flag for heap-backed priority queues.
///
/// Grid cells are flat row-major indices `r * width + c` into
/// `FixedArray[Int]`s — never a nested `FixedArray[FixedArray[Int]]`,
/// which a real probe found `moon prove` rejects outright (see
/// `astar_grid.mbtp`'s header comment and `moon-forge/docs/LESSONS.md`).
///
/// Every function below that carries a `where` contract is restricted to
/// `FixedArray`s and primitive operators in its body — growable
/// `Array`/`.push` construction is rejected inside a contracted function
/// body (real error: "unsupported expression in contracted function
/// body"), and a contracted function may only call other contracted
/// functions, `#proof_pure` functions, or primitives (real error: "only
/// contracted functions, imported proof-callable functions, pure
/// functions, and primitive operators can be called"). See
/// `moon-forge/docs/LESSONS.md` for both real error texts.
///|
/// Row/column decomposition of a flat index. Written as an ordinary
/// contracted function (not `#proof_pure`) so its division's
/// `width != 0` safety obligation can draw on a real `proof_require`
/// premise — a real probe found `#proof_pure` functions cannot carry any
/// `where` contract at all (real error: "pure functions cannot carry
/// verification contracts yet"), which left the division provably unsafe
/// with no way to state its precondition. See `moon-forge/docs/LESSONS.md`.
fn row_of(idx : Int, width : Int, height : Int) -> Int where {
  proof_require: 0 < width,
  proof_require: 0 <= idx,
  proof_require: idx < width * height,
  proof_ensure: result => 0 <= result && result < height,
  proof_ensure: result => result == idx / width,
} {
  idx / width
}

///|
fn col_of(idx : Int, width : Int) -> Int where {
  proof_require: 0 < width,
  proof_require: 0 <= idx,
  proof_ensure: result => 0 <= result && result < width,
  proof_ensure: result => result == idx - idx / width * width,
} {
  idx - idx / width * width
}

///|
/// Whether `(r, c)` is a valid, in-bounds neighbor of the cell at flat
/// index `from` reached by offset `(dr, dc)`. Returns `-1` for an
/// out-of-bounds neighbor. No division/indexing inside, so no
/// precondition is needed and this stays `#proof_pure`.
#proof_pure
fn neighbor_flat(width : Int, height : Int, r : Int, c : Int, dr : Int, dc : Int) -> Int {
  let nr = r + dr
  let nc = c + dc
  if 0 <= nr && nr < height && 0 <= nc && nc < width {
    nr * width + nc
  } else {
    -1
  }
}

///|
/// Contracted wrapper around `neighbor_flat` for call sites that need the
/// flat-index bounds fact as a precondition to a mutating helper.
fn checked_neighbor_flat(
  width : Int,
  height : Int,
  r : Int,
  c : Int,
  dr : Int,
  dc : Int,
) -> Int where {
  proof_axiomatized: true,
  proof_require: valid_dims(width, height),
  proof_require: in_bounds(width, height, r, c),
  proof_require: (dr == -1 && dc == 0) ||
    (dr == 1 && dc == 0) ||
    (dr == 0 && dc == -1) ||
    (dr == 0 && dc == 1),
  proof_ensure: result => result == -1 || (0 <= result && result < width * height),
} {
  neighbor_flat(width, height, r, c, dr, dc)
}

///|
/// Scan every cell for the cheapest discovered-but-not-yet-closed
/// (`open`) one. Returns `-1` if no open cell remains.
fn find_min_open(
  width : Int,
  height : Int,
  closed : FixedArray[Bool],
  cost : FixedArray[Int],
) -> Int where {
  proof_require: valid_dims(width, height),
  proof_require: same_shape(width, height, cost),
  proof_require: closed.length() == width * height,
  proof_ensure: result => (
    result == -1 ||
    (0 <= result && result < width * height && !closed[result] &&
      0 <= cost[result])
  ),
} {
  for i = 0, best = -1; i < width * height; {
    let is_better = !closed[i] &&
      0 <= cost[i] &&
      (best == -1 || cost[i] < cost[best])
    let new_best = if is_better { i } else { best }
    continue i + 1, new_best
  } nobreak {
    best
  } where {
    // @MOONFORGE_INVARIANT_FIND_MIN_OPEN_START
proof_invariant: 0 <= i,
proof_invariant: i <= width * height,
proof_invariant: best == -1 || (0 <= best && best < i && !closed[best] && 0 <= cost[best]),
proof_invariant: ∀ j : Int, 0 <= j && j < i → (0 <= cost[j] && !closed[j]) → (best != -1 && cost[j] >= cost[best]),
    // @MOONFORGE_INVARIANT_FIND_MIN_OPEN_END
  }
}

///|
/// Relax the single edge `from -> target` with weight `weights[target]`,
/// updating `cost`/`came_from` in place when it improves `target`'s
/// tentative cost. `target == -1` (an out-of-bounds neighbor) and
/// obstacle targets are both no-ops, so callers do not need to guard
/// those cases themselves.
///
/// The parameter is named `target`, not `to` — `to` is a WhyML reserved
/// word (used in `for ... to ...` loop syntax) and this toolchain lowers
/// MoonBit parameter names directly into WhyML identifiers, so a
/// parameter literally named `to` produces a real syntax error at the
/// `moon prove` stage: `"...mlw", line N, characters C-C: syntax error`
/// pointing at the generated `to` token, with no MoonBit-side diagnostic
/// at all (`moon check` accepts `to` as an ordinary identifier). See
/// `moon-forge/docs/LESSONS.md`.
fn relax_edge(
  width : Int,
  weights : FixedArray[Int],
  cost : FixedArray[Int],
  came_from : FixedArray[Int],
  from : Int,
  target : Int,
) -> Unit where {
  proof_require: 0 < width,
  proof_require: cost.length() == weights.length(),
  proof_require: came_from.length() == weights.length(),
  proof_require: 0 <= from,
  proof_require: from < weights.length(),
  proof_require: target == -1 || (0 <= target && target < weights.length()),
  proof_require: 0 <= cost[from],
} {
  if target != -1 && weights[target] != 0 {
    let candidate = cost[from] + weights[target]
    if cost[target] == -1 || candidate < cost[target] {
      cost[target] = candidate
      came_from[target] = from
    }
  }
}

///|
/// Mark a cell as settled while keeping the Bool worklist's length fact
/// explicit at the call boundary. This isolates the `FixedArray[Bool]`
/// mutation from `search`'s already-heavy loop VC.
fn mark_settled(
  settled : FixedArray[Bool],
  idx : Int,
  len : Int,
) -> Unit where {
  proof_require: settled.length() == len,
  proof_require: 0 <= idx,
  proof_require: idx < settled.length(),
  proof_ensure: settled.length() == len,
} {
  settled[idx] = true
}

///|
/// Construct the local Bool worklist behind a small contract. Keeping the
/// raw `FixedArray::make(..., false)` out of `search`'s main VC avoids
/// exposing its internal `make_checked` name to the heavy loop frame.
fn make_settled(len : Int) -> FixedArray[Bool] where {
  proof_require: 0 <= len,
  proof_ensure: result => result.length() == len,
} {
  FixedArray::make(len, false)
}

///|
/// Trusted one-edge preservation bridge. This is intentionally smaller
/// than trusting the whole search loop: it states that one `relax_edge`
/// call preserves exactly the facts later consumed by `search_post`.
fn relax_one_neighbor(
  weights : FixedArray[Int],
  width : Int,
  height : Int,
  cost : FixedArray[Int],
  came_from : FixedArray[Int],
  current : Int,
  target : Int,
  start : Int,
) -> Unit where {
  proof_axiomatized: true,
  proof_require: valid_grid(width, height, weights),
  proof_require: valid_weights(width, height, weights),
  proof_require: same_shape(width, height, cost),
  proof_require: came_from.length() == width * height,
  proof_require: 0 <= current,
  proof_require: current < width * height,
  proof_require: target == -1 || (0 <= target && target < width * height),
  proof_require: 0 <= cost[current],
  proof_require: discovered_avoids_obstacles(width, height, weights, cost),
  proof_require: came_from_valid(width, height, cost, came_from),
  proof_require: came_from_decreases_cost(width, height, cost, came_from),
  proof_require: cost_sentinel_or_nonneg(width, height, cost),
  proof_require: came_from_neg_one_implies_start(width, height, cost, came_from, start),
  proof_ensure: same_shape(width, height, cost),
  proof_ensure: came_from.length() == width * height,
  proof_ensure: 0 <= cost[current],
  proof_ensure: discovered_avoids_obstacles(width, height, weights, cost),
  proof_ensure: came_from_valid(width, height, cost, came_from),
  proof_ensure: came_from_decreases_cost(width, height, cost, came_from),
  proof_ensure: cost_sentinel_or_nonneg(width, height, cost),
  proof_ensure: came_from_neg_one_implies_start(width, height, cost, came_from, start),
} {
  relax_edge(width, weights, cost, came_from, current, target)
}

///|
/// Relax all four grid neighbors of `current` behind one contract, so the
/// main search loop only has to preserve its semantic invariants across a
/// single call instead of four separate array-mutating calls.
fn relax_neighbors(
  weights : FixedArray[Int],
  width : Int,
  height : Int,
  cost : FixedArray[Int],
  came_from : FixedArray[Int],
  current : Int,
  start : Int,
) -> Unit where {
  proof_require: valid_grid(width, height, weights),
  proof_require: valid_weights(width, height, weights),
  proof_require: same_shape(width, height, cost),
  proof_require: came_from.length() == width * height,
  proof_require: 0 <= current,
  proof_require: current < width * height,
  proof_require: 0 <= cost[current],
  proof_require: discovered_avoids_obstacles(width, height, weights, cost),
  proof_require: came_from_valid(width, height, cost, came_from),
  proof_require: came_from_decreases_cost(width, height, cost, came_from),
  proof_require: cost_sentinel_or_nonneg(width, height, cost),
  proof_require: came_from_neg_one_implies_start(width, height, cost, came_from, start),
  proof_ensure: same_shape(width, height, cost),
  proof_ensure: came_from.length() == width * height,
  proof_ensure: discovered_avoids_obstacles(width, height, weights, cost),
  proof_ensure: came_from_valid(width, height, cost, came_from),
  proof_ensure: came_from_decreases_cost(width, height, cost, came_from),
  proof_ensure: cost_sentinel_or_nonneg(width, height, cost),
  proof_ensure: came_from_neg_one_implies_start(width, height, cost, came_from, start),
} {
  let r = row_of(current, width, height)
  let c = col_of(current, width)
  relax_one_neighbor(weights, width, height, cost, came_from, current, checked_neighbor_flat(width, height, r, c, -1, 0), start)
  relax_one_neighbor(weights, width, height, cost, came_from, current, checked_neighbor_flat(width, height, r, c, 1, 0), start)
  relax_one_neighbor(weights, width, height, cost, came_from, current, checked_neighbor_flat(width, height, r, c, 0, -1), start)
  relax_one_neighbor(weights, width, height, cost, came_from, current, checked_neighbor_flat(width, height, r, c, 0, 1), start)
}

///|
/// Bundles `search`'s result arrays so callers (and `proof_ensure`)
/// project named fields (`result.cost`) rather than tuple indices
/// (`result.0`) — struct field projection is fine in a logic body, tuple
/// projection is rejected (real error: "unsupported expression in logic
/// body"); see `moon-forge/docs/LESSONS.md`.
pub struct SearchState {
  cost : FixedArray[Int]
  came_from : FixedArray[Int]
}

///|
/// Run a zero-heuristic A* / Dijkstra search from `start` over the
/// `width`x`height` grid described by `weights`. `weights[i] == 0` marks
/// an obstacle; every other cell's weight is the cost of stepping onto
/// it. Returns the cost/came_from arrays `build_path_core` needs
/// to reconstruct a safe path to any reached target.
pub fn search(
  weights : FixedArray[Int],
  width : Int,
  height : Int,
  start : Int,
) -> SearchState where {
  proof_require: valid_grid(width, height, weights),
  proof_require: valid_weights(width, height, weights),
  proof_require: 0 <= start,
  proof_require: start < width * height,
  proof_require: weights[start] != 0,
  proof_ensure: result => search_post(
    width, height, weights, result.cost, result.came_from, start,
  ),
} {
  let settled = make_settled(width * height)
  let cost = FixedArray::make(width * height, -1)
  let came_from = FixedArray::make(width * height, -1)
  proof_assert settled.length() == width * height
  cost[start] = 0
  proof_assert settled.length() == width * height
  proof_assert cost.length() == width * height
  proof_assert came_from.length() == width * height
  // The flat single-index form (`cost[j]`) matches `FixedArray::make`'s
  // update axiom trigger directly and proves in seconds; the row/column
  // form (`cost[r * width + c]`) is logically equivalent (`in_bounds`
  // means `r * width + c` ranges over exactly the same indices as `j`)
  // but real-tested `Timeout`s — the trigger pattern on the update axiom
  // is keyed on the raw array index expression, and matching it against
  // `add (mul r width) c` needs more instantiation work than matching a
  // bare variable `j`, even though both terms denote the same value. See
  // `moon-forge/docs/LESSONS.md`.
  proof_assert ∀ j : Int, 0 <= j && j < width * height && j != start →
    cost[j] == -1
  proof_assert discovered_avoids_obstacles(width, height, weights, cost)
  let max_cells = width * height
  for step = 0; step < max_cells; {
    let current = find_min_open(width, height, settled, cost)
    if current == -1 {
      continue step + 1
    } else {
      mark_settled(settled, current, width * height)
      relax_neighbors(weights, width, height, cost, came_from, current, start)
      continue step + 1
    }
  } nobreak {
    { cost, came_from }
  } where {
    // @MOONFORGE_INVARIANT_SEARCH_START
proof_invariant: 0 <= step && step <= max_cells,
proof_invariant: 0 <= max_cells - step,
proof_invariant: settled.length() == width * height,
proof_invariant: same_shape(width, height, cost),
proof_invariant: came_from.length() == width * height,
proof_invariant: discovered_avoids_obstacles(width, height, weights, cost),
proof_invariant: came_from_valid(width, height, cost, came_from),
proof_invariant: came_from_decreases_cost(width, height, cost, came_from),
proof_invariant: cost_sentinel_or_nonneg(width, height, cost),
proof_invariant: came_from_neg_one_implies_start(width, height, cost, came_from, start),
proof_yield: result => search_post(width, height, weights, result.cost, result.came_from, start),
    // @MOONFORGE_INVARIANT_SEARCH_END
  }
}

///|
/// Walk `came_from` backwards from `target` to `start`, writing the path
/// into `buf` (start-to-target order) and returning its valid length, or
/// `-1` if `target` was never discovered (unreachable from `start`).
/// `buf` must be preallocated with at least `width * height` slots by
/// the caller — this function never resizes it, since growable-`Array`
/// construction is rejected inside a contracted function body.
pub fn build_path_core(
  weights : FixedArray[Int],
  width : Int,
  height : Int,
  cost : FixedArray[Int],
  came_from : FixedArray[Int],
  start : Int,
  target : Int,
  buf : FixedArray[Int],
) -> Int where {
  proof_require: valid_dims(width, height),
  proof_require: search_post(width, height, weights, cost, came_from, start),
  proof_require: 0 <= start,
  proof_require: start < width * height,
  proof_require: 0 <= target,
  proof_require: target < width * height,
  proof_require: came_from[start] == -1,
  proof_require: buf.length() == width * height,
  proof_ensure: result => (
    result == -1 || path_avoids_obstacles(width, height, weights, buf, result)
  ),
} {
  if cost[target] == -1 {
    -1
  } else {
    let scratch = FixedArray::make(width * height, -1)
    proof_assert scratch.length() == width * height
    scratch[0] = target
    proof_assert scratch.length() == width * height
    // `cost[target] != -1` (the `if` guard above) only becomes
    // `discovered(width, cost, target)` (needed for the WALK loop's
    // `came_from`/`path_avoids_obstacles` init facts below) once it's
    // connected through `cost_sentinel_or_nonneg` — without that conjunct
    // in `search_post`, "not -1" does not rule out some other negative
    // value. See `moon-forge/docs/LESSONS.md`.
    proof_assert 0 <= cost[target]
    // Same trigger-matching gap as `search`'s `discovered_avoids_obstacles`
    // (see `moon-forge/docs/LESSONS.md`): `came_from_valid` is quantified
    // over `r, c` with `r * width + c` inside, but the WALK loop's own
    // invariant needs the bare-flat-index fact `came_from[target] == -1
    // || (0 <= came_from[target] && came_from[target] < width * height)`.
    // A universally-quantified assert stated with `r * width + c ==
    // target` as a premise (rather than the row/column split done here
    // explicitly) leaves the solver to find its own witness `r, c` for
    // that equality — real-tested to fail (existential witness-finding
    // inside a universal's antecedent is not something automatic
    // theorem provers do well, even for a trivially computable witness).
    // Supplying the concrete decomposition directly sidesteps the
    // witness-search problem entirely.
    let target_r = row_of(target, width, height)
    let target_c = col_of(target, width)
    proof_assert in_bounds(width, height, target_r, target_c)
    proof_assert target_r * width + target_c == target
    proof_assert discovered(width, cost, target_r, target_c)
    proof_assert came_from[target] == -1 ||
      (0 <= came_from[target] && came_from[target] < width * height)
    for step = 0, len = 1, current = target; step < width * height; {
      if current == start {
        continue width * height, len, current
      } else if len >= width * height {
        continue width * height, len, current
      } else {
        let prev = came_from[current]
        if prev == -1 {
          // `came_from[current] == -1` alone does not rule out `current`
          // being some unreachable-from-`relax_edge` discovered cell —
          // `came_from_neg_one_implies_start` (see `astar_grid.mbtp`)
          // closes that gap: paired with `0 <= cost[current]` (this
          // loop's own invariant), it gives `current == start` directly.
          proof_assert 0 <= cost[current]
          proof_assert current == start
          continue width * height, len, start
        } else {
        // The WALK guard includes `len < scratch.length()`, so this write
        // is guarded operationally instead of relying on the earlier
        // pigeonhole/counting proof that the predecessor chain cannot fill
        // the buffer. If the guard ever runs out before reaching `start`,
        // the loop exits and this function returns `-1`.
        let current_r = row_of(current, width, height)
        let current_c = col_of(current, width)
        proof_assert current_r * width + current_c == current
        proof_assert in_bounds(width, height, current_r, current_c)
        proof_assert cost[came_from[current]] < cost[current]
        proof_assert cost[prev] < cost[current]
        // `0 <= cost[current]` (this loop's own invariant) needs to be
        // preserved into the next iteration's `current = prev`.
        // `came_from_valid` (from `search_post`) gives the predecessor's
        // non-negative cost directly; `closed` is only an internal search
        // worklist marker and does not need to be exposed to path
        // reconstruction.
        let prev_r = row_of(prev, width, height)
        let prev_c = col_of(prev, width)
        proof_assert prev_r * width + prev_c == prev
        proof_assert in_bounds(width, height, prev_r, prev_c)
        proof_assert 0 <= cost[prev]
        proof_assert discovered(width, cost, prev_r, prev_c)
        proof_assert !is_obstacle(width, weights, prev_r, prev_c)
        proof_assert weights[prev] != 0
        // Needed for the WALK loop's own invariant to survive into the
        // next iteration's `current = prev`: `came_from_valid`
        // instantiated at `prev`'s row/column decomposition gives
        // `came_from[prev]`'s bounds whenever it isn't `-1`; paired
        // with `prev != start`'s alternative (`came_from[prev] == -1`
        // is itself one of the invariant's three disjuncts), this
        // covers the same three-way disjunction the loop invariant
        // requires.
        proof_assert prev == start ||
          came_from[prev] == -1 ||
          (0 <= came_from[prev] && came_from[prev] < width * height)
        proof_assert len < scratch.length()
        scratch[len] = prev
        proof_assert scratch.length() == width * height
        continue step + 1, len + 1, prev
        }
      }
    } nobreak {
      if current == start {
        for i = 0; i < len; {
          buf[i] = scratch[len - 1 - i]
          continue i + 1
        } where {
          // @MOONFORGE_INVARIANT_BUILD_PATH_COPY_START
proof_invariant: 0 <= i,
proof_invariant: i <= len,
proof_invariant: 1 <= len && len <= width * height,
proof_invariant: buf.length() == width * height,
proof_invariant: path_avoids_obstacles(width, height, weights, scratch, len),
proof_invariant: ∀ j : Int, 0 <= j && j < i → buf[j] == scratch[len - 1 - j],
proof_invariant: ∀ j : Int, 0 <= j && j < i → 0 <= len - 1 - j && len - 1 - j < len,
proof_invariant: ∀ j : Int, 0 <= j && j < i → 0 <= buf[j] && buf[j] < width * height && weights[buf[j]] != 0,
proof_invariant: path_avoids_obstacles(width, height, weights, buf, i),
          // @MOONFORGE_INVARIANT_BUILD_PATH_COPY_END
        }
        len
      } else {
        -1
      }
    } where {
      // @MOONFORGE_INVARIANT_BUILD_PATH_WALK_START
proof_invariant: 0 <= step && step <= width * height,
proof_invariant: 1 <= len && len <= width * height,
proof_invariant: len <= step + 1,
proof_invariant: 0 <= current && current < width * height,
proof_invariant: scratch.length() == width * height,
proof_invariant: scratch[0] == target,
proof_invariant: scratch[len - 1] == current,
proof_invariant: path_avoids_obstacles(width, height, weights, scratch, len),
proof_invariant: ∀ i : Int, 0 <= i && i < len → 0 <= scratch[i] && scratch[i] < width * height,
proof_invariant: ∀ i : Int, 0 <= i && i < len → weights[scratch[i]] != 0,
proof_invariant: current == start || came_from[current] == -1 || (0 <= came_from[current] && came_from[current] < width * height),
proof_invariant: 0 <= cost[current],
      // @MOONFORGE_INVARIANT_BUILD_PATH_WALK_END
    }
  }
}
