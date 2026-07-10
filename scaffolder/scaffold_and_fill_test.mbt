///|
/// End-to-end acceptance test for `generate_and_fill`: the first real
/// exercise of the full chain — a natural-language task description goes
/// in, `generate` scaffolds a brand-new package with a loop whose
/// `proof_invariant` region is left empty and tagged, and
/// `orchestrator.run` is then handed that generated file to fill the
/// invariants in and drive it to a real `moon prove` success. Until this
/// test, `ScaffoldConfig.invariant_tags` existed as a field but nothing
/// had ever exercised the handoff between the two pipelines.
///
/// The target task (integer square root via binary search) mirrors this
/// project's own `isqrt_demo` fixture's contract exactly (see
/// `fixtures/target_examples/isqrt_demo/isqrt/isqrt.mbtp`) — same
/// `nonneg`/`isqrt_ok` predicates, same binary-search shape — so a
/// generation or fill-in failure here can be directly compared against a
/// known-good hand-written reference rather than an unfamiliar target.
///
/// This test makes real external calls (two real `codex exec` calls, one
/// per stage; a real local `moon check`; a real `wsl.exe`-bridged `moon
/// prove`), matching this project's own testing discipline of exercising
/// the actual integration rather than mocking it.
async test "generate_and_fill scaffolds a fresh isqrt package and fills its invariants to a real moon prove success" {
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/scaffold_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/scaffold_demo"
  let package_path = "isqrt_chain"
  let package_dir = windows_module_root + "/" + package_path
  if @fs.exists(package_dir) {
    @fs.rmdir(package_dir, recursive=true)
  }
  let scratch = @fs.tmpdir(prefix="moonforge_scaffold_and_fill_e2e_")
  let backend = @llm.ShellBackend::new(scratch, model="gpt-5.5")
  let start_tag = "// @MOONFORGE_INVARIANT_START"
  let end_tag = "// @MOONFORGE_INVARIANT_END"
  let scaffold_config : @scaffolder.ScaffoldConfig = {
    module_root: windows_module_root,
    package_path,
    pkg_name: "isqrt_chain",
    user_task: (
      #|Generate a MoonBit function `isqrt(n : Int) -> Int` that computes
      #|the integer square root of a non-negative `n` via binary search
      #|over `lo`/`hi`. It must be verified by `moon prove` (a Why3/SMT-
      #|backed pipeline) with:
      #|
      #|  proof_require: nonneg(n)
      #|  proof_ensure: result => isqrt_ok(n, result)
      #|
      #|where the predicates (defined in the .mbtp file) are:
      #|
      #|  predicate nonneg(n : Int) { n >= 0 }
      #|  predicate isqrt_ok(n : Int, result : Int) {
      #|    (result >= 0) && (result * result <= n) && (n < (result + 1) * (result + 1))
      #|  }
      #|
      #|Structure the loop as `for lo = 0, hi = n + 1; lo < hi - 1; { ... }`
      #|so this toolchain can auto-generate a termination variant.
    ),
    invariant_tags: Some((start_tag, end_tag)),
    max_rounds: 5,
  }
  let env_setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  let prove_runner = @prover_loop.WslProveRunner::new("Ubuntu-24.04", env_setup)
  let config : @scaffolder.ScaffoldAndFillConfig = {
    scaffold: scaffold_config,
    prove_module_root: wsl_module_root,
    fill_task: (
      #|Fill in the loop invariants for the `isqrt` function's binary
      #|search, so `moon prove` accepts it. You will need invariants
      #|tracking the search bounds and the relationship between `lo`/`hi`
      #|and `n` that the postcondition depends on.
      #|
      #|Return ONLY the `proof_invariant: ...,` lines that belong inside
      #|the function's `where { ... }` block, one invariant per line, each
      #|ending with a comma, inside a single fenced ```mbt code block.
    ),
    fill_max_rounds: 5,
  }
  let result = @scaffolder.generate_and_fill(
    backend,
    @prover_loop.RealCheckGate::{  },
    prove_runner,
    config,
  )
  match result {
    @scaffolder.FullSuccess(fill_rounds_used~, ..) =>
      assert_true(fill_rounds_used >= 1)
    @scaffolder.ScaffoldStageFailed(_) =>
      fail("expected FullSuccess, got ScaffoldStageFailed")
    @scaffolder.FillStageFailed(_) =>
      fail("expected FullSuccess, got FillStageFailed")
  }
  @fs.rmdir(package_dir, recursive=true)
}
