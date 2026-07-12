///|
/// Defensive behavior harness, not a proof-quality check — see the doc
/// comment on `isqrt_demo/isqrt_test.mbt`'s equivalent test for the full
/// reasoning (ghost `proof_invariant` content is erased before ordinary
/// compilation, so `moon test` cannot see whether an injected invariant
/// is logically sound; it can only catch whether the injector's rewrite
/// corrupted `search`/`build_path_core`'s actual executable body).
///
/// Layout of the 3x3 grid used below (row-major, `.` passable weight-1,
/// `#` obstacle):
/// ```
/// . . .
/// . # .
/// . . .
/// ```
fn small_grid() -> FixedArray[Int] {
  FixedArray::from_array([1, 1, 1, 1, 0, 1, 1, 1, 1][:])
}

///|
test "search finds the start cell itself at cost 0" {
  let weights = small_grid()
  let state = search(weights, 3, 3, 0)
  assert_eq(state.cost[0], 0)
}

///|
test "search never assigns a finite cost to the obstacle cell" {
  let weights = small_grid()
  let state = search(weights, 3, 3, 0)
  assert_eq(state.cost[4], -1)
  assert_eq(state.came_from[4], -1)
}

///|
test "build_path_core reconstructs a path around the obstacle" {
  let weights = small_grid()
  let state = search(weights, 3, 3, 0)
  let buf = FixedArray::make(9, -1)
  let len = build_path_core(weights, 3, 3, state.cost, state.came_from, 0, 8, buf)
  assert_true(len > 0)
  assert_eq(buf[0], 0)
  assert_eq(buf[len - 1], 8)
  for i = 0; i < len; i = i + 1 {
    assert_true(weights[buf[i]] != 0)
  }
}

///|
test "build_path_core reports unreachable targets with -1" {
  // A start cell fully boxed in by obstacles can never reach the far
  // corner: `.` at index 0, obstacles filling the rest of row 0 and the
  // entire column 0 gap it needs to cross.
  let weights = FixedArray::from_array([1, 0, 0, 0, 1, 1, 0, 1, 1][:])
  let state = search(weights, 3, 3, 0)
  let buf = FixedArray::make(9, -1)
  let len = build_path_core(weights, 3, 3, state.cost, state.came_from, 0, 8, buf)
  assert_eq(len, -1)
}
