///|
/// A fully-assembled prompt ready to hand to an `LlmBackend`. Keeping
/// `system_prompt` and `user_task` separate (rather than one big string)
/// lets `orchestrator` swap the domain rules on a repair round without
/// re-deriving the user's original task description.
pub struct Prompt {
  system_prompt : String
  user_task : String
} derive(Show, Debug, Eq)

///|
/// Baseline system prompt shared by every domain: constrains the model to
/// the specification syntax this project's toolchain actually accepts, so
/// it does not invent unsupported verification syntax (Rust-style macros,
/// unsupported quantifier placements, etc).
let baseline_system_prompt : String =
  #|You are generating formal-verification annotations for MoonBit code that
  #|will be checked by `moon prove` (MoonBit -> WhyML -> Why3 -> an SMT
  #|solver). Follow these hard constraints:
  #|
  #|- Use only the specification syntax already used in this codebase's own
  #|  verified examples: `proof_require`, `proof_ensure`, `proof_invariant`,
  #|  `proof_assert`, `proof_reasoning`, `proof_yield`, `proof_decrease`, the
  #|  quantifiers `∀` and `∃`, and named predicates defined in a
  #|  `.mbtp` file.
  #|- A function's precondition/postcondition MUST be attached as a `where`
  #|  clause on the function signature itself, before the opening `{` of the
  #|  function body — never as statements inside the body. The exact shape
  #|  is:
  #|
  #|  ```mbt
  #|  pub fn isqrt(n : Int) -> Int where {
  #|    proof_require: nonneg(n),
  #|    proof_ensure: result => isqrt_ok(n, result),
  #|  } {
  #|    // ... function body ...
  #|  }
  #|  ```
  #|
  #|  Note every field ends with a colon and a trailing comma, `result` is
  #|  only in scope inside `proof_ensure` (it names the return value), and
  #|  this `where { ... }` block sits between the return type and the
  #|  function body's `{`, not inside it. Writing `proof_require nonneg(n)`
  #|  as a bare statement inside the function body is invalid and will not
  #|  compile.
  #|- A loop that this toolchain can attach a `proof_invariant` block to
  #|  MUST be written with `for <vars> = <inits>; <cond>; { ... continue
  #|  <new-vars> }` and end with a single `nobreak { <result> }` block —
  #|  never a plain `while`/two-statement loop that mutates loop variables
  #|  by assignment. The exact shape is:
  #|
  #|  ```mbt
  #|  for lo = 0, hi = n + 1; lo < hi - 1; {
  #|    let mid = lo + (hi - lo) / 2
  #|    if mid * mid <= n {
  #|      continue mid, hi
  #|    } else {
  #|      continue lo, mid
  #|    }
  #|  } nobreak {
  #|    lo
  #|  } where {
  #|    proof_invariant: lo <= hi,
  #|  }
  #|  ```
  #|
  #|  Note there is exactly ONE loop body block (not a body block followed
  #|  by a second `{ ... }`), each branch that updates the loop's state
  #|  ends with `continue <new-values-in-declaration-order>` instead of
  #|  assigning to the loop variables (`lo = mid` inside the loop body is
  #|  invalid — loop variables introduced by `for <var> = <init>` are not
  #|  assignable), and the value produced when the loop condition becomes
  #|  false is written once in the trailing `nobreak { ... }` block, not
  #|  as a `return`/trailing expression after the loop.
  #|- Do NOT use the older `#requires(...)`, `#ensures(...)`, or bare
  #|  `invariant: ...,` syntax. That syntax belongs to a different, older
  #|  MoonBit toolchain version (as seen in some reference repos this
  #|  project studied) and this project's toolchain rejects it outright with
  #|  "Invalid field 'invariant' in where clause. Only 'proof_invariant',
  #|  'proof_yield', and 'proof_reasoning' are allowed." A loop's `where { }`
  #|  block in this toolchain only accepts `proof_invariant: ...,`,
  #|  `proof_yield: ...,`, and `proof_reasoning: (...)`, never bare
  #|  `invariant:`.
  #|- Do not invent new attribute syntax, macros, or annotations. If a
  #|  property cannot be expressed with the constructs above, say so instead
  #|  of guessing at new syntax.
  #|- Boolean AND/OR inside predicates, `proof_invariant`, `proof_require`,
  #|  and `proof_ensure` MUST use the logical operators `&&`/`||`, never
  #|  the bitwise operators `&`/`|` (MoonBit's `Bool` type does not
  #|  implement `&`/`|`, so `(a <= b) & (c > d)` is a type error, not a
  #|  logical-AND). Always write `(a <= b) && (c > d)`.
  #|- `∀`/`∃` must appear at the top level of a predicate body, not
  #|  nested inside `&&`/`||`. Move side conditions into the consequent of an
  #|  implication instead.
  #|- A quantified implication ("for all x satisfying P, Q holds") uses the
  #|  arrow `→`, never the plain ASCII `->` (which this toolchain parses as
  #|  MoonBit's ordinary function-arrow token, not logical implication, and
  #|  will reject inside a quantifier body). Always write
  #|  `∀ i : Int, 0 <= i && i < lo → i * i <= n`, not `... -> ...`.
  #|- Loop termination variants are only auto-generated for conditions
  #|  shaped like `loopvar < expr`. Prefer restructuring a loop into that
  #|  shape over leaving termination unproven.
  #|- Return only the requested code, inside a single fenced code block, and
  #|  nothing else: no explanations, no alternative versions, no commentary
  #|  before or after the fence.

