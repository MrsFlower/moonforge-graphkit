///|
/// Classification of why a `moon prove` run failed. Chosen based on real
/// recorded output (see `fixtures/recorded_prove_outputs/`), not just the
/// four categories the original design sketch assumed:
///
/// - `SyntaxError` covers both MoonBit-level parse/type errors and
///   `.mbtp` predicate-syntax errors. These abort before Why3 ever runs,
///   so there is no `.proof.json` report at all — classification here is
///   necessarily text-based.
/// - `Unproved` covers every case where Why3 ran but at least one goal did
///   not come back `valid`. Note that in the toolchain version this
///   project has verified against, a *false* postcondition or invariant
///   does not reliably come back as a clean SMT "invalid, here is a
///   counterexample" — it comes back `Timeout`/`Unknown`, the same as a
///   goal that is actually true but too hard for the solvers in the time
///   given. `Unproved` therefore does not attempt to distinguish "this is
///   provably false" from "the solver gave up"; both need the same next
///   step (strengthen or fix the invariant/predicate), so the repair
///   prompt does not need to tell them apart to be useful. `has_invalid`
///   is still surfaced separately for the rare case a future toolchain
///   version *does* return a clean counterexample, so `repair_prompt` can
///   choose a more targeted message when that information is available.
/// - `ProverCrashed` covers the toolchain-robustness failures recorded in
///   this project's own `TODO.md` (Why3 server socket errors, `moonc
///   prove` internal compiler errors) — these need a retry or a smaller
///   reproducer, not a code fix.
/// - `Unknown` is the honest fallback when nothing matched; callers should
///   surface the raw output for human review rather than guessing.
pub(all) enum FailureKind {
  SyntaxError
  Unproved(has_invalid~ : Bool, timeout_goals~ : Int, unknown_goals~ : Int)
  ProverCrashed
  Unknown
} derive(Show, Debug, Eq)

///|
/// Classify a `ProveOutcome` that is already known to represent a failure
/// (non-zero exit code, or a `.proof.json` whose `result` is not
/// `"success"`). Callers should check `exit_code == 0` separately for the
/// success path; this function does not re-derive success/failure, only
/// the failure category.
pub fn classify(outcome : ProveOutcome) -> FailureKind {
  match outcome.proof_json {
    Some(report) => classify_from_report(report)
    None => classify_from_text(outcome.stdout + "\n" + outcome.stderr)
  }
}

///|
/// Classify using the structured `.proof.json` report, which is available
/// whenever `moon prove` got far enough to invoke Why3. Preferred over
/// text matching because the solver verdicts are exposed directly as
/// data, rather than needing to be parsed back out of a human-readable
/// rendering.
fn classify_from_report(report : Json) -> FailureKind {
  guard report is Object(fields) else { return Unknown }
  guard fields.get("summary") is Some(Object(summary)) else { return Unknown }
  let invalid = int_field(summary, "invalid")
  let timeout = int_field(summary, "timeout")
  let unknown = int_field(summary, "unknown")
  let step_limit = int_field(summary, "step_limit")
  let oom = int_field(summary, "oom")
  let failure = int_field(summary, "failure")
  if timeout + unknown + step_limit + oom + failure + invalid == 0 {
    // Nothing failed according to the report; this should not happen for
    // a `ProveOutcome` the caller already believes failed, but fall back
    // to Unknown rather than asserting success on the caller's behalf.
    Unknown
  } else {
    Unproved(
      has_invalid=invalid > 0,
      timeout_goals=timeout,
      unknown_goals=unknown,
    )
  }
}

///|
fn int_field(fields : Map[String, Json], key : String) -> Int {
  match fields.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// Classify using only the terminal text, for the cases where `moon
/// prove`/`moonc prove` aborted before producing a `.proof.json` (a
/// MoonBit-level parse/type error, or an `.mbtp` predicate-syntax error).
/// The substrings matched here are taken from real recorded output in
/// `fixtures/recorded_prove_outputs/syntax_error.txt` and from the
/// toolchain-robustness issues recorded in this project's own `TODO.md`
/// (Why3 server socket errors, `moonc prove` internal compiler errors).
fn classify_from_text(text : String) -> FailureKind {
  let syntax_markers = [
    "Parsing error", "UnexpectedToken", "unexpected id", "is unbound", "Unexpected line break",
    "unsupported expression in contracted function body", "only local contracted functions and primitive operators can be called",
    "Invalid field", "in where clause",
  ]
  let crash_markers = [
    "why3server", "Connection error", "Invalid_argument", "Internal Error", "Invalid_argument(\"String.sub",
  ]
  if syntax_markers.iter().any(marker => text.contains(marker)) {
    SyntaxError
  } else if crash_markers.iter().any(marker => text.contains(marker)) {
    ProverCrashed
  } else {
    Unknown
  }
}
