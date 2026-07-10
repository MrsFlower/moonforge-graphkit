///|
/// End-to-end acceptance test matching this project's own acceptance
/// criteria: given a `.mbt` file with a `@MOONFORGE_INVARIANT_START`/`_END`
/// tagged region and a missing loop invariant, running the full
/// MoonForge pipeline (`codex exec` for generation, a WSL2-bridged
/// `moon prove` for verification) should reach `VerificationSuccess`
/// within a small number of rounds.
///
/// This test makes real external calls (a real `codex exec` process and a
/// real `wsl.exe`-bridged `moon prove`), matching this project's own
/// testing discipline of exercising the actual integration rather than
/// mocking it. It is deliberately given a generous round budget since an
/// LLM's first attempt at a loop invariant is not guaranteed to be exactly
/// what this toolchain's automatic termination-variant inference expects.
async test "MoonForge end-to-end: fills in isqrt's missing invariant and reaches VerificationSuccess" {
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/isqrt_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/isqrt_demo"
  let target_file = windows_module_root + "/isqrt/isqrt.mbt"
  let original_source = @fs.read_file(target_file).text()
  let scratch = @fs.tmpdir(prefix="moonforge_e2e_")
  let backend = @llm.ShellBackend::new(scratch, model="gpt-5.5")
  let env_setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  let prove_runner = @prover_loop.WslProveRunner::new("Ubuntu-24.04", env_setup)
  let config : @orchestrator.RunConfig = {
    module_root: wsl_module_root,
    native_module_root: windows_module_root,
    package_path: "isqrt",
    pkg_name: "isqrt",
    target_file,
    start_tag: "// @MOONFORGE_INVARIANT_START",
    end_tag: "// @MOONFORGE_INVARIANT_END",
    user_task: (
      #|Fill in the loop invariants for this MoonBit function, which is
      #|verified by `moon prove` (a Why3/SMT-backed pipeline). The function
      #|computes the integer square root of a non-negative `n` via binary
      #|search over `lo`/`hi`. Its contract is:
      #|
      #|  proof_require: nonneg(n)
      #|  proof_ensure: result => isqrt_ok(n, result)
      #|
      #|where the predicates (already defined in isqrt.mbtp) are:
      #|
      #|  predicate nonneg(n : Int) { n >= 0 }
      #|  predicate isqrt_ok(n : Int, result : Int) {
      #|    (result >= 0) && (result * result <= n) && (n < (result + 1) * (result + 1))
      #|  }
      #|
      #|Return ONLY the `invariant: ...,` lines that belong inside the
      #|function's `where { ... }` block (the block is currently empty),
      #|one invariant per line, each ending with a comma, inside a single
      #|fenced ```mbt code block. Do not return the whole function, only
      #|the invariant lines.
    ),
    max_rounds: 5,
  }
  let result = @orchestrator.run(
    backend,
    @prover_loop.RealCheckGate::{  },
    prove_runner,
    config,
  )
  // Always restore the fixture file, whether the run succeeded or not, so
  // repeated test runs start from the same known-missing-invariant state
  // and this test does not leave the repository's working tree dirty.
  @fs.write_file(target_file, original_source)
  match result {
    @orchestrator.VerificationSuccess(rounds_used~) => {
      assert_true(rounds_used >= 1)
      assert_true(rounds_used <= 5)
    }
    @orchestrator.NeedsHumanReview(reason~) =>
      fail("expected VerificationSuccess, got NeedsHumanReview: " + reason)
    @orchestrator.RoundsExhausted(last_outcome~, ..) =>
      fail(
        "expected VerificationSuccess, got RoundsExhausted. stdout: " +
        last_outcome.stdout +
        " stderr: " +
        last_outcome.stderr,
      )
  }
}

