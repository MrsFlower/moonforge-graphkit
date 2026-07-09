///|
/// Defensive behavior harness, not a proof-quality check. `proof_require`,
/// `proof_ensure`, and every `proof_invariant` line MoonForge injects into
/// the tagged region above are ghost code: verified by hand against this
/// project's own toolchain that an empty `proof_invariant` block (and even
/// an obviously-false `proof_assert`) compiles and runs cleanly under
/// `moon check`/`moon test`, because those annotations are erased before
/// ordinary compilation. `moon test` therefore cannot see whether a given
/// round's injected invariants are logically sound — only `moon prove`
/// can. What this test *can* catch: whether the injector's tag-based
/// text replacement corrupted `isqrt`'s actual executable body (a
/// stray brace, a mismatched paren, a shifted return), which would make
/// the function misbehave even though its ghost contract still "reads"
/// fine. This is the safety-net role such a test can honestly play: a
/// regression check on observable behavior across MoonForge's repeated
/// rewrites of this file, not a substitute for `moon prove`.
test "isqrt's observable behavior survives repeated tagged-region rewrites" {
  // n = 0 and small values exercise the loop's boundary explicitly,
  // since quickcheck's uniform sampling below is unlikely to hit them.
  assert_eq(isqrt(0), 0)
  assert_eq(isqrt(1), 1)
  assert_eq(isqrt(2), 1)
  assert_eq(isqrt(3), 1)
  assert_eq(isqrt(4), 2)
  for trial = 0; trial < 200; trial = trial + 1 {
    let raw : Int = @quickcheck.gen(size=1_000_000)
    let n = if raw < 0 { -raw } else { raw }
    let result = isqrt(n)
    assert_true(result >= 0)
    assert_true(result * result <= n)
    assert_true(n < (result + 1) * (result + 1))
  }
}
