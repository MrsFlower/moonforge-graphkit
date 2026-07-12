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
pub(all) struct BfsQueue {
  queue : FixedArray[Int]
  head : Int
  tail : Int
}

///|
pub(all) struct BfsDequeue {
  vertex : Int
  queue : BfsQueue
}

///|
pub(all) struct BfsDiscoverEnqueue {
  candidate : Int
  queue : BfsQueue
}

///|
pub(all) struct BfsPopDiscoverEnqueue {
  source : Int
  candidate : Int
  queue : BfsQueue
}

///|
pub(all) struct BfsInit {
  seed : BfsSeed
  queue : BfsQueue
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

///|
pub fn seed_start_queue(
  vertices : Int,
  start : Int,
) -> BfsQueue where {
  proof_require: valid_vertex_count(vertices),
  proof_require: valid_vertex(vertices, start),
  proof_ensure: result => bfs_queue_seed_post(vertices, start, result),
} {
  let queue = FixedArray::make(vertices, vertices)
  proof_assert queue_shape(vertices, queue)
  queue[0] = start
  proof_assert queue_shape(vertices, queue)
  proof_assert queue[0] == start
  let head = 0
  let tail = 1
  proof_assert tail <= vertices
  let result = { queue, head, tail }
  proof_assert queue_shape(vertices, result.queue)
  proof_assert result.head == 0
  proof_assert result.tail == 1
  proof_assert result.queue[0] == start
  proof_assert queue_valid_prefix(vertices, result, result.tail)
  proof_assert bfs_queue_seed_post(vertices, start, result)
  result
}

///|
pub fn init_start_frontier(
  vertices : Int,
  edges : FixedArray[Int],
  start : Int,
) -> BfsInit where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: valid_vertex(vertices, start),
  proof_ensure: result => bfs_init_post(vertices, edges, start, result),
} {
  let seed = seed_start_layer(vertices, edges, start)
  proof_assert bfs_seed_post(vertices, edges, start, seed)
  let queue = seed_start_queue(vertices, start)
  proof_assert bfs_queue_seed_post(vertices, start, queue)
  let result = { seed, queue }
  proof_assert bfs_seed_post(vertices, edges, start, result.seed)
  proof_assert bfs_queue_seed_post(vertices, start, result.queue)
  proof_assert bfs_init_post(vertices, edges, start, result)
  result
}

///|
pub fn enqueue_one(
  vertices : Int,
  state : BfsQueue,
  vertex : Int,
) -> BfsQueue where {
  proof_require: valid_vertex_count(vertices),
  proof_require: queue_bounds(vertices, state),
  proof_require: queue_valid_prefix(vertices, state, state.tail),
  proof_require: valid_vertex(vertices, vertex),
  proof_require: state.tail < vertices,
  proof_ensure: result => enqueue_valid_post(vertices, state, vertex, result),
} {
  state.queue[state.tail] = vertex
  proof_assert queue_shape(vertices, state.queue)
  proof_assert state.queue[state.tail] == vertex
  proof_assert ∀ i : Int,
    0 <= i && i < state.tail → valid_vertex(vertices, state.queue[i])
  let queue = state.queue
  let head = state.head
  let tail = state.tail + 1
  proof_assert tail <= vertices
  let result = { queue, head, tail }
  proof_assert result.head == state.head
  proof_assert result.tail == state.tail + 1
  proof_assert result.queue[state.tail] == vertex
  proof_assert queue_bounds(vertices, result)
  proof_assert ∀ i : Int,
    0 <= i && i < result.tail → valid_vertex(vertices, result.queue[i])
  proof_assert queue_valid_prefix(vertices, result, result.tail)
  proof_assert enqueue_post(vertices, state, vertex, result)
  proof_assert enqueue_valid_post(vertices, state, vertex, result)
  result
}

///|
pub fn dequeue_one(
  vertices : Int,
  state : BfsQueue,
) -> BfsDequeue where {
  proof_require: valid_vertex_count(vertices),
  proof_require: queue_bounds(vertices, state),
  proof_require: queue_valid_prefix(vertices, state, state.tail),
  proof_require: state.head < state.tail,
  proof_ensure: result => dequeue_valid_post(vertices, state, result),
} {
  let vertex = state.queue[state.head]
  proof_assert valid_vertex(vertices, vertex)
  let queue_buffer = state.queue
  let head = state.head + 1
  let tail = state.tail
  proof_assert head <= tail
  let next_queue = { queue: queue_buffer, head, tail }
  proof_assert queue_shape(vertices, next_queue.queue)
  proof_assert next_queue.head == state.head + 1
  proof_assert next_queue.tail == state.tail
  proof_assert queue_bounds(vertices, next_queue)
  let queue = next_queue
  let result = { vertex, queue }
  proof_assert result.vertex == state.queue[state.head]
  proof_assert result.queue.head == state.head + 1
  proof_assert result.queue.tail == state.tail
  proof_assert queue_bounds(vertices, result.queue)
  proof_assert ∀ i : Int,
    0 <= i && i < result.queue.tail →
    valid_vertex(vertices, result.queue.queue[i])
  proof_assert queue_valid_prefix(vertices, result.queue, result.queue.tail)
  proof_assert dequeue_post(vertices, state, result)
  proof_assert dequeue_valid_post(vertices, state, result)
  result
}

