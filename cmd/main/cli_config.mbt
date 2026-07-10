///|
/// Runtime backend/runner selection and config-building from parsed
/// `argparse.Matches`. `orchestrator.run`/`scaffolder.generate*` are
/// compile-time generic over their trait-bounded type parameters, so a
/// `--backend`/`--prove-runner` flag chosen at runtime needs a small
/// dispatching wrapper to feed into a single call site.

///|
enum AnyBackend {
  Shell(@llm.ShellBackend)
  Http(@llm.HttpBackend)
}

///|
impl @llm.LlmBackend for AnyBackend with fn complete(
  self,
  system_prompt,
  user_prompt,
) {
  match self {
    Shell(backend) => backend.complete(system_prompt, user_prompt)
    Http(backend) => backend.complete(system_prompt, user_prompt)
  }
}

///|
enum AnyProveRunner {
  Wsl(@prover_loop.WslProveRunner)
  Local(@prover_loop.LocalProveRunner)
}

///|
impl @prover_loop.ProveRunner for AnyProveRunner with fn run_prove(
  self,
  module_root,
  package_path,
  pkg_name,
) {
  match self {
    Wsl(runner) => runner.run_prove(module_root, package_path, pkg_name)
    Local(runner) => runner.run_prove(module_root, package_path, pkg_name)
  }
}

///|
/// Read a single required option value out of `matches.values`, raising a
/// clear usage error if it is absent (should not normally happen for a
/// `required=true` `OptionArg`, since `argparse` itself already enforces
/// that — this is a defensive fallback, not the primary validation path).
fn required_value(matches : @argparse.Matches, name : String) -> String raise {
  guard matches.values.get(name) is Some([value, ..]) else {
    fail("missing required argument: --\{name}")
  }
  value
}

