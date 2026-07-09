///|
/// Real fixture module for `run_check_gate`, verified by hand against this
/// project's own toolchain: `moon check valid_pkg` succeeds cleanly, and
/// `moon check broken_pkg` fails with `[4021] ... is unbound` for a
/// predicate name that is never declared in that package's `.mbtp` file
/// (see `broken_pkg/thing.mbt`'s doc comment). These tests run a real
/// `moon check` subprocess, matching this project's own testing
/// discipline of exercising the actual integration rather than mocking
/// the result.
fn fixture_module_root() -> String {
  // Resolved relative to this project's module root, matching how `moon
  // test` itself is invoked (cwd = the module containing moon.mod).
  "fixtures/target_examples/check_gate_fixture"
}

///|
async test "run_check_gate passes for a package moon check accepts" {
  let result = @prover_loop.run_check_gate(fixture_module_root(), "valid_pkg")
  assert_true(result.passed)
  assert_true(result.kind is None)
}

///|
async test "run_check_gate fails and classifies SyntaxError for an unbound predicate name" {
  let result = @prover_loop.run_check_gate(
    fixture_module_root(), "broken_pkg",
  )
  assert_true(!result.passed)
  assert_eq(result.kind, Some(@prover_loop.SyntaxError))
  assert_true(result.raw_output.contains("is unbound"))
}
