///|
/// A single chat message in the OpenAI-compatible `/chat/completions`
/// request body.
priv struct ChatMessage {
  role : String
  content : String
} derive(ToJson)

///|
priv struct ChatRequest {
  model : String
  messages : Array[ChatMessage]
} derive(ToJson)

///|
priv struct ChatChoiceMessage {
  content : String
} derive(FromJson)

///|
priv struct ChatChoice {
  message : ChatChoiceMessage
} derive(FromJson)

///|
priv struct ChatResponse {
  choices : Array[ChatChoice]
} derive(FromJson)

///|
/// Secondary LLM backend: connects directly to an OpenAI-compatible
/// `/chat/completions` endpoint over HTTP, bypassing any local CLI tool.
/// Used to reach providers that are only available via API key (for
/// example DeepSeek, or Mistral's Leanstral models) or as a fallback when
/// the `codex` session backing `ShellBackend` is unavailable, expired, or
/// rate-limited.
pub struct HttpBackend {
  /// Base URL up to but not including `/chat/completions`, e.g.
  /// `"https://api.deepseek.com/v1"`.
  base_url : String
  api_key : String
  model : String
  /// Optional HTTP proxy the underlying `@http.Client` should tunnel
  /// through, e.g. `"http://192.168.1.161:7897"`. Some providers are only
  /// reachable from this project's development machine via a local proxy
  /// (see `.agents/skills/proxy-env/SKILL.md`); others (e.g. DeepSeek) are
  /// reachable directly. `None` connects without a proxy.
  proxy_url : String?
  /// Optional text appended to every `system_prompt` this backend
  /// receives, after `bouncer`'s domain rules and before nothing else
  /// (it is always the last thing the model reads before the user task).
  /// Used for backend-specific guidance that has nothing to do with the
  /// target's domain (DeFi/graph/...) but everything to do with this
  /// particular model's own known habits — see `leanstral_prompt_addendum`
  /// for the motivating case. `None` sends `system_prompt` unmodified.
  extra_system_prompt : String?
}

///|
pub fn HttpBackend::new(
  base_url : String,
  api_key : String,
  model : String,
  proxy_url? : String,
  extra_system_prompt? : String,
) -> HttpBackend {
  { base_url, api_key, model, proxy_url, extra_system_prompt }
}

///|
/// Backend-specific system-prompt addendum for Mistral's Leanstral 1.5.
/// Leanstral is trained for Lean 4 proof engineering, not MoonBit.
///
/// A first version of this addendum (see `MoonForge_PLAN.md` section 15/16
/// for the full evaluation writeup) stated the two observed Lean-4-habit
/// mistakes as descriptive rules ("do not invent a predicate", "do not
/// reference `result`"). That version was measured, not assumed, to make
/// things *worse*: a follow-up evaluation run (5 full pipeline runs plus 3
/// raw-probe calls) found the descriptive-rules version reduced the
/// `isqrt` convergence rate from 8/9 (without any addendum) to 1/5, and 0
/// of the 3 raw probes actually followed either rule — they kept using the
/// legacy `invariant:` field and referencing `result` in the loop body
/// exactly as before. This is consistent with reasoning-specialized models
/// often having weak instruction-following for prohibitive meta-rules
/// ("don't do X") even when their underlying mathematical reasoning is
/// sound; a worked example of the *correct* pattern is the fix that was
/// actually tested and kept.
///
/// This version instead gives one small, complete, worked example of a
/// correctly-shaped `proof_invariant` block for a binary search unrelated
/// to any of this project's real fixtures (so it cannot be copied
/// verbatim as the answer), demonstrating both points positively: every
/// invariant uses `proof_invariant:` (never the legacy `invariant:`), and
/// every invariant only mentions the loop's own state variables, never the
/// function's `result` binding.
pub let leanstral_prompt_addendum : String =
  #|You are Leanstral, trained for Lean 4 proof engineering. This task is
  #|MoonBit, not Lean 4. Here is a worked example of the exact shape this
  #|toolchain expects for a whole function's contract AND a loop's
  #|invariant block (a different function than the one you are asked
  #|about below, shown only to demonstrate the required syntax):
  #|
  #|```mbt
  #|// Function: find the largest index `i` in a sorted, ascending array
  #|// `xs` such that `xs[i] <= target` (or -1 if none exists).
  #|fn search(xs : Array[Int], target : Int) -> Int where {
  #|  proof_require: sorted(xs),
  #|  proof_ensure: result => search_post(xs, target, result),
  #|} {
  #|  for lo = -1, hi = xs.length(); lo < hi - 1; {
  #|    let mid = lo + (hi - lo) / 2
  #|    if xs[mid] <= target {
  #|      continue mid, hi
  #|    } else {
  #|      continue lo, mid
  #|    }
  #|  } nobreak {
  #|    lo
  #|  } where {
  #|    proof_invariant: -1 <= lo,
  #|    proof_invariant: lo < hi,
  #|    proof_invariant: hi <= xs.length(),
  #|    proof_invariant: below_target(xs, target, lo),
  #|  }
  #|}
  #|```
  #|
  #|Notice several things about this shape: (1) the function's own
  #|precondition/postcondition go in a `where { ... }` clause attached to
  #|the function SIGNATURE, between the return type and the opening `{` of
  #|the body — never as bare statements inside the body (`proof_require
  #|sorted(xs)` written as a body statement is invalid and will not
  #|compile); (2) every field there uses a colon and ends with a comma
  #|(`proof_require: ...,`, `proof_ensure: ...,`); (3) the loop's own
  #|`where { ... }` block (attached to the loop, not the function) is a
  #|separate block using `proof_invariant:` lines, never the older
  #|`invariant:`; and (4) each `proof_invariant` line only mentions this
  #|loop's own state variables (`lo`, `hi`) and predicates already declared
  #|elsewhere (`below_target`) — none of them mention `result`, because
  #|`result` is the function's return value, bound only in the
  #|function-level `proof_ensure` postcondition, not inside the loop body.
  #|Follow this same shape for the task below.

///|
pub impl LlmBackend for HttpBackend with fn complete(
  self,
  system_prompt,
  user_prompt,
) {
  let system_prompt = match self.extra_system_prompt {
    Some(extra) => system_prompt + "\n\n" + extra
    None => system_prompt
  }
  let request = ChatRequest::{
    model: self.model,
    messages: [
      { role: "system", content: system_prompt },
      { role: "user", content: user_prompt },
    ],
  }
  let body = request.to_json().stringify()
  let headers = {
    "Authorization": "Bearer " + self.api_key,
    "Content-Type": "application/json",
    "Connection": "close",
  }
  let proxy = match self.proxy_url {
    Some(proxy_url) => Some(@http.Client(proxy_url))
    None => None
  }
  let (response, response_body) = @http.post(
    self.base_url + "/chat/completions",
    body,
    headers~,
    proxy?,
  )
  if response.code < 200 || response.code >= 300 {
    fail(
      "HTTP backend request failed: \{response.code} \{response.reason}\nbody: \{response_body.text()}",
    )
  }
  let parsed : ChatResponse = @json.from_json(response_body.json())
  guard parsed.choices is [first, ..] else {
    fail("HTTP backend returned no choices in response")
  }
  first.message.content
}
