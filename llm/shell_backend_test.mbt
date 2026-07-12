///|
async test "ShellBackend.complete round-trips a trivial prompt through codex exec" {
  let scratch = @fs.tmpdir(prefix="moonforge_llm_test_")
  let backend = ShellBackend::new(scratch, model="gpt-5.5")
  let reply = backend.complete(
    "You are a terse test fixture.", "Reply with exactly this text and nothing else: MOONFORGE_LLM_BACKEND_OK",
  )
  assert_true(reply.contains("MOONFORGE_LLM_BACKEND_OK"))
}

///|
async test "ShellBackend.complete with activity_log streams real codex exec --json events to disk" {
  let scratch = @fs.tmpdir(prefix="moonforge_llm_test_")
  let log_path = scratch + "/activity.log"
  let backend = ShellBackend::new(
    scratch,
    model="gpt-5.5",
    activity_log=log_path,
  )
  let reply = backend.complete(
    "You are a terse test fixture.", "Reply with exactly this text and nothing else: MOONFORGE_LLM_BACKEND_JSON_OK",
  )
  assert_true(reply.contains("MOONFORGE_LLM_BACKEND_JSON_OK"))
  // Real `codex exec --json` output: one JSON object per line, so at
  // minimum this should not be empty and should look like JSONL, not
  // plain prose or the final-answer text alone.
  let logged = @fs.read_file(log_path).text()
  assert_true(logged.contains("{"))
  assert_true(logged.length() > 0)
}
