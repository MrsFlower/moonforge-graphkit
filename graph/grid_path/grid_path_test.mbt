///|
test "copy and reverse path prefixes" {
  let src = FixedArray::make(4, 0)
  src[0] = 1
  src[1] = 2
  src[2] = 5
  src[3] = 8
  let copied = FixedArray::make(4, -1)
  @grid_path.copy_path_prefix(src, 3, copied)
  debug_inspect(
    [copied[0], copied[1], copied[2], copied[3]],
    content="[1, 2, 5, -1]",
  )
  let reversed = FixedArray::make(4, -1)
  @grid_path.reverse_path_prefix(src, 3, reversed)
  debug_inspect(
    [reversed[0], reversed[1], reversed[2], reversed[3]],
    content="[5, 2, 1, -1]",
  )
}

///|
test "copy and reverse path prefixes preserve endpoints" {
  let src = FixedArray::make(5, 0)
  src[0] = 3
  src[1] = 4
  src[2] = 7
  src[3] = 9
  src[4] = 11
  let copied = FixedArray::make(5, -1)
  @grid_path.copy_path_with_endpoints(src, 4, copied)
  assert_eq(copied[0], 3)
  assert_eq(copied[3], 9)
  let reversed = FixedArray::make(5, -1)
  @grid_path.reverse_path_with_endpoints(src, 4, reversed)
  assert_eq(reversed[0], 9)
  assert_eq(reversed[3], 3)
}

///|
test "passable prefix check" {
  let weights = FixedArray::make(6, 1)
  weights[4] = 0
  let path = FixedArray::make(3, 0)
  path[0] = 0
  path[1] = 1
  path[2] = 2
  assert_true(@grid_path.all_passable_prefix(3, 2, weights, path, 3))
  path[2] = 4
  assert_false(@grid_path.all_passable_prefix(3, 2, weights, path, 3))
}
