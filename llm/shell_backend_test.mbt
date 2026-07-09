///|
async test "ShellBackend.complete round-trips a trivial prompt through codex exec" {
  let scratch = @fs.tmpdir(prefix="moonforge_llm_test_")
  let backend = ShellBackend::new(scratch, model="gpt-5.5")
  let reply = backend.complete(
    "You are a terse test fixture.", "Reply with exactly this text and nothing else: MOONFORGE_LLM_BACKEND_OK",
  )
  assert_true(reply.contains("MOONFORGE_LLM_BACKEND_OK"))
}
