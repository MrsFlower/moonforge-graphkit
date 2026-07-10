///|
/// Declarative `argparse` surface for the CLI. This file only builds
/// `Command`/`OptionArg`/`FlagArg` values — no config resolution or
/// pipeline logic lives here (see `cli_config.mbt`/`cli_report.mbt`).

///|
/// Backend-selection flags shared by every subcommand (even `scaffold`,
/// which never calls a `ProveRunner`, still needs an `LlmBackend`).
fn common_backend_options() -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg(
      "backend",
      about="LLM backend: \"shell\" (codex exec, default) or \"http\" (OpenAI-compatible /chat/completions)",
      default_values=["shell"],
    ),
    @argparse.OptionArg(
      "model",
      about="Model name. Defaults to \"gpt-5.5\" for --backend shell; required for --backend http",
    ),
    @argparse.OptionArg(
      "scratch-dir",
      about="Dedicated scratch directory for --backend shell (codex's working root). Defaults to a fresh temp dir",
    ),
    @argparse.OptionArg(
      "base-url",
      about="API base URL for --backend http, e.g. https://api.deepseek.com/v1 (required for http)",
    ),
    @argparse.OptionArg(
      "api-key",
      about="Literal API key for --backend http. Visible in shell history/process listings; prefer --api-key-env",
    ),
    @argparse.OptionArg(
      "api-key-env",
      about="Name of the environment variable holding the API key for --backend http",
      default_values=["MOONFORGE_API_KEY"],
    ),
    @argparse.OptionArg(
      "proxy-url",
      about="HTTP proxy for --backend http. Defaults to $MOONFORGE_HTTP_PROXY when unset",
    ),
  ]
}

///|
fn common_backend_flags() -> Array[@argparse.FlagArg] {
  [
    @argparse.FlagArg(
      "leanstral-prompt",
      about="Append the Leanstral-specific few-shot prompt addendum (for --backend http --model labs-leanstral-1-5)",
    ),
  ]
}

///|
/// Prove-runner-selection flags, shared by `fill` and `scaffold-and-fill`
/// (plain `scaffold` only ever runs `moon check` locally, never a
/// `ProveRunner`).
fn common_runner_options() -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg(
      "prove-runner",
      about="How to run `moon prove`: \"wsl\" (bridge into a WSL2 distro, default) or \"local\" (run directly on this machine)",
      default_values=["wsl"],
    ),
    @argparse.OptionArg(
      "wsl-distro",
      about="WSL2 distro name for --prove-runner wsl",
      default_values=["Ubuntu-24.04"],
    ),
    @argparse.OptionArg(
      "wsl-env-setup",
      about="Shell snippet exported before `moon prove` runs inside WSL2 (PATH/LD_LIBRARY_PATH overrides). Defaults to this project's own dev-machine layout",
      default_values=[default_wsl_env_setup()],
    ),
  ]
}

///|
/// Default `env_setup` for `WslProveRunner`, matching every real end-to-end
/// test in `orchestrator_test.mbt`/`scaffold_and_fill_test.mbt`. This is
/// this project's own dev machine's WSL2 toolchain layout, not a portable
/// default — override with `--wsl-env-setup` on any other machine.
fn default_wsl_env_setup() -> String {
  let setup =
    #|export PATH="$HOME/.moon/bin:$HOME/.opam/moonforge/bin:$HOME/tools:$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    #|export LD_LIBRARY_PATH="$HOME/tools"
  setup
}

///|
/// Task-text flags for a given prefix ("task" or "fill-task"): an inline
/// string and a file-path alternative, mutually exclusive via an
/// `ArgGroup` the caller adds separately (see `build_*_command`).
fn task_text_options(prefix : String) -> Array[@argparse.OptionArg] {
  [
    @argparse.OptionArg(
      prefix,
      about="Natural-language task description, inline",
    ),
    @argparse.OptionArg(
      prefix + "-file",
      about="Path to a file containing the natural-language task description",
    ),
  ]
}

