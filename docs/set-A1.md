# Checklist Set A1

> **AGENT PRE-FLIGHT DIRECTIVE:** 
> 1. Inspect all target files to verify each checklist item is still unresolved before modifying code.
> 2. Skip items already implemented in the current working tree.
> 3. Only execute changes for actively reproduced or verified gaps.

## Checklist

### Set A1 — `pipefail` + `curl --fail` sweep — *≈30 min*

**Implement:** Use `curl -fsSL` for all download commands, do not use `wget`
**Findings:** BUG-02, SEC-03, CONF-01, CONF-10
**Files (8):** `install-1password.sh`, `install-azcli.sh`, `install-chrome.sh`, `install-docker.sh`, `install-homebrew.sh`, `install-ngrok.sh`, `install-nvm.sh`, `install-vscode.sh`
**Why batched:** one identical two-line change plus a flag normalisation; identical verification for all eight.

- [ ] Add `set -o pipefail` immediately after `set -e` in all 8 scripts.
- [ ] Normalise every fetch to `curl -fsSL` (adds `--fail`) at all **5** sites that lack it: `install-1password.sh:21,38,43` (`-sS`), `install-azcli.sh:18` (`-sLS`), `install-ngrok.sh:16` (`-sSL`), `install-nvm.sh:16` (`-o-`), `install-vscode.sh:20` (`wget -qO-`).
- [ ] `install-vscode.sh:20` — switch `wget -qO-` to `curl -fsSL` per the Implement line. Then change the prerequisite install at `:17` from `wget gpg` to `curl gpg`, or the script pulls a package it no longer uses.
- [ ] `install-homebrew.sh:34` — `pipefail` does **not** fix this line; see BUG-02 addendum below. Capture the installer to a variable, assert it is non-empty, then execute it.
- [ ] `install-homebrew.sh:39` — `brew --version | head -n1` becomes a failure path once `pipefail` is on (SIGPIPE → 141). Convert to the reference form used by `install-tailscale.sh:23` / `install-qemu.sh:59` (`… 2>/dev/null || echo …`) in the same commit.
- [ ] Re-check the **4** real keyring pipelines now abort on a failed fetch rather than writing a 0-byte file: `install-1password.sh:21,38,43`, `install-azcli.sh:18-19`, `install-ngrok.sh:16`, `install-vscode.sh:20-21`.
- [ ] While in `install-1password.sh`: `:21` and `:43` fetch the identical key twice — collapse if trivial, otherwise leave and note it.

**Scope note:** `install-chrome.sh` and `install-docker.sh` are in this set for CONF-01 consistency only. Neither pipes a network fetch — chrome has no pipelines at all, and docker's single pipeline (`:40`) is a local `echo … | sudo tee`. Both already fetch with `curl -fsSL … -o`. Do not go looking for a keyring pipeline in them.

**Verify:** `bash -n` + `shellcheck` on all 8 — note that shellcheck flags **none** of this work (neither `pipefail` nor `--fail` are shellcheck rules), so it is a syntax gate, not a correctness one. The real gate: in a scratch copy, point each of the 5 changed fetch sites at an unreachable URL in turn and confirm a non-zero exit *before* the apt source or keyring is written. Separately confirm `install-homebrew.sh` still reaches its closing version line with `pipefail` enabled.

## Code-review Report

### BUG-02 — Missing `pipefail` turns failed downloads into "successful" installs

**Files:** `install-1password.sh` (`:21-22`, `:38-39`, `:43-44`), `install-azcli.sh:18-19`, `install-docker.sh`, `install-ngrok.sh:16-17`, `install-vscode.sh:20-21`, `install-chrome.sh`, `install-nvm.sh:16`, `install-homebrew.sh:34`

Eight scripts set `set -e` but not `set -o pipefail`, while piping a network fetch into `gpg --dearmor`, `sudo tee`, or `bash`. In bash the exit status of a pipeline is the status of its **last** command, so a failed `curl` is invisible.

Reproduced locally:

```text
$ bash -c 'set -e; false | cat | tee /tmp/keyring.out >/dev/null; echo "exit=$?"'
exit=0        # and /tmp/keyring.out is 0 bytes
```

Real consequences in this repo:

- `install-azcli.sh:18-19` — a failed key fetch writes a **0-byte `/etc/apt/keyrings/microsoft.gpg`**, the repo is registered against an empty keyring, and the failure surfaces later as an opaque `apt-get update` error.
- `install-ngrok.sh:16` — same for `/etc/apt/trusted.gpg.d/ngrok.asc`.
- `install-1password.sh:21` / `install-vscode.sh:20` — same for their keyrings.
- `install-nvm.sh:16` — a 404/HTML body is piped straight into `bash`.

**Related:** four of these also omit `curl -f` (SEC-03), so an HTTP error page is delivered as content with exit status 0 — the two defects compound.

**Addendum — two files in the list do not match the description above.** Verified against the working tree:

- `install-homebrew.sh:34` is `/bin/bash -c "$(curl -fsSL …)"` — command substitution, **not** a pipeline. `pipefail` has no effect on it. Under `set -e` a failed substitution in an argument position yields an empty string and `bash -c ""` exits 0, so the silent-success failure mode survives this sweep unless the line is restructured.
- `install-chrome.sh` and `install-docker.sh` contain no network-fetch pipeline at all (chrome: no pipelines; docker: one local `echo … | sudo tee` at `:40`). They belong in the set under CONF-01, not BUG-02.

### SEC-03 - Missing `curl -f`

Missing `curl -f`: `install-1password.sh:21,38,43`, `install-azcli.sh:18`, `install-ngrok.sh:16`, `install-nvm.sh:16` omit `--fail`, so an HTTP error page is piped into `gpg`/`tee`/`bash` with exit status 0. Compounds BUG-02.

**Correction:** the source report omits `install-ngrok.sh:16` (`curl -sSL`) from this finding. It is included above. It is the highest-consequence instance of the four, because SEC-02 places that key in `/etc/apt/trusted.gpg.d/`, where it is trusted for every repository on the host.

### CONF-01 - Add `set -o pipefail`

`set -o pipefail` present in only 10 of 18 install scripts; `enable-gnome-rdp.sh` alone uses `set -euo pipefail`. Drives BUG-02.

Files affected: 8 scripts

### CONF-10 - Standardize `curl -fsSL`

Mixed usage of `curl` and `wget`. Downloader flag drift: `curl -fsSL` (majority), `curl -sS` (`1password`), `curl -sLS` (`azcli`), `curl -sSL` (`ngrok`), `curl -o-` (`nvm`), `wget -qO-` (`vscode`). Variants without `-f` are a correctness issue, not a style one (SEC-03).

Files affected: 5 scripts
