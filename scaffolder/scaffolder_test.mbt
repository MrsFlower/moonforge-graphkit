///|
/// End-to-end acceptance test for `scaffolder.generate`: given only a
/// natural-language task description, generate a brand-new MoonBit
/// package (`.mbt` + `.mbtp` + fixed `moon.pkg`) from scratch, verify it
/// passes the cheap `moon check` gate, and then verify it actually
/// proves — a real `moon prove` run via the WSL2 bridge, matching this
/// project's own acceptance criterion of a "100% formally verified"
/// output, not just a compiling one.
///
/// This test makes real external calls (a real `codex exec` process, a
/// real local `moon check`, and a real `wsl.exe`-bridged `moon prove`),
/// matching this project's own testing discipline of exercising the
/// actual integration rather than mocking it. The target task
/// (`clamp(x, lo, hi)`) is deliberately simple and loop-free — this is
/// the first real end-to-end run of the scaffold-generation pipeline
/// itself, so it is scoped to validate the mechanism (can a from-scratch
/// package be generated, written, and proved at all), not to stress-test
/// generation difficulty.
async test "scaffolder generates a brand-new clamp package that moon check and moon prove both accept" {
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/scaffold_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/scaffold_demo"
  let package_path = "clamp"
  let package_dir = windows_module_root + "/" + package_path
  // Guard against a leftover directory from a previous failed run so this
  // test can be re-run without manual cleanup, without ever silently
  // overwriting content a previous run's failure investigation might
  // still need — only remove a directory this exact test fixture owns.
  if @fs.exists(package_dir) {
    @fs.rmdir(package_dir, recursive=true)
  }
  let scratch = @fs.tmpdir(prefix="moonforge_scaffold_e2e_")
  let backend = @llm.ShellBackend::new(scratch, model="gpt-5.5")
  let config : @scaffolder.ScaffoldConfig = {
    module_root: windows_module_root,
    package_path,
    pkg_name: "clamp",
    user_task: (
      #|Generate a MoonBit function `clamp(x : Int, lo : Int, hi : Int) -> Int`
      #|that clamps `x` into the range `[lo, hi]`: returns `lo` if `x < lo`,
      #|`hi` if `x > hi`, and `x` otherwise. It must be verified by `moon
      #|prove` (a Why3/SMT-backed pipeline) with:
      #|
      #|- a precondition that `lo <= hi` (define it as a named predicate in
      #|  the `.mbtp` file, e.g. `valid_bounds(lo, hi)` — `proof_require`
      #|  only accepts predicate calls, not inline expressions)
      #|- a postcondition that the result is within `[lo, hi]` (also a named
      #|  predicate, e.g. `clamped(lo, hi, result)`)
      #|
      #|This function has no loops, so no loop invariants are needed.
    ),
    invariant_tags: None,
    max_rounds: 5,
  }
  let result = @scaffolder.generate(
    backend,
    @prover_loop.RealCheckGate::{  },
    config,
  )
  match result {
    @scaffolder.ScaffoldSuccess(files_written~, ..) => {
      assert_true(files_written.contains("moon.pkg"))
      assert_true(files_written.contains("clamp.mbt"))
      assert_true(files_written.contains("clamp.mbtp"))
      let env_setup =
        #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        #|export LD_LIBRARY_PATH="$HOME/tools"
      let prove_runner = @prover_loop.WslProveRunner::new(
        "Ubuntu-24.04", env_setup,
      )
      let outcome = prove_runner.run_prove(
        wsl_module_root, package_path, "clamp",
      )
      if !@prover_loop.is_success(outcome) {
        fail(
          "generated clamp package passed moon check but failed moon prove: stdout=\{outcome.stdout} stderr=\{outcome.stderr}",
        )
      }
    }
    @scaffolder.NeedsHumanReview(reason~) =>
      fail("expected ScaffoldSuccess, got NeedsHumanReview: " + reason)
    @scaffolder.RoundsExhausted(raw_output~, ..) =>
      fail(
        "expected ScaffoldSuccess, got RoundsExhausted. output: " + raw_output,
      )
  }
  @fs.rmdir(package_dir, recursive=true)
}
