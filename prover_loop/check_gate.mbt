///|
/// A cheap pre-flight gate run after `injector.inject` writes a candidate
/// region but before the (expensive, cross-process) `ProveRunner.run_prove`
/// call. Runs `moon check <package_path>` on the current machine — no Why3,
/// no SMT solver, no WSL2 bridge — and, when it fails, classifies the
/// failure using the same text-matching rules `diagnosis.classify_from_text`
/// already uses for `moon prove` output.
///
/// What this gate is, and is not:
/// - It is NOT faster because `moon prove` is slow to fail on a syntax
///   error: measured on this project's own machine, a syntax error surfaces
///   from the WSL2-bridged `moon prove` call in well under half a second
///   once the `wsl.exe` process pool is warm (Why3 is never invoked — the
///   MoonBit/`.mbtp` frontend rejects the file first). The real cost this
///   gate avoids is the WSL2 round-trip itself (an extra `wsl.exe` process,
///   any network/WSL2 flakiness) for the common case where the candidate
///   is syntactically broken, not a large latency win on the failing path.
/// - It does NOT fully subsume `moon prove`'s own syntax checking. `moon
///   check` and `moon prove` (via `moonc prove`) use different frontends:
///   probing this toolchain found a case where `moonc prove` raised a
///   second, prove-specific diagnostic (`only direct logic-function calls,
///   pure function calls, ... are supported in logic body`, error code
///   4207) that plain `moon check` never reports for the same file. A
///   candidate that passes this gate can still fail `run_prove` with
///   `SyntaxError` — callers must not skip that classification path just
///   because this gate passed.
/// - It cannot see anything about loop invariants, `proof_require`, or
///   `proof_ensure` *content* — `proof_invariant`/`proof_assert`/etc. are
///   ghost code, erased before `moon check`'s ordinary type-checking phase
///   even runs. Verified directly on this toolchain: an empty
///   `proof_invariant` block, and a body containing `proof_assert (1 ==
///   2)`, both pass `moon check` (and `moon test`) cleanly. This gate only
///   catches malformed *syntax* (unbound predicate names, malformed
///   quantifier nesting, missing commas, the legacy `invariant:` field,
///   ...), never a false-but-well-formed contract.
pub struct CheckGateResult {
  /// Whether `moon check` succeeded. When `false`, `kind` and `raw_output`
  /// describe the failure.
  passed : Bool
  /// Failure classification, reusing `diagnosis.FailureKind`. Always
  /// `SyntaxError` when `passed` is `false`, since `moon check` only ever
  /// reports parse/type/predicate-syntax errors — it has no path to
  /// `Unproved`/`ProverCrashed`, which are specific to the Why3 stage this
  /// gate never reaches.
  kind : FailureKind?
  /// Combined stdout+stderr from `moon check`, for building a repair
  /// prompt without re-running anything.
  raw_output : String
}

///|
/// Construct a `CheckGateResult` directly, for tests that need to feed a
/// scripted result to `orchestrator` without running a real `CheckGate`
/// (mirrors `ProveOutcome::new` for the same reason).
pub fn CheckGateResult::new(
  passed : Bool,
  kind : FailureKind?,
  raw_output : String,
) -> CheckGateResult {
  { passed, kind, raw_output }
}

///|
/// A pluggable way to run the `moon check` pre-flight gate, mirroring
/// `ProveRunner`'s shape for the same reason: `orchestrator`'s
/// control-flow tests (`orchestrator_wbtest.mbt`) need to exercise
/// round-by-round logic without shelling out to a real `moon` binary
/// against a real project directory, exactly as `AlwaysSucceedsRunner`
/// lets them skip a real `moon prove`/WSL2 round trip.
pub(open) trait CheckGate {
  async fn run_check(Self, module_root : String, package_path : String) -> CheckGateResult
}

///|
/// The real implementation: shells out to `moon check` on this process's
/// own machine. This is the default `CheckGate` every non-test caller
/// should use.
pub(all) struct RealCheckGate {}

///|
pub impl CheckGate for RealCheckGate with fn run_check(
  _self,
  module_root,
  package_path,
) {
  run_check_gate(module_root, package_path)
}

///|
/// Run `moon check <package_path>` on the current machine (the same
/// machine MoonForge's own process runs on — this gate never crosses the
/// WSL2 bridge, unlike `WslProveRunner`) against the module rooted at
/// `module_root`. Does not read or write any `.proof.json` report; `moon
/// check` never produces one.
///
/// Exposed as a free function (in addition to `RealCheckGate`'s trait
/// method, which just calls this) so `check_gate_test.mbt` can call it
/// directly without going through the trait indirection.
pub async fn run_check_gate(
  module_root : String,
  package_path : String,
) -> CheckGateResult {
  let result = @shell.run_capture(
    "moon",
    ["check", package_path],
    cwd=module_root,
  )
  let combined = result.stdout + "\n" + result.stderr
  if result.exit_code == 0 {
    { passed: true, kind: None, raw_output: combined }
  } else {
    // `moon check` reports a non-zero, tool-specific exit code (observed
    // 127 on this toolchain, not the POSIX "command not found" it usually
    // means) on any failure; the exit code itself carries no information
    // about *why* it failed, only that it did. Classification is always
    // text-based here, reusing the same substrings `diagnosis` already
    // trusts for `moon prove` syntax failures, since `moon check` failures
    // are drawn from the same MoonBit/`.mbtp` frontend errors.
    {
      passed: false,
      kind: Some(classify_from_text(combined)),
      raw_output: combined,
    }
  }
}
