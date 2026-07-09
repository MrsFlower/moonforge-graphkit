///|
/// Defensive behavior harness, not a proof-quality check — see the doc
/// comment on `isqrt_test.mbt`'s equivalent test in the `isqrt_demo`
/// fixture for the full reasoning (ghost `proof_invariant` content is
/// erased before ordinary compilation, so `moon test` cannot see whether
/// an injected invariant is logically sound; it can only catch whether
/// the injector's rewrite corrupted `clearing_quantity`'s actual
/// executable body). This test additionally guards the two-array
/// generator itself: `gen_desc`/`gen_asc` are hand-written (`.mbtp`
/// predicates like `bids_desc`/`asks_asc` are ghost code and cannot be
/// called from this test — verified directly against this toolchain,
/// referencing them here would fail with an unbound-identifier error the
/// same way `check_gate_test.mbt`'s `broken_pkg` fixture does on purpose),
/// so the fixed test cases below double-check the generator's own
/// ordering guarantee independent of quickcheck's randomization.
fn gen_desc(size : Int) -> Array[Int] {
  let raw : Array[Int] = @quickcheck.gen(size~)
  let normalized = Array::makei(raw.length(), i => {
    let v = raw[i] % 1000
    if v < 0 { -v } else { v }
  })
  normalized.sort_by((a, b) => b - a)
  normalized
}

///|
fn gen_asc(size : Int) -> Array[Int] {
  let raw : Array[Int] = @quickcheck.gen(size~)
  let normalized = Array::makei(raw.length(), i => {
    let v = raw[i] % 1000
    if v < 0 { -v } else { v }
  })
  normalized.sort_by((a, b) => a - b)
  normalized
}

///|
/// Check `clearing_quantity_post`'s two quantified halves directly in
/// executable code (this is what the ghost predicates `all_cross_before`/
/// `all_fail_from` state, re-expressed as a runtime loop since the ghost
/// versions cannot be called here).
fn check_clearing_split(
  bids : FixedArray[Int],
  asks : FixedArray[Int],
  result : Int,
) -> Unit raise {
  let n = bids.length()
  assert_true(0 <= result)
  assert_true(result <= n)
  for i = 0; i < result; i = i + 1 {
    assert_true(asks[i] <= bids[i])
  }
  for i = result; i < n; i = i + 1 {
    assert_true(bids[i] < asks[i])
  }
}

///|
test "auction clears at the first non-crossing level (fixed regression case)" {
  let bids = FixedArray::from_array([110, 105, 100, 90][:])
  let asks = FixedArray::from_array([80, 95, 101, 120][:])
  let result = clear_book(bids, asks)
  assert_eq(result.quantity, 2)
  assert_eq(result.price, 100)
  check_clearing_split(bids, asks, result.quantity)
}

///|
test "fully crossed books match every level (fixed regression case)" {
  let bids = FixedArray::from_array([110, 108, 105][:])
  let asks = FixedArray::from_array([80, 90, 100][:])
  let result = clear_book(bids, asks)
  assert_eq(result.quantity, 3)
  assert_eq(result.price, 102)
  check_clearing_split(bids, asks, result.quantity)
}

///|
test "empty crossing returns zero quantity and zero price (fixed regression case)" {
  let bids = FixedArray::from_array([90, 85, 80][:])
  let asks = FixedArray::from_array([95, 100, 110][:])
  let result = clear_book(bids, asks)
  assert_eq(result.quantity, 0)
  assert_eq(result.price, 0)
  check_clearing_split(bids, asks, result.quantity)
}

///|
test "clearing_quantity's observable split property survives repeated tagged-region rewrites" {
  for trial = 0; trial < 200; trial = trial + 1 {
    let bids_raw = gen_desc(20)
    let asks_raw = gen_asc(20)
    let n = if bids_raw.length() < asks_raw.length() {
      bids_raw.length()
    } else {
      asks_raw.length()
    }
    if n == 0 {
      continue
    }
    let bids : FixedArray[Int] = FixedArray::from_array(bids_raw[:n])
    let asks : FixedArray[Int] = FixedArray::from_array(asks_raw[:n])
    let result = clearing_quantity(bids, asks)
    check_clearing_split(bids, asks, result)
  }
}
