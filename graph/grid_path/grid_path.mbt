///|
pub fn cell_count(
  width : Int,
  height : Int,
) -> Int where {
  proof_require: valid_dims(width, height),
  proof_ensure: result => result == width * height && result > 0,
} {
  width * height
}

///|
pub fn is_valid_cell(
  width : Int,
  height : Int,
  cell : Int,
) -> Bool where {
  proof_require: valid_dims(width, height),
  proof_ensure: result => result == valid_cell(width, height, cell),
} {
  0 <= cell && cell < width * height
}

///|
pub fn is_passable_cell(
  width : Int,
  height : Int,
  weights : FixedArray[Int],
  cell : Int,
) -> Bool where {
  proof_require: valid_dims(width, height),
  proof_require: same_shape(width, height, weights),
  proof_ensure: result => result == passable_cell(width, height, weights, cell),
} {
  if is_valid_cell(width, height, cell) {
    weights[cell] != 0
  } else {
    false
  }
}

///|
pub fn copy_path_prefix(
  src : FixedArray[Int],
  len : Int,
  dst : FixedArray[Int],
) -> Unit where {
  proof_require: 0 <= len,
  proof_require: len <= src.length(),
  proof_require: len <= dst.length(),
  proof_ensure: path_copy_prefix(src, dst, len, len),
} {
  for i = 0; i < len; {
    dst[i] = src[i]
    continue i + 1
  } where {
    proof_invariant: path_copy_prefix(src, dst, len, i),
  }
}

///|
pub fn reverse_path_prefix(
  src : FixedArray[Int],
  len : Int,
  dst : FixedArray[Int],
) -> Unit where {
  proof_require: 0 <= len,
  proof_require: len <= src.length(),
  proof_require: len <= dst.length(),
  proof_ensure: path_reverse_prefix(src, dst, len, len),
} {
  for i = 0; i < len; {
    dst[i] = src[len - 1 - i]
    continue i + 1
  } where {
    proof_invariant: path_reverse_prefix(src, dst, len, i),
  }
}

///|
pub fn copy_path_with_endpoints(
  src : FixedArray[Int],
  len : Int,
  dst : FixedArray[Int],
) -> Unit where {
  proof_require: 1 <= len,
  proof_require: len <= src.length(),
  proof_require: len <= dst.length(),
  proof_ensure: copied_path_endpoints(src, dst, len),
} {
  copy_path_prefix(src, len, dst)
  proof_assert path_copy_prefix(src, dst, len, len)
  proof_assert dst[0] == src[0]
  proof_assert 0 <= len - 1
  proof_assert len - 1 < len
  proof_assert dst[len - 1] == src[len - 1]
}

///|
pub fn reverse_path_with_endpoints(
  src : FixedArray[Int],
  len : Int,
  dst : FixedArray[Int],
) -> Unit where {
  proof_require: 1 <= len,
  proof_require: len <= src.length(),
  proof_require: len <= dst.length(),
  proof_ensure: reversed_path_endpoints(src, dst, len),
} {
  reverse_path_prefix(src, len, dst)
  proof_assert path_reverse_prefix(src, dst, len, len)
  proof_assert dst[0] == src[len - 1]
  proof_assert 0 <= len - 1
  proof_assert len - 1 < len
  proof_assert dst[len - 1] == src[0]
}

///|
pub fn all_passable_prefix(
  width : Int,
  height : Int,
  weights : FixedArray[Int],
  path : FixedArray[Int],
  len : Int,
) -> Bool where {
  proof_require: valid_dims(width, height),
  proof_require: same_shape(width, height, weights),
  proof_require: 0 <= len,
  proof_require: len <= path.length(),
  proof_ensure: result => {
    result → valid_path_prefix(width, height, weights, path, len)
  },
} {
  for i = 0; i < len; {
    if is_passable_cell(width, height, weights, path[i]) {
      continue i + 1
    } else {
      break false
    }
  } nobreak {
    true
  } where {
    proof_invariant: 0 <= i,
    proof_invariant: i <= len,
    proof_invariant: ∀ j : Int,
      0 <= j && j < i → passable_cell(width, height, weights, path[j]),
  }
}
