///|
/// Outcome of cleaning a raw LLM response into something safe to inject
/// into a MoonBit source file.
pub enum SanitizeResult {
  /// The response contained exactly one fenced code block; `code` is its
  /// contents with the fence markers removed.
  Clean(code~ : String)
  /// The response could not be confidently reduced to pure code. `reason`
  /// explains why, so the caller can surface it for human review instead
  /// of silently writing prose into a source file.
  NeedsReview(reason~ : String)
} derive(Debug, Eq)

///|
/// Clean a raw LLM response into pure MoonBit source text.
///
/// Strategy:
/// 1. If the response contains one or more fenced code blocks (```` ``` ````
///    optionally tagged `mbt`/`moonbit`), extract the contents of the
///    *first* fence and require that no other fence follows. Multiple
///    fences usually mean the model included both an explanation and a
///    code block, or produced more than one candidate; either way, blindly
///    picking one wrong is worse than asking for review.
/// 2. If there are no fences at all, fall back to treating the whole
///    response as code, but only after a heuristic check that it does not
///    look like prose (see `looks_like_prose`). This keeps short, fence-free
///    completions usable while still catching the common failure mode of
///    the model explaining itself instead of returning code.
pub fn strip_markdown(raw : String) -> SanitizeResult {
  let fence_positions = find_all_fences(raw)
  match fence_positions {
    [] =>
      if looks_like_prose(raw) {
        NeedsReview(
          reason="no fenced code block found, and the response looks like prose rather than code",
        )
      } else {
        Clean(code=trim_edges(raw))
      }
    [open_idx, close_idx] => {
      // Exactly one fence pair (two fence markers): extract the interior.
      let after_open = skip_fence_line(raw, open_idx)
      let interior = raw[after_open:close_idx]
      Clean(code=trim_edges(interior.to_owned()))
    }
    _ =>
      NeedsReview(
        reason="response contains multiple fenced code blocks; refusing to guess which one is authoritative",
      )
  }
}

///|
/// Return the offsets (UTF-16 code unit positions) of every ` ``` ` fence
/// marker line-start in `text`, in order. A well-formed single code block
/// yields exactly two entries (open, close).
fn find_all_fences(text : String) -> Array[Int] {
  let positions = []
  let mut search_from = 0
  while text[search_from:].find("```") is Some(offset) {
    let absolute = search_from + offset
    positions.push(absolute)
    search_from = absolute + 3
    if search_from > text.length() {
      break
    }
  }
  positions
}

///|
/// Given the offset of an opening ` ``` ` marker, skip past the marker
/// itself and any language tag on the same line (e.g. ` ```mbt`), landing
/// on the first character of the fenced content.
fn skip_fence_line(text : String, fence_start : Int) -> Int {
  let after_backticks = fence_start + 3
  match text[after_backticks:].find("\n") {
    Some(newline_offset) => after_backticks + newline_offset + 1
    None => after_backticks
  }
}

///|
/// Trim leading/trailing blank lines and whitespace without disturbing
/// internal blank lines that may be meaningful MoonBit formatting.
fn trim_edges(text : String) -> String {
  text[:].trim(char_set=" \t\r\n").to_owned()
}

///|
/// Build repair instructions for a `NeedsReview` outcome, so `orchestrator`
/// can retry with a clearer instruction instead of immediately surfacing
/// `NeedsHumanReview`. Deliberately generic across every `NeedsReview`
/// reason `strip_markdown` can produce (multiple fenced code blocks,
/// fence-free prose, an empty response, ...): all of them mean "the
/// response wasn't reducible to exactly one authoritative code block", and
/// the fix is the same instruction either way. This has been observed to
/// matter in practice for models less familiar with this project's own
/// conventions than the primary `codex`/gpt-5.5 backend — for example
/// Mistral's Leanstral 1.5 (trained for Lean 4, not MoonBit) sometimes
/// returns a first attempt followed by a "corrected" second fenced block.
pub fn build_repair_instructions(reason : String) -> String {
  let header =
    #|The previous response could not be safely extracted as code:
    #|
  let footer =
    #|
    #|
    #|Return your answer as EXACTLY ONE fenced code block (a single ``` ... ```
    #|pair), containing only the requested code and nothing else: no
    #|alternative versions, no explanation before or after the fence, and no
    #|second fenced block showing a corrected or final version. If you want
    #|to revise your own draft, revise it silently and return only the
    #|final version, inside that single fence.
  header + reason + footer
}

///|
/// Heuristic check for "this text is natural-language explanation, not
/// MoonBit code". Intentionally conservative: it only flags text that has
/// none of the syntactic markers we would expect in even a single
/// unfenced MoonBit snippet, so it does not reject terse fence-free code.
fn looks_like_prose(text : String) -> Bool {
  let trimmed = text[:].trim(char_set=" \t\r\n")
  if trimmed.length() == 0 {
    return true
  }
  let code_markers = [
    "fn ", "let ", "pub ", "struct ", "enum ", "predicate ", "proof_", "#requires",
    "#ensures", "{", ";",
  ]
  let has_marker = code_markers.iter().any(marker => trimmed.contains(marker))
  !has_marker
}
