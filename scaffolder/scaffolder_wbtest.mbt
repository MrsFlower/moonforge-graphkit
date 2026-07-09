///|
/// A scripted `LlmBackend` that returns a fixed sequence of replies, one
/// per call, for testing `scaffolder`'s round-by-round control flow
/// without any real LLM. Mirrors `orchestrator_wbtest.mbt`'s
/// `ScriptedBackend` (a separate copy, not a shared helper, since each
/// package's white-box tests are self-contained and this project's own
/// convention keeps test doubles local rather than exported).
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
/// A `CheckGate` that always reports a pass, for testing rounds that
/// happen before or without needing a real `moon check` call.
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
/// A `CheckGate` that always reports the same syntax failure, for
/// testing the repair-and-retry path without a real `moon check` call.
struct AlwaysFailsGate {}

///|
impl @prover_loop.CheckGate for AlwaysFailsGate with fn run_check(
  _self,
  _module_root,
  _package_path,
) {
  @prover_loop.CheckGateResult::new(
    false, Some(@prover_loop.SyntaxError), "simulated syntax error",
  )
}

///|
async fn scratch_module_root() -> String {
  @fs.tmpdir(prefix="moonforge_scaffolder_wbtest_")
}

///|
fn valid_two_file_reply() -> String {
  "```mbt:widget.mbt\npub fn widget(x : Int) -> Int { x }\n```\n```mbtp:widget.mbtp\npredicate p(x : Int) { x >= 0 }\n```"
}

///|
async test "generate refuses to write into an already-existing package directory" {
  let module_root = scratch_module_root()
  @fs.mkdir(module_root + "/taken", recursive=true)
  let backend = ScriptedBackend::new([])
  let config : ScaffoldConfig = {
    module_root,
    package_path: "taken",
    pkg_name: "taken",
    user_task: "irrelevant for this test",
    invariant_tags: None,
    max_rounds: 1,
  }
  let result = generate(backend, AlwaysPassesGate::{  }, config)
  match result {
    NeedsHumanReview(reason~) => assert_true(reason.contains("already exists"))
    ScaffoldSuccess(_) => fail("expected NeedsHumanReview, got ScaffoldSuccess")
    RoundsExhausted(_) => fail("expected NeedsHumanReview, got RoundsExhausted")
  }
}

///|
async test "generate writes moon.pkg and both LLM-generated files on a clean pass" {
  let module_root = scratch_module_root()
  let backend = ScriptedBackend::new([valid_two_file_reply()])
  let config : ScaffoldConfig = {
    module_root,
    package_path: "widget",
    pkg_name: "widget",
    user_task: "irrelevant for this test",
    invariant_tags: None,
    max_rounds: 1,
  }
  let result = generate(backend, AlwaysPassesGate::{  }, config)
  match result {
    ScaffoldSuccess(package_dir~, files_written~) => {
      assert_eq(files_written.length(), 3)
      assert_true(files_written.contains("moon.pkg"))
      assert_true(files_written.contains("widget.mbt"))
      assert_true(files_written.contains("widget.mbtp"))
      assert_true(@fs.exists(package_dir + "/moon.pkg"))
      assert_true(@fs.exists(package_dir + "/widget.mbt"))
      assert_true(@fs.exists(package_dir + "/widget.mbtp"))
    }
    NeedsHumanReview(reason~) =>
      fail("expected ScaffoldSuccess, got NeedsHumanReview: " + reason)
    RoundsExhausted(_) => fail("expected ScaffoldSuccess, got RoundsExhausted")
  }
}

///|
async test "generate retries a NeedsReview response and succeeds on the next round" {
  let module_root = scratch_module_root()
  let backend = ScriptedBackend::new([
    "here is my attempt (no fences at all, just prose explaining what I would do)",
    valid_two_file_reply(),
  ])
  let config : ScaffoldConfig = {
    module_root,
    package_path: "widget",
    pkg_name: "widget",
    user_task: "irrelevant for this test",
    invariant_tags: None,
    max_rounds: 2,
  }
  let result = generate(backend, AlwaysPassesGate::{  }, config)
  match result {
    ScaffoldSuccess(_) => ()
    NeedsHumanReview(reason~) =>
      fail("expected ScaffoldSuccess after retry, got NeedsHumanReview: " + reason)
    RoundsExhausted(_) =>
      fail("expected ScaffoldSuccess after retry, got RoundsExhausted")
  }
}

///|
async test "generate rejects generated code that fails the purity gate" {
  let module_root = scratch_module_root()
  let impure_reply = "```mbt:widget.mbt\nimport moonbitlang/async\npub fn widget() -> Unit { println(\"hi\") }\n```\n```mbtp:widget.mbtp\npredicate p(x : Int) { x >= 0 }\n```"
  let backend = ScriptedBackend::new([impure_reply])
  let config : ScaffoldConfig = {
    module_root,
    package_path: "widget",
    pkg_name: "widget",
    user_task: "irrelevant for this test",
    invariant_tags: None,
    max_rounds: 1,
  }
  let result = generate(backend, AlwaysPassesGate::{  }, config)
  match result {
    NeedsHumanReview(reason~) => assert_true(reason.contains("purity gate"))
    ScaffoldSuccess(_) => fail("expected NeedsHumanReview, got ScaffoldSuccess")
    RoundsExhausted(_) => fail("expected NeedsHumanReview, got RoundsExhausted")
  }
}

///|
async test "generate exhausts rounds when the check gate always fails" {
  let module_root = scratch_module_root()
  let backend = ScriptedBackend::new([valid_two_file_reply(), valid_two_file_reply()])
  let config : ScaffoldConfig = {
    module_root,
    package_path: "widget",
    pkg_name: "widget",
    user_task: "irrelevant for this test",
    invariant_tags: None,
    max_rounds: 2,
  }
  let result = generate(backend, AlwaysFailsGate::{  }, config)
  match result {
    RoundsExhausted(last_kind~, raw_output~) => {
      assert_eq(last_kind, @prover_loop.SyntaxError)
      assert_true(raw_output.contains("simulated syntax error"))
    }
    ScaffoldSuccess(_) => fail("expected RoundsExhausted, got ScaffoldSuccess")
    NeedsHumanReview(reason~) =>
      fail("expected RoundsExhausted, got NeedsHumanReview: " + reason)
  }
}