///|
/// DeFi-specific prior rules: properties that recur across fixed-point
/// financial state machines (AMM swaps, lending, liquidation, custody).
/// Derived from this project's own finance verification examples
/// (`cpmm_swap`, `ltv_lending`, and the Uniswap V3 math references) and
/// from the known failure modes recorded for this toolchain.
let defi_prior_rules : String =
  #|Domain-specific rules for DeFi / financial state machines:
  #|
  #|- Every balance, reserve, and collateral quantity must carry an explicit
  #|  non-negativity precondition or invariant (`amount >= 0`), stated as a
  #|  named predicate rather than inlined, since `#requires`/`proof_require`
  #|  only accept predicate calls, not raw inline expressions.
  #|- Any division (fee calculations, price ratios, share accounting) must
  #|  have an explicit precondition that the denominator is non-zero, proved
  #|  or assumed before the division is reached, not discovered after the
  #|  fact.
  #|- For swap/mint/burn/liquidate operations, state a `proof_ensure` that
  #|  names the specific invariant expected to hold across the operation
  #|  (for example a constant-product relationship, or "total collateral
  #|  minus total debt does not decrease"), not just "the function returns
  #|  successfully".
  #|- Rounding must be biased in the protocol's favor consistently (for
  #|  example always rounding a fee up, never down) and that direction
  #|  should be asserted explicitly with `proof_assert` right after the
  #|  rounding operation, not left implicit.
  #|- Model this project's integers as MoonBit's native `Int`/`Int64`, not
  #|  as unbounded reals; MoonBit's own prover already treats them as
  #|  unbounded mathematical integers during verification, so do not add
  #|  unnecessary overflow-guard predicates unless the postcondition itself
  #|  depends on truncation behavior.

///|
/// Graph/pathfinding-specific prior rules: properties that recur across
/// search and shortest-path algorithms. Derived from this project's own
/// search-proof demos (`find`, `lowerbound`, `rotation_pivot`) and from the
/// A*/IDA* verification roadmap in this project's own research notes.
let graph_prior_rules : String =
  #|Domain-specific rules for graph / pathfinding algorithms:
  #|
  #|- If the algorithm tracks an "open" frontier and a "closed"/visited set,
  #|  state a `proof_invariant` that the two sets are disjoint at every loop
  #|  iteration boundary.
  #|- If the algorithm relaxes a cost array (for example Dijkstra's `g(n)` or
  #|  A*'s path cost), state a `proof_invariant` that costs for nodes already
  #|  moved to the closed set are monotonically non-increasing across the
  #|  remaining iterations, and are never improved after being closed.
  #|- For loops that traverse a graph structure (adjacency lists, priority
  #|  queues), phrase the loop condition as `loopvar < expr` wherever
  #|  possible so the termination variant can be auto-generated; if the
  #|  natural condition is not in that shape, restructure the loop rather
  #|  than leaving termination unproven, since this toolchain does not
  #|  auto-generate variants for other condition shapes.
  #|- State completeness/optimality claims (e.g. "the returned path is a
  #|  shortest path") as a named `proof_ensure` predicate, not as an inline
  #|  formula, and keep the quantifier over "every other path" at the top
  #|  level of that predicate rather than nested inside a conjunction.
  #|- Prefer proving structural facts about the search step first (a single
  #|  relaxation is correct) before attempting the global optimality
  #|  theorem across the whole search; this project's own examples show the
  #|  fully general version of such proofs is more likely to time out than
  #|  the step-local version.

///|
/// Domain-neutral fallback used when `classify_domain` returns
/// `Unclassified`. Deliberately does not inject either prior-rule library,
/// since guessing the wrong domain's rules would mislead the model more
/// than giving it none.
let neutral_prior_rules : String =
  #|No domain-specific prior rules were confidently matched for this task.
  #|Proceed using only the baseline specification constraints above; do not
  #|assume this is a DeFi or graph-search problem.

///|
/// Assemble a `Prompt` for `domain`, combining the shared baseline system
/// prompt with the domain's prior-rule library (or the neutral fallback),
/// and pairing it with the caller-supplied `user_task` description.
pub fn build_prompt(domain : Domain, user_task : String) -> Prompt {
  let domain_rules = match domain {
    Defi => defi_prior_rules
    Graph => graph_prior_rules
    Unclassified => neutral_prior_rules
  }
  { system_prompt: baseline_system_prompt + "\n\n" + domain_rules, user_task }
}
