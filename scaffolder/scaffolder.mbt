///|
/// Configuration for generating a brand-new MoonBit package from a
/// natural-language task description. Unlike `orchestrator.RunConfig`
/// (which fills in a tagged region of an *existing* file), `scaffolder`
/// creates the package directory, `moon.pkg`, `.mbt`, and `.mbtp` files
/// from nothing.
pub(all) struct ScaffoldConfig {
  /// Absolute path to the MoonBit module root (the directory with
  /// `moon.mod`), as seen by *this process*. `scaffolder` always runs
  /// `moon check` locally via `CheckGate` — it never crosses the WSL2
  /// bridge `orchestrator.RunConfig.module_root` sometimes needs for
  /// `ProveRunner`, so there is only one path convention here, not two.
  module_root : String
  /// New package's path relative to `module_root`, e.g. `"clamp"`. Must
  /// not already exist — `generate` refuses to write into a directory
  /// that might hold real project content (mirrors `injector`'s "ask,
  /// don't guess" discipline for ambiguous existing state).
  package_path : String
  /// Bare package name, used to name the generated files
  /// (`<pkg_name>.mbt` / `<pkg_name>.mbtp`).
  pkg_name : String
  /// Natural-language description of the algorithm/data structure to
  /// generate, becomes the LLM's user-facing task description.
  user_task : String
  /// When `Some((start_tag, end_tag))`, instructs the LLM to leave any
  /// loop invariants inside those tag lines empty, so a later
  /// `orchestrator.run` call can fill them in — the two pipelines are
  /// deliberately not auto-chained by this function; the caller decides
  /// whether and when to run `orchestrator.run` against the file this
  /// produces. `None` means the generated code should be fully
  /// self-contained (no loops needing separate invariant-filling, or the
  /// caller does not intend to follow up with `orchestrator.run`).
  invariant_tags : (String, String)?
  /// Maximum number of LLM <-> `moon check` rounds before giving up.
  /// Must be at least 1.
  max_rounds : Int
}

///|
/// Terminal outcome of a `scaffolder.generate` run.
pub(all) enum ScaffoldResult {
  /// `moon check` accepted the generated package within `max_rounds`.
  /// `files_written` lists the files actually written to disk (always
  /// `moon.pkg` plus the two LLM-generated files).
  ScaffoldSuccess(package_dir~ : String, files_written~ : Array[String])
  /// The target package already existed, the LLM's response could not be
  /// reduced to exactly the two files a scaffold needs (see
  /// `sanitizer.ScaffoldSanitizeResult`), or the generated content failed
  /// the purity gate before ever reaching `moon check`.
  NeedsHumanReview(reason~ : String)
  /// `max_rounds` were exhausted without `moon check` accepting the
  /// generated package.
  RoundsExhausted(last_kind~ : @prover_loop.FailureKind, raw_output~ : String)
}

///|
/// Generate a new MoonBit package at `config.module_root/config.package_path`
/// from `config.user_task`'s natural-language description: ask `backend`
/// for a `.mbt` file and a `.mbtp` file, sanitize the response into two
/// named files, write them (plus a fixed `moon.pkg`) to disk, and run the
/// cheap `moon check` gate. If the gate fails, build a targeted repair
/// prompt from the failure and try again, up to `config.max_rounds`
/// times.
///
/// As with `orchestrator.run`, this function performs the actual file
/// writes itself — the LLM backend never touches the filesystem (see the
/// safety note on `ShellBackend` in the `llm` package).
pub async fn[B : @llm.LlmBackend, G : @prover_loop.CheckGate] generate(
  backend : B,
  check_gate : G,
  config : ScaffoldConfig,
) -> ScaffoldResult {
  guard config.max_rounds >= 1 else { fail("max_rounds must be at least 1") }
  let package_dir = config.module_root + "/" + config.package_path
  guard !@fs.exists(package_dir) else {
    return NeedsHumanReview(
      reason="target package directory already exists: \{package_dir} — refusing to overwrite possibly-real content",
    )
  }
  let domain = @bouncer.classify_domain(config.user_task)
  let base_prompt = @bouncer.build_prompt(domain, config.user_task)
  let system_prompt = base_prompt.system_prompt +
    "\n\n" +
    scaffold_instructions(config)
  loop_rounds(backend, check_gate, config, system_prompt, 1)
}

