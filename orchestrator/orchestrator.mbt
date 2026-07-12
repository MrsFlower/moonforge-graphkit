///|
/// Configuration for a single `MoonForge` run against one target file.
pub(all) struct RunConfig {
  /// Absolute path to the MoonBit module root that contains the target
  /// package (the directory with `moon.mod`), *as seen by `prove_runner`*.
  /// For `WslProveRunner` this is a path inside the WSL2 distro (e.g.
  /// `/mnt/c/...`), not a Windows path — see that runner's own doc
  /// comment. `moon prove` is invoked with this as its working directory.
  module_root : String
  /// Absolute path to the same module root, but as seen by *this
  /// process* (the machine MoonForge itself is running on — Windows
  /// native, per this project's own architecture). Used only by
  /// `check_gate`, which always runs `moon check` locally and never
  /// crosses the WSL2 bridge, so it needs the local path convention even
  /// when `module_root` above is a WSL2-internal path for a
  /// `WslProveRunner`. When `prove_runner` already runs locally (e.g. a
  /// `LocalProveRunner` inside the same WSL2/Linux/macOS environment this
  /// process runs in), this is simply equal to `module_root`.
  native_module_root : String
  /// Package path relative to `module_root`, e.g. `"examples/demos/isqrt"`.
  package_path : String
  /// Bare package name, used to locate the `.proof.json` report
  /// (`_build/verif/<package_path>/<pkg_name>.proof.json`).
  pkg_name : String
  /// Absolute path to the target `.mbt` file containing the tagged
  /// region to fill in.
  target_file : String
  /// Tag lines delimiting the region MoonForge is allowed to rewrite.
  start_tag : String
  end_tag : String
  /// Human-readable description of what the tagged region should
  /// contain, becomes the LLM's user-facing task description.
  user_task : String
  /// Maximum number of LLM <-> `moon prove` rounds before giving up.
  /// Must be at least 1.
  max_rounds : Int
}

///|
/// Terminal outcome of a `MoonForge` run.
pub(all) enum RunResult {
  /// `moon prove` succeeded within `max_rounds`. `rounds_used` is at
  /// least 1.
  VerificationSuccess(rounds_used~ : Int)
  /// The LLM's response could not be reduced to code MoonForge trusts
  /// enough to inject (see `sanitizer.NeedsReview`), or the target file
  /// failed the purity gate before any LLM call was made.
  NeedsHumanReview(reason~ : String)
  /// `max_rounds` were exhausted without a successful proof.
  RoundsExhausted(
    last_kind~ : @prover_loop.FailureKind,
    last_outcome~ : @prover_loop.ProveOutcome
  )
}

///|
/// One tagged region in a multi-region sequence. All regions in a
/// `SequenceRunConfig` share the same module/package/prove runner settings,
/// but each region has its own tag pair and task text.
pub(all) struct RunRegion {
  name : String
  start_tag : String
  end_tag : String
  user_task : String
}

///|
/// Configuration for a cumulative multi-region run against one target file.
/// Regions are filled in order. After each region, MoonForge runs the same
/// `moon check` and `moon prove` gates as a normal one-region `run`.
pub(all) struct SequenceRunConfig {
  module_root : String
  native_module_root : String
  package_path : String
  pkg_name : String
  target_file : String
  regions : Array[RunRegion]
  max_rounds : Int
  clear_current_region : Bool
}

///|
pub(all) struct SequenceStepSuccess {
  name : String
  rounds_used : Int
}

///|
pub(all) enum SequenceRunResult {
  SequenceSuccess(steps~ : Array[SequenceStepSuccess])
  SequenceStopped(step_index~ : Int, step_name~ : String, result~ : RunResult)
}

///|
/// Fill several tagged regions cumulatively. This is intentionally a
/// conservative orchestration layer over `run`, not a new multi-region LLM
/// protocol: each step sees the file as modified by earlier successful steps
/// and must pass the normal whole-package proof gate before the next region is
/// attempted.
pub async fn[
  B : @llm.LlmBackend,
  G : @prover_loop.CheckGate,
  R : @prover_loop.ProveRunner,
] run_sequence(
  backend : B,
  check_gate : G,
  prove_runner : R,
  config : SequenceRunConfig,
) -> SequenceRunResult {
  guard config.regions.length() > 0 else {
    fail("sequence must contain at least one region")
  }
  let successes : Array[SequenceStepSuccess] = []
  for i in 0..<config.regions.length() {
    let region = config.regions[i]
    if config.clear_current_region {
      let source = @fs.read_file(config.target_file).text()
      let cleared = @injector.inject(
        source,
        region.start_tag,
        region.end_tag,
        "",
      )
      @fs.write_file(config.target_file, cleared)
    }
    let step_config : RunConfig = {
      module_root: config.module_root,
      native_module_root: config.native_module_root,
      package_path: config.package_path,
      pkg_name: config.pkg_name,
      target_file: config.target_file,
      start_tag: region.start_tag,
      end_tag: region.end_tag,
      user_task: region.user_task,
      max_rounds: config.max_rounds,
    }
    match run(backend, check_gate, prove_runner, step_config) {
      VerificationSuccess(rounds_used~) =>
        successes.push({ name: region.name, rounds_used })
      result =>
        return SequenceStopped(step_index=i, step_name=region.name, result~)
    }
  }
  SequenceSuccess(steps=successes)
}

