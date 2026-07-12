# MoonForge GraphKit

AI-assisted formal verification infrastructure and verified graph algorithm
building blocks for MoonBit.

MoonForge GraphKit has two connected goals:

- provide a MoonBit framework that can call LLM backends, inject proof code, run
  `moon check` / `moon prove`, and use verifier feedback to repair attempts;
- grow a verified graph algorithms library from small reusable proof blocks,
  including adjacency matrices, grid paths, BFS frontier invariants, and an A*
  grid pathfinding case study.

## Current Highlights

- OpenAI-compatible HTTP backend for model calls, with DeepSeek as the default
  profile and a Leanstral/Mistral evaluation profile.
- Shell backend retained for Codex-style assisted runs.
- Structured proof loop components: context injection, scaffold filling,
  sanitizer, verifier runner, failure diagnosis, and repair prompts.
- A* grid pathfinding fixture used as the hard validation case for the
  framework approach.
- Verified graph packages under `graph/`:
  - `adjacency_matrix`
  - `grid_path`
  - `visited_frontier`

## Verified Graph Work

The strongest current graph package is `graph/visited_frontier`. It proves BFS
frontier and visited-marking preservation facts in small composable steps:

- queue enqueue/dequeue bounds;
- source seed and start-marking facts;
- marked vertex preservation;
- marked queue-prefix preservation;
- discover/enqueue and pop/discover/enqueue wrappers;
- guarded pop-expand steps;
- fixed-count loop wrappers.

The latest local validation before publication included:

```powershell
moon check graph/visited_frontier
moon prove graph/visited_frontier
moon test graph/visited_frontier
moon info
```

with `moon prove graph/visited_frontier` proving 39 goals.

## Framework Layout

Important packages:

- `cmd/main`: command-line entry point and HTTP model profile configuration.
- `llm`: LLM backend abstraction, HTTP backend, and shell backend.
- `orchestrator`: high-level proof repair loop.
- `injector`: tagged-region replacement for generated proof/code fragments.
- `sanitizer`: reduction of model output to reviewable code.
- `prover_loop`: `moon check` / `moon prove` runner integration and diagnosis.
- `graph`: verified graph algorithm components.
- `fixtures/target_examples`: case studies and regression fixtures.

## Running Checks

From the repository root:

```powershell
moon check
moon test
moon info
```

Targeted graph checks:

```powershell
moon check graph/adjacency_matrix
moon check graph/grid_path
moon check graph/visited_frontier
moon test graph/visited_frontier
```

If your environment has Why3 and MoonBit proof tooling configured:

```powershell
moon prove graph/adjacency_matrix
moon prove graph/grid_path
moon prove graph/visited_frontier
```

## LLM Configuration

For HTTP backend runs, prefer environment variables over literal command-line
keys:

```powershell
$env:DEEPSEEK_API_KEY = "..."
```

The CLI supports `--api-key`, but environment variables are safer because
literal keys may appear in shell history or process listings.

## Status

This project is research-grade but already contains machine-checked proof
artifacts and a committed incremental proof history. Current verified graph
work focuses on safety, shape, boundary, and preservation facts. Full BFS
reachability, shortest-path optimality, and a general-purpose verified A*
library are planned next steps rather than current claims.

## License

Apache-2.0.
