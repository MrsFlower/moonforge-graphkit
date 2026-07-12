///|
test "strip_markdown extracts a single fenced mbt block" {
  let raw =
    #|Here is the invariant you asked for:
    #|```mbt
    #|proof_invariant: 0 <= i,
    #|proof_invariant: i <= xs.length(),
    #|```
    #|Let me know if you need adjustments.
  let result = @sanitizer.strip_markdown(raw)
  guard result is Clean(code~) else { fail("expected Clean, got NeedsReview") }
  assert_eq(
    code, "proof_invariant: 0 <= i,\nproof_invariant: i <= xs.length(),",
  )
}

///|
test "strip_markdown extracts a plain fenced block with no language tag" {
  let raw =
    #|```
    #|let x = 1
    #|```
  let result = @sanitizer.strip_markdown(raw)
  guard result is Clean(code~) else { fail("expected Clean, got NeedsReview") }
  assert_eq(code, "let x = 1")
}

///|
test "strip_markdown accepts fence-free code that has syntactic markers" {
  let raw = "proof_invariant: 0 <= i,"
  let result = @sanitizer.strip_markdown(raw)
  guard result is Clean(code~) else { fail("expected Clean, got NeedsReview") }
  assert_eq(code, "proof_invariant: 0 <= i,")
}

///|
test "strip_markdown flags fence-free prose for review" {
  let raw = "I looked at your project and I think the invariant should hold because the array stays sorted throughout the loop."
  let result = @sanitizer.strip_markdown(raw)
  assert_true(result is NeedsReview(_))
}

///|
test "strip_markdown flags multiple fenced blocks for review" {
  let raw =
    #|```mbt
    #|let a = 1
    #|```
    #|Also consider:
    #|```mbt
    #|let b = 2
    #|```
  let result = @sanitizer.strip_markdown(raw)
  assert_true(result is NeedsReview(_))
}

///|
test "strip_markdown flags an empty response for review" {
  let result = @sanitizer.strip_markdown("")
  assert_true(result is NeedsReview(_))
}

///|
test "strip_markdown flags whitespace-only response for review" {
  let result = @sanitizer.strip_markdown("   \n\n  \t  ")
  assert_true(result is NeedsReview(_))
}

///|
test "strip_markdown trims blank lines inside the fence" {
  let raw =
    #|```mbt
    #|
    #|let x = 1
    #|
    #|```
  let result = @sanitizer.strip_markdown(raw)
  guard result is Clean(code~) else { fail("expected Clean, got NeedsReview") }
  assert_eq(code, "let x = 1")
}

///|
test "validate_invariant_fragment accepts invariant-only code" {
  let code =
    #|proof_invariant: 0 <= i,
    #|proof_invariant: i <= xs.length(),
    #|proof_assert xs.length() == ys.length()
  let result = @sanitizer.validate_invariant_fragment(code)
  guard result is Clean(code~) else { fail("expected Clean, got NeedsReview") }
  assert_true(code.contains("proof_invariant"))
}

///|
test "validate_invariant_fragment rejects a whole function" {
  let code =
    #|///|
    #|pub fn isqrt(n : Int) -> Int {
    #|  n
    #|}
  let result = @sanitizer.validate_invariant_fragment(code)
  assert_true(result is NeedsReview(_))
}

///|
test "validate_invariant_fragment rejects top-level declarations without delimiter" {
  let code =
    #|pub struct Bad {
    #|  value : Int
    #|}
  let result = @sanitizer.validate_invariant_fragment(code)
  assert_true(result is NeedsReview(_))
}

///|
test "validate_invariant_fragment rejects repeated MoonForge tags" {
  let code =
    #|// @MOONFORGE_INVARIANT_START
    #|proof_invariant: 0 <= i,
    #|// @MOONFORGE_INVARIANT_END
  let result = @sanitizer.validate_invariant_fragment(code)
  assert_true(result is NeedsReview(_))
}

///|
test "build_invariant_fragment_repair_instructions asks for only tag contents" {
  let prompt = @sanitizer.build_invariant_fragment_repair_instructions(
    "response contains top-level MoonBit syntax",
  )
  assert_true(prompt.contains("ONLY the tagged invariant region"))
  assert_true(prompt.contains("Do not return the whole function"))
}
