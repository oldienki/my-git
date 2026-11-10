# Architecture Proposal: Multi-Registry Docker Credentials per Profile
<!-- Link base: write relative links with the repository root as the base. -->

> **Note:** This proposal follows the workflow defined in [ARCHITECT.md](agentic/ARCHITECT.md).

- **Author:** agent session
- **Created:** 2026-11-10
- **Status:** created
- **Implemented:**

## 1. Summary

Extend the profile format so one profile can hold credentials for multiple
container registries (for example `docker.io` and `ghcr.io`). Credentials live
in named sections `[docker:<registry>]`. The existing flat `docker_user`,
`docker_token`, and `docker_registry` keys stay as the default credential set.
When the target registry has no matching section, `git-docker-publish` uses the
flat keys.

## 2. Motivation

Today a profile binds exactly one registry credential triple
(`docker_user`, `docker_token`, `docker_registry`). A user who publishes to both
Docker Hub and GHCR must either pass `--user`/`--registry` overrides with a
foreign token, or maintain a second profile bound to a different email. Both
options break the single-identity model described in
[ARCHITECTURE.md](docs/ARCHITECTURE.md) Section 1. The change keeps one profile
per identity and adds per-registry credential sets.

## 3. Current Architecture

- `git-docker-publish` reads three flat keys through `parse_field` and resolves
  the token through `resolve_token` (lines 100–105). It derives the target
  registry from the image prefix, the `-r` flag, or `docker_registry`
  (lines 126–131).
- `parse_field` in `my-git-core.inc.sh` scans a profile for a single flat
  `key = value` pair. It does not understand sections.
- `protect_profile_tokens` rewrites flat keys listed in
  `MY_GIT_SENSITIVE_KEYS` (`cargo_token`, `pypi_token`, `docker_token`) into
  `secret-tool:` references. Its key regex `([a-zA-Z0-9_]+)` and the sensitive
  list do not cover section content.
- `git-export-profile` iterates `MY_GIT_SENSITIVE_KEYS` on the staged profile
  and resolves each value to plaintext for the archive.
- `git-import-profile --protect` re-secures imported tokens through
  `protect_profile_tokens`.

```text
profile file ──> parse_field(docker_user|docker_token|docker_registry)
             ──> resolve_token ──> docker login <registry> ──> docker push
```

## 4. Proposed Changes

### Profile format

Flat keys remain the default credential set. Named sections add extra
registries:

```ini
# default (current variant) — applies when no section matches
docker_registry = docker.io
docker_user = the@oldienki.xyz
docker_token = dckr_pat_...

[docker:ghcr.io]
user = oldienki
token = secret-tool:service=my-git,profile=oldienki,token=docker_ghcr_io

[docker:quay.io]
user = robot+ci
token = ...
```

- Section name: literal `docker:` prefix plus the registry host
  (`[docker:ghcr.io]`). Dots in the registry name are legal inside the
  brackets.
- Section keys: `user` and `token`. Each is optional inside a section.
- `token` values accept the same references `resolve_token` already supports
  (`secret-tool:`, `pass:`, plaintext).

### Resolution algorithm in `git-docker-publish`

1. Determine `TARGET_REGISTRY` exactly as today: image prefix, else `-r`, else
   `docker_registry`, else `docker.io`.
2. Read the `[docker:<TARGET_REGISTRY>]` section via a new shared function
   `parse_section_field(file, section, key)`.
3. `DOCKER_USER` = section `user`, else flat `docker_user`.
   `DOCKER_TOKEN` = section `token`, else flat `docker_token`.
4. Apply `-u`/`--user` override last, as today.

If the section exists but lacks `token` while a flat `docker_token` exists, the
flat token is used. This keeps a single-source-of-truth for registries that
share a token with the default account.

### Structural changes

- **`my-git-core.inc.sh`:** add `parse_section_field(file, section, key)` —
  reads lines between the `[section]` header and the next `[...]` header or
  EOF, reusing the same trim/unquote logic as `parse_field`. Keep `parse_field`
  unchanged so it ignores section content (it stops matching keys inside
  sections only if needed — see note below).
- **`my-git-core.inc.sh`:** extend `protect_profile_tokens` to track the
  current `[docker:*]` section and treat `token` keys inside it as sensitive
  (stored under `token=docker_<registry_sanitized>`).
- **`git-export-profile`:** enumerate `[docker:*]` sections and resolve their
  `token` values to plaintext alongside flat sensitive keys.
