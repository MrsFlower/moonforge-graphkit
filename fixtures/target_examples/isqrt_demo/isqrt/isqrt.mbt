///|
pub fn isqrt(n : Int) -> Int where {
  proof_require: nonneg(n),
  proof_ensure: result => isqrt_ok(n, result),
} {
  for lo = 0, hi = n + 1; lo < hi - 1; {
    let mid = lo + (hi - lo) / 2
    if mid * mid <= n {
      continue mid, hi
    } else {
      continue lo, mid
    }
  } nobreak {
    lo
  } where {
    // @MOONFORGE_INVARIANT_START
proof_invariant: nonneg(n),
  proof_invariant: (lo >= 0) && (hi >= 0),
  proof_invariant: lo <= hi + 1,
  proof_invariant: lo * lo <= n,
  proof_invariant: n < (hi + 1) * (hi + 1),
  proof_invariant: (hi - lo) >= 0,
    // @MOONFORGE_INVARIANT_END
  }
}