///|
fn build_fill_command() -> @argparse.Command {
  @argparse.Command(
    "fill",
    about="Fill in a tagged invariant region of an existing file (wraps orchestrator.run)",
    options=common_backend_options() +
      common_runner_options() +
      task_text_options("task") +
      [
        @argparse.OptionArg(
          "module-root",
          about="Windows path to the MoonBit module root (directory with moon.mod)",
          required=true,
        ),
        @argparse.OptionArg(
          "wsl-module-root",
          about="WSL2-internal path to the module root, overriding automatic C:/... -> /mnt/c/... derivation",
        ),
        @argparse.OptionArg(
          "package-path",
          about="Package path relative to module-root, e.g. \"isqrt\"",
          required=true,
        ),
        @argparse.OptionArg(
          "pkg-name",
          about="Bare package name. Defaults to the last segment of --package-path",
        ),
        @argparse.OptionArg(
          "target-file",
          about="Windows path to the .mbt file containing the tagged region",
          required=true,
        ),
        @argparse.OptionArg("start-tag", about="Start tag line", default_values=[
          "// @MOONFORGE_INVARIANT_START",
        ]),
        @argparse.OptionArg("end-tag", about="End tag line", default_values=[
          "// @MOONFORGE_INVARIANT_END",
        ]),
        @argparse.OptionArg(
          "max-rounds",
          about="Maximum LLM <-> moon prove rounds",
          default_values=["5"],
        ),
      ],
    flags=common_backend_flags(),
    groups=[
      @argparse.ArgGroup("task", required=true, multiple=false, args=[
        "task", "task-file",
      ]),
    ],
  )
}

///|
fn build_scaffold_command() -> @argparse.Command {
  @argparse.Command(
    "scaffold",
    about="Generate a brand-new package from a natural-language task description (wraps scaffolder.generate)",
    options=common_backend_options() +
      task_text_options("task") +
      [
        @argparse.OptionArg(
          "module-root",
          about="Path to the MoonBit module root (directory with moon.mod)",
          required=true,
        ),
        @argparse.OptionArg(
          "package-path",
          about="New package's path relative to module-root, e.g. \"clamp\"",
          required=true,
        ),
        @argparse.OptionArg(
          "pkg-name",
          about="Bare package name. Defaults to the last segment of --package-path",
        ),
        @argparse.OptionArg(
          "start-tag",
          about="Start tag line, used only with --with-invariant-tags",
          default_values=["// @MOONFORGE_INVARIANT_START"],
        ),
        @argparse.OptionArg(
          "end-tag",
          about="End tag line, used only with --with-invariant-tags",
          default_values=["// @MOONFORGE_INVARIANT_END"],
        ),
        @argparse.OptionArg(
          "max-rounds",
          about="Maximum LLM <-> moon check rounds",
          default_values=["5"],
        ),
      ],
    flags=common_backend_flags() +
      [
        @argparse.FlagArg(
          "with-invariant-tags",
          about="Leave loop invariants empty and tagged for a later `fill` run, instead of generating fully self-contained code",
        ),
      ],
    groups=[
      @argparse.ArgGroup("task", required=true, multiple=false, args=[
        "task", "task-file",
      ]),
    ],
  )
}

///|
fn build_scaffold_and_fill_command() -> @argparse.Command {
  @argparse.Command(
    "scaffold-and-fill",
    about="Generate a brand-new package AND fill in its invariant region in one pass (wraps scaffolder.generate_and_fill) -- the headline natural-language-to-verified-code path",
    options=common_backend_options() +
      common_runner_options() +
      task_text_options("task") +
      task_text_options("fill-task") +
      [
        @argparse.OptionArg(
          "module-root",
          about="Windows path to the MoonBit module root (directory with moon.mod)",
          required=true,
        ),
        @argparse.OptionArg(
          "prove-module-root",
          about="WSL2-internal path to the module root for the fill stage's moon prove call, overriding automatic derivation",
        ),
        @argparse.OptionArg(
          "package-path",
          about="New package's path relative to module-root, e.g. \"clamp\"",
          required=true,
        ),
        @argparse.OptionArg(
          "pkg-name",
          about="Bare package name. Defaults to the last segment of --package-path",
        ),
        @argparse.OptionArg("start-tag", about="Start tag line", default_values=[
          "// @MOONFORGE_INVARIANT_START",
        ]),
        @argparse.OptionArg("end-tag", about="End tag line", default_values=[
          "// @MOONFORGE_INVARIANT_END",
        ]),
        @argparse.OptionArg(
          "max-rounds",
          about="Maximum LLM <-> moon check rounds for the scaffold stage",
          default_values=["5"],
        ),
        @argparse.OptionArg(
          "fill-max-rounds",
          about="Maximum LLM <-> moon prove rounds for the fill stage",
          default_values=["5"],
        ),
      ],
    flags=common_backend_flags(),
    groups=[
      @argparse.ArgGroup("task", required=true, multiple=false, args=[
        "task", "task-file",
      ]),
      @argparse.ArgGroup("fill-task", required=true, multiple=false, args=[
        "fill-task", "fill-task-file",
      ]),
    ],
  )
}

///|
fn build_root_command() -> @argparse.Command {
  @argparse.Command(
    "moonforge",
    about="MoonForge: turn a natural-language task description into formally-verified MoonBit code",
    subcommand_required=true,
    subcommands=[
      build_fill_command(),
      build_scaffold_command(),
      build_scaffold_and_fill_command(),
    ],
  )
}
