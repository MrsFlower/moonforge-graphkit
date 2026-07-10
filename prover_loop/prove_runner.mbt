///|
/// Outcome of running `moon prove <package>` once against a package
/// directory, combining the raw terminal output with the structured
/// `<package>.proof.json` report when one was produced.
///
/// The structured report is preferred for classification (see
/// `diagnosis.mbt`): it exposes per-goal solver verdicts (`valid`,
/// `timeout`, `unknown`, ...) directly, whereas the terminal text is a
/// human-readable rendering that is more brittle to match against.
/// `moon prove` does not always produce a report — for example a parse
/// error aborts before Why3 is even invoked — so `proof_json` is
/// optional.
pub struct ProveOutcome {
  exit_code : Int
  stdout : String
  stderr : String
  proof_json : Json?
}

///|
/// Construct a `ProveOutcome` directly, for tests that need to feed a
/// scripted result to `orchestrator` without running a real `ProveRunner`.
pub fn ProveOutcome::new(
  exit_code : Int,
  stdout : String,
  stderr : String,
  proof_json : Json?,
) -> ProveOutcome {
  { exit_code, stdout, stderr, proof_json }
}

///|
/// Whether a `ProveOutcome` represents a fully successful `moon prove`
/// run. Prefers the structured report's own `result` field
/// (`"success"`) when present, since that is exactly what `moon prove`
/// itself uses to decide the package passed; falls back to the process
/// exit code when no report was produced (which should only happen
/// together with a non-zero exit code, but the fallback keeps this
/// function total either way).
pub fn is_success(outcome : ProveOutcome) -> Bool {
  match outcome.proof_json {
    Some(Object(fields)) =>
      match fields.get("result") {
        Some(String(s)) => s == "success"
        _ => outcome.exit_code == 0
      }
    _ => outcome.exit_code == 0
  }
}

///|
/// A pluggable way to actually invoke `moon prove`. `moon prove` requires
/// a working Why3 + SMT solver installation on the machine it runs on;
/// this project's own verified environment lives in WSL2 on Windows
/// hosts (see `MoonForge_PLAN.md` section 6), so the runner that performs
/// the invocation needs to be swappable in the same way `LlmBackend` is:
/// `LocalProveRunner` for when `moon`/Why3 are on the same machine
/// (typically inside WSL2/Linux/macOS directly), and `WslProveRunner` for
/// bridging from a native Windows host process into a WSL2 distro that
/// has the toolchain installed.
pub(open) trait ProveRunner {
  /// Run `moon prove <package_path>` against the module rooted at
  /// `module_root` (a path meaningful to wherever this runner actually
  /// executes `moon`, not necessarily the caller's own filesystem view —
  /// see `WslProveRunner`), and collect the `.proof.json` report named
  /// after `pkg_name` if one was produced.
  async fn run_prove(
    Self,
    module_root : String,
    package_path : String,
    pkg_name : String,
  ) -> ProveOutcome
}

///|
/// Runs `moon prove` directly on the current machine. Use this when the
/// process running MoonForge already has `moon`, Why3, and the SMT
/// solvers on its own `PATH` — for example when MoonForge itself is
/// running inside the same WSL2 distro the toolchain was installed into.
pub(all) struct LocalProveRunner {}

///|
pub impl ProveRunner for LocalProveRunner with fn run_prove(
  _self,
  module_root,
  package_path,
  pkg_name,
) {
  let result = @shell.run_capture(
    "moon",
    ["prove", package_path],
    cwd=module_root,
  )
  let report_path = module_root +
    "/_build/verif/" +
    package_path +
    "/" +
    pkg_name +
    ".proof.json"
  let proof_json = read_proof_json_if_present(report_path)
  {
    exit_code: result.exit_code,
    stdout: result.stdout,
    stderr: result.stderr,
    proof_json,
  }
}

///|
/// Runs `moon prove` inside a WSL2 distro from a native Windows host
/// process, by shelling out to `wsl.exe`. `module_root` must be a path as
/// seen *inside* the WSL2 distro (e.g. `/home/user/project`, or a
/// `/mnt/c/...` path into the Windows filesystem), not a Windows path —
/// the caller is responsible for translating, since only the caller
/// knows which distro and mount layout it is targeting.
pub struct WslProveRunner {
  /// WSL distro name, e.g. `"Ubuntu-24.04"`.
  distro : String
  /// Shell snippet exported before `moon prove` runs, typically a `PATH`
  /// override pointing at the toolchain installed for this project (moon,
  /// why3, alt-ergo, z3, cvc5 are not necessarily on the distro's default
  /// login-shell `PATH`).
  env_setup : String
}

///|
pub fn WslProveRunner::new(
  distro : String,
  env_setup : String,
) -> WslProveRunner {
  { distro, env_setup }
}

///|
pub impl ProveRunner for WslProveRunner with fn run_prove(
  self,
  module_root,
  package_path,
  pkg_name,
) {
  let inner_command = self.env_setup +
    "\ncd '" +
    module_root +
    "' && moon prove '" +
    package_path +
    "'"
  let result = @shell.run_capture("wsl.exe", [
    "-d",
    self.distro,
    "--",
    "bash",
    "-lc",
    inner_command,
  ])
  let report_path = module_root +
    "/_build/verif/" +
    package_path +
    "/" +
    pkg_name +
    ".proof.json"
  let read_command = "cat '" + report_path + "' 2>/dev/null"
  let read_result = @shell.run_capture("wsl.exe", [
    "-d",
    self.distro,
    "--",
    "bash",
    "-lc",
    read_command,
  ])
  let proof_json = if read_result.exit_code == 0 && read_result.stdout != "" {
    Some(@json.parse(read_result.stdout)) catch {
      _ => None
    }
  } else {
    None
  }
  {
    exit_code: result.exit_code,
    stdout: result.stdout,
    stderr: result.stderr,
    proof_json,
  }
}

///|
/// Best-effort read of a `.proof.json` report from the local filesystem.
/// Used by `LocalProveRunner`; `WslProveRunner` reads its report through
/// the WSL bridge instead, since the path is not one the host process can
/// open directly.
async fn read_proof_json_if_present(path : String) -> Json? {
  guard @fs.exists(path) else { return None }
  let text = @fs.read_file(path).text() catch { _ => return None }
  Some(@json.parse(text)) catch {
    _ => None
  }
}
