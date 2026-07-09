///|
test "split_scaffold_files accepts exactly two filename-tagged fences" {
  let raw =
    #|Here is the scaffold:
    #|```mbt:clamp.mbt
    #|pub fn clamp(lo : Int, hi : Int, x : Int) -> Int {
    #|  if x < lo { lo } else if x > hi { hi } else { x }
    #|}
    #|```
    #|```mbtp:clamp.mbtp
    #|predicate valid_bounds(lo : Int, hi : Int) { lo <= hi }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  guard result is ScaffoldClean(files~) else {
    fail("expected ScaffoldClean, got NeedsReview")
  }
  assert_eq(files.length(), 2)
  assert_eq(files[0].filename, "clamp.mbt")
  assert_true(files[0].content.contains("pub fn clamp"))
  assert_eq(files[1].filename, "clamp.mbtp")
  assert_true(files[1].content.contains("predicate valid_bounds"))
}

///|
test "split_scaffold_files rejects a fence with no filename in its info string" {
  let raw =
    #|```mbt
    #|pub fn clamp(x : Int) -> Int { x }
    #|```
    #|```mbtp:clamp.mbtp
    #|predicate p(x : Int) { x >= 0 }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  guard result is ScaffoldNeedsReview(reason~) else {
    fail("expected ScaffoldNeedsReview")
  }
  assert_true(reason.contains("lack a filename"))
}

///|
test "split_scaffold_files rejects fewer than two files" {
  let raw =
    #|```mbt:clamp.mbt
    #|pub fn clamp(x : Int) -> Int { x }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  guard result is ScaffoldNeedsReview(reason~) else {
    fail("expected ScaffoldNeedsReview")
  }
  assert_true(reason.contains("found 1"))
}

///|
test "split_scaffold_files rejects more than two files" {
  let raw =
    #|```mbt:a.mbt
    #|fn a() -> Unit { () }
    #|```
    #|```mbtp:a.mbtp
    #|predicate p(x : Int) { x >= 0 }
    #|```
    #|```mbt:b.mbt
    #|fn b() -> Unit { () }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  guard result is ScaffoldNeedsReview(reason~) else {
    fail("expected ScaffoldNeedsReview")
  }
  assert_true(reason.contains("found 3"))
}

///|
test "split_scaffold_files rejects two files of the same extension" {
  let raw =
    #|```mbt:a.mbt
    #|fn a() -> Unit { () }
    #|```
    #|```mbt:b.mbt
    #|fn b() -> Unit { () }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  guard result is ScaffoldNeedsReview(reason~) else {
    fail("expected ScaffoldNeedsReview")
  }
  assert_true(reason.contains("found 2 .mbt and 0 .mbtp"))
}

///|
test "split_scaffold_files rejects duplicate filenames" {
  let raw =
    #|```mbt:a.mbt
    #|fn a() -> Unit { () }
    #|```
    #|```mbtp:a.mbt
    #|predicate p(x : Int) { x >= 0 }
    #|```
  let result = @sanitizer.split_scaffold_files(raw)
  // Same filename "a.mbt" used for both fences means neither extension
  // check nor the duplicate check alone tells the full story; this
  // particular input actually fails the extension check first (0 .mbtp
  // files), which is still a correct NeedsReview outcome.
  assert_true(result is ScaffoldNeedsReview(_))
}

///|
test "split_scaffold_files rejects an empty response" {
  let result = @sanitizer.split_scaffold_files("")
  guard result is ScaffoldNeedsReview(reason~) else {
    fail("expected ScaffoldNeedsReview")
  }
  assert_true(reason.contains("no fenced code blocks"))
}

///|
test "build_scaffold_repair_instructions names the two-fence convention" {
  let instructions = @sanitizer.build_scaffold_repair_instructions(
    "found 1 fenced block(s)",
  )
  assert_true(instructions.contains("found 1 fenced block(s)"))
  assert_true(instructions.contains("```mbt:<name>.mbt"))
  assert_true(instructions.contains("```mbtp:<name>.mbtp"))
}
