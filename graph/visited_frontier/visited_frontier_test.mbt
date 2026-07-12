///|
test "mark vertex" {
  let visited = FixedArray::make(4, 0)
  assert_false(@visited_frontier.is_marked(4, visited, 2))
  @visited_frontier.mark_vertex(4, visited, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "mark vertex preserves marked" {
  let visited = FixedArray::make(4, 0)
  @visited_frontier.mark_vertex(4, visited, 1)
  @visited_frontier.mark_vertex_preserve_marked(4, visited, 3, 1)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 3))
}

///|
test "discover first unmarked out edge prefix" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  assert_eq(
    @visited_frontier.discover_first_unmarked_out_edge_prefix(
      4, edges, visited, 0, 4,
    ),
    2,
  )
  assert_true(@visited_frontier.is_marked(4, visited, 2))
  assert_eq(
    @visited_frontier.discover_first_unmarked_out_edge_prefix(
      4, edges, visited, 3, 4,
    ),
    4,
  )
}

///|
test "discover first unmarked out edge prefix preserves marked" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  let found = @visited_frontier.discover_first_unmarked_out_edge_prefix_preserve_marked(
    4, edges, visited, 0, 4, 1,
  )
  assert_eq(found, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "mark out neighbors prefix" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[3] = 1
  let visited = FixedArray::make(4, 0)
  @visited_frontier.mark_out_neighbors_prefix(4, edges, visited, 0, 3)
  assert_false(@visited_frontier.is_marked(4, visited, 0))
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_false(@visited_frontier.is_marked(4, visited, 2))
  assert_false(@visited_frontier.is_marked(4, visited, 3))
  @visited_frontier.mark_out_neighbors_prefix(4, edges, visited, 0, 4)
  assert_true(@visited_frontier.is_marked(4, visited, 3))
}

///|
test "seed start and neighbors" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[3] = 1
  let visited = @visited_frontier.seed_start_and_neighbors(4, edges, 0)
  assert_true(@visited_frontier.is_marked(4, visited, 0))
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_false(@visited_frontier.is_marked(4, visited, 2))
  assert_true(@visited_frontier.is_marked(4, visited, 3))
}

///|
test "seed start neighbor parents" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[3] = 1
  let parent = @visited_frontier.seed_start_neighbor_parents(4, edges, 0)
  assert_eq(@visited_frontier.parent_of(4, parent, 0), 0)
  assert_eq(@visited_frontier.parent_of(4, parent, 1), 0)
  assert_eq(@visited_frontier.parent_of(4, parent, 2), 4)
  assert_eq(@visited_frontier.parent_of(4, parent, 3), 0)
}

///|
test "seed start layer" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[3] = 1
  let seed = @visited_frontier.seed_start_layer(4, edges, 0)
  assert_true(@visited_frontier.is_marked(4, seed.visited, 0))
  assert_true(@visited_frontier.is_marked(4, seed.visited, 1))
  assert_false(@visited_frontier.is_marked(4, seed.visited, 2))
  assert_true(@visited_frontier.is_marked(4, seed.visited, 3))
  assert_eq(@visited_frontier.parent_of(4, seed.parent, 0), 0)
  assert_eq(@visited_frontier.parent_of(4, seed.parent, 1), 0)
  assert_eq(@visited_frontier.parent_of(4, seed.parent, 2), 4)
  assert_eq(@visited_frontier.parent_of(4, seed.parent, 3), 0)
}

///|
test "seed start queue" {
  let queue = @visited_frontier.seed_start_queue(4, 2)
  assert_eq(queue.head, 0)
  assert_eq(queue.tail, 1)
  assert_eq(queue.queue[0], 2)
}

///|
test "init start frontier" {
  let edges = FixedArray::make(16, 0)
  edges[1] = 1
  edges[3] = 1
  let init = @visited_frontier.init_start_frontier(4, edges, 0)
  assert_eq(init.queue.head, 0)
  assert_eq(init.queue.tail, 1)
  assert_eq(init.queue.queue[0], 0)
  assert_true(@visited_frontier.is_marked(4, init.seed.visited, 1))
  assert_eq(@visited_frontier.parent_of(4, init.seed.parent, 3), 0)
}

