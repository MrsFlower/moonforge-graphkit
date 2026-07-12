///|
test "check_purity accepts a pure function with no flagged imports or calls" {
  let source =
    #|pub fn isqrt(n : Int) -> Int {
    #|  for lo = 0, hi = n + 1; lo < hi - 1; {
    #|    let mid = lo + (hi - lo) / 2
    #|    if mid * mid <= n { continue mid, hi } else { continue lo, mid }
    #|  } nobreak { lo }
    #|}
  let reasons = @bouncer.check_purity(source)
  assert_eq(reasons, [])
}

///|
test "check_purity flags a side-effecting import" {
  let source =
    #|import {
    #|  "moonbitlang/async/process",
    #|}
    #|pub fn f() -> Unit { () }
  let reasons = @bouncer.check_purity(source)
  assert_true(
    reasons.contains(SideEffectingImport(pkg_name="moonbitlang/async/process")),
  )
}

///|
test "check_purity flags a side-effecting call even without a visible import line" {
  let source = "pub fn f() -> Unit { println(\"hi\") }"
  let reasons = @bouncer.check_purity(source)
  assert_true(reasons.contains(SideEffectingCall(call="println(")))
}

///|
test "check_purity can flag multiple reasons at once" {
  let source =
    #|import {
    #|  "moonbitlang/async/fs",
    #|}
    #|pub fn f() -> Unit { println("hi") }
  let reasons = @bouncer.check_purity(source)
  assert_true(
    reasons.contains(SideEffectingImport(pkg_name="moonbitlang/async/fs")),
  )
  assert_true(reasons.contains(SideEffectingCall(call="println(")))
}

///|
test "classify_domain recognizes DeFi keywords" {
  let source =
    #|pub fn swap(reserve_in : Int, reserve_out : Int, amount_in : Int) -> Int {
    #|  reserve_out * amount_in / (reserve_in + amount_in)
    #|}
  assert_eq(@bouncer.classify_domain(source), Defi)
}

///|
test "classify_domain recognizes graph keywords" {
  let source =
    #|pub fn astar(graph : Graph, start : Node, goal : Node) -> Path? {
    #|  let open_set = [start]
    #|  let visited = []
    #|  None
    #|}
  assert_eq(@bouncer.classify_domain(source), Graph)
}

///|
test "classify_domain returns Unclassified when no keywords match" {
  let source =
    #|pub fn add(a : Int, b : Int) -> Int {
    #|  a + b
    #|}
  assert_eq(@bouncer.classify_domain(source), Unclassified)
}

///|
test "classify_domain returns Unclassified on an exact tie" {
  // one DeFi keyword ("price"), one graph keyword ("node"): a tie should
  // not be resolved by guessing.
  let source = "price node"
  assert_eq(@bouncer.classify_domain(source), Unclassified)
}

///|
test "build_prompt injects DeFi prior rules for the Defi domain" {
  let prompt = @bouncer.build_prompt(Defi, "verify this swap function")
  assert_true(prompt.system_prompt.contains("DeFi / financial state machines"))
  assert_true(prompt.system_prompt.contains("non-negativity"))
  assert_eq(prompt.user_task, "verify this swap function")
}

///|
test "build_prompt injects graph prior rules for the Graph domain" {
  let prompt = @bouncer.build_prompt(Graph, "verify this pathfinder")
  assert_true(prompt.system_prompt.contains("graph / pathfinding algorithms"))
  assert_true(prompt.system_prompt.contains("disjoint"))
  assert_true(prompt.system_prompt.contains("length1"))
  assert_true(prompt.system_prompt.contains("one edge relaxation"))
  assert_true(prompt.system_prompt.contains("defensive"))
}

///|
test "build_prompt falls back to neutral rules for Unclassified" {
  let prompt = @bouncer.build_prompt(Unclassified, "verify this function")
  assert_true(prompt.system_prompt.contains("No domain-specific prior rules"))
  assert_true(!prompt.system_prompt.contains("DeFi / financial state machines"))
  assert_true(!prompt.system_prompt.contains("graph / pathfinding algorithms"))
}

///|
test "build_prompt always includes the shared baseline constraints" {
  let prompt = @bouncer.build_prompt(Defi, "task")
  assert_true(prompt.system_prompt.contains("proof_require"))
  assert_true(prompt.system_prompt.contains("single fenced code block"))
}
