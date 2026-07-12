///|
/// Build the extra system-prompt text to append for a repair round, given
/// the previous round's `FailureKind` and the raw `moon prove` output that
/// produced it. Returned text is meant to be appended to (not replace)
/// the domain prompt already assembled by `bouncer.build_prompt`, so the
/// domain's prior rules stay in effect across repair rounds.
pub fn build_repair_instructions(
  kind : FailureKind,
  outcome : ProveOutcome,
) -> String {
  match kind {
    SyntaxError => syntax_repair_instructions(outcome)
    Unproved(has_invalid~, timeout_goals~, unknown_goals~) =>
      unproved_repair_instructions(
        has_invalid, timeout_goals, unknown_goals, outcome,
      )
    ProverCrashed => crash_repair_instructions()
    Unknown => unknown_repair_instructions(outcome)
  }
}

///|
fn syntax_repair_instructions(outcome : ProveOutcome) -> String {
  let header =
    #|The previous attempt failed with a MoonBit/predicate syntax error, before
    #|any SMT solving happened. Fix only the syntax; do not change the
    #|intended logical meaning of the contract or invariant. Common causes in
    #|this toolchain: `proof_require`/`proof_ensure` referencing an undefined
    #|predicate name, a missing comma between clauses in a `where { ... }`
    #|block, a quantifier nested inside `&&`/`||` instead of at the top
    #|level of a predicate body, or using the bare `invariant: ...,` field
    #|from an older MoonBit toolchain version instead of this toolchain's
    #|`proof_invariant: ...,` (a loop's `where { }` block here only accepts
    #|`proof_invariant`, `proof_yield`, and `proof_reasoning`).
    #|
    #|Compiler output from the failed attempt:
    #|
  header + outcome.stdout + outcome.stderr
}

///|
fn unproved_repair_instructions(
  has_invalid : Bool,
  timeout_goals : Int,
  unknown_goals : Int,
  outcome : ProveOutcome,
) -> String {
  let invalid_note =
    #|At least one goal came back as an outright counterexample (the
    #|solver found concrete values that violate the claimed property).
    #|Treat this as strong evidence the stated contract/invariant is
    #|actually false as written, not just hard to prove: re-derive the
    #|correct property from the code rather than only strengthening the
    #|existing one.
  let no_counterexample_note =
    #|No goal came back with an explicit counterexample; every failing
    #|goal timed out or returned unknown. In this toolchain, a false
    #|postcondition or invariant and a true-but-hard-to-prove one often
    #|look identical at this level (both come back as timeout/unknown), so
    #|first double check whether the stated property is actually true for
    #|the code before assuming this is only a missing-lemma problem.
  let counterexample_note = if has_invalid {
    invalid_note
  } else {
    no_counterexample_note
  }
  let summary_line = "The previous attempt compiled to WhyML successfully, but Why3 could not discharge \{timeout_goals} timeout and \{unknown_goals} unknown goal(s)."
  let fixes =
    #|Likely fixes, roughly in order of how often they apply in this
    #|project's own verified examples:
    #|1. A loop invariant is missing a fact the postcondition needs (add a
    #|   `proof_invariant` that states the relationship between the loop
    #|   state and the goal explicitly).
    #|2. A local `proof_assert` is needed right after a branch, array
    #|   write, or loop, to give the solver an intermediate fact it cannot
    #|   derive on its own.
    #|3. The loop's termination variant was not auto-generated because the
    #|   condition is not shaped like `loopvar < expr`; restructure the
    #|   loop into that shape.
    #|4. The property itself needs a named helper lemma in the `.mbtp` file
    #|   rather than being provable directly at the call site.
    #|
    #|Raw prove output from the failed attempt:
    #|
  summary_line +
  "\n\n" +
  counterexample_note +
  "\n\n" +
  lowering_repair_note(outcome) +
  fixes +
  outcome.stdout +
  outcome.stderr
}

///|
fn lowering_repair_note(outcome : ProveOutcome) -> String {
  let combined = outcome.stdout + "\n" + outcome.stderr
  if combined.contains("length1") ||
    combined.contains("termination of this expression cannot be proved") {
    let note =
      #|This failure mentions `length1` or a loop termination/lowering warning.
      #|For MoonBit proof code in this project, that is often a frontend/lowering
      #|shape problem around mutable arrays or worklists, not a missing global
      #|invariant. Before adding more invariants, try reshaping the loop to one
      #|upward counter (`i < n`, `continue i + 1`). If that exposes many array
      #|write preservation goals, isolate one update or one edge relaxation in a
      #|small helper and compose those helpers. Use `proof_axiomatized` only as a
      #|temporary narrow bridge with concrete preconditions and a named
      #|postcondition; do not trust the whole loop.
      #|
    note
  } else {
    ""
  }
}

///|
fn crash_repair_instructions() -> String {
  let message =
    #|The prover pipeline itself crashed (a Why3 server connection error or a
    #|`moonc prove` internal error), not the code under verification. This is
    #|a toolchain robustness issue, not necessarily something wrong with the
    #|contracts. Recommended response: simplify the proof surface (fewer
    #|synchronized loop-state variables, a smaller reproducer) rather than
    #|adding more contracts, since past instances of this failure in this
    #|project were resolved by reducing complexity rather than by fixing
    #|logic.
  message
}

///|
fn unknown_repair_instructions(outcome : ProveOutcome) -> String {
  let header =
    #|The previous attempt failed in a way that did not match any known
    #|failure pattern for this toolchain. Inspect the raw output below
    #|carefully before making changes; do not assume this is the same kind
    #|of fix as a normal syntax error or unproved goal.
    #|
    #|Raw output from the failed attempt:
    #|
  header + outcome.stdout + outcome.stderr
}