- **`git-protect`:** no direct change; it calls `protect_profile_tokens`.
- **`git-docker-publish`:** implement the resolution algorithm above.
- **`docs/ARCHITECTURE.md`:** update Section 2.3 / data flows.
- **`my-git-completion.bash`:** no change required.

### Note on `parse_field` inside sections

`parse_field` breaks on the first exact key match and would read a section
`token` key only if the flat name were also `token`. Flat keys are
`docker_user`/`docker_token`, so section keys `user`/`token` never collide.
No change needed.

### Trust and state changes

- No new persistent state. The ephemeral `DOCKER_CONFIG` flow is unchanged.
- Section tokens move through the same `secret-tool` migration path as flat
  tokens; `git-protect` keeps profile files free of plaintext secrets.

## 5. Trade-offs

### Benefits

- **[One identity, many registries]:** A single profile serves `docker push`
  to any number of registries without CLI overrides or extra profiles.
- **[Backward compatibility]:** Existing profiles work unchanged; flat keys
  remain the fallback.
- **[Keyring parity]:** Section tokens migrate to `secret-tool` through the
  existing protect/export/import machinery.

### Costs and Risks

- **[Parser complexity]:** `parse_section_field` adds section state to a
  previously flat format. Mitigation: 20-line function, bats tests for
  section boundaries, comments, and missing keys.
- **[Ambiguous fallback]:** A section with `user` but no `token` silently
  inherits the flat token, which may target a different account. Mitigation:
  document the rule; warn on stderr when a partial section is used.

### Alternatives Considered

- **[Flat suffixed keys (`docker_ghcr_io_...`)]:** No parser changes, but key
  names embed registry data and `protect_profile_tokens` needs pattern
  matching anyway. Sections are clearer and keep key names stable.
- **[Credential list in one field (`docker_credentials = reg:user:tok,...`)]:**
  Compact but fragile, hard to quote, and incompatible with `secret-tool:`
  references inside values.

## 6. Implementation Plan

Execute under `agentic/WORKFLOW.md` (Standard tier; public-interface change to
the profile format). Tasks below become execution tasks in
`project/PLAN_docker_multi_registry.md` (local-only file).

1. **Shared parser**
   - **Goal:** read keys inside `[docker:<registry>]` sections.
   - **Files to touch:** `my-git-core.inc.sh`, `tests/core.bats`.
   - **Approach:** add `parse_section_field`; share the trim/unquote loop with
     `parse_field` where practical.

2. **Publish resolution**
   - **Goal:** select per-registry credentials with flat fallback.
   - **Files to touch:** `git-docker-publish`, `tests/*.bats` (new or
     existing docker test file).
   - **Approach:** reorder target-registry detection before credential reads;
     add fallback logic and the partial-section warning.

3. **Protect/export coverage**
   - **Goal:** section tokens flow through keyring migration and archives.
   - **Files to touch:** `my-git-core.inc.sh` (`protect_profile_tokens`),
     `git-export-profile`, `tests/export_import.bats`, `tests/*.bats`.
   - **Approach:** track current section in `protect_profile_tokens`; store
     section tokens under `token=docker_<registry with dots→underscores>`;
     enumerate sections in export.

4. **Documentation**
   - **Goal:** describe the section format.
   - **Files to touch:** `README.md`, `docs/ARCHITECTURE.md`.

## 7. Testing Strategy

- **Unit tests (bats):** `parse_section_field` returns section values, ignores
  keys outside the section, stops at the next header, and returns `""` for
  missing sections/keys.
- **Integration tests:** `git-docker-publish` with a stubbed `docker` binary —
  assert `login` receives the section `user`/`token` for `ghcr.io` and flat
  values for `docker.io`; assert `-r quay.io` selects `[docker:quay.io]`.
- **Negative cases:** missing section falls back to flat keys; partial section
  emits the warning; empty section token falls back rather than failing.
- **Invariant checks:** `git-protect` leaves zero plaintext tokens in a
  profile that uses sections; export→import→`--protect` round-trip preserves
  section credentials.
- **Regression:** existing flat-only profiles behave byte-identically.

## 8. Open Questions

- **Keyring attribute name for section tokens** (`docker_<sanitized_registry>`
  vs raw `user`/`token` per section): `non-blocking` — implementation detail,
  decided in Phase 3 task.
- **Should `[docker:*]` sections support a `registry` alias or extra keys
  (e.g., namespace default)?** `non-blocking` — out of scope; can be added
  later without format change.
