///|
pub fn is_marked(
  vertices : Int,
  visited : FixedArray[Int],
  vertex : Int,
) -> Bool where {
  proof_require: valid_vertex_count(vertices),
  proof_require: visited_shape(vertices, visited),
  proof_require: valid_vertex(vertices, vertex),
  proof_ensure: result => result == marked_vertex(vertices, visited, vertex),
} {
  visited[vertex] != 0
}

///|
pub fn mark_vertex(
  vertices : Int,
  visited : FixedArray[Int],
  vertex : Int,
) -> Unit where {
  proof_require: valid_vertex_count(vertices),
  proof_require: visited_shape(vertices, visited),
  proof_require: valid_vertex(vertices, vertex),
  proof_ensure: visited_shape(vertices, visited),
  proof_ensure: marked_vertex(vertices, visited, vertex),
} {
  visited[vertex] = 1
}

///|
fn edge_index(
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
fn is_edge(
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
pub fn discover_first_unmarked_out_edge_prefix(
  vertices : Int,
  edges : FixedArray[Int],
  visited : FixedArray[Int],
  source : Int,
  upto : Int,
) -> Int where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: visited_shape(vertices, visited),
  proof_require: valid_vertex(vertices, source),
  proof_require: 0 <= upto,
  proof_require: upto <= vertices,
  proof_ensure: result => {
    discover_prefix_post(vertices, edges, visited, source, upto, result)
  },
} {
  for candidate = 0; candidate < upto; {
    if is_edge(vertices, edges, source, candidate) &&
      !is_marked(vertices, visited, candidate) {
      mark_vertex(vertices, visited, candidate)
      proof_assert has_edge(vertices, edges, source, candidate)
      proof_assert marked_vertex(vertices, visited, candidate)
      break candidate
    } else {
      proof_assert !unmarked_out_edge(
        vertices, edges, visited, source, candidate,
      )
      proof_assert no_unmarked_out_edge_prefix(
        vertices,
        edges,
        visited,
        source,
        candidate + 1,
      )
      continue candidate + 1
    }
  } nobreak {
    vertices
  } where {
    proof_invariant: 0 <= candidate,
    proof_invariant: candidate <= upto,
    proof_invariant: no_unmarked_out_edge_prefix(
      vertices, edges, visited, source, candidate,
    ),
    proof_yield: result => {
      discover_prefix_post(vertices, edges, visited, source, upto, result)
    },
  }
}

///|
pub fn mark_out_neighbors_prefix(
  vertices : Int,
  edges : FixedArray[Int],
  visited : FixedArray[Int],
  source : Int,
  upto : Int,
) -> Unit where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: visited_shape(vertices, visited),
  proof_require: valid_vertex(vertices, source),
  proof_require: 0 <= upto,
  proof_require: upto <= vertices,
  proof_ensure: out_neighbors_marked_prefix(
    vertices, edges, visited, source, upto,
  ),
} {
  for candidate = 0; candidate < upto; {
    if is_edge(vertices, edges, source, candidate) {
      visited[candidate] = 1
      proof_assert visited_shape(vertices, visited)
      proof_assert marked_vertex(vertices, visited, candidate)
      proof_assert ∀ target : Int,
        0 <= target &&
        target < candidate &&
        has_edge(vertices, edges, source, target) →
        marked_vertex(vertices, visited, target)
    }
    proof_assert out_neighbors_marked_prefix(
      vertices,
      edges,
      visited,
      source,
      candidate + 1,
    )
    continue candidate + 1
  } where {
    proof_invariant: 0 <= candidate,
    proof_invariant: candidate <= upto,
    proof_invariant: out_neighbors_marked_prefix(
      vertices, edges, visited, source, candidate,
    ),
  }
}

