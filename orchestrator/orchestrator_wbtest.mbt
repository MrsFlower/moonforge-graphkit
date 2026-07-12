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

///|
async test "whole-file responses for invariant regions are retried before injection" {
  let fixture = make_tagged_fixture()
  let target_file = @fs.tmpdir(prefix="moonforge_wbtest_fragment_") +
    "/target.mbt"
  @fs.write_file(target_file, fixture, create_mode=CreateOrTruncate)
  let backend = ScriptedBackend::new([
    "```mbt\n///|\npub fn bad() -> Int { 1 }\n```", "```mbt\nproof_invariant: lo <= hi,\n```",
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
        "expected retry after whole-file fragment rejection, got NeedsHumanReview: " +
        reason,
      )
    RoundsExhausted(_) =>
      fail("expected retry success after whole-file fragment rejection")
  }
  let written = @fs.read_file(target_file).text()
  assert_true(!written.contains("pub fn bad"))
  assert_true(written.contains("proof_invariant: lo <= hi"))
}

///|
async test "run_sequence fills regions cumulatively in order" {
  let fixture =
    #|before
    #|// A_START
    #|stale first
    #|// A_END
    #|between
    #|// B_START
    #|stale second
    #|// B_END
    #|after
  let target_file = @fs.tmpdir(prefix="moonforge_wbtest_sequence_") +
    "/target.mbt"
  @fs.write_file(target_file, fixture, create_mode=CreateOrTruncate)
  let backend = ScriptedBackend::new([
    "```mbt\nproof_invariant: a <= b,\n```", "```mbt\nproof_invariant: c <= d,\n```",
  ])
  let config : SequenceRunConfig = {
    module_root: "unused",
    native_module_root: "unused",
    package_path: "unused",
    pkg_name: "unused",
    target_file,
    regions: [
      {
        name: "first",
        start_tag: "// A_START",
        end_tag: "// A_END",
        user_task: "fill first",
      },
      {
        name: "second",
        start_tag: "// B_START",
        end_tag: "// B_END",
        user_task: "fill second",
      },
    ],
    max_rounds: 1,
    clear_current_region: true,
  }
  let result = run_sequence(
    backend,
    AlwaysPassesGate::{  },
    AlwaysSucceedsRunner::{  },
    config,
  )
  match result {
    SequenceSuccess(steps~) => {
      assert_eq(steps.length(), 2)
      assert_eq(steps[0].name, "first")
      assert_eq(steps[0].rounds_used, 1)
      assert_eq(steps[1].name, "second")
      assert_eq(steps[1].rounds_used, 1)
    }
    SequenceStopped(step_name~, ..) =>
      fail("expected sequence success, stopped at \{step_name}")
  }
  let written = @fs.read_file(target_file).text()
  assert_true(written.contains("proof_invariant: a <= b"))
  assert_true(written.contains("proof_invariant: c <= d"))
  assert_true(!written.contains("stale first"))
  assert_true(!written.contains("stale second"))
}