///|
/// Run the full MoonForge pipeline once: classify the target's domain,
/// build a domain-aware prompt, ask `backend` for the tagged region's
/// contents, inject the (sanitized) response, run the cheap `moon check`
/// pre-flight gate, and — only if that passes — call `moon prove`. If
/// either the gate or the proof fails, build a targeted repair prompt
/// from the failure and try again, up to `config.max_rounds` times.
///
/// This function performs the actual file write on every round via
/// `injector` — the LLM backend itself never touches `config.target_file`
/// (see the safety note on `ShellBackend` in the `llm` package).
pub async fn[
  B : @llm.LlmBackend,
  G : @prover_loop.CheckGate,
  R : @prover_loop.ProveRunner,
] run(
  backend : B,
  check_gate : G,
  prove_runner : R,
  config : RunConfig,
) -> RunResult {
  guard config.max_rounds >= 1 else { fail("max_rounds must be at least 1") }
  let original_source = @fs.read_file(config.target_file).text()
  let domain = @bouncer.classify_domain(original_source)
  let purity_issues = @bouncer.check_purity(original_source)
  guard purity_issues is [] else {
    return NeedsHumanReview(
      reason="target file failed the purity gate before any LLM call: \{purity_issues.length()} issue(s) found",
    )
  }
  let base_prompt = @bouncer.build_prompt(domain, config.user_task)
  loop_rounds(
    backend,
    check_gate,
    prove_runner,
    config,
    original_source,
    base_prompt.system_prompt,
    1,
  )
}

///|
/// Build the full task text sent to the LLM for one round: the real,
/// current contents of `target_file` (and its sibling `.mbtp` predicate
/// file, when one exists alongside it — same base name, `.mbtp` extension
/// instead of `.mbt`), followed by `config.user_task`'s natural-language
/// description. Recomputed fresh from `current_source` on every round
/// (not just the first) so that on a repair round the LLM sees its own
/// previous attempt still sitting in the tagged region, not a stale
/// blank-slate snapshot from before its first try.
///
/// This exists because `ShellBackend` runs `codex exec -s read-only -C
/// <scratch_dir>` with the scratch dir deliberately empty and unrelated to
/// the real project (see that backend's own safety note) — the LLM
/// backend genuinely cannot read `target_file`, its sibling `.mbtp`, or
/// anything else in the module by itself. Without this, the model is
/// guessing predicate names, field names, and the exact loop shape purely
/// from whatever `config.user_task` happens to describe in prose, which is
/// exactly the kind of drift a human transcribing predicates by hand into
/// a task string can introduce (and did, in earlier fixtures — see
/// `docs/LESSONS.md`). Inlining the real, current file contents here
/// makes every backend (not just `ShellBackend`) work from ground truth
/// instead of a paraphrase, and keeps the prompt in sync automatically
/// when the target file's contracts change.
async fn build_user_task(
  target_file : String,
  current_source : String,
  user_task : String,
) -> String {
  source_context_block(target_file, current_source) + "\n\n" + user_task
}

///|
async fn source_context_block(target_file : String, source : String) -> String {
  let mbt_block = "The target file (\{target_file}) currently contains:\n\n```mbt\n" +
    source +
    "\n```"
  if target_file.has_suffix(".mbt") {
    let mbtp_path = target_file[0:target_file.length() - 4].to_owned() + ".mbtp"
    let mbtp_source = try @fs.read_file(mbtp_path).text() catch {
      _ => None
    } noraise {
      text => Some(text)
    }
    match mbtp_source {
      Some(mbtp_source) =>
        mbt_block +
        "\n\nIts sibling predicate file (\{mbtp_path}) currently contains:\n\n```mbt\n" +
        mbtp_source +
        "\n```"
      None => mbt_block
    }
  } else {
    mbt_block
  }
}

