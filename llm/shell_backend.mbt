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
  /// When set, every `complete` call runs `codex exec --json` and streams
  /// its JSONL event log (agent reasoning fragments, tool calls, token
  /// usage — everything `codex exec` would print to a real terminal) to
  /// this file path *as the call is still in progress*, not just once it
  /// finishes. Overwritten (not appended) at the start of every call, so
  /// it always reflects only the most recent `complete` invocation. This
  /// is what lets a caller watch a long-running `complete` call's real
  /// progress by re-reading this path from an independent process/task,
  /// instead of only finding out what happened after the whole call
  /// (potentially many minutes) returns. When `None` (the default),
  /// `complete` behaves exactly as before this field was added: no
  /// `--json`, no intermediate visibility, only the final response.
  activity_log : String?
}

///|
/// Build a `ShellBackend` that invokes `codex exec`. `scratch_dir` should
/// be an existing, empty-ish directory dedicated to MoonForge's own
/// bookkeeping; it is not the project being verified.
pub fn ShellBackend::new(
  scratch_dir : String,
  model? : String,
  activity_log? : String,
) -> ShellBackend {
  { command: "codex", model, scratch_dir, activity_log }
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
  // The prompt goes to `codex` over stdin (see `build_exec_args`'s doc
  // comment on why: passing it as a trailing argv element instead, as
  // this backend used to, segfaults `codex exec` once the prompt gets
  // large enough — a real, reproduced crash, not a theoretical concern).
  let prompt_file = self.scratch_dir + "/prompt.txt"
  @fs.write_file(prompt_file, combined_prompt, create_mode=CreateOrTruncate)
  let args = build_exec_args(
    self.model,
    self.scratch_dir,
    output_file,
    json=self.activity_log is Some(_),
  )
  match self.activity_log {
    None => {
      let result = @shell.run_capture(
        self.command,
        args,
        cwd=self.scratch_dir,
        stdin_path=prompt_file,
      )
      if result.exit_code != 0 {
        fail(
          "codex exec failed with exit code \{result.exit_code}\nstderr: \{result.stderr}\nstdout: \{result.stdout}",
        )
      }
    }
    Some(log_path) => {
      let (exit_code, stderr) = @shell.run_capture_to_file(
        self.command,
        args,
        log_path,
        cwd=self.scratch_dir,
        stdin_path=prompt_file,
      )
      if exit_code != 0 {
        fail(
          "codex exec failed with exit code \{exit_code}\nstderr: \{stderr}\nsee \{log_path} for the JSONL event log",
        )
      }
    }
  }
  @fs.read_file(output_file).text()
}

///|
/// Build the `codex exec` argument vector for a single non-interactive
/// call. Always uses `-s read-only` (no filesystem writes outside the
/// scratch dir) and `--skip-git-repo-check` (the scratch dir is not a git
/// repository), and always writes the final response to `output_file` via
/// `-o` so the caller can read plain text without parsing the JSONL event
/// stream.
///
/// The prompt itself is NOT included here — it is written to a scratch
/// file by `complete` and delivered over stdin (`redirect_from_file`, see
/// `shell.run_capture`'s `stdin_path` parameter), not as a trailing argv
/// element. A real crash, reproduced directly against a bare `codex exec`
/// invocation, forced this: `codex exec` on Windows segfaults (exit code
/// `-1073741819` / `STATUS_ACCESS_VIOLATION`) when its prompt argv element
/// gets large — confirmed to happen somewhere between roughly 9KB (fine)
/// and roughly 18KB (crashes) of prompt text — while the exact same prompt
/// content delivered over stdin works at any size tested. This was never
/// hit before `orchestrator.build_user_task` started inlining whole target
/// files into the prompt (see `docs/LESSONS.md`); a short hand-written
/// task description alone stayed well under the threshold. The trailing
/// positional argument this array used to end with is gone entirely now —
/// omitting it (rather than passing an explicit `"-"`) is what makes
/// `codex exec` read from stdin, per its own `--help` text.
///
/// When `json` is true, `--json` is added so `codex exec` prints one JSON
/// event per line to stdout as it runs (reasoning fragments, tool calls,
/// token usage) instead of only its final answer — this is what
/// `ShellBackend.activity_log` streams to disk in real time.
fn build_exec_args(
  model : String?,
  scratch_dir : String,
  output_file : String,
  json~ : Bool,
) -> Array[String] {
  let args = [
    "exec", "-s", "read-only", "-C", scratch_dir, "--skip-git-repo-check", "-o",
    output_file,
  ]
  if json {
    args.push("--json")
  }
  match model {
    Some(model) => {
      args.push("-m")
      args.push(model)
    }
    None => ()
  }
  args
}
