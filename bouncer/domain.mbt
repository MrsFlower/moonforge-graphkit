///|
/// The two verification domains MoonForge specializes in. Anything that
/// does not clearly match either is `Unclassified`, which the caller
/// should treat as "do not inject domain-specific prior rules" rather than
/// guessing.
pub(all) enum Domain {
  Defi
  Graph
  Unclassified
} derive(Show, Debug, Eq)

///|
/// Reason a source file was rejected before ever reaching the LLM.
pub(all) enum RejectionReason {
  /// The file imports a package known to perform I/O, process spawning,
  /// or other externally-visible side effects, which formal verification
  /// targets in this project are not designed to reason about.
  SideEffectingImport(pkg_name~ : String)
  /// The file's body calls a function commonly associated with side
  /// effects (printing, filesystem access, process control) even though
  /// the import itself might be indirect.
  SideEffectingCall(call~ : String)
} derive(Show, Debug, Eq)

///|
/// Packages that indicate the file under review is not a pure
/// computation and therefore out of scope for this project's proof
/// pipeline (which only targets pure algorithmic/state-machine code).
let side_effecting_imports : Array[String] = [
  "moonbitlang/async", "moonbitlang/core/env", "moonbitlang/async/fs", "moonbitlang/async/process",
  "moonbitlang/async/http", "moonbitlang/async/stdio", "moonbitlang/async/socket",
]

///|
/// Call substrings commonly associated with side effects. This is a
/// deliberately coarse lexical check, not a real effect analysis: it
/// exists to reject obviously-impure submissions early, not to certify
/// purity.
let side_effecting_calls : Array[String] = [
  "println(", "@fs.", "@process.", "@env.get_env_var", "@env.set_env_var", "@http.",
]

///|
/// Check whether `source` (the full contents of a `.mbt` file, including
/// its `moon.pkg`-declared imports if the caller chooses to concatenate
/// them) looks like a side-effect-free candidate for formal verification.
/// Returns every reason found, empty when nothing suspicious was
/// detected — an empty result is not a purity proof, only the absence of
/// this coarse check's red flags.
pub fn check_purity(source : String) -> Array[RejectionReason] {
  let reasons = []
  for pkg in side_effecting_imports {
    if source.contains(pkg) {
      reasons.push(SideEffectingImport(pkg_name=pkg))
    }
  }
  for call in side_effecting_calls {
    if source.contains(call) {
      reasons.push(SideEffectingCall(call~))
    }
  }
  reasons
}

///|
/// Keywords that suggest a DeFi/financial verification target: fixed-point
/// arithmetic, pool/collateral accounting, price math, and similar.
let defi_keywords : Array[String] = [
  "price", "liquidity", "collateral", "sqrt_price", "reserve", "swap", "mint", "burn",
  "vault", "ltv", "margin", "liquidat", "solvency", "tick",
]

///|
/// Keywords that suggest a graph/pathfinding verification target.
let graph_keywords : Array[String] = [
  "graph", "node", "edge", "path", "heuristic", "neighbor", "frontier", "visited",
  "open_set", "closed_set", "dijkstra", "astar", "a_star",
]

///|
/// Classify `source` into one of the two specialized domains by counting
/// case-insensitive keyword hits. Ties, and the all-zero case, resolve to
/// `Unclassified` rather than guessing — the caller should fall back to a
/// domain-neutral prompt in that case instead of injecting misleading
/// prior rules.
pub fn classify_domain(source : String) -> Domain {
  let lowered = source.to_lower()
  let defi_hits = count_hits(lowered, defi_keywords)
  let graph_hits = count_hits(lowered, graph_keywords)
  if defi_hits == 0 && graph_hits == 0 {
    Unclassified
  } else if defi_hits > graph_hits {
    Defi
  } else if graph_hits > defi_hits {
    Graph
  } else {
    Unclassified
  }
}

///|
fn count_hits(lowered_source : String, keywords : Array[String]) -> Int {
  let mut count = 0
  for keyword in keywords {
    if lowered_source.contains(keyword) {
      count = count + 1
    }
  }
  count
}
