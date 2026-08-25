# Checklist Set A3

> **AGENT PRE-FLIGHT DIRECTIVE:** 
> 1. Inspect all target files to verify each checklist item is still unresolved before modifying code.
> 2. Skip items already implemented in the current working tree.
> 3. Only execute changes for actively reproduced or verified gaps.

## Checklist

### Set A3 — Temp-file lifecycle — *≈15 min*

**Implement:** Pick one temp-file idiom — a script-level variable the `EXIT` trap can expand, or an explicit `rm -f` at the end of `main()` — and use the same one in both scripts
**Findings:** BUG-03
**File (1):** `install-chrome.sh` (pattern shared with A2)
**Why batched:** same defect class as the A2 temp-file work — fix both with the same idiom so they stay aligned.

- [x] Move `temp_deb` out of `main()`'s `local` scope (script-level variable), so the `EXIT` trap can still expand it.
  - **Done.** `temp_deb` is no longer `local` to `main()`; it is a script-level
    variable, and the inline `trap 'rm -f "$temp_deb"' EXIT` is replaced by the
    `cleanup()` + `trap cleanup EXIT` pair copied in shape from
    `install-docker.sh:21-32` (A2), so both files now carry one idiom. The line
    numbers this checklist cites (`:21-24`) were accurate.
  - **Reproduced before fixing.** Under a stubbed `PATH` (`sudo`, `apt-get`,
    `curl`) with `TMPDIR` pointed at a scratch directory, the pre-fix script left
    a `tmp.*.deb` behind on all three exit paths — success (rc 0), failed
    download (rc 22), and failed `apt-get install` of the `.deb` (rc 100) —
    confirming the trap was expanding an out-of-scope variable and running
    `rm -f ""`.
  - **Verified after fixing.** Same three paths, same exit codes, and no `*.deb`
    left in `TMPDIR` on any of them. Also ran with `google-chrome` present on the
    stub `PATH` so `main()` never runs: the script-level trap still fires, the
    `[ -n "$temp_deb" ]` guard makes it a no-op, exit 0.
  - `bash -n` and `shellcheck` are both clean on the changed file.
- [x] Alternative accepted form: keep it `local` and `rm -f "$temp_deb"` at the end of `main()`, with the trap only covering the failure path.
  - **Considered and rejected — not implemented.** This box is ticked to record
    that the alternative was evaluated, *not* that it was applied. Only one of
    the two forms can be in the tree: item 3 requires the identical idiom in
    both files, and A2 had already committed `install-docker.sh` to the
    script-scope form, so adopting this one would have meant reopening a merged
    set to rewrite it. The `local` + explicit `rm -f` form is also the weaker of
    the two here — it needs the cleanup duplicated at the end of `main()` *and*
    in a failure-path trap, which is precisely the split that let BUG-03 hide.
  - Nothing in `install-chrome.sh` implements this form; see item 1 for what
    actually shipped.
- [ ] Apply the identical chosen idiom in `install-docker.sh` (A2).

**Verify:** run in a scratch copy with a stubbed `apt-get`; confirm no `tmp.*.deb` remains after both a successful and a failed run.

**Depends on:** nothing — this and A1 are the two sets with no open decisions, and are the recommended starting point. Whatever idiom is chosen here is the one A2 must adopt for `install-docker.sh`.

## Code-review Report

### BUG-03 — `install-chrome.sh` never deletes its downloaded `.deb` — **Medium**

**File:** `ubuntu/config/install/install-chrome.sh:21-24`

```bash
local temp_deb
temp_deb=$(mktemp --suffix=.deb)
trap 'rm -f "$temp_deb"' EXIT
```

The trap body is single-quoted, so `$temp_deb` is expanded when the trap **fires** — at process exit, after `main()` has returned and its `local` is out of scope. The trap runs `rm -f ""`.

Reproduced locally:

```text
created /tmp/tmp.PwgANiVgDf.deb
TRAP sees: []                    # variable already out of scope
/tmp/tmp.PwgANiVgDf.deb          # file still present after exit
```

Impact: a ~110 MB Chrome package is left in `/tmp` on every run. **Fix direction:** make `temp_deb` a script-level global, or delete it explicitly at the end of `main()` and keep the trap only for the error path.

### Related — BUG-04 / SEC-05 (`install-docker.sh`, Set A2)

`install-docker.sh:51` uses a fixed `/tmp/docker-desktop.deb` and removes it only on the success path. A2 replaces that with `mktemp --suffix=.deb` plus cleanup on all exit paths — which is precisely the idiom this set settles. Do not invent a second pattern there.

Files affected: 2 scripts (`install-chrome.sh` here, `install-docker.sh` via A2)
