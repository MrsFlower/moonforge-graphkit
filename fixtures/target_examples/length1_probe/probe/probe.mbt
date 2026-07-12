///|
/// A contracted helper that conditionally writes one array, called from
/// inside `probe`'s loop -- mirrors `relax_edge` being called from
/// `search`'s loop body.
fn maybe_set(arr : FixedArray[Int], idx : Int, value : Int) -> Unit where {
  proof_require: 0 <= idx,
  proof_require: idx < arr.length(),
} {
  if arr[idx] == -1 {
    arr[idx] = value
  }
}

///|
pub struct ProbeState {
  a : FixedArray[Bool]
  b : FixedArray[Int]
  c : FixedArray[Int]
} derive(Eq)

///|
/// Mirrors `search`'s shape: three `FixedArray::make` calls, a `for` loop
/// that writes `a` directly and `b`/`c` via a called contracted function,
/// then constructs a record from the three arrays right after the loop --
/// to check whether the `not X.length1 = Y.length1` pattern (see
/// `astar_grid.mbtp`/`LESSONS.md` sec. 9) reproduces without any A*
/// business logic.
pub fn probe(n : Int) -> ProbeState where {
  proof_require: 0 < n,
} {
  let a = FixedArray::make(n, false)
  let b = FixedArray::make(n, -1)
  let c = FixedArray::make(n, -1)
  for i = 0; i < n; {
    a[i] = true
    maybe_set(b, i, i)
    maybe_set(c, i, i)
    continue i + 1
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= n,
    proof_invariant: a.length() == n,
    proof_invariant: b.length() == n,
    proof_invariant: c.length() == n,
  }
  { a, b, c }
}
