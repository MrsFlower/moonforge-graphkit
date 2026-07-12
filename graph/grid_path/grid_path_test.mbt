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
