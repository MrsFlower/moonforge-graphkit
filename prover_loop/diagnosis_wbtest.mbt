///|
/// Load a recorded `moon prove` fixture pair (stdout+stderr text, and its
/// optional companion `.proof.json`) from `fixtures/recorded_prove_outputs/`.
/// Paths are relative to the module root, matching how `moon test` runs.
async fn load_fixture(base_name : String) -> ProveOutcome {
  let text_path = "fixtures/recorded_prove_outputs/" + base_name + ".txt"
  let json_path = "fixtures/recorded_prove_outputs/" + base_name + ".proof.json"
  let text = @fs.read_file(text_path).text()
  let proof_json = if @fs.exists(json_path) {
    Some(@json.parse(@fs.read_file(json_path).text()))
  } else {
    None
  }
  { exit_code: 1, stdout: text, stderr: "", proof_json }
}

///|
async test "classify recognizes the real recorded syntax error fixture" {
  let outcome = load_fixture("syntax_error")
  assert_eq(classify(outcome), SyntaxError)
}

///|
/// Real failure recorded while testing the `batch_auction` end-to-end
/// challenge: the LLM emitted the older toolchain's bare `invariant: ...,`
/// field instead of this toolchain's `proof_invariant: ...,`, which
/// `moonc prove` rejects before Why3 ever runs. This must classify as
/// `SyntaxError` (not `Unknown`) so `build_repair_instructions` picks the
/// syntax-specific repair message that names the `proof_invariant` fix.
async test "classify recognizes the legacy `invariant:` field as a SyntaxError" {
  let outcome = load_fixture("legacy_invariant_syntax_error")
  assert_eq(classify(outcome), SyntaxError)
}

///|
async test "classify recognizes the real recorded false-postcondition fixture as Unproved" {
  let outcome = load_fixture("assertion_failed_or_timeout")
  let kind = classify(outcome)
  guard kind is Unproved(has_invalid~, timeout_goals~, ..) else {
    fail("expected Unproved, got a different FailureKind")
  }
  assert_eq(has_invalid, false)
  assert_eq(timeout_goals, 1)
}

///|
test "classify_from_report reports Unproved with the right goal counts" {
  let report = @json.parse(
    (
      #|{"result":"proof_failure","summary":{"valid":8,"invalid":0,"timeout":1,"oom":0,"step_limit":0,"unknown":0,"failure":0}}
    ),
  )
  let kind = classify_from_report(report)
  assert_eq(kind, Unproved(has_invalid=false, timeout_goals=1, unknown_goals=0))
}

///|
test "classify_from_report reports Unknown when nothing actually failed" {
  let report = @json.parse(
    (
      #|{"result":"success","summary":{"valid":1,"invalid":0,"timeout":0,"oom":0,"step_limit":0,"unknown":0,"failure":0}}
    ),
  )
  assert_eq(classify_from_report(report), Unknown)
}

///|
test "classify_from_text recognizes a Why3 server crash" {
  let text = "Connection error: client_connect: connection failed: No such file or directory (socket_name=/var/.../why3server...sock)"
  assert_eq(classify_from_text(text), ProverCrashed)
}

///|
test "classify_from_text recognizes a moonc prove internal compiler error" {
  let text = "Error: Invalid_argument(\"String.sub / Bytes.sub\")"
  assert_eq(classify_from_text(text), ProverCrashed)
}

///|
test "classify_from_text falls back to Unknown for unrecognized output" {
  let text = "something completely unexpected happened"
  assert_eq(classify_from_text(text), Unknown)
}

///|
async test "classify recognizes the real recorded success fixtures as not-failed via proof_json" {
  // Success fixtures are included for completeness of the fixture set;
  // classify() is only meaningful for outcomes already known to have
  // failed, so here we only check that the report's own summary shows an
  // all-valid outcome (0 invalid/timeout/unknown), which is what the
  // caller uses to decide *not* to call classify() at all.
  let outcome = load_fixture("success_isqrt")
  guard outcome.proof_json is Some(Object(fields)) else {
    fail("expected a parsed proof.json for success_isqrt fixture")
  }
  guard fields.get("summary") is Some(Object(summary)) else {
    fail("expected a summary object")
  }
  assert_eq(int_field(summary, "valid"), 1)
  assert_eq(int_field(summary, "timeout"), 0)
  assert_eq(int_field(summary, "invalid"), 0)
}
