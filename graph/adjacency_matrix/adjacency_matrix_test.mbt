///|
test "edge index and edge query" {
  let edges = FixedArray::make(9, 0)
  edges[1] = 1
  edges[5] = 1
  assert_eq(@adjacency_matrix.vertex_capacity(3), 9)
  assert_true(@adjacency_matrix.is_valid_vertex(3, 2))
  assert_false(@adjacency_matrix.is_valid_vertex(3, 3))
  assert_eq(@adjacency_matrix.edge_index(3, 1, 2), 5)
  assert_true(@adjacency_matrix.is_edge(3, edges, 0, 1))
  assert_true(@adjacency_matrix.is_edge(3, edges, 1, 2))
  assert_false(@adjacency_matrix.is_edge(3, edges, 2, 1))
}

///|
test "find out edge prefix" {
  let edges = FixedArray::make(16, 0)
  edges[2] = 1
  edges[7] = 1
  assert_eq(@adjacency_matrix.find_out_edge_prefix(4, edges, 0, 1), 4)
  assert_eq(@adjacency_matrix.find_out_edge_prefix(4, edges, 0, 4), 2)
  assert_eq(@adjacency_matrix.find_out_edge_prefix(4, edges, 1, 4), 3)
  assert_eq(@adjacency_matrix.find_out_edge_prefix(4, edges, 2, 4), 4)
}
