///|
async test "build_repair_instructions for SyntaxError includes the raw compiler output" {
  let outcome = load_fixture("syntax_error")
  let kind = classify(outcome)
  let instructions = build_repair_instructions(kind, outcome)
  assert_true(instructions.contains("syntax error"))
  assert_true(instructions.contains("is unbound"))
}

///|
async test "build_repair_instructions for Unproved without a counterexample warns about ambiguity" {
  let outcome = load_fixture("assertion_failed_or_timeout")
  let kind = classify(outcome)
  let instructions = build_repair_instructions(kind, outcome)
  assert_true(
    instructions.contains("No goal came back with an explicit counterexample"),
  )
  assert_true(
    instructions.contains(
      "first double check whether the stated property is actually true",
    ),
  )
}

///|
test "build_repair_instructions for Unproved with a counterexample points at falsity, not just difficulty" {
  let outcome : ProveOutcome = {
    exit_code: 1,
    stdout: "",
    stderr: "",
    proof_json: None,
  }
  let kind = Unproved(has_invalid=true, timeout_goals=0, unknown_goals=0)
  let instructions = build_repair_instructions(kind, outcome)
  assert_true(instructions.contains("counterexample"))
  assert_true(instructions.contains("actually false as written"))
}

///|
test "build_repair_instructions for ProverCrashed recommends simplifying, not adding contracts" {
  let outcome : ProveOutcome = {
    exit_code: 1,
    stdout: "",
    stderr: "",
    proof_json: None,
  }
  let instructions = build_repair_instructions(ProverCrashed, outcome)
  assert_true(instructions.contains("toolchain robustness"))
  assert_true(instructions.contains("simplify"))
}

///|
test "build_repair_instructions for Unknown surfaces the raw output for review" {
  let outcome : ProveOutcome = {
    exit_code: 1,
    stdout: "some unrecognized failure text",
    stderr: "",
    proof_json: None,
  }
  let instructions = build_repair_instructions(Unknown, outcome)
  assert_true(instructions.contains("did not match any known"))
  assert_true(instructions.contains("some unrecognized failure text"))
}
