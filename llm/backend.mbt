///|
/// A pluggable LLM completion backend. `MoonForge` depends only on this
/// trait, never on a concrete provider, so the default backend can be
/// swapped (for example between `codex exec` and a direct HTTP call to an
/// OpenAI-compatible endpoint) without touching orchestration code.
pub(open) trait LlmBackend {
  /// Send `system_prompt` and `user_prompt` to the backend and return the
  /// model's final text response. Implementations should return only the
  /// model's raw text; any markdown/code-fence cleanup happens later in the
  /// `sanitizer` package, not here.
  async fn complete(Self, system_prompt : String, user_prompt : String) -> String
}
