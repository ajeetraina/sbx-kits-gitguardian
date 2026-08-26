# gitguardian-kit — GitGuardian (ggshield) for Docker Sandboxes

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **mixin** that adds
[GitGuardian](https://www.gitguardian.com/)'s
[`ggshield`](https://github.com/GitGuardian/ggshield) secret scanner to an AI
coding-agent sandbox, and wires it in as the agent's own **AI hook** so the
agent's actions are scanned for hardcoded secrets automatically.

> **Source, issues, and full docs:**
> https://github.com/ajeetraina/sbx-kits-gitguardian

## Key isolation property

`ggshield` inside the microVM only ever holds a placeholder value for
`GITGUARDIAN_API_KEY`. When it calls the GitGuardian API, the sbx proxy rewrites
the `Authorization: Token …` header with the real key (sourced from the host) on
the wire, and denies any egress outside the kit's allowlist. **The real key
never enters the sandbox** — not in the environment, shell history, or `ps`
output.

## One repo, one tag per agent

`ggshield`'s AI hook is agent-specific (each assistant reads a different hook
file), so this repo carries one tag per coding agent. Consumers **pin by
digest** (sbx rejects OCI tags at consume time) — the tag is just a label
pointing at the digest to copy.

| Tag        | Agent   | Hook file                     |
|------------|---------|-------------------------------|
| `:claude`  | claude  | `~/.claude/settings.json`     |
| `:codex`   | codex   | `~/.codex/hooks.json`         |
| `:copilot` | copilot | `~/.copilot/hooks/hooks.json` |
| `:cursor`  | cursor  | `~/.cursor/hooks.json`        |
| `:latest`  | claude (default) | —                    |

`ggshield`'s AI-hook support covers `claude-code`, `codex`, `copilot`, and
`cursor`. Other sbx agents (`gemini`, `droid`, `kiro`, `opencode`) have no
ggshield AI hook — layer the kit onto them for the `ggshield` CLI + manual
scanning, but there is no automatic enforcement hook.

## Usage

Pin by digest (get the current digest for a tag from the
[repo Tags](https://hub.docker.com/r/ajeetraina777/gitguardian-kit/tags) or the
[GitHub README](https://github.com/ajeetraina/sbx-kits-gitguardian#usage)):

```console
sbx run claude --kit "oci://docker.io/ajeetraina777/gitguardian-kit@sha256:<claude-digest>" .
sbx run codex  --kit "oci://docker.io/ajeetraina777/gitguardian-kit@sha256:<codex-digest>" .
```

Requires a GitGuardian API key (Personal or Service Account, `scan` scope) bound
on the host as the `gitguardian` credential; the sandbox only ever sees a
proxy-managed placeholder.

## What it installs

- `ggshield` from a pinned, digest-verified GitHub release.
- The agent's AI hook via `ggshield machine setup --agent <agent>
  --no-git-hooks --no-honeytokens`, run as the agent user, registering
  `PreToolUse` / `PostToolUse` / `UserPromptSubmit` handlers that run
  `ggshield secret scan ai-hook` inside the agent's own tool loop.

A blocked action means a real secret was detected — remove and rotate it, don't
retry or bypass. Manual scans (`ggshield secret scan path -r .`,
`ggshield secret scan repo .`) remain available as an escape hatch.

---

Licensed under the terms in the
[GitHub repository](https://github.com/ajeetraina/sbx-kits-gitguardian).
