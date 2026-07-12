///|
test "mark vertex" {
  let visited = FixedArray::make(4, 0)
  assert_false(@visited_frontier.is_marked(4, visited, 2))
  @visited_frontier.mark_vertex(4, visited, 2)
  assert_true(@visited_frontier.is_marked(4, visited, 2))
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