///|
/// A harder DeFi-domain challenge, going beyond the `isqrt` demo's binary
/// search invariant. `batch_auction` is a real verified example from this
/// project's own finance case studies (uniform-price batch auction
/// clearing quantity search): it needs two quantified array invariants
/// (`all_cross_before`/`all_fail_from` over the bid/ask order books)
/// working together, not just scalar bounds, and its final postcondition
/// ties the clearing price to specific bid/ask levels. Verified by hand
/// (see `MoonForge_PLAN.md` section 11) that removing the invariants
/// genuinely breaks the proof (5 of 9 goals time out), so this is a real
/// difficulty step up, not an already-trivial case in disguise.
///
/// This exercises `bouncer`'s DeFi domain classification and prior-rule
/// injection end-to-end, which the `isqrt` test above does not (`isqrt`
/// classifies as `Unclassified`).
async test "MoonForge end-to-end: fills in batch_auction's missing two-array invariants (DeFi challenge)" {
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/batch_auction_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/batch_auction_demo"
  let target_file = windows_module_root + "/batch_auction/batch_auction.mbt"
  let original_source = @fs.read_file(target_file).text()
  let scratch = @fs.tmpdir(prefix="moonforge_e2e_defi_")
  let backend = @llm.ShellBackend::new(scratch, model="gpt-5.5")
  let env_setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  let prove_runner = @prover_loop.WslProveRunner::new("Ubuntu-24.04", env_setup)
  let config : @orchestrator.RunConfig = {
    module_root: wsl_module_root,
    native_module_root: windows_module_root,
    package_path: "batch_auction",
    pkg_name: "batch_auction",
    target_file,
    start_tag: "// @MOONFORGE_INVARIANT_START",
    end_tag: "// @MOONFORGE_INVARIANT_END",
    user_task: (
      #|Fill in the loop invariants for `clearing_quantity`, which is
      #|verified by `moon prove` (a Why3/SMT-backed pipeline). The function
      #|binary-searches a uniform-price batch auction's clearing quantity:
      #|`bids` is sorted descending, `asks` is sorted ascending, and the
      #|search finds the boundary index where `asks[i] <= bids[i]` stops
      #|holding. Its contract is:
      #|
      #|  proof_require: same_length(bids, asks)
      #|  proof_require: bids_desc(bids)
      #|  proof_require: asks_asc(asks)
      #|  proof_ensure: result => clearing_quantity_post(bids, asks, result)
      #|
      #|where the relevant predicates (already defined in
      #|batch_auction.mbtp) are:
      #|
      #|  predicate in_bounds(xs, i) { 0 <= i && i < xs.length() }
      #|  predicate all_cross_before(bids, asks, idx) {
      #|    forall i, (0 <= i && i < idx) implies asks[i] <= bids[i]
      #|  }
      #|  predicate all_fail_from(bids, asks, idx) {
      #|    forall i, (idx <= i && i < bids.length()) implies bids[i] < asks[i]
      #|  }
      #|  predicate clearing_quantity_post(bids, asks, result) {
      #|    same_length(bids, asks) && 0 <= result && result <= bids.length() &&
      #|    all_cross_before(bids, asks, result) && all_fail_from(bids, asks, result)
      #|  }
      #|
      #|You will need invariants tracking: the search bounds (`0 <= lo`,
      #|`lo <= hi`, `hi <= bids.length()`), and that everything before `lo`
      #|already crosses while everything from `hi` onward already fails to
      #|cross (using `all_cross_before`/`all_fail_from` against the current
      #|`lo`/`hi`, not the final `result`).
      #|
      #|Return ONLY the `proof_invariant: ...,` lines that belong inside the
      #|function's `where { ... }` block (the block is currently empty),
      #|one invariant per line, each ending with a comma, inside a single
      #|fenced ```mbt code block. Do not return the whole function, only
      #|the invariant lines. Use the ASCII spellings `forall`/`implies` only
      #|in this task description; in actual MoonBit code use the real
      #|Unicode quantifier and implication operators this toolchain expects.
    ),
    max_rounds: 6,
  }
  let result = @orchestrator.run(
    backend,
    @prover_loop.RealCheckGate::{  },
    prove_runner,
    config,
  )
  @fs.write_file(target_file, original_source)
  match result {
    @orchestrator.VerificationSuccess(rounds_used~) => {
      assert_true(rounds_used >= 1)
      assert_true(rounds_used <= 6)
    }
    @orchestrator.NeedsHumanReview(reason~) =>
      fail("expected VerificationSuccess, got NeedsHumanReview: " + reason)
    @orchestrator.RoundsExhausted(last_outcome~, ..) =>
      fail(
        "expected VerificationSuccess, got RoundsExhausted. stdout: " +
        last_outcome.stdout +
        " stderr: " +
        last_outcome.stderr,
      )
  }
}

