///|
/// Deliberately references a predicate name that is never declared in
/// `thing.mbtp`, matching the real "unbound identifier" `moon check`
/// failure this fixture's `check_gate_test.mbt` tests were written
/// against (verified by hand against this project's own toolchain before
/// writing the test: `moon check broken_pkg` reports `[4021] ... is
/// unbound` for this exact file).
pub fn double(n : Int) -> Int where {
  proof_require: totally_bogus_predicate(n),
  proof_ensure: result => result == n * 2,
} {
  n * 2
}
