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
- [x] **SEC-02** — move the ngrok key out of `/etc/apt/trusted.gpg.d/` into `/etc/apt/keyrings/ngrok.asc` and reference it with `signed-by=` in the repo line (`install-ngrok.sh:16-17`), matching `docker`/`vscode`/`azcli`.
  - **Done.** The key is fetched to `/etc/apt/keyrings/ngrok.asc` after a
    `sudo install -m 0755 -d /etc/apt/keyrings`, made world-readable with
    `chmod a+r`, and the repo line now carries
    `[signed-by=/etc/apt/keyrings/ngrok.asc]` — the same three-step shape as
    `install-docker.sh:56-59`, which already relies on an *armoured* `.asc`
    under `signed-by=`, so no dearmouring step is needed here either.
  - **Also removes the old key.** `sudo rm -f /etc/apt/trusted.gpg.d/ngrok.asc`
    runs alongside the write. Without it the fix scopes nothing on a host any
    earlier run of this script has already touched: the globally-trusted copy
    would simply stay there next to the new scoped one. This is the only change
    in A5 that deletes pre-existing state on the host, and it is deliberate.
  - **Reproduced before fixing.** Stub-`PATH` harness with a fake root, in all
    three invocation modes (sudo-as-operator, direct root, plain user): the key
    landed in `/etc/apt/trusted.gpg.d/ngrok.asc`, `/etc/apt/keyrings/` was never
    created, and the repo line was a bare
    `deb https://ngrok-agent.s3.amazonaws.com bookworm main` with no `signed-by=`.
  - **Verified after fixing.** Same three modes, and additionally with the host
    pre-seeded with the old globally-trusted key to simulate an already-
    provisioned machine: `/etc/apt/trusted.gpg.d/ngrok.asc` absent in every
    case, `/etc/apt/keyrings/ngrok.asc` present, repo line
    `deb [signed-by=/etc/apt/keyrings/ngrok.asc] https://ngrok-agent.s3.amazonaws.com bookworm main`.
  - `bash -n` and `shellcheck` 0.11.0 are both clean on the changed file.
- [x] **SEC-02** — document (inline comment) why the Debian suite `bookworm` is used on Ubuntu, or switch to whatever ngrok currently publishes.
  - **Resolved as "document", on evidence.** The checklist offered a switch as
    the alternative; there is nothing to switch to. Enumerating the live bucket
    (`ngrok-agent.s3.amazonaws.com/?list-type=2&prefix=dists/&delimiter=/`)
    returns exactly three suites — `bookworm`, `bullseye`, `buster` — all
    Debian, no Ubuntu codename at all. Per-suite probes agree: `bookworm` and
    `bullseye` 200; `trixie`, `noble`, `jammy`, `focal`, `resolute`, `questing`,
    `plucky`, `stable`, `oldstable` all 404. `bookworm` is already the newest
    suite ngrok publishes.
  - **Done.** Inline comment above the repo line records that the suite is
    Debian's and deliberately not derived from the host codename, what the
    bucket actually contains, that the package is a release-independent static
    binary, and — the part that matters for whoever reads this next — that
    templating it from `/etc/os-release` would 404 on every Ubuntu host. That
    last line is worth having beside `install-azcli.sh`, where A5-1 does exactly
    the opposite for exactly the opposite reason.
  - `bash -n` and `shellcheck` 0.11.0 are both clean on the changed file.
- [x] **BUG-09** — write ngrok completions to the invoking user's home (`${SUDO_USER:-}` resolution), or skip with a warning when running as root.
  - **Done.** The three inline lines at the end of `main()` became
    `install_completions()`. It resolves `target_user="${SUDO_USER:-$(id -un)}"`
    — the same idiom as `install-docker.sh:96` — reads that user's home from
    `getent passwd … | cut -d: -f6`, and writes to
    `<their home>/.local/share/bash-completion/completions/ngrok`.
  - **Ownership, not just path.** A new `run_as()` helper runs the `mkdir` and
    the `tee` under `sudo -u "$user" -H` while the script is root, so the
    directory and file belong to the operator rather than being root-owned
    files sitting in their home. When the script is *not* root it runs the same
    commands directly — using `sudo` there would only add a password prompt to
    a write into the user's own home.
  - **Root and missing-user paths.** `target_user` = `root` warns (twice: what
    was skipped, and the one-liner to run as themselves) and returns — the
    checklist's explicit "or skip with a warning when running as root". A
    `SUDO_USER` with no passwd entry, or whose home does not exist, warns and
    returns as well. None of these fail the install.
  - **Also closed the unchecked `PATH` assumption** noted in the BUG-09 report:
    `install_completions()` does `hash -r` and re-tests `command -v ngrok`
    before using it, because the top-level guard already ran `command -v ngrok`
    and bash may still hold that negative lookup. Previously the script simply
    assumed the binary was there.
  - **Reproduced before fixing.** Stub-`PATH` harness, `sudo` run with
    `SUDO_USER=operator` and `HOME=/root`: the completion file was written to
    `/root/.local/share/bash-completion/completions/ngrok` — the operator never
    got it. The script reported "Ngrok installed successfully." regardless.
  - **Verified after fixing.** Six cases. `sudo` as operator -> file lands in
    `/home/operator/...`, and the `sudo -u` log shows both writes performed as
    `operator`; direct root shell with no `SUDO_USER` -> skipped with the
    warning, nothing written; plain non-root user -> written to their own home
    with **no** `sudo -u` call at all; `SUDO_USER` with no passwd entry ->
    warned and skipped; `SUDO_USER` with a non-existent home -> warned and
    skipped; ngrok absent from `PATH` after the apt install -> warned and
    skipped. Every case exits 0.
  - `bash -n` and `shellcheck` 0.11.0 are both clean on the changed file.

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
