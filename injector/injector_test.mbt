///|
test "locate_region finds the region between tags" {
  let source =
    #|pub fn f(xs : FixedArray[Int]) -> Int {
    #|  // @MOONFORGE_INVARIANT_START
    #|  0
    #|  // @MOONFORGE_INVARIANT_END
    #|}
  let tagged = @injector.locate_region(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
  )
  assert_eq(tagged.region, "  0\n")
}

///|
test "inject replaces the tagged region and preserves the rest of the file" {
  let source =
    #|pub fn f(xs : FixedArray[Int]) -> Int {
    #|  // @MOONFORGE_INVARIANT_START
    #|  0
    #|  // @MOONFORGE_INVARIANT_END
    #|}
  let result = @injector.inject(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END", "  proof_invariant: 0 <= i,\n",
  )
  assert_eq(
    result,
    (
      #|pub fn f(xs : FixedArray[Int]) -> Int {
      #|  // @MOONFORGE_INVARIANT_START
      #|  proof_invariant: 0 <= i,
      #|  // @MOONFORGE_INVARIANT_END
      #|}
    ),
  )
}

///|
test "inject on an unchanged region round-trips byte for byte" {
  let source =
    #|before
    #|// @MOONFORGE_INVARIANT_START
    #|middle
    #|// @MOONFORGE_INVARIANT_END
    #|after
  let tagged = @injector.locate_region(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
  )
  let result = @injector.replace_region(tagged, tagged.region)
  assert_eq(result, source)
}

///|
test "locate_region fails when the start tag is missing" {
  let source =
    #|no tags here
    #|// @MOONFORGE_INVARIANT_END
  try
    @injector.locate_region(
      source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected locate_region to raise")
  }
}

///|
test "locate_region fails when the end tag is missing" {
  let source =
    #|// @MOONFORGE_INVARIANT_START
    #|no closing tag
  try
    @injector.locate_region(
      source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected locate_region to raise")
  }
}

///|
test "locate_region fails when both tags are entirely absent" {
  let source = "just some plain source code with no tags at all"
  try
    @injector.locate_region(
      source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected locate_region to raise")
  }
}

///|
test "locate_region fails when the end tag precedes the start tag" {
  let source =
    #|// @MOONFORGE_INVARIANT_END
    #|middle
    #|// @MOONFORGE_INVARIANT_START
  try
    @injector.locate_region(
      source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected locate_region to raise")
  }
}

///|
test "locate_region fails when the start tag appears twice" {
  let source =
    #|// @MOONFORGE_INVARIANT_START
    #|middle
    #|// @MOONFORGE_INVARIANT_START
    #|// @MOONFORGE_INVARIANT_END
  try
    @injector.locate_region(
      source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    )
    |> ignore
  catch {
    _ => ()
  } noraise {
    _ => fail("expected locate_region to raise")
  }
}

///|
test "locate_region handles an empty region between adjacent tags" {
  let source =
    #|// @MOONFORGE_INVARIANT_START
    #|// @MOONFORGE_INVARIANT_END
  let tagged = @injector.locate_region(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
  )
  assert_eq(tagged.region, "")
}

///|
test "inject on an empty region inserts new content cleanly" {
  let source =
    #|// @MOONFORGE_INVARIANT_START
    #|// @MOONFORGE_INVARIANT_END
  let result = @injector.inject(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END", "new content\n",
  )
  assert_eq(
    result,
    (
      #|// @MOONFORGE_INVARIANT_START
      #|new content
      #|// @MOONFORGE_INVARIANT_END
    ),
  )
}

///|
test "inject normalizes a region with no trailing newline so it does not merge with the end tag line" {
  let source =
    #|before
    #|// @MOONFORGE_INVARIANT_START
    #|// @MOONFORGE_INVARIANT_END
    #|after
  // Note: no trailing "\n" on the injected content, unlike the other
  // test cases in this file. This reproduces a real bug found during
  // orchestrator end-to-end testing: an LLM-authored region without a
  // final newline used to merge onto the same line as the end tag,
  // corrupting the next round's locate_region.
  let result = @injector.inject(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END", "invariant: 0 <= i,",
  )
  assert_eq(
    result,
    (
      #|before
      #|// @MOONFORGE_INVARIANT_START
      #|invariant: 0 <= i,
      #|// @MOONFORGE_INVARIANT_END
      #|after
    ),
  )
}

///|
test "a second inject round on the result of a no-trailing-newline round still locates the tags correctly" {
  let source =
    #|// @MOONFORGE_INVARIANT_START
    #|// @MOONFORGE_INVARIANT_END
  let after_round_one = @injector.inject(
    source, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END", "invariant: 0 <= i,",
  )
  let after_round_two = @injector.inject(
    after_round_one, "// @MOONFORGE_INVARIANT_START", "// @MOONFORGE_INVARIANT_END",
    "invariant: 0 <= i,\ninvariant: i <= n,",
  )
  assert_eq(
    after_round_two,
    (
      #|// @MOONFORGE_INVARIANT_START
      #|invariant: 0 <= i,
      #|invariant: i <= n,
      #|// @MOONFORGE_INVARIANT_END
    ),
  )
}
