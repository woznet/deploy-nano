# Checklist Set A5

> **AGENT PRE-FLIGHT DIRECTIVE:** 
> 1. Inspect all target files to verify each checklist item is still unresolved before modifying code.
> 2. Skip items already implemented in the current working tree.
> 3. Only execute changes for actively reproduced or verified gaps.

## Checklist

### Set A5 — apt-source robustness & sudo-`HOME` — *≈45 min*

**Implement:** Never leave a broken apt source behind — verify the suite before writing it, scope every key with `signed-by=`, and resolve `$HOME` to the invoking user rather than `root`
**Findings:** BUG-08, BUG-09, SEC-02
**Files (2):** `install-azcli.sh`, `install-ngrok.sh`
**Why batched:** both are third-party apt repositories with suite/key problems, and both are the two remaining scripts that mishandle `$HOME` or global trust.

- [x] **BUG-08** — in `install-azcli.sh:22`, fall back to the newest supported LTS codename when `lsb_release -cs` returns a suite Microsoft does not publish; verify the suite before writing `/etc/apt/sources.list.d/azure-cli.sources`, and remove the source file if the following `apt-get update` fails.
  - **Done.** `suite_is_published()` HEAD-probes
    `packages.microsoft.com/repos/azure-cli/dists/<suite>/Release` and
    `resolve_az_suite()` tries the host codename first, then walks
    `AZ_FALLBACK_SUITES='noble jammy focal'` newest-first. Nothing is written
    until a suite resolves; if none does, the script warns and exits 1 with no
    source file created. The `apt-get update` that follows the write is wrapped:
    on failure it `rm -f`s `/etc/apt/sources.list.d/azure-cli.sources` and exits
    1, so a broken source cannot survive into a later script's run.
  - **Codename detection.** Switched from bare `lsb_release -cs` to
    `/etc/os-release` (`${UBUNTU_CODENAME:-$VERSION_CODENAME}`, the A2 idiom
    from `install-docker.sh:63-64`) with `lsb_release -cs` kept as the fallback:
    `/etc/os-release` is present on every Ubuntu/Debian image, `lsb-release` is
    a package a minimal image may drop. The prerequisite install of
    `lsb-release` is unchanged.
  - **Reproduced before fixing.** Under a stubbed `PATH` (`sudo`, `apt-get`,
    `curl`, `gpg`, `lsb_release`, `dpkg`) with a fake root, the pre-fix script
    on a `resolute` (26.04) host wrote `Suites: resolute` into
    `azure-cli.sources`, left it on disk, and exited **0** — a repository
    Microsoft does not publish, registered silently.
  - **Grounded against the live repository.** Running the committed
    `suite_is_published()` against the real host:
    `resolute`, `questing`, `plucky` -> not published; `noble`, `jammy`,
    `focal` -> published. The directory index at
    `packages.microsoft.com/repos/azure-cli/dists/` confirms `noble` is the
    newest Ubuntu suite there. So on the default target OS (26.04) the pre-fix
    script produced a broken source on *every* run, not in an edge case.
  - **Verified after fixing.** Same harness, six cases: `resolute` ->
    warns and falls back to `noble`; `questing` -> falls back to `noble`;
    `noble` and `jammy` -> used as-is, no warning; post-write `apt-get update`
    forced to fail -> source file removed, rc 1; no suite published at all ->
    nothing written, rc 1. The `/etc/os-release` branch was exercised with a
    logic-identical copy whose one `/etc/os-release` literal was redirected to a
    scratch file (`/etc` is not writable on this workstation): with os-release
    saying `resolute` and the `lsb_release` stub saying `noble`, os-release
    correctly won and the fallback then applied.
  - `bash -n` and `shellcheck` 0.11.0 are both clean on the changed file.
  - Left for B4 per CONF-02: no `main()` restructure: the install logic stays
    inline in the `if` branch so that diff stays mechanical.
- [ ] **SEC-02** — move the ngrok key out of `/etc/apt/trusted.gpg.d/` into `/etc/apt/keyrings/ngrok.asc` and reference it with `signed-by=` in the repo line (`install-ngrok.sh:16-17`), matching `docker`/`vscode`/`azcli`.
- [ ] **SEC-02** — document (inline comment) why the Debian suite `bookworm` is used on Ubuntu, or switch to whatever ngrok currently publishes.
- [ ] **BUG-09** — write ngrok completions to the invoking user's home (`${SUDO_USER:-}` resolution), or skip with a warning when running as root.

**Verify:** `apt-get update -qq` succeeds after each script on a current Ubuntu VM; `apt-key`-free layout confirmed with `apt-config dump | grep -i trusted`; completion file lands in the operator's home.

**Depends on:** A1 — both scripts are `pipefail`/`curl -f` targets, and BUG-02's 0-byte-keyring failure mode is what makes a broken source survive here. B4 later restructures `install-azcli.sh` into the house `main()` shape; keep this set to correctness so that diff stays mechanical.

## Code-review Report

### BUG-08 — `install-azcli.sh` has no fallback for unsupported Ubuntu suites — **Medium**

**File:** `install-azcli.sh:22`

`AZ_DIST=$(lsb_release -cs)` is written verbatim into the `.sources` file. Microsoft's `azure-cli` repository does not publish every Ubuntu codename promptly (interim releases especially), so on a newer host the subsequent `apt-get update -qq` fails on a repository the script just added — leaving a broken apt source behind for every later script. **Fix direction:** map unknown codenames to the most recent supported LTS suite, or verify the suite exists before writing the source file and clean up on failure.

### BUG-09 — Completion file lands in the wrong home under `sudo` — **Low**

**File:** `install-ngrok.sh:24-26`

`$HOME/.local/share/bash-completion/completions` resolves to `/root/...` when the script is invoked as `sudo ./install-ngrok.sh`, so the operator never gets completions. Same class as BUG-05. Also assumes `ngrok` is immediately on `PATH` after the apt install (true today, but unchecked).

### SEC-02 — ngrok key in `/etc/apt/trusted.gpg.d`

`install-ngrok.sh:16` grants that key trust for **all** repositories, rather than scoping it with `signed-by=` as `docker`/`vscode`/`1password`/`azcli` do. The repo line also hardcodes the Debian suite `bookworm` on Ubuntu hosts (`:17`).

Files affected: 1 script

### BUG-02 (context) — Why a broken source survives

Neither script sets `pipefail`, so a failed key fetch writes a **0-byte keyring** and the apt source is registered against it anyway: `install-azcli.sh:18-19` for `/etc/apt/keyrings/microsoft.gpg`, `install-ngrok.sh:16` for `/etc/apt/trusted.gpg.d/ngrok.asc`. The failure only surfaces later as an opaque `apt-get update` error — in a *different* script's run. A1 fixes the pipeline; this set fixes what the pipeline writes.

### CONF-02 (context) — `install-azcli.sh` has no `main()`

`install-azcli.sh` is the only script with **no `main()`** — install logic lives inline in the `if` branch, with no per-step `log` calls and no success message. That restructure belongs to B4, not here; expect to touch the same lines twice and keep this diff limited to the suite and cleanup logic.
