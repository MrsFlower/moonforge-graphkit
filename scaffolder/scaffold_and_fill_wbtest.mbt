///|
/// A `ProveRunner` that always reports success, for testing
/// `generate_and_fill`'s handoff into `orchestrator.run` without a real
/// `moon prove`/WSL2 round trip. Mirrors `orchestrator_wbtest.mbt`'s
/// `AlwaysSucceedsRunner` (kept as a separate local copy — see
/// `scaffolder_wbtest.mbt`'s note on why test doubles are not shared
/// across packages here).
struct AlwaysSucceedsRunner {}

///|
impl @prover_loop.ProveRunner for AlwaysSucceedsRunner with fn run_prove(
  _self,
  _module_root,
  _package_path,
  _pkg_name,
) {
  @prover_loop.ProveOutcome::new(
    0,
    "",
    "",
    Some(
      @json.parse(
        "{\"result\":\"success\",\"summary\":{\"valid\":1,\"invalid\":0,\"timeout\":0,\"oom\":0,\"step_limit\":0,\"unknown\":0,\"failure\":0}}",
      ),
    ),
  )
}

///|
/// A reply carrying a loop whose invariant region is tagged and left
/// empty, matching what `generate` is instructed to produce when
/// `invariant_tags` is `Some`.
fn scaffold_reply_with_tagged_loop(start_tag : String, end_tag : String) -> String {
  "```mbt:searchy.mbt\npub fn searchy(n : Int) -> Int {\n  for lo = 0, hi = n; lo < hi; {\n    continue lo + 1, hi\n  } nobreak {\n    lo\n  } where {\n    \{start_tag}\n    \{end_tag}\n  }\n}\n```\n```mbtp:searchy.mbtp\npredicate ok(n : Int) { n >= 0 }\n```"
}

///|
async test "generate_and_fill rejects a config whose invariant_tags is None" {
  let module_root = scratch_module_root()
  let backend = ScriptedBackend::new([])
  let scaffold_config : ScaffoldConfig = {
    module_root,
    package_path: "searchy",
    pkg_name: "searchy",
    user_task: "irrelevant",
    invariant_tags: None,
    max_rounds: 1,
  }
  let config : ScaffoldAndFillConfig = {
    scaffold: scaffold_config,
    prove_module_root: module_root,
    fill_task: "irrelevant",
    fill_max_rounds: 1,
  }
  try
    generate_and_fill(
      backend, AlwaysPassesGate::{  }, AlwaysSucceedsRunner::{  }, config,
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected generate_and_fill to raise when invariant_tags is None")
  }
}

///|
async test "generate_and_fill chains a successful scaffold into a successful fill-in" {
  let module_root = scratch_module_root()
  let start_tag = "// @START"
  let end_tag = "// @END"
  let backend = ScriptedBackend::new([
    scaffold_reply_with_tagged_loop(start_tag, end_tag),
    "```mbt\nproof_invariant: 0 <= lo,\n```",
  ])
  let scaffold_config : ScaffoldConfig = {
    module_root,
    package_path: "searchy",
    pkg_name: "searchy",
    user_task: "irrelevant",
    invariant_tags: Some((start_tag, end_tag)),
    max_rounds: 1,
  }
  let config : ScaffoldAndFillConfig = {
    scaffold: scaffold_config,
    prove_module_root: module_root,
    fill_task: "irrelevant",
    fill_max_rounds: 1,
  }
  let result = generate_and_fill(
    backend, AlwaysPassesGate::{  }, AlwaysSucceedsRunner::{  }, config,
  )
  match result {
    FullSuccess(fill_rounds_used~, ..) => assert_eq(fill_rounds_used, 1)
    ScaffoldStageFailed(_) =>
      fail("expected FullSuccess, got ScaffoldStageFailed")
    FillStageFailed(_) => fail("expected FullSuccess, got FillStageFailed")
  }
}

///|
async test "generate_and_fill surfaces a scaffold-stage failure without attempting the fill-in stage" {
  let module_root = scratch_module_root()
  let start_tag = "// @START"
  let end_tag = "// @END"
  // Never produces a valid two-file response, so the scaffold stage
  // exhausts its single round; the fill-in stage must never be attempted
  // (there would be no target file to fill in).
  let backend = ScriptedBackend::new(["this is not a fenced response at all"])
  let scaffold_config : ScaffoldConfig = {
    module_root,
    package_path: "searchy",
    pkg_name: "searchy",
    user_task: "irrelevant",
    invariant_tags: Some((start_tag, end_tag)),
    max_rounds: 1,
  }
  let config : ScaffoldAndFillConfig = {
    scaffold: scaffold_config,
    prove_module_root: module_root,
    fill_task: "irrelevant",
    fill_max_rounds: 1,
  }
  let result = generate_and_fill(
    backend, AlwaysPassesGate::{  }, AlwaysSucceedsRunner::{  }, config,
  )
  assert_true(result is ScaffoldStageFailed(_))
}
