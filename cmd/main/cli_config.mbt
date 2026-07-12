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
  match optional_value(matches, "backend").unwrap_or("http") {
    "shell" => {
      let scratch_dir = match optional_value(matches, "scratch-dir") {
        Some(dir) => dir
        None => @fs.tmpdir(prefix="moonforge_cli_")
      }
      let model = optional_value(matches, "model").unwrap_or("gpt-5.5")
      let activity_log = optional_value(matches, "activity-log")
      Shell(@llm.ShellBackend::new(scratch_dir, model~, activity_log?))
    }
    "http" => {
      let profile = resolve_http_profile(matches)
      let base_url = optional_value(matches, "base-url").unwrap_or(
        default_http_base_url(profile),
      )
      let model = optional_value(matches, "model").unwrap_or(
        default_http_model(profile),
      )
      let api_key = resolve_api_key(
        matches,
        default_env=default_http_api_key_env(profile),
      )
      let proxy_url = match optional_value(matches, "proxy-url") {
        Some(url) => Some(url)
        None => @env.get_env_var("MOONFORGE_HTTP_PROXY")
      }
      let extra_system_prompt = if profile == "leanstral" ||
        matches.flags.get_or_default("leanstral-prompt", false) {
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
fn resolve_http_profile(matches : @argparse.Matches) -> String raise {
  match optional_value(matches, "model-profile").unwrap_or("deepseek") {
    "deepseek" => "deepseek"
    "leanstral" => "leanstral"
    other =>
      fail(
        "unknown --model-profile \{other}, expected \"deepseek\" or \"leanstral\"",
      )
  }
}

///|
fn default_http_base_url(profile : String) -> String {
  match profile {
    "leanstral" => "https://api.mistral.ai/v1"
    _ => "https://api.deepseek.com/v1"
  }
}

///|
fn default_http_model(profile : String) -> String {
  match profile {
    "leanstral" => "labs-leanstral-1-5"
    _ => "deepseek-v4-pro"
  }
}

///|
fn default_http_api_key_env(profile : String) -> String {
  match profile {
    "leanstral" => "MISTRAL_API_KEY"
    _ => "DEEPSEEK_API_KEY"
  }
}

///|
/// Resolve the HTTP backend's API key: a literal `--api-key` value takes
/// precedence (documented as a scripting convenience with a shell-history
/// exposure tradeoff), otherwise read `--api-key-env`'s named environment
/// variable. The default env var is chosen by the HTTP model profile;
/// `MOONFORGE_API_KEY` remains a fallback for existing scripts. Fails
/// before ever constructing `HttpBackend` if neither resolves to a
/// non-empty string, so a request is never sent with an empty credential.
fn resolve_api_key(
  matches : @argparse.Matches,
  default_env~ : String,
) -> String raise {
  match optional_value(matches, "api-key") {
    Some(key) if key != "" => key
    _ => {
      let env_var = optional_value(matches, "api-key-env").unwrap_or(
        default_env,
      )
      match @env.get_env_var(env_var) {
        Some(key) if key != "" => key
        _ =>
          match @env.get_env_var("MOONFORGE_API_KEY") {
            Some(key) if key != "" => key
            _ =>
              fail(
                "no API key available: --api-key was not given and neither environment variable \{env_var} nor MOONFORGE_API_KEY is set to a non-empty value",
              )
          }
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
async fn build_sequence_run_config(
  matches : @argparse.Matches,
) -> @orchestrator.SequenceRunConfig {
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
  let plan_file = required_value(matches, "plan-file")
  let plan_text = @fs.read_file(plan_file).text()
  let regions = parse_sequence_regions(plan_text)
  {
    module_root,
    native_module_root,
    package_path,
    pkg_name,
    target_file,
    regions,
    max_rounds: @string.parse_int(
      optional_value(matches, "max-rounds").unwrap_or("5"),
    ),
    clear_current_region: matches.flags.get_or_default(
      "clear-current-region", false,
    ),
  }
}

///|
fn parse_sequence_regions(
  plan_text : String,
) -> Array[@orchestrator.RunRegion] raise {
  let parsed = @json.parse(plan_text)
  guard parsed is Object(fields) else {
    fail("fill-sequence plan must be a JSON object")
  }
  guard fields.get("regions") is Some(Array(items)) else {
    fail("fill-sequence plan must contain a regions array")
  }
  guard items.length() > 0 else {
    fail("fill-sequence plan must contain at least one region")
  }
  let regions : Array[@orchestrator.RunRegion] = []
  for i in 0..<items.length() {
    guard items[i] is Object(region_fields) else {
      fail("fill-sequence regions[\{i}] must be a JSON object")
    }
    let default_name = "step-\{i + 1}"
    regions.push({
      name: optional_json_string(region_fields, "name").unwrap_or(default_name),
      start_tag: required_json_string(region_fields, "start_tag"),
      end_tag: required_json_string(region_fields, "end_tag"),
      user_task: required_json_string(region_fields, "task"),
    })
  }
  regions
}

///|
fn required_json_string(
  fields : Map[String, Json],
  key : String,
) -> String raise {
  match fields.get(key) {
    Some(String(value)) => value
    Some(_) => fail("fill-sequence plan field \{key} must be a string")
    None => fail("fill-sequence plan is missing required field \{key}")
  }
}

///|
fn optional_json_string(
  fields : Map[String, Json],
  key : String,
) -> String? raise {
  match fields.get(key) {
    Some(String(value)) => Some(value)
    Some(_) => fail("fill-sequence plan field \{key} must be a string")
    None => None
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