///|
test "enqueue one" {
  let queue = @visited_frontier.seed_start_queue(4, 2)
  let queue2 = @visited_frontier.enqueue_one(4, queue, 3)
  assert_eq(queue2.head, 0)
  assert_eq(queue2.tail, 2)
  assert_eq(queue2.queue[0], 2)
  assert_eq(queue2.queue[1], 3)
}

///|
test "enqueue one preserves marked prefix" {
  let visited = FixedArray::make(4, 0)
  visited[2] = 1
  visited[3] = 1
  let queue = @visited_frontier.seed_start_queue(4, 2)
  let queue2 = @visited_frontier.enqueue_one_preserve_marked_prefix(
    4, visited, queue, 3,
  )
  assert_eq(queue2.head, 0)
  assert_eq(queue2.tail, 2)
  assert_eq(queue2.queue[0], 2)
  assert_eq(queue2.queue[1], 3)
  assert_true(@visited_frontier.is_marked(4, visited, queue2.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, queue2.queue[1]))
}

///|
test "dequeue one" {
  let queue = @visited_frontier.seed_start_queue(4, 2)
  let queue2 = @visited_frontier.enqueue_one(4, queue, 3)
  let first = @visited_frontier.dequeue_one(4, queue2)
  assert_eq(first.vertex, 2)
  assert_eq(first.queue.head, 1)
  assert_eq(first.queue.tail, 2)
  let second = @visited_frontier.dequeue_one(4, first.queue)
  assert_eq(second.vertex, 3)
  assert_eq(second.queue.head, 2)
  assert_eq(second.queue.tail, 2)
}

///|
test "dequeue one preserves marked prefix" {
  let visited = FixedArray::make(4, 0)
  visited[2] = 1
  visited[3] = 1
  let queue = @visited_frontier.seed_start_queue(4, 2)
  let queue2 = @visited_frontier.enqueue_one_preserve_marked_prefix(
    4, visited, queue, 3,
  )
  let first = @visited_frontier.dequeue_one_preserve_marked_prefix(
    4, visited, queue2,
  )
  assert_eq(first.vertex, 2)
  assert_eq(first.queue.head, 1)
  assert_eq(first.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, first.queue.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, first.queue.queue[1]))
}

///|
test "discover and enqueue one" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let expanded = @visited_frontier.discover_and_enqueue_one(
    4, edges, visited, 0, queue, 4,
  )
  assert_eq(expanded.candidate, 2)
  assert_eq(expanded.queue.head, 0)
  assert_eq(expanded.queue.tail, 2)
  assert_eq(expanded.queue.queue[1], 2)
  assert_true(@visited_frontier.is_marked(4, visited, 2))
  let no_more = @visited_frontier.discover_and_enqueue_one(
    4,
    edges,
    visited,
    0,
    expanded.queue,
    4,
  )
  assert_eq(no_more.candidate, 4)
  assert_eq(no_more.queue.tail, 2)
}

///|
test "discover and enqueue one preserves marked" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let expanded = @visited_frontier.discover_and_enqueue_one_preserve_marked(
    4, edges, visited, 0, queue, 4, 1,
  )
  assert_eq(expanded.candidate, 2)
  assert_eq(expanded.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "discover and enqueue one preserves marked prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[0] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let expanded = @visited_frontier.discover_and_enqueue_one_preserve_marked_prefix(
    4, edges, visited, 0, queue, 4,
  )
  assert_eq(expanded.candidate, 2)
  assert_eq(expanded.queue.head, 0)
  assert_eq(expanded.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, expanded.queue.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, expanded.queue.queue[1]))
}

///|
test "pop discover and enqueue one" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let step = @visited_frontier.pop_discover_and_enqueue_one(
    4, edges, visited, queue, 4,
  )
  assert_eq(step.source, 0)
  assert_eq(step.candidate, 2)
  assert_eq(step.queue.head, 1)
  assert_eq(step.queue.tail, 2)
  assert_eq(step.queue.queue[1], 2)
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "pop discover and enqueue one preserves marked" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let step = @visited_frontier.pop_discover_and_enqueue_one_preserve_marked(
    4, edges, visited, queue, 4, 1,
  )
  assert_eq(step.source, 0)
  assert_eq(step.candidate, 2)
  assert_eq(step.queue.head, 1)
  assert_eq(step.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "pop discover and enqueue one preserves marked prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[0] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let step = @visited_frontier.pop_discover_and_enqueue_one_preserve_marked_prefix(
    4, edges, visited, queue, 4,
  )
  assert_eq(step.source, 0)
  assert_eq(step.candidate, 2)
  assert_eq(step.queue.head, 1)
  assert_eq(step.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, step.queue.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, step.queue.queue[1]))
}