///|
async fn[
  B : @llm.LlmBackend,
  G : @prover_loop.CheckGate,
  R : @prover_loop.ProveRunner,
] loop_rounds(
  backend : B,
  check_gate : G,
  prove_runner : R,
  config : RunConfig,
  original_source : String,
  system_prompt : String,
  round : Int,
) -> RunResult {
  let user_task = build_user_task(
    config.target_file,
    original_source,
    config.user_task,
  )
  let raw_reply = backend.complete(system_prompt, user_task)
  let sanitized = @sanitizer.strip_markdown(raw_reply)
  match sanitized {
    NeedsReview(reason~) =>
      if round >= config.max_rounds {
        NeedsHumanReview(reason~)
      } else {
        let repair_instructions = @sanitizer.build_repair_instructions(reason)
        let next_system_prompt = system_prompt + "\n\n" + repair_instructions
        loop_rounds(
          backend,
          check_gate,
          prove_runner,
          config,
          original_source,
          next_system_prompt,
          round + 1,
        )
      }
    Clean(code~) =>
      match @sanitizer.validate_invariant_fragment(code) {
        NeedsReview(reason~) =>
          if round >= config.max_rounds {
            NeedsHumanReview(reason~)
          } else {
            let repair_instructions = @sanitizer.build_invariant_fragment_repair_instructions(
              reason,
            )
            let next_system_prompt = system_prompt +
              "\n\n" +
              repair_instructions
            loop_rounds(
              backend,
              check_gate,
              prove_runner,
              config,
              original_source,
              next_system_prompt,
              round + 1,
            )
          }
        Clean(code~) => {
          let updated_source = @injector.inject(
            original_source,
            config.start_tag,
            config.end_tag,
            code,
          )
          @fs.write_file(config.target_file, updated_source)
          // Cheap pre-flight: `moon check` runs on this process's own machine
          // (never crosses the WSL2 bridge `prove_runner` may need), and
          // avoids paying for a `run_prove` round trip (an extra `wsl.exe`
          // process, any WSL2/network flakiness) for candidates that are
          // syntactically broken. It is not a substitute for `run_prove`'s
          // own syntax checking (see `check_gate.mbt` for the documented gap:
          // `moonc prove` can raise diagnostics plain `moon check` never
          // does), so a pass here still proceeds to a real `run_prove` call
          // rather than short-circuiting success.
          let gate = check_gate.run_check(
            config.native_module_root,
            config.package_path,
          )
          if gate.passed {
            run_prove_round(
              backend, check_gate, prove_runner, config, updated_source, system_prompt,
              round,
            )
          } else {
            let kind = gate.kind.unwrap_or(SyntaxError)
            let gate_outcome = @prover_loop.ProveOutcome::new(
              1,
              gate.raw_output,
              "",
              None,
            )
            if round >= config.max_rounds {
              RoundsExhausted(last_kind=kind, last_outcome=gate_outcome)
            } else {
              let repair_instructions = @prover_loop.build_repair_instructions(
                kind, gate_outcome,
              )
              let next_system_prompt = system_prompt +
                "\n\n" +
                repair_instructions
              loop_rounds(
                backend,
                check_gate,
                prove_runner,
                config,
                updated_source,
                next_system_prompt,
                round + 1,
              )
            }
          }
        }
      }
  }
}

///|
/// The `run_prove` half of a round: only reached once the cheap `moon
/// check` gate in `loop_rounds` has passed. Split out so `loop_rounds`
/// does not need a second, deeply-nested `if`/`else` arm for the gate
/// check.
async fn[
  B : @llm.LlmBackend,
  G : @prover_loop.CheckGate,
  R : @prover_loop.ProveRunner,
] run_prove_round(
  backend : B,
  check_gate : G,
  prove_runner : R,
  config : RunConfig,
  updated_source : String,
  system_prompt : String,
  round : Int,
) -> RunResult {
  let outcome = prove_runner.run_prove(
    config.module_root,
    config.package_path,
    config.pkg_name,
  )
  if @prover_loop.is_success(outcome) {
    VerificationSuccess(rounds_used=round)
  } else if round >= config.max_rounds {
    RoundsExhausted(
      last_kind=@prover_loop.classify(outcome),
      last_outcome=outcome,
    )
  } else {
    let kind = @prover_loop.classify(outcome)
    let repair_instructions = @prover_loop.build_repair_instructions(
      kind, outcome,
    )
    let next_system_prompt = system_prompt + "\n\n" + repair_instructions
    loop_rounds(
      backend,
      check_gate,
      prove_runner,
      config,
      updated_source,
      next_system_prompt,
      round + 1,
    )
  }
}
