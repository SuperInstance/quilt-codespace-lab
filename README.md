# quilt-codespace-lab

**The codespace as an ephemeral honest worker.**

Fleet problem this repo solves: waves 50/51 proved a Codespace can provision (~11 min) but sandbox-side exec (ssh into it) was blocked. Pivot: **don't reach into the codespace — make it push.** A `postCreateCommand` runs one experiment during provisioning and pushes its own receipts to a unique `codespace-run/<timestamp>` branch. The keeper then reads receipts via the normal API and deletes the codespace. No ssh, no tunnel, no extraction — the receipt is the product.

## The protocol (codespace-as-tool, receipts-first)

```
create codespace (repo-scoped endpoint)
   └─ provisioning (~11 min)
        └─ postCreateCommand (.codespace/run-experiment.sh)
             ├─ runs ONE pre-registered experiment
             ├─ writes .codespace/receipts/<ts>/RECEIPT.md (+ logs)
             └─ git push origin codespace-run/<ts>   ← self-pushed proof
keeper: poll branch via API → fetch receipts → verdict → DELETE codespace
```

Laws: the receipt is pushed **even on FAIL**; the worker's token is never printed or stored; zero-extraction (nothing leaves the GitHub boundary); the codespace is deleted after its run — a worker, not a home.

## Experiment E-CS52-1 — close the Package Registry loop — **VERDICT: PASS (attempt 8)**

Consume **`@superinstance/qthe`** (published to GitHub Packages the same day) *inside* a codespace, run its sealed 54-assert selftest, and self-push the receipt. Publish → registry → consume → receipt, entirely inside the GitHub boundary.

Predictions (registered before the first codespace was created) and their verdicts:

- P1: registry install succeeds inside the codespace using the codespace-provided token — **FAIL, receipted twice**: the codespace token carries neither an npm-authenticated .npmrc (E401, attempt 2) nor `read:packages` (E403 `permission_denied: read_package`, attempt 3). Honest adaptation: **release-asset channel** (contents:read suffices) — install rc=0 from attempt 4 onward.
- P2: selftest reproduces 54/54 asserts, 0 escapes — **PASS at attempt 8**, via the registered `--mtime-witness` evolution of the reader (fleet law A4), mode receipted in every walk.
- P3: the receipts branch `codespace-run/<ts>` exists after the codespace reaches Available — **PASS from attempt 2 onward**, every attempt self-pushed its receipts.

### The 8-attempt honest-failure arc (each step receipted on its own `codespace-run/*` branch)

| # | what it proved | verdict |
|---|---|---|
| 1 | pre-hardening worker: no branch — postCreate fragility was real | FAIL (rolled) |
| 2 | self-push mechanism PROVEN (token-url path); npm E401 (no .npmrc) | P3 PASS |
| 3 | npm auth fixed; codespace token lacks `read:packages` (E403) — platform boundary | P1 FAIL receipted |
| 4 | release-asset channel install rc=0; **worker caught the non-hermetic selftest** (repo-relative fixture paths) | package defect gift |
| 5 | v0.1.1 hermetic fixtures; 53 escapes with S5-only pass = pin-table refusal pattern | honest FAIL |
| 6 | identical tarball sha both sides; per-case: detected but `first_failure: null` | diagnostics |
| 7 | reader stderr verbatim: `mtime does not match seal.mtime_local (… vs 499162500000)` + tar-extract control 54/54 → **npm's 1985-epoch mtime normalization isolated** | root cause |
| 8 | qthe v0.2.0 (registered `--mtime-witness`, fleet law A4): **54/54, 0 escapes, witness mode receipted** | **PASS** |

The root cause was not guessed — it was dictated by the reader's own fail-closed message and isolated by a tar-vs-npm extraction control. The fix was REGISTERED (reseal `7efea995…` declares the witness law in `seal.method`), not slipped.

## Layout

- `.devcontainer/devcontainer.json` — image + node feature + `postCreateCommand`
- `.codespace/run-experiment.sh` — the honest worker script (fail-open, always pushes)
- `.codespace/receipts/` — empty on main; receipts live on `codespace-run/*` branches