///|
pub fn discover_and_enqueue_one(
  vertices : Int,
  edges : FixedArray[Int],
  visited : FixedArray[Int],
  source : Int,
  state : BfsQueue,
  upto : Int,
) -> BfsDiscoverEnqueue where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: visited_shape(vertices, visited),
  proof_require: valid_vertex(vertices, source),
  proof_require: queue_bounds(vertices, state),
  proof_require: queue_valid_prefix(vertices, state, state.tail),
  proof_require: state.tail < vertices,
  proof_require: 0 <= upto,
  proof_require: upto <= vertices,
  proof_ensure: result => {
    discover_enqueue_post(vertices, edges, visited, source, upto, state, result)
  },
  proof_ensure: result => {
    discover_prefix_post(
      vertices,
      edges,
      visited,
      source,
      upto,
      result.candidate,
    )
  },
  proof_ensure: result => queue_bounds(vertices, result.queue),
  proof_ensure: result => {
    queue_valid_prefix(vertices, result.queue, result.queue.tail)
  },
  proof_ensure: result => result.queue.head == state.head,
  proof_ensure: result => state.tail <= result.queue.tail,
  proof_ensure: result => result.queue.tail <= state.tail + 1,
  proof_ensure: result => {
    !(result.candidate < vertices) || result.queue.tail == state.tail + 1
  },
  proof_ensure: result => {
    !(vertices <= result.candidate) || result.queue.tail == state.tail
  },
} {
  let candidate = discover_first_unmarked_out_edge_prefix(
    vertices, edges, visited, source, upto,
  )
  proof_assert discover_prefix_post(
    vertices, edges, visited, source, upto, candidate,
  )
  if candidate < vertices {
    proof_assert valid_vertex(vertices, candidate)
    let next_queue = enqueue_one(vertices, state, candidate)
    proof_assert enqueue_valid_post(vertices, state, candidate, next_queue)
    let result = { candidate, queue: next_queue }
    proof_assert result.queue.head == state.head
    proof_assert result.queue.tail == state.tail + 1
    proof_assert state.tail <= result.queue.tail
    proof_assert result.queue.tail <= state.tail + 1
    proof_assert !(result.candidate < vertices) ||
      result.queue.tail == state.tail + 1
    proof_assert !(vertices <= result.candidate) ||
      result.queue.tail == state.tail
    proof_assert discover_prefix_post(
      vertices,
      edges,
      visited,
      source,
      upto,
      result.candidate,
    )
    proof_assert enqueue_valid_post(
      vertices,
      state,
      result.candidate,
      result.queue,
    )
    proof_assert discover_enqueue_post(
      vertices, edges, visited, source, upto, state, result,
    )
    result
  } else {
    proof_assert vertices <= candidate
    let result = { candidate, queue: state }
    proof_assert queue_bounds(vertices, result.queue)
    proof_assert queue_valid_prefix(vertices, result.queue, result.queue.tail)
    proof_assert result.queue.head == state.head
    proof_assert result.queue.tail == state.tail
    proof_assert state.tail <= result.queue.tail
    proof_assert result.queue.tail <= state.tail + 1
    proof_assert !(result.candidate < vertices) ||
      result.queue.tail == state.tail + 1
    proof_assert !(vertices <= result.candidate) ||
      result.queue.tail == state.tail
    proof_assert discover_enqueue_post(
      vertices, edges, visited, source, upto, state, result,
    )
    result
  }
}

///|
pub fn pop_discover_and_enqueue_one(
  vertices : Int,
  edges : FixedArray[Int],
  visited : FixedArray[Int],
  state : BfsQueue,
  upto : Int,
) -> BfsPopDiscoverEnqueue where {
  proof_require: valid_vertex_count(vertices),
  proof_require: adjacency_shape(vertices, edges),
  proof_require: visited_shape(vertices, visited),
  proof_require: queue_bounds(vertices, state),
  proof_require: queue_valid_prefix(vertices, state, state.tail),
  proof_require: state.head < state.tail,
  proof_require: state.tail < vertices,
  proof_require: 0 <= upto,
  proof_require: upto <= vertices,
  proof_ensure: result => {
    pop_discover_enqueue_post(vertices, edges, visited, upto, state, result)
  },
} {
  let popped = dequeue_one(vertices, state)
  proof_assert dequeue_valid_post(vertices, state, popped)
  proof_assert valid_vertex(vertices, popped.vertex)
  proof_assert popped.vertex == state.queue[state.head]
  proof_assert queue_bounds(vertices, popped.queue)
  proof_assert queue_valid_prefix(vertices, popped.queue, popped.queue.tail)
  proof_assert popped.queue.head == state.head + 1
  proof_assert popped.queue.tail == state.tail
  proof_assert popped.queue.tail < vertices
  let expanded = discover_and_enqueue_one(
    vertices,
    edges,
    visited,
    popped.vertex,
    popped.queue,
    upto,
  )
  proof_assert discover_enqueue_post(
    vertices,
    edges,
    visited,
    popped.vertex,
    upto,
    popped.queue,
    expanded,
  )
  let result = {
    source: popped.vertex,
    candidate: expanded.candidate,
    queue: expanded.queue,
  }
  proof_assert result.queue.head == popped.queue.head
  proof_assert result.queue.head == state.head + 1
  proof_assert popped.queue.tail <= result.queue.tail
  proof_assert result.queue.tail <= popped.queue.tail + 1
  proof_assert state.tail <= result.queue.tail
  proof_assert result.queue.tail <= state.tail + 1
  proof_assert !(result.candidate < vertices) ||
    result.queue.tail == state.tail + 1
  proof_assert !(vertices <= result.candidate) ||
    result.queue.tail == state.tail
  proof_assert valid_vertex(vertices, result.source)
  proof_assert discover_prefix_post(
    vertices,
    edges,
    visited,
    result.source,
    upto,
    result.candidate,
  )
  proof_assert queue_bounds(vertices, result.queue)
  proof_assert queue_valid_prefix(vertices, result.queue, result.queue.tail)
  proof_assert pop_discover_enqueue_post(
    vertices, edges, visited, upto, state, result,
  )
  result
}
