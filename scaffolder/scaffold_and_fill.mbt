///|
/// Configuration for chaining `generate` (this package) into
/// `orchestrator.run` (the `orchestrator` package): scaffold a brand-new
/// package with a loop whose `proof_invariant` lines are left empty and
/// tagged, then immediately hand that generated file to `orchestrator.run`
/// to fill them in. This is the first real link between the two
/// pipelines — until now, `scaffold.invariant_tags` existed as a field
/// but nothing ever exercised the handoff.
pub(all) struct ScaffoldAndFillConfig {
  /// The scaffold-generation config. `invariant_tags` must be `Some` —
  /// this function exists specifically to fill those tags in
  /// afterward, so a `None` here is a caller error (see `generate_and_fill`'s
  /// guard), not a runtime outcome worth modeling as a result variant.
  scaffold : ScaffoldConfig
  /// Module root as seen by `prove_runner` for the fill-in stage's
  /// `moon prove` call — mirrors `orchestrator.RunConfig.module_root`'s
  /// own doc comment (a WSL2-internal path for a `WslProveRunner`, equal
  /// to `scaffold.module_root` for a runner that already runs locally).
  /// The scaffold stage itself never needs this: `generate`'s own
  /// `CheckGate` call always runs locally against `scaffold.module_root`.
  prove_module_root : String
  /// Human-readable description of what the tagged invariant region
  /// should contain, becomes the fill-in stage's `orchestrator.RunConfig.user_task`.
  fill_task : String
  /// Maximum LLM <-> `moon prove` rounds for the fill-in stage. Separate
  /// from `scaffold.max_rounds`, which bounds only the scaffold-generation
  /// stage.
  fill_max_rounds : Int
}

///|
/// Terminal outcome of `generate_and_fill`.
pub(all) enum ScaffoldAndFillResult {
  /// Both stages succeeded: the scaffold was generated, and the fill-in
  /// stage's `moon prove` call succeeded within `fill_max_rounds`.
  FullSuccess(package_dir~ : String, fill_rounds_used~ : Int)
  /// The scaffold-generation stage itself did not reach `ScaffoldSuccess`
  /// — the fill-in stage was never attempted.
  ScaffoldStageFailed(result~ : ScaffoldResult)
  /// The scaffold was generated successfully, but `orchestrator.run`'s
  /// fill-in stage did not reach `VerificationSuccess`.
  FillStageFailed(result~ : @orchestrator.RunResult)
}

///|
/// Run `generate` to scaffold a new package with an empty, tagged
/// invariant region, then run `orchestrator.run` against the generated
/// `.mbt` file to fill that region in. `config.scaffold.invariant_tags`
/// must be `Some((start_tag, end_tag))` — those exact tag lines are what
/// `orchestrator.run` is told to look for in the generated file.
pub async fn[B : @llm.LlmBackend, G : @prover_loop.CheckGate, R : @prover_loop.ProveRunner] generate_and_fill(
  backend : B,
  check_gate : G,
  prove_runner : R,
  config : ScaffoldAndFillConfig,
) -> ScaffoldAndFillResult {
  guard config.scaffold.invariant_tags is Some((start_tag, end_tag)) else {
    fail(
      "generate_and_fill requires config.scaffold.invariant_tags to be Some — there is nothing to fill in otherwise",
    )
  }
  let scaffold_result = generate(backend, check_gate, config.scaffold)
  guard scaffold_result is ScaffoldSuccess(package_dir~, ..) else {
    return ScaffoldStageFailed(result=scaffold_result)
  }
  let target_file = package_dir + "/" + config.scaffold.pkg_name + ".mbt"
  let run_config : @orchestrator.RunConfig = {
    module_root: config.prove_module_root,
    native_module_root: config.scaffold.module_root,
    package_path: config.scaffold.package_path,
    pkg_name: config.scaffold.pkg_name,
    target_file,
    start_tag,
    end_tag,
    user_task: config.fill_task,
    max_rounds: config.fill_max_rounds,
  }
  let fill_result = @orchestrator.run(
    backend, check_gate, prove_runner, run_config,
  )
  match fill_result {
    @orchestrator.VerificationSuccess(rounds_used~) =>
      FullSuccess(package_dir~, fill_rounds_used=rounds_used)
    _ => FillStageFailed(result=fill_result)
  }
}