///|
test "guarded pop expand one" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let ready = @visited_frontier.guarded_pop_expand_one(
    4, edges, visited, queue, 4,
  )
  assert_eq(ready.head, 1)
  assert_eq(ready.tail, 2)
  assert_eq(ready.queue[1], 2)
  let empty = @visited_frontier.dequeue_one(
      4,
      @visited_frontier.seed_start_queue(4, 1),
    ).queue
  let unchanged = @visited_frontier.guarded_pop_expand_one(
    4, edges, visited, empty, 4,
  )
  assert_eq(unchanged.head, empty.head)
  assert_eq(unchanged.tail, empty.tail)
}

///|
test "guarded pop expand one preserves marked" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let ready = @visited_frontier.guarded_pop_expand_one_preserve_marked(
    4, edges, visited, queue, 4, 1,
  )
  assert_eq(ready.head, 1)
  assert_eq(ready.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "guarded pop expand one preserves marked prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[0] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let ready = @visited_frontier.guarded_pop_expand_one_preserve_marked_prefix(
    4, edges, visited, queue, 4,
  )
  assert_eq(ready.head, 1)
  assert_eq(ready.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, ready.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, ready.queue[1]))
}

///|
test "guarded pop expand steps" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let done = @visited_frontier.guarded_pop_expand_steps(
    4, edges, visited, queue, 4, 2,
  )
  assert_eq(done.head, 2)
  assert_eq(done.tail, 2)
  assert_eq(done.queue[1], 2)
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "guarded pop expand steps preserves marked" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[1] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let done = @visited_frontier.guarded_pop_expand_steps_preserve_marked(
    4, edges, visited, queue, 4, 2, 1,
  )
  assert_eq(done.head, 2)
  assert_eq(done.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 1))
  assert_true(@visited_frontier.is_marked(4, visited, 2))
}

///|
test "guarded pop expand steps preserves marked prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let visited = FixedArray::make(4, 0)
  visited[0] = 1
  let queue = @visited_frontier.seed_start_queue(4, 0)
  let done = @visited_frontier.guarded_pop_expand_steps_preserve_marked_prefix(
    4, edges, visited, queue, 4, 2,
  )
  assert_eq(done.head, 2)
  assert_eq(done.tail, 2)
  assert_true(@visited_frontier.is_marked(4, visited, done.queue[0]))
  assert_true(@visited_frontier.is_marked(4, visited, done.queue[1]))
}

///|
test "seed and expand queue steps" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let queue = @visited_frontier.seed_and_expand_queue_steps(4, edges, 0, 2)
  assert_eq(queue.head, 2)
  assert_eq(queue.tail, 2)
  assert_eq(queue.queue[0], 0)
  assert_eq(queue.queue[1], 2)
}

///|
test "seed and expand steps returns visited" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let expanded = @visited_frontier.seed_and_expand_steps(4, edges, 0, 2)
  assert_eq(expanded.queue.head, 2)
  assert_eq(expanded.queue.tail, 2)
  assert_true(@visited_frontier.is_marked(4, expanded.visited, 0))
  assert_true(@visited_frontier.is_marked(4, expanded.visited, 2))
  assert_false(@visited_frontier.is_marked(4, expanded.visited, 1))
}

///|
test "seed and expand steps preserves marked prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  let expanded = @visited_frontier.seed_and_expand_steps_preserve_marked_prefix(
    4, edges, 0, 2,
  )
  assert_eq(expanded.queue.head, 2)
  assert_eq(expanded.queue.tail, 2)
  assert_true(
    @visited_frontier.is_marked(4, expanded.visited, expanded.queue.queue[0]),
  )
  assert_true(
    @visited_frontier.is_marked(4, expanded.visited, expanded.queue.queue[1]),
  )
}

///|
test "seed start only state" {
  let seed = @visited_frontier.seed_start_only_state(4, 2)
  assert_eq(seed.queue.head, 0)
  assert_eq(seed.queue.tail, 1)
  assert_eq(seed.queue.queue[0], 2)
  assert_true(@visited_frontier.is_marked(4, seed.visited, 2))
  assert_false(@visited_frontier.is_marked(4, seed.visited, 0))
}
