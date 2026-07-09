///|
/// Default LLM backend: shells out to the `codex` CLI (`codex exec`) in
/// non-interactive mode. This is the backend used when the caller has an
/// authenticated `codex` session and wants access to whichever model that
/// session is configured for (for example `gpt-5.5`), without needing an
/// API key.
///
/// Safety note: `codex` is an autonomous coding agent, not a plain
/// completion endpoint. It is invoked here with `-s read-only` and a
/// dedicated scratch working directory so it can only read/reason, never
/// write to the caller's real project files. All file edits in MoonForge
/// are performed exclusively by the `injector` package based on explicit
/// tag matches, never by the LLM backend itself.
pub struct ShellBackend {
  /// Path to the `codex` executable, or a bare name resolved via PATH.
  command : String
  /// Model name to request, e.g. `"gpt-5.5"`. When `None`, `codex` uses
  /// whatever model its own config/session defaults to.
  model : String?
  /// Scratch directory used as `codex`'s working root and for the
  /// `--output-last-message` file. Must not be the caller's real project
  /// directory, since `codex` is otherwise free to read the whole tree.
  scratch_dir : String
}

///|
/// Build a `ShellBackend` that invokes `codex exec`. `scratch_dir` should
/// be an existing, empty-ish directory dedicated to MoonForge's own
/// bookkeeping; it is not the project being verified.
pub fn ShellBackend::new(scratch_dir : String, model? : String) -> ShellBackend {
  { command: "codex", model, scratch_dir }
}

///|
pub impl LlmBackend for ShellBackend with fn complete(
  self,
  system_prompt,
  user_prompt,
) {
  @fs.mkdir(self.scratch_dir, recursive=true) catch {
    _ => () // already exists is fine; other failures surface on the codex call below
  }
  let output_file = self.scratch_dir + "/last_message.txt"
  let combined_prompt = system_prompt + "\n\n" + user_prompt
  let args = build_exec_args(
    self.model,
    self.scratch_dir,
    output_file,
    combined_prompt,
  )
  let result = @shell.run_capture(self.command, args, cwd=self.scratch_dir)
  if result.exit_code != 0 {
    fail(
      "codex exec failed with exit code \{result.exit_code}\nstderr: \{result.stderr}\nstdout: \{result.stdout}",
    )
  }
  @fs.read_file(output_file).text()
}

///|
/// Build the `codex exec` argument vector for a single non-interactive
/// call. Always uses `-s read-only` (no filesystem writes outside the
/// scratch dir) and `--skip-git-repo-check` (the scratch dir is not a git
/// repository), and always writes the final response to `output_file` via
/// `-o` so the caller can read plain text without parsing the JSONL event
/// stream. The prompt is passed as a trailing positional argument (not
/// through a shell string), so it needs no shell-quoting: the process
/// backend delivers it to `codex` as a single argv element regardless of
/// its contents.
fn build_exec_args(
  model : String?,
  scratch_dir : String,
  output_file : String,
  prompt : String,
) -> Array[String] {
  let args = [
    "exec", "-s", "read-only", "-C", scratch_dir, "--skip-git-repo-check", "-o",
    output_file,
  ]
  match model {
    Some(model) => {
      args.push("-m")
      args.push(model)
    }
    None => ()
  }
  args.push(prompt)
  args
}
