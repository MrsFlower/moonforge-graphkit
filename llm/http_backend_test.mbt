///|
async test "HttpBackend.complete round-trips a trivial prompt through DeepSeek" {
  guard @env.get_env_var("DEEPSEEK_API_KEY") is Some(api_key) else {
    // No key configured in this environment; skip rather than fail so the
    // rest of the suite still runs on machines without DeepSeek access.
    return
  }
  let backend = HttpBackend::new(
    "https://api.deepseek.com/v1", api_key, "deepseek-chat",
  )
  let reply = backend.complete(
    "You are a terse test fixture.", "Reply with exactly this text and nothing else: MOONFORGE_HTTP_BACKEND_OK",
  )
  assert_true(reply.contains("MOONFORGE_HTTP_BACKEND_OK"))
}

///|
/// Mistral's Leanstral 1.5 (a formal-verification-specialized model,
/// `labs-leanstral-1-5`) reached over the same OpenAI-compatible
/// `/chat/completions` shape `HttpBackend` already speaks for DeepSeek.
/// Its account requires the "Labs models" org setting to be enabled (see
/// `MoonForge_PLAN.md`), and this development machine can only reach
/// `api.mistral.ai` through a local proxy (see
/// `.agents/skills/proxy-env/SKILL.md`) — both are opt-in via env vars so
/// this test skips cleanly on machines without them.
async test "HttpBackend.complete round-trips a trivial prompt through Mistral's Leanstral 1.5" {
  guard @env.get_env_var("MISTRAL_API_KEY") is Some(api_key) else {
    return
  }
  let proxy_url = @env.get_env_var("MOONFORGE_HTTP_PROXY")
  let backend = HttpBackend::new(
    "https://api.mistral.ai/v1", api_key, "labs-leanstral-1-5", proxy_url?,
  )
  let reply = backend.complete(
    "You are a terse test fixture.", "Reply with exactly this text and nothing else: MOONFORGE_LEANSTRAL_OK",
  )
  assert_true(reply.contains("MOONFORGE_LEANSTRAL_OK"))
}
