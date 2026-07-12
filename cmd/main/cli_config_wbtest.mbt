///|
fn parse_scaffold_args(extra~ : Array[String]) -> @argparse.Matches raise {
  let matches = build_root_command().parse(
    argv=[
      "scaffold", "--module-root", "C:/tmp/moonforge", "--package-path", "demo",
      "--task", "verify a tiny function", "--api-key", "test-key", ..extra,
    ],
  )
  guard matches.subcommand is Some(("scaffold", sub_matches)) else {
    fail("expected scaffold subcommand")
  }
  sub_matches
}

///|
fn parse_fill_sequence_args(extra~ : Array[String]) -> @argparse.Matches raise {
  let matches = build_root_command().parse(
    argv=[
      "fill-sequence", "--module-root", "C:/tmp/moonforge", "--package-path", "demo",
      "--target-file", "C:/tmp/moonforge/demo/demo.mbt", "--plan-file", "C:/tmp/moonforge/sequence.json",
      "--api-key", "test-key", ..extra,
    ],
  )
  guard matches.subcommand is Some(("fill-sequence", sub_matches)) else {
    fail("expected fill-sequence subcommand")
  }
  sub_matches
}

///|
async test "resolve_backend defaults to HTTP when no backend flag is present" {
  let matches = parse_scaffold_args(extra=[])
  match resolve_backend(matches) {
    Http(_) => ()
    Shell(_) => fail("expected default backend to be HTTP")
  }
}

///|
async test "resolve_backend still allows explicit shell backend" {
  let matches = parse_scaffold_args(extra=[
    "--backend", "shell", "--scratch-dir", "C:/tmp/moonforge_cli_backend_test",
  ])
  match resolve_backend(matches) {
    Shell(_) => ()
    Http(_) => fail("expected explicit shell backend")
  }
}

///|
test "CLI spec advertises HTTP as the default backend" {
  let sub_matches = parse_scaffold_args(extra=[])
  guard optional_value(sub_matches, "backend") is Some("http") else {
    fail("expected CLI default backend to be http")
  }
  guard optional_value(sub_matches, "model-profile") is Some("deepseek") else {
    fail("expected CLI default model profile to be deepseek")
  }
  guard optional_value(sub_matches, "model") is None else {
    fail("expected --model to be resolved dynamically, not by argparse")
  }
  guard optional_value(sub_matches, "api-key-env") is None else {
    fail("expected --api-key-env to be resolved dynamically, not by argparse")
  }
}

///|
test "HTTP profile defaults resolve to DeepSeek and Leanstral settings" {
  let deepseek_matches = parse_scaffold_args(extra=[])
  guard resolve_http_profile(deepseek_matches) == "deepseek" else {
    fail("expected default HTTP profile to be deepseek")
  }
  guard default_http_base_url("deepseek") == "https://api.deepseek.com/v1" else {
    fail("expected DeepSeek base URL")
  }
  guard default_http_model("deepseek") == "deepseek-v4-pro" else {
    fail("expected DeepSeek default model")
  }
  guard default_http_api_key_env("deepseek") == "DEEPSEEK_API_KEY" else {
    fail("expected DeepSeek API key env")
  }
  let leanstral_matches = parse_scaffold_args(extra=[
    "--model-profile", "leanstral",
  ])
  guard resolve_http_profile(leanstral_matches) == "leanstral" else {
    fail("expected leanstral HTTP profile")
  }
  guard default_http_base_url("leanstral") == "https://api.mistral.ai/v1" else {
    fail("expected Mistral base URL")
  }
  guard default_http_model("leanstral") == "labs-leanstral-1-5" else {
    fail("expected Leanstral default model")
  }
  guard default_http_api_key_env("leanstral") == "MISTRAL_API_KEY" else {
    fail("expected Mistral API key env")
  }
}

///|
test "fill-sequence command is available and defaults to HTTP" {
  let matches = parse_fill_sequence_args(extra=[])
  guard optional_value(matches, "backend") is Some("http") else {
    fail("expected fill-sequence default backend to be http")
  }
  guard optional_value(matches, "model-profile") is Some("deepseek") else {
    fail("expected fill-sequence default model profile to be deepseek")
  }
  guard !matches.flags.get_or_default("clear-current-region", false) else {
    fail("expected clear-current-region to be opt-in")
  }
  let clear_matches = parse_fill_sequence_args(extra=["--clear-current-region"])
  guard clear_matches.flags.get_or_default("clear-current-region", false) else {
    fail("expected clear-current-region flag to parse")
  }
}

///|
test "parse_sequence_regions reads a compact JSON plan" {
  let regions = parse_sequence_regions(
    (
      #|{
      #|  "regions": [
      #|    {
      #|      "name": "find_min",
      #|      "start_tag": "// START_A",
      #|      "end_tag": "// END_A",
      #|      "task": "fill first region"
      #|    },
      #|    {
      #|      "start_tag": "// START_B",
      #|      "end_tag": "// END_B",
      #|      "task": "fill second region"
      #|    }
      #|  ]
      #|}
    ),
  )
  assert_eq(regions.length(), 2)
  assert_eq(regions[0].name, "find_min")
  assert_eq(regions[0].start_tag, "// START_A")
  assert_eq(regions[0].end_tag, "// END_A")
  assert_eq(regions[0].user_task, "fill first region")
  assert_eq(regions[1].name, "step-2")
  assert_eq(regions[1].start_tag, "// START_B")
  assert_eq(regions[1].end_tag, "// END_B")
  assert_eq(regions[1].user_task, "fill second region")
}
