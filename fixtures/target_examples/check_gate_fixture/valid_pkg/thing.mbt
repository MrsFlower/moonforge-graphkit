///|
pub fn double(n : Int) -> Int where {
  proof_require: nonneg(n),
  proof_ensure: result => result == n * 2,
} {
  n * 2
}