///|
/// Read a single optional option value out of `matches.values`.
fn optional_value(matches : @argparse.Matches, name : String) -> String? {
  match matches.values.get(name) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
/// `--pkg-name` defaults to the last `/`-separated segment of
/// `--package-path` when not given explicitly.
fn resolve_pkg_name(
  matches : @argparse.Matches,
  package_path : String,
) -> String {
  match optional_value(matches, "pkg-name") {
    Some(name) => name
    None =>
      match package_path.rev_split_once("/") {
        Some((_, last)) => last.to_owned()
        None => package_path
      }
  }
}

///|
/// Reject values that would land inside `WslProveRunner`'s single-quoted
/// shell splice (`cd '<module_root>' && moon prove '<package_path>'`) —
/// `prover_loop.WslProveRunner` does no escaping of its own (see
/// `docs/LESSONS.md`), so the CLI is the only place this can be caught
/// before an embedded `'` breaks out of the quoting.
fn validate_no_shell_metacharacters(
  value : String,
  field_name : String,
) -> Unit raise {
  guard !value.contains("'") else {
    fail(
      "--\{field_name} must not contain a single-quote character (would break out of WslProveRunner's shell quoting): \{value}",
    )
  }
}

///|
/// Derive a WSL2-internal path from a Windows path, following the
/// standard `C:\...`/`C:/...` -> `/mnt/c/...` drive-mount convention. This
/// is this project's own dev-machine convention, not guaranteed on every
/// WSL2 setup — `--wsl-module-root`/`--prove-module-root` override this
/// when it does not apply.
fn windows_path_to_wsl(path : String) -> String raise {
  let normalized = path.replace_all(old="\\", new="/")
  guard normalized.get_char(1) is Some(':') &&
    normalized.get_char(0) is Some(drive_char) else {
    fail(
      "cannot derive a WSL2 path from \{path}: expected a Windows drive path like C:/... (pass --wsl-module-root/--prove-module-root explicitly instead)",
    )
  }
  let drive = "\{drive_char}".to_lower()
  let rest = normalized[2:].to_owned()
  "/mnt/" + drive + rest
}

///|
/// Resolve the `--<prefix>`/`--<prefix>-file` pair into task text (the
/// `argparse.ArgGroup` on the command spec already enforces exactly one of
/// the two is given).
async fn resolve_task_text(
  matches : @argparse.Matches,
  prefix : String,
) -> String {
  match optional_value(matches, prefix) {
    Some(text) => text
    None =>
      match optional_value(matches, prefix + "-file") {
        Some(path) => @fs.read_file(path).text()
        None => fail("one of --\{prefix} or --\{prefix}-file is required")
      }
  }
}

///|
async fn resolve_backend(matches : @argparse.Matches) -> AnyBackend {
  match optional_value(matches, "backend").unwrap_or("shell") {
    "shell" => {
      let scratch_dir = match optional_value(matches, "scratch-dir") {
        Some(dir) => dir
        None => @fs.tmpdir(prefix="moonforge_cli_")
      }
      let model = optional_value(matches, "model").unwrap_or("gpt-5.5")
      Shell(@llm.ShellBackend::new(scratch_dir, model~))
    }
    "http" => {
      let base_url = match optional_value(matches, "base-url") {
        Some(url) => url
        None => fail("--base-url is required when --backend http")
      }
      let model = match optional_value(matches, "model") {
        Some(model) => model
        None => fail("--model is required when --backend http")
      }
      let api_key = resolve_api_key(matches)
      let proxy_url = match optional_value(matches, "proxy-url") {
        Some(url) => Some(url)
        None => @env.get_env_var("MOONFORGE_HTTP_PROXY")
      }
      let extra_system_prompt = if matches.flags.get_or_default(
          "leanstral-prompt", false,
        ) {
        Some(@llm.leanstral_prompt_addendum)
      } else {
        None
      }
      Http(
        @llm.HttpBackend::new(
          base_url,
          api_key,
          model,
          proxy_url?,
          extra_system_prompt?,
        ),
      )
    }
    other => fail("unknown --backend \{other}, expected \"shell\" or \"http\"")
  }
}

///|
/// Resolve the HTTP backend's API key: a literal `--api-key` value takes
/// precedence (documented as a scripting convenience with a shell-history
/// exposure tradeoff), otherwise read `--api-key-env`'s named environment
/// variable. Fails before ever constructing `HttpBackend` if neither
/// resolves to a non-empty string, so a request is never sent with an
/// empty credential.
fn resolve_api_key(matches : @argparse.Matches) -> String raise {
  match optional_value(matches, "api-key") {
    Some(key) if key != "" => key
    _ => {
      let env_var = optional_value(matches, "api-key-env").unwrap_or(
        "MOONFORGE_API_KEY",
      )
      match @env.get_env_var(env_var) {
        Some(key) if key != "" => key
        _ =>
          fail(
            "no API key available: --api-key was not given and environment variable \{env_var} is unset or empty",
          )
      }
    }
  }
}

///|
async fn resolve_prove_runner(matches : @argparse.Matches) -> AnyProveRunner {
  match optional_value(matches, "prove-runner").unwrap_or("wsl") {
    "wsl" => {
      let distro = optional_value(matches, "wsl-distro").unwrap_or(
        "Ubuntu-24.04",
      )
      let env_setup = optional_value(matches, "wsl-env-setup").unwrap_or(
        default_wsl_env_setup(),
      )
      Wsl(@prover_loop.WslProveRunner::new(distro, env_setup))
    }
    "local" => {
      @stdio.stderr.write(
        "warning: --prove-runner local is unverified/experimental -- no real test in this codebase has ever exercised LocalProveRunner; only use this if MoonForge itself is running inside a machine with moon and Why3 already on PATH\n",
      )
      Local(@prover_loop.LocalProveRunner::{  })
    }
    other =>
      fail("unknown --prove-runner \{other}, expected \"wsl\" or \"local\"")
  }
}

///|
async fn build_run_config(
  matches : @argparse.Matches,
) -> @orchestrator.RunConfig {
  let native_module_root = required_value(matches, "module-root")
  let package_path = required_value(matches, "package-path")
  let pkg_name = resolve_pkg_name(matches, package_path)
  validate_no_shell_metacharacters(native_module_root, "module-root")
  validate_no_shell_metacharacters(package_path, "package-path")
  validate_no_shell_metacharacters(pkg_name, "pkg-name")
  let module_root = match optional_value(matches, "wsl-module-root") {
    Some(path) => path
    None =>
      if optional_value(matches, "prove-runner").unwrap_or("wsl") == "local" {
        native_module_root
      } else {
        windows_path_to_wsl(native_module_root)
      }
  }
  let target_file = required_value(matches, "target-file")
  let user_task = resolve_task_text(matches, "task")
  {
    module_root,
    native_module_root,
    package_path,
    pkg_name,
    target_file,
    start_tag: optional_value(matches, "start-tag").unwrap_or(
      "// @MOONFORGE_INVARIANT_START",
    ),
    end_tag: optional_value(matches, "end-tag").unwrap_or(
      "// @MOONFORGE_INVARIANT_END",
    ),
    user_task,
    max_rounds: @string.parse_int(
      optional_value(matches, "max-rounds").unwrap_or("5"),
    ),
  }
}

///|
async fn build_scaffold_config(
  matches : @argparse.Matches,
  with_tags~ : Bool,
) -> @scaffolder.ScaffoldConfig {
  let module_root = required_value(matches, "module-root")
  let package_path = required_value(matches, "package-path")
  let pkg_name = resolve_pkg_name(matches, package_path)
  validate_no_shell_metacharacters(module_root, "module-root")
  validate_no_shell_metacharacters(package_path, "package-path")
  validate_no_shell_metacharacters(pkg_name, "pkg-name")
  let user_task = resolve_task_text(matches, "task")
  let with_tags = with_tags ||
    matches.flags.get_or_default("with-invariant-tags", false)
  let invariant_tags = if with_tags {
    Some(
      (
        optional_value(matches, "start-tag").unwrap_or(
          "// @MOONFORGE_INVARIANT_START",
        ),
        optional_value(matches, "end-tag").unwrap_or(
          "// @MOONFORGE_INVARIANT_END",
        ),
      ),
    )
  } else {
    None
  }
  {
    module_root,
    package_path,
    pkg_name,
    user_task,
    invariant_tags,
    max_rounds: @string.parse_int(
      optional_value(matches, "max-rounds").unwrap_or("5"),
    ),
  }
}

///|
async fn build_scaffold_and_fill_config(
  matches : @argparse.Matches,
) -> @scaffolder.ScaffoldAndFillConfig {
  let scaffold = build_scaffold_config(matches, with_tags=true)
  let prove_module_root = match optional_value(matches, "prove-module-root") {
    Some(path) => path
    None =>
      if optional_value(matches, "prove-runner").unwrap_or("wsl") == "local" {
        scaffold.module_root
      } else {
        windows_path_to_wsl(scaffold.module_root)
      }
  }
  let fill_task = resolve_task_text(matches, "fill-task")
  {
    scaffold,
    prove_module_root,
    fill_task,
    fill_max_rounds: @string.parse_int(
      optional_value(matches, "fill-max-rounds").unwrap_or("5"),
    ),
  }
}
