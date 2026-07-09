///|
/// A source file split around a tagged region:
/// before + start_tag_line + region + end_tag_line + after.
///
/// before/after include the tag lines' surrounding newlines exactly as
/// found, so reassembling with replace_region reproduces the original
/// file byte-for-byte when region is unchanged.
pub struct TaggedRegion {
  before : String
  start_tag_line : String
  region : String
  end_tag_line : String
  after : String
}

///|
/// Locate the region between a start_tag line and an end_tag line in
/// source (both tags must appear as whole lines, e.g.
/// "// @MOONFORGE_INVARIANT_START"). Fails loudly rather than silently
/// matching the wrong thing when a tag is missing, duplicated, or the end
/// tag precedes the start tag.
pub fn locate_region(
  source : String,
  start_tag : String,
  end_tag : String,
) -> TaggedRegion raise {
  let start_positions = find_all(source, start_tag)
  let end_positions = find_all(source, end_tag)
  guard start_positions is [start_at] else {
    fail(
      "expected exactly one occurrence of start tag \{start_tag}, found \{start_positions.length()}",
    )
  }
  guard end_positions is [end_at] else {
    fail(
      "expected exactly one occurrence of end tag \{end_tag}, found \{end_positions.length()}",
    )
  }
  guard start_at < end_at else {
    fail("end tag \{end_tag} appears before start tag \{start_tag}")
  }
  let before = source[:start_at].to_owned()
  let start_line_end = line_end_after(source, start_at)
  let start_tag_line = source[start_at:start_line_end].to_owned()
  let end_line_start = line_start_before(source, end_at)
  let region = source[start_line_end:end_line_start].to_owned()
  let end_line_end = line_end_after(source, end_at)
  let end_tag_line = source[end_line_start:end_line_end].to_owned()
  let after = source[end_line_end:].to_owned()
  { before, start_tag_line, region, end_tag_line, after }
}

///|
/// Reassemble a source file from a TaggedRegion, substituting new_region
/// for the original content between the tag lines. The tag lines
/// themselves are always preserved verbatim, so the tags remain in place
/// for the next round of injection.
///
/// new_region is normalized to end with exactly one newline (unless it is
/// empty) before being spliced in. Without this, a region that does not
/// end in a newline would merge onto the same line as the end-tag line,
/// which corrupts locate_region's line-based tag detection on the next
/// round: the merged line would then be mistaken for the end-tag line,
/// silently pulling this round's content into what the next
/// locate_region treats as immutable tag boilerplate, so it only ever
/// grows instead of being replaced.
pub fn replace_region(tagged : TaggedRegion, new_region : String) -> String {
  let normalized_region = ensure_trailing_newline(new_region)
  tagged.before +
  tagged.start_tag_line +
  normalized_region +
  tagged.end_tag_line +
  tagged.after
}

///|
/// Ensure text ends with exactly one newline, unless text is empty (an
/// empty region should stay empty, not become a single blank line).
fn ensure_trailing_newline(text : String) -> String {
  if text == "" {
    text
  } else if text.has_suffix("\n") {
    text
  } else {
    text + "\n"
  }
}

///|
/// Convenience wrapper: locate the region delimited by start_tag/end_tag
/// in source and replace its contents with new_region in one call.
pub fn inject(
  source : String,
  start_tag : String,
  end_tag : String,
  new_region : String,
) -> String raise {
  let tagged = locate_region(source, start_tag, end_tag)
  replace_region(tagged, new_region)
}

///|
/// Return every start offset at which needle occurs in haystack, without
/// overlapping matches.
fn find_all(haystack : String, needle : String) -> Array[Int] {
  let positions = []
  let mut search_from = 0
  while haystack[search_from:].find(needle) is Some(offset) {
    let absolute = search_from + offset
    positions.push(absolute)
    search_from = absolute + needle.length()
    if search_from > haystack.length() {
      break
    }
  }
  positions
}

///|
/// Offset just past the end of the line containing pos (i.e. just past
/// the newline, or end-of-string if pos's line is the last line).
fn line_end_after(text : String, pos : Int) -> Int {
  match text[pos:].find("\n") {
    Some(offset) => pos + offset + 1
    None => text.length()
  }
}

///|
/// Offset of the start of the line containing pos (i.e. just past the
/// preceding newline, or 0 if pos's line is the first line).
fn line_start_before(text : String, pos : Int) -> Int {
  match text[:pos].rev_find("\n") {
    Some(offset) => offset + 1
    None => 0
  }
}
