///|
/// One file extracted from a scaffold-generation response: a fenced code
/// block whose info string names the file it belongs to, e.g.
/// ` ```mbt:clamp.mbt `. Named distinctly from `SanitizeResult`'s `Clean`
/// (see `sanitizer.mbt`) because a scaffold response carries multiple
/// named files, not one anonymous code block.
pub struct ScaffoldFile {
  filename : String
  content : String
} derive(Eq)

///|
/// Outcome of parsing a scaffold-generation response into named files.
pub enum ScaffoldSanitizeResult {
  /// The response contained exactly the two files a scaffold needs — one
  /// `.mbt` and one `.mbtp`, each in its own fenced block whose info
  /// string named it. `files` preserves the order they appeared in.
  ScaffoldClean(files~ : Array[ScaffoldFile])
  /// The response could not be confidently reduced to exactly one `.mbt`
  /// and one `.mbtp` file. `reason` explains why, so the caller can retry
  /// with a clearer instruction instead of guessing which fence is which
  /// file (the same "ask, don't guess" discipline `strip_markdown` uses
  /// for multiple anonymous fences).
  ScaffoldNeedsReview(reason~ : String)
} derive(Eq)

///|
/// Parse a raw scaffold-generation response into exactly one `.mbt` file
/// and one `.mbtp` file. Requires each fence's info string to name its
/// file (` ```mbt:<name>.mbt ` / ` ```mbtp:<name>.mbtp `) — unlike
/// `strip_markdown`'s single anonymous block, a scaffold response is
/// inherently multi-file, so there is no positional convention ("first
/// fence is the .mbt") safe enough to guess from silently.
pub fn split_scaffold_files(raw : String) -> ScaffoldSanitizeResult {
  let fences = find_scaffold_fences(raw)
  if fences.length() == 0 {
    return ScaffoldNeedsReview(reason="no fenced code blocks found in the response")
  }
  let unlabeled = fences.iter().filter(f => f.filename is None).count()
  if unlabeled > 0 {
    return ScaffoldNeedsReview(
      reason="found \{fences.length()} fenced block(s), but \{unlabeled} lack a filename in the fence info string (expected e.g. ```mbt:<name>.mbt)",
    )
  }
  if fences.length() != 2 {
    return ScaffoldNeedsReview(
      reason="expected exactly 2 fenced files (one .mbt, one .mbtp), found \{fences.length()}",
    )
  }
  let files : Array[ScaffoldFile] = fences.map(f => ScaffoldFile::{
    filename: f.filename.unwrap(),
    content: f.content,
  })
  let mbt_count = files.iter().filter(f => f.filename.has_suffix(".mbt")).count()
  let mbtp_count = files.iter().filter(f => f.filename.has_suffix(".mbtp")).count()
  if mbt_count != 1 || mbtp_count != 1 {
    return ScaffoldNeedsReview(
      reason="expected exactly one .mbt file and one .mbtp file, found \{mbt_count} .mbt and \{mbtp_count} .mbtp",
    )
  }
  let distinct_names = {}
  for f in files {
    distinct_names[f.filename] = true
  }
  if distinct_names.length() != files.length() {
    return ScaffoldNeedsReview(reason="duplicate filenames across fenced blocks")
  }
  ScaffoldClean(files~)
}

///|
priv struct RawFence {
  filename : String?
  content : String
}

///|
/// Find every fenced block in `text` along with the filename named in its
/// info string, if any (` ```mbt:name.mbt ` -> `Some("name.mbt")`;
/// ` ```mbt ` or ` ``` ` alone -> `None`).
fn find_scaffold_fences(text : String) -> Array[RawFence] {
  let fences = []
  let mut search_from = 0
  while text[search_from:].find("```") is Some(offset) {
    let open_at = search_from + offset
    let info_line_end = match text[open_at + 3:].find("\n") {
      Some(nl) => open_at + 3 + nl
      None => text.length()
    }
    let info_string = text[open_at + 3:info_line_end].to_owned()
    let content_start = if info_line_end < text.length() {
      info_line_end + 1
    } else {
      info_line_end
    }
    match text[content_start:].find("```") {
      Some(close_offset) => {
        let close_at = content_start + close_offset
        let content = text[content_start:close_at].to_owned()
        let filename = parse_fence_filename(info_string)
        fences.push(
          RawFence::{ filename, content: trim_scaffold_content(content) },
        )
        search_from = close_at + 3
      }
      None =>
        // Unclosed fence: stop scanning rather than looping forever or
        // misreading the remainder of the file as fence content.
        search_from = text.length()
    }
    if search_from > text.length() {
      break
    }
  }
  fences
}

///|
/// Extract the filename from a fence info string like `"mbt:clamp.mbt"`.
/// Returns `None` for a bare language tag (`"mbt"`) or no tag (`""`) —
/// both mean the fence did not name its file.
fn parse_fence_filename(info_string : String) -> String? {
  let trimmed = info_string[:].trim(char_set=" \t\r").to_owned()
  match trimmed.split_once(":") {
    Some((_lang, filename)) => {
      let name = filename[:].trim(char_set=" \t\r").to_owned()
      if name == "" {
        None
      } else {
        Some(name)
      }
    }
    None => None
  }
}

///|
fn trim_scaffold_content(text : String) -> String {
  text[:].trim(char_set=" \t\r\n").to_owned()
}

///|
/// Build repair instructions for a `ScaffoldNeedsReview` outcome. Mirrors
/// `sanitizer.build_repair_instructions`'s "explain what was expected, ask
/// for exactly that" shape, but spells out the two-file, filename-tagged
/// fence convention scaffold generation requires.
pub fn build_scaffold_repair_instructions(reason : String) -> String {
  let header =
    #|The previous response could not be split into the two files this
    #|scaffold needs:
    #|
  let footer =
    #|
    #|
    #|Return your answer as EXACTLY TWO fenced code blocks: one tagged
    #|```mbt:<name>.mbt containing the executable code and contracts, and
    #|one tagged ```mbtp:<name>.mbtp containing the predicate definitions
    #|— for example:
    #|
    #|```mbt:clamp.mbt
    #|... MoonBit code here ...
    #|```
    #|
    #|```mbtp:clamp.mbtp
    #|... predicate definitions here ...
    #|```
    #|
    #|Do not omit the filename after the colon, do not add any other
    #|fenced blocks, and do not include any explanation outside the two
    #|fences.
  header + reason + footer
}
