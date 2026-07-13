# Add a Local Model

## Outcome

Make the intended local-model workflow usable and appropriately reproducible without committing machine-specific endpoints, credentials, mutable Pi state, or model weights to the dotfiles repository.

## Context / current state

This item is partly implemented outside the repo. Pi already has global settings and a custom LM Studio provider under `~/.pi/agent/`, and multiple local model weights are present on the workstation. The shell templates already add LM Studio's CLI directory to `PATH` when it exists. The current Pi provider endpoint is machine/network-specific, and Pi's global directory also contains authentication, trust, and other mutable state.

There are two materially different possible tasks:

1. Codify the stable parts of the existing working setup in a portable way.
2. Select, download, and evaluate a new local model for coding-agent use.

The implementing agent must establish which outcome is intended before making configuration changes.

## Scope

- Inspect the current Pi and LM Studio configuration without exposing credentials or copying secret-bearing files.
- Decide which settings are stable dotfiles and which belong in per-machine state.
- If codifying the existing setup, manage only stable file-level configuration and provide a safe way to supply the endpoint/model choice locally.
- If evaluating a model, define representative coding and tool-use checks before selecting one.
- Verify model discovery, server availability, tool calling, context handling, and failure behavior when the server is offline.
- Document the local prerequisites and the boundary between repo-managed and machine-managed state.

## Boundaries / non-goals

- Do not symlink or commit the entire `~/.pi/agent` directory.
- Do not commit `auth.json`, `trust.json`, sessions, tokens, LAN addresses, or other machine/user-specific values.
- Do not store model weights in this repository or make `install.sh` download large models.
- Do not hardcode Homebrew or other machine-specific executable paths into shared shell rc files.
- Do not call a model “supported” based only on appearing in `/model`; exercise agent tool use and a realistic coding task.
- Do not conflate portable configuration work with a broad model benchmark unless evaluation is the chosen outcome.

## Open decisions

- Is the goal to codify the existing model setup or add/evaluate a different model?
- Which machines should host inference, and is a loopback endpoint or a LAN-hosted endpoint expected?
- Which provider/server should be canonical: LM Studio, Ollama, or another OpenAI-compatible runtime?
- Which settings belong in a committed template versus `~/.local/share/dotfiles/local.*` or another per-machine file?
- What workload and minimum quality/latency define a useful local coding model?
- Should model selection be a default or an opt-in alternative to remote providers?

## Acceptance criteria

For a portability-focused implementation:

- A fresh machine can discover how to configure the supported local provider without copying secrets or another machine's address.
- Repo-managed files contain only stable settings; Pi's mutable/auth/session files remain outside repository ownership.
- Missing LM Studio or an offline server does not break shell startup or unrelated Pi providers.
- Install and uninstall behavior is non-destructive and idempotent if they manage any file-level links.

For a model-evaluation implementation:

- The selected model is identified by exact artifact/quantization and fits the target machine with documented resource expectations.
- It successfully completes representative read/edit/bash tool calls and at least one realistic repository task.
- Basic latency, context, reliability, and failure observations are recorded well enough to justify making it available.

## Verification

- Validate committed JSON with `jq` or Pi's current configuration command.
- Confirm the provider/model appears through Pi's current model-listing UI.
- Start the inference server and run a small tool-using coding prompt in a disposable fixture.
- Stop the server and verify the failure is clear and does not affect unrelated shell or editor startup.
- If installer behavior changes, test it twice under a temporary `HOME` and ensure existing unmanaged Pi files survive.

Re-read current Pi custom-model and LM Studio server documentation immediately before implementation; provider schemas and compatibility flags are version-sensitive.

## Starting points / references

- [`templates/local.fish`](../../templates/local.fish) and [`templates/local.zsh`](../../templates/local.zsh) — optional per-machine PATH activation.
- [`install.sh`](../../install.sh) — per-machine file and non-destructive install contract.
- [`AGENTS.md`](../../AGENTS.md) — platform-path and dependency policy.
- [Pi custom-model documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/models.md).
- [LM Studio developer documentation](https://lmstudio.ai/docs/developer).

The existing files under `~/.pi/agent/` are evidence to inspect locally, not source files to copy into the repository.
