///|
pub fn vertex_capacity(
  vertices : Int,
) -> Int where {
  proof_require: valid_vertex_count(vertices),
  proof_ensure: result => result == vertices * vertices && result > 0,
} {
  vertices * vertices
}

///|
pub fn is_valid_vertex(
  vertices : Int,
  vertex : Int,
) -> Bool where {
  proof_require: valid_vertex_count(vertices),
  proof_ensure: result => result == valid_vertex(vertices, vertex),
} {
  0 <= vertex && vertex < vertices
}

///|
pub fn edge_index(
  vertices : Int,
  source : Int,
  target : Int,
) -> Int where {
  proof_require: valid_vertex_count(vertices),
  proof_require: valid_vertex(vertices, source),
  proof_require: valid_vertex(vertices, target),
  proof_ensure: result => result == edge_offset(vertices, source, target),
  proof_ensure: result => 0 <= result && result < vertices * vertices,
} {
  source * vertices + target
}

///|
pub fn is_edge(
  vertices : Int,
  edges : FixedArray[Int],
  source : Int,
  target : Int,
) -> Bool where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, source),
  proof_require: valid_vertex(vertices, target),
  proof_ensure: result => result == has_edge(vertices, edges, source, target),
} {
  edges[edge_index(vertices, source, target)] != 0
}

///|
pub fn find_out_edge_prefix(
  vertices : Int,
  edges : FixedArray[Int],
  source : Int,
  upto : Int,
) -> Int where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, source),
  proof_require: 0 <= upto,
  proof_require: upto <= vertices,
  proof_ensure: result => {
    out_edge_search_post(vertices, edges, source, upto, result)
  },
} {
  for candidate = 0; candidate < upto; {
    if is_edge(vertices, edges, source, candidate) {
      break candidate
    } else {
      proof_assert !has_edge(vertices, edges, source, candidate)
      proof_assert no_out_edge_prefix(vertices, edges, source, candidate + 1)
      continue candidate + 1
    }
  } nobreak {
    vertices
  } where {
    proof_invariant: 0 <= candidate,
    proof_invariant: candidate <= upto,
    proof_invariant: no_out_edge_prefix(vertices, edges, source, candidate),
    proof_yield: result => {
      out_edge_search_post(vertices, edges, source, upto, result)
    },
  }
}