///|
/// Instructions specific to scaffold generation: the two-file,
/// filename-tagged fence convention `sanitizer.split_scaffold_files`
/// expects, and (when present) the invariant-tag convention for loops
/// meant to be filled in later by `orchestrator.run`.
fn scaffold_instructions(config : ScaffoldConfig) -> String {
  // `\{...}` interpolation does not expand inside a `#|` multiline string
  // literal — verified directly on this toolchain: it is emitted
  // verbatim as literal text (`\{config.pkg_name}`), which is exactly
  // the bug that first shipped here (the LLM dutifully wrote a file
  // literally named `{config.pkg_name}.mbt`). The filename-bearing lines
  // are therefore built with regular interpolated strings and spliced
  // into the surrounding `#|` prose instead.
  let intro =
    #|You are generating a brand-new MoonBit package from scratch: exactly
    #|two files, a `<name>.mbt` file (executable code and `moon prove`
    #|contracts) and a `<name>.mbtp` file (predicate definitions used by
    #|those contracts).
    #|
    #|Return your answer as EXACTLY TWO fenced code blocks, each tagged
    #|with its filename after a colon:
    #|
  let fence_example = "```mbt:\{config.pkg_name}.mbt\n... MoonBit code here ...\n```\n\n" +
    "```mbtp:\{config.pkg_name}.mbtp\n... predicate definitions here ...\n```\n"
  let outro =
    #|
    #|Do not include any explanation outside the two fences. Do not import
    #|or call anything from `moonbitlang/async` or other side-effecting
    #|packages — this package must be pure, side-effect-free code.
  let base = intro + fence_example + outro
  match config.invariant_tags {
    Some((start_tag, end_tag)) =>
      base +
      "\n\nIf the algorithm requires a loop, leave that loop's `proof_invariant` lines empty and wrap the empty space with these exact tag lines on their own lines, so a later step can fill them in:\n" +
      start_tag +
      "\n" +
      end_tag
    None => base
  }
}

///|
async fn[B : @llm.LlmBackend, G : @prover_loop.CheckGate] loop_rounds(
  backend : B,
  check_gate : G,
  config : ScaffoldConfig,
  system_prompt : String,
  round : Int,
) -> ScaffoldResult {
  let raw_reply = backend.complete(system_prompt, config.user_task)
  let sanitized = @sanitizer.split_scaffold_files(raw_reply)
  match sanitized {
    ScaffoldNeedsReview(reason~) =>
      if round >= config.max_rounds {
        NeedsHumanReview(reason~)
      } else {
        let repair = @sanitizer.build_scaffold_repair_instructions(reason)
        loop_rounds(
          backend,
          check_gate,
          config,
          system_prompt + "\n\n" + repair,
          round + 1,
        )
      }
    ScaffoldClean(files~) => {
      let combined_source = files
        .map(f => f.content)
        .fold(init="", (acc, c) => acc + "\n" + c)
      let purity_issues = @bouncer.check_purity(combined_source)
      if purity_issues is [_, ..] {
        if round >= config.max_rounds {
          NeedsHumanReview(
            reason="generated code failed the purity gate: \{purity_issues.length()} issue(s) found",
          )
        } else {
          let repair =
            #|The generated code was rejected because it imports or calls
            #|something with side effects. This package must be pure,
            #|side-effect-free MoonBit code: no `moonbitlang/async`, no
            #|`println`, no filesystem or process access.
          loop_rounds(
            backend,
            check_gate,
            config,
            system_prompt + "\n\n" + repair,
            round + 1,
          )
        }
      } else {
        write_package(config, files)
        let gate = check_gate.run_check(config.module_root, config.package_path)
        if gate.passed {
          let package_dir = config.module_root + "/" + config.package_path
          ScaffoldSuccess(
            package_dir~,
            files_written=["moon.pkg", ..files.map(f => f.filename)],
          )
        } else {
          let kind = gate.kind.unwrap_or(SyntaxError)
          if round >= config.max_rounds {
            RoundsExhausted(last_kind=kind, raw_output=gate.raw_output)
          } else {
            let gate_outcome = @prover_loop.ProveOutcome::new(
              1,
              gate.raw_output,
              "",
              None,
            )
            let repair = @prover_loop.build_repair_instructions(
              kind, gate_outcome,
            )
            loop_rounds(
              backend,
              check_gate,
              config,
              system_prompt + "\n\n" + repair,
              round + 1,
            )
          }
        }
      }
    }
  }
}

///|
/// Write the fixed `moon.pkg` and the LLM-generated files to
/// `config.module_root/config.package_path`. Always (re)writes all
/// files on every round, matching `injector.inject`'s per-round rewrite
/// discipline in `orchestrator` — a repair round's response fully
/// replaces the previous attempt rather than patching it.
async fn write_package(
  config : ScaffoldConfig,
  files : Array[@sanitizer.ScaffoldFile],
) -> Unit {
  let package_dir = config.module_root + "/" + config.package_path
  @fs.mkdir(package_dir, recursive=true) catch {
    _ => () // already exists is fine; a real failure surfaces on the writes below
  }
  @fs.write_file(
    package_dir + "/moon.pkg",
    fixed_moon_pkg_contents(),
    create_mode=CreateOrTruncate,
  )
  for f in files {
    @fs.write_file(
      package_dir + "/" + f.filename,
      f.content,
      create_mode=CreateOrTruncate,
    )
  }
}

///|
/// The `moon.pkg` every scaffolded package gets. Fixed rather than
/// LLM-generated: it is always the same three lines for a proof-enabled
/// package with no extra imports, so generating it would only add a
/// chance for the LLM to invent unsupported options — see
/// `moonbit-proof/TODO.md`'s note that an empty `moon.pkg` must not be
/// written as `{}`.
fn fixed_moon_pkg_contents() -> String {
  "options(\n  \"proof-enabled\": true,\n)\n"
}
