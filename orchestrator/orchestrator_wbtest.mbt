///|
/// A scripted `LlmBackend` that returns a fixed sequence of replies, one
/// per call, for testing `orchestrator`'s round-by-round control flow
/// without any real LLM. Panics if called more times than it has replies
/// queued, so a test that expects N rounds must supply exactly N replies.
struct ScriptedBackend {
  replies : Array[String]
  mut next : Int
}

///|
fn ScriptedBackend::new(replies : Array[String]) -> ScriptedBackend {
  { replies, next: 0 }
}

///|
impl @llm.LlmBackend for ScriptedBackend with fn complete(
  self,
  _system_prompt,
  _user_prompt,
) {
  guard self.next < self.replies.length() else {
    fail("ScriptedBackend called more times than it has replies queued")
  }
  let reply = self.replies[self.next]
  self.next += 1
  reply
}

///|
/// A `ProveRunner` that always reports success, for testing rounds that
/// happen entirely before `moon prove` would ever be invoked (i.e. this
/// test only cares whether `orchestrator` gets far enough to call
/// `run_prove` at all).
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
/// A `CheckGate` that always reports a pass, for testing rounds that
/// happen entirely before the `moon check` pre-flight would matter — this
/// project's own toolchain integration for `run_check_gate` is covered by
/// `prover_loop/check_gate_test.mbt`'s real subprocess tests; these
/// control-flow tests only need a stand-in that never shells out.
struct AlwaysPassesGate {}

///|
impl @prover_loop.CheckGate for AlwaysPassesGate with fn run_check(
  _self,
  _module_root,
  _package_path,
) {
  @prover_loop.CheckGateResult::new(true, None, "")
}

///|
fn make_tagged_fixture() -> String {
  "before\n// START\n// END\nafter\n"
}

///|
/// A response with two fenced code blocks should not immediately end the
/// run: the fix for this project's Leanstral 1.5 evaluation (see
/// `MoonForge_PLAN.md`) is that `NeedsReview` gets a repair round just
/// like a `moon prove` failure does, instead of going straight to
/// `NeedsHumanReview` on the first bad response.
async test "a NeedsReview response is retried, not treated as terminal, when rounds remain" {
  let fixture = make_tagged_fixture()
  let target_file = @fs.tmpdir(prefix="moonforge_wbtest_") + "/target.mbt"
  @fs.write_file(target_file, fixture, create_mode=CreateOrTruncate)
  let backend = ScriptedBackend::new([
    "Here is my first attempt:\n```mbt\nfoo\n```\nand here is a corrected version:\n```mbt\nbar\n```",
    "```mbt\nproof_invariant: lo <= hi,\n```",
  ])
  let config : RunConfig = {
    module_root: "unused",
    native_module_root: "unused",
    package_path: "unused",
    pkg_name: "unused",
    target_file,
    start_tag: "// START",
    end_tag: "// END",
    user_task: "irrelevant for this test",
    max_rounds: 2,
  }
  let result = run(
    backend,
    AlwaysPassesGate::{  },
    AlwaysSucceedsRunner::{  },
    config,
  )
  match result {
    VerificationSuccess(rounds_used~) => assert_eq(rounds_used, 2)
    NeedsHumanReview(reason~) =>
      fail(
        "expected VerificationSuccess after the retry, got NeedsHumanReview: " +
        reason,
      )
    RoundsExhausted(_) =>
      fail("expected VerificationSuccess after the retry, got RoundsExhausted")
  }
}

///|
/// If every round is exhausted on `NeedsReview` responses, the run still
/// ends in `NeedsHumanReview` (not an infinite loop, and not silently
/// injecting the unreviewable response).
async test "NeedsReview exhausting all rounds still ends in NeedsHumanReview" {
  let fixture = make_tagged_fixture()
  let target_file = @fs.tmpdir(prefix="moonforge_wbtest_exhaust_") +
    "/target.mbt"
  @fs.write_file(target_file, fixture, create_mode=CreateOrTruncate)
  let bad_reply = "```mbt\nfoo\n```\n```mbt\nbar\n```"
  let backend = ScriptedBackend::new([bad_reply, bad_reply])
  let config : RunConfig = {
    module_root: "unused",
    native_module_root: "unused",
    package_path: "unused",
    pkg_name: "unused",
    target_file,
    start_tag: "// START",
    end_tag: "// END",
    user_task: "irrelevant for this test",
    max_rounds: 2,
  }
  let result = run(
    backend,
    AlwaysPassesGate::{  },
    AlwaysSucceedsRunner::{  },
    config,
  )
  match result {
    NeedsHumanReview(reason~) =>
      assert_true(reason.contains("multiple fenced code blocks"))
    VerificationSuccess(_) =>
      fail(
        "expected NeedsHumanReview after exhausting rounds, got VerificationSuccess",
      )
    RoundsExhausted(_) =>
      fail(
        "expected NeedsHumanReview after exhausting rounds, got RoundsExhausted",
      )
  }
}