///|
/// Evaluation run (not a strict pass/fail acceptance test): drives the
/// `batch_auction` DeFi challenge fixture (see the `codex`/gpt-5.5 version
/// of this test above) through the full pipeline with Leanstral 1.5, to
/// see whether the harder two-array-invariant case (which needs
/// `bouncer`'s DeFi prior-rule injection to have a real shot) is within
/// reach for a Lean-4-specialized-but-MoonBit-unfamiliar model, not just
/// the single-scalar-invariant `isqrt` case. Skips cleanly when
/// `MISTRAL_API_KEY` is not configured; prints the outcome rather than
/// failing, for the same reason as the `isqrt` evaluation test above.
async test "MoonForge evaluation: Leanstral 1.5 filling in batch_auction's missing invariants" {
  guard @env.get_env_var("MISTRAL_API_KEY") is Some(api_key) else { return }
  let proxy_url = @env.get_env_var("MOONFORGE_HTTP_PROXY")
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/batch_auction_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/batch_auction_demo"
  let target_file = windows_module_root + "/batch_auction/batch_auction.mbt"
  let original_source = @fs.read_file(target_file).text()
  let backend = @llm.HttpBackend::new(
    "https://api.mistral.ai/v1",
    api_key,
    "labs-leanstral-1-5",
    proxy_url?,
    extra_system_prompt=@llm.leanstral_prompt_addendum,
  )
  let env_setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  let prove_runner = @prover_loop.WslProveRunner::new("Ubuntu-24.04", env_setup)
  let config : @orchestrator.RunConfig = {
    module_root: wsl_module_root,
    native_module_root: windows_module_root,
    package_path: "batch_auction",
    pkg_name: "batch_auction",
    target_file,
    start_tag: "// @MOONFORGE_INVARIANT_START",
    end_tag: "// @MOONFORGE_INVARIANT_END",
    user_task: (
      #|Fill in the loop invariants for `clearing_quantity`, which is
      #|verified by `moon prove` (a Why3/SMT-backed pipeline). The function
      #|binary-searches a uniform-price batch auction's clearing quantity:
      #|`bids` is sorted descending, `asks` is sorted ascending, and the
      #|search finds the boundary index where `asks[i] <= bids[i]` stops
      #|holding. Its contract is:
      #|
      #|  proof_require: same_length(bids, asks)
      #|  proof_require: bids_desc(bids)
      #|  proof_require: asks_asc(asks)
      #|  proof_ensure: result => clearing_quantity_post(bids, asks, result)
      #|
      #|where the relevant predicates (already defined in
      #|batch_auction.mbtp) are:
      #|
      #|  predicate in_bounds(xs, i) { 0 <= i && i < xs.length() }
      #|  predicate all_cross_before(bids, asks, idx) {
      #|    forall i, (0 <= i && i < idx) implies asks[i] <= bids[i]
      #|  }
      #|  predicate all_fail_from(bids, asks, idx) {
      #|    forall i, (idx <= i && i < bids.length()) implies bids[i] < asks[i]
      #|  }
      #|  predicate clearing_quantity_post(bids, asks, result) {
      #|    same_length(bids, asks) && 0 <= result && result <= bids.length() &&
      #|    all_cross_before(bids, asks, result) && all_fail_from(bids, asks, result)
      #|  }
      #|
      #|You will need invariants tracking: the search bounds (`0 <= lo`,
      #|`lo <= hi`, `hi <= bids.length()`), and that everything before `lo`
      #|already crosses while everything from `hi` onward already fails to
      #|cross (using `all_cross_before`/`all_fail_from` against the current
      #|`lo`/`hi`, not the final `result`).
      #|
      #|Return ONLY the `proof_invariant: ...,` lines that belong inside the
      #|function's `where { ... }` block (the block is currently empty),
      #|one invariant per line, each ending with a comma, inside a single
      #|fenced ```mbt code block. Do not return the whole function, only
      #|the invariant lines. Use the ASCII spellings `forall`/`implies` only
      #|in this task description; in actual MoonBit code use the real
      #|Unicode quantifier and implication operators this toolchain expects.
    ),
    max_rounds: 6,
  }
  let result = @orchestrator.run(
    backend,
    @prover_loop.RealCheckGate::{  },
    prove_runner,
    config,
  )
  @fs.write_file(target_file, original_source)
  match result {
    @orchestrator.VerificationSuccess(rounds_used~) =>
      println(
        "Leanstral 1.5 (batch_auction): VerificationSuccess in \{rounds_used} round(s)",
      )
    @orchestrator.NeedsHumanReview(reason~) =>
      println("Leanstral 1.5 (batch_auction): NeedsHumanReview - \{reason}")
    @orchestrator.RoundsExhausted(last_kind~, last_outcome~) =>
      println(
        "Leanstral 1.5 (batch_auction): RoundsExhausted, last_kind=\{last_kind}\nlast stdout: \{last_outcome.stdout}\nlast stderr: \{last_outcome.stderr}",
      )
  }
}