///|
pub fn seed_start_and_neighbors(
  vertices : Int,
  edges : FixedArray[Int],
  start : Int,
) -> FixedArray[Int] where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, start),
  proof_ensure: result => start_seed_post(vertices, edges, start, result),
} {
  let visited = FixedArray::make(vertices, 0)
  proof_assert visited_shape(vertices, visited)
  visited[start] = 1
  proof_assert visited_shape(vertices, visited)
  proof_assert marked_vertex(vertices, visited, start)
  mark_out_neighbors_prefix(vertices, edges, visited, start, vertices)
  proof_assert visited_shape(vertices, visited)
  proof_assert out_neighbors_marked_prefix(
    vertices, edges, visited, start, vertices,
  )
  visited[start] = 1
  proof_assert visited_shape(vertices, visited)
  proof_assert marked_vertex(vertices, visited, start)
  proof_assert ∀ target : Int,
    0 <= target && target < vertices && has_edge(vertices, edges, start, target) →
    marked_vertex(vertices, visited, target)
  proof_assert out_neighbors_marked_prefix(
    vertices, edges, visited, start, vertices,
  )
  visited
}

///|
pub fn parent_of(
  vertices : Int,
  parent : FixedArray[Int],
  vertex : Int,
) -> Int where {
  proof_require: valid_vertex_count(vertices),
  proof_require: parent_shape(vertices, parent),
  proof_require: valid_vertex(vertices, vertex),
  proof_ensure: result => result == parent[vertex],
} {
  parent[vertex]
}

///|
pub fn seed_start_neighbor_parents(
  vertices : Int,
  edges : FixedArray[Int],
  start : Int,
) -> FixedArray[Int] where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, start),
  proof_ensure: result => start_parent_seed_post(vertices, edges, start, result),
} {
  let parent = FixedArray::make(vertices, vertices)
  proof_assert parent_shape(vertices, parent)
  parent[start] = start
  proof_assert parent_shape(vertices, parent)
  proof_assert parent[start] == start
  for candidate = 0; candidate < vertices; {
    if is_edge(vertices, edges, start, candidate) {
      parent[candidate] = start
      proof_assert parent_shape(vertices, parent)
      proof_assert parent[candidate] == start
      proof_assert ∀ target : Int,
        0 <= target &&
        target < candidate &&
        has_edge(vertices, edges, start, target) →
        parent[target] == start
    }
    proof_assert direct_parent_prefix(
      vertices,
      edges,
      parent,
      start,
      candidate + 1,
    )
    continue candidate + 1
  } where {
    proof_invariant: 0 <= candidate,
    proof_invariant: candidate <= vertices,
    proof_invariant: direct_parent_prefix(
      vertices, edges, parent, start, candidate,
    ),
  }
  proof_assert direct_parent_prefix(vertices, edges, parent, start, vertices)
  parent[start] = start
  proof_assert parent_shape(vertices, parent)
  proof_assert parent[start] == start
  proof_assert ∀ target : Int,
    0 <= target && target < vertices && has_edge(vertices, edges, start, target) →
    parent[target] == start
  proof_assert direct_parent_prefix(vertices, edges, parent, start, vertices)
  parent
}

///|
pub(all) struct BfsSeed {
  visited : FixedArray[Int]
  parent : FixedArray[Int]
}

///|
pub fn seed_start_layer(
  vertices : Int,
  edges : FixedArray[Int],
  start : Int,
) -> BfsSeed where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, start),
  proof_ensure: result => bfs_seed_post(vertices, edges, start, result),
} {
  let visited = seed_start_and_neighbors(vertices, edges, start)
  proof_assert start_seed_post(vertices, edges, start, visited)
  let parent = seed_start_neighbor_parents(vertices, edges, start)
  proof_assert start_parent_seed_post(vertices, edges, start, parent)
  let result = { visited, parent }
  proof_assert start_seed_post(vertices, edges, start, result.visited)
  proof_assert start_parent_seed_post(vertices, edges, start, result.parent)
  proof_assert bfs_seed_post(vertices, edges, start, result)
  result
}