///|
/// Evaluation run (not a strict pass/fail acceptance test): drives the
/// same `isqrt` fixture through the full pipeline with Mistral's
/// Leanstral 1.5 (a model trained for Lean 4 formal-proof engineering,
/// not MoonBit) as the `LlmBackend`, to see how well a
/// verification-specialized-but-wrong-language model performs against a
/// generalist coding model on this project's own `proof_invariant`
/// syntax. Skips cleanly when `MISTRAL_API_KEY` is not configured. Prints
/// the outcome instead of failing on `RoundsExhausted`, since the point
/// of this test is to observe and report Leanstral's behavior (which
/// round it converges on, if any, and what kind of mistakes it makes),
/// not to gate the build on a model this project does not depend on.
async test "MoonForge evaluation: Leanstral 1.5 filling in isqrt's missing invariant" {
  guard @env.get_env_var("MISTRAL_API_KEY") is Some(api_key) else { return }
  let proxy_url = @env.get_env_var("MOONFORGE_HTTP_PROXY")
  let windows_module_root = "C:/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/isqrt_demo"
  let wsl_module_root = "/mnt/c/Users/15866/Documents/codeheaven/moonbit/proveTask/moon-forge/fixtures/target_examples/isqrt_demo"
  let target_file = windows_module_root + "/isqrt/isqrt.mbt"
  let original_source = @fs.read_file(target_file).text()
  let backend = @llm.HttpBackend::new(
    "https://api.mistral.ai/v1",
    api_key,
    "labs-leanstral-1-5",
    proxy_url?,
    extra_system_prompt=@llm.leanstral_prompt_addendum,
  )
  let env_setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  let prove_runner = @prover_loop.WslProveRunner::new("Ubuntu-24.04", env_setup)
  let config : @orchestrator.RunConfig = {
    module_root: wsl_module_root,
    native_module_root: windows_module_root,
    package_path: "isqrt",
    pkg_name: "isqrt",
    target_file,
    start_tag: "// @MOONFORGE_INVARIANT_START",
    end_tag: "// @MOONFORGE_INVARIANT_END",
    user_task: (
      #|Fill in the loop invariants for this MoonBit function, which is
      #|verified by `moon prove` (a Why3/SMT-backed pipeline). The function
      #|computes the integer square root of a non-negative `n` via binary
      #|search over `lo`/`hi`. Its contract is:
      #|
      #|  proof_require: nonneg(n)
      #|  proof_ensure: result => isqrt_ok(n, result)
      #|
      #|where the predicates (already defined in isqrt.mbtp) are:
      #|
      #|  predicate nonneg(n : Int) { n >= 0 }
      #|  predicate isqrt_ok(n : Int, result : Int) {
      #|    (result >= 0) && (result * result <= n) && (n < (result + 1) * (result + 1))
      #|  }
      #|
      #|Return ONLY the `invariant: ...,` lines that belong inside the
      #|function's `where { ... }` block (the block is currently empty),
      #|one invariant per line, each ending with a comma, inside a single
      #|fenced ```mbt code block. Do not return the whole function, only
      #|the invariant lines.
    ),
    max_rounds: 6,
  }
  let result = @orchestrator.run(
    backend,
    @prover_loop.RealCheckGate::{  },
    prove_runner,
    config,
  )
  @fs.write_file(target_file, original_source)
  match result {
    @orchestrator.VerificationSuccess(rounds_used~) =>
      println("Leanstral 1.5: VerificationSuccess in \{rounds_used} round(s)")
    @orchestrator.NeedsHumanReview(reason~) =>
      println("Leanstral 1.5: NeedsHumanReview - \{reason}")
    @orchestrator.RoundsExhausted(last_kind~, last_outcome~) =>
      println(
        "Leanstral 1.5: RoundsExhausted, last_kind=\{last_kind}\nlast stdout: \{last_outcome.stdout}\nlast stderr: \{last_outcome.stderr}",
      )
  }
}
