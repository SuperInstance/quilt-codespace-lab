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

## Experiment E-CS52-1 — close the Package Registry loop

Consume **`@superinstance/qthe`** (published to GitHub Packages the same day) *inside* a codespace, run its sealed 54-assert selftest, and self-push the receipt. Publish → registry → consume → receipt, entirely inside the GitHub boundary.

Predictions (registered before the codespace was created):
- P1: registry install succeeds inside the codespace using the codespace-provided token (packages:read on same-owner package). If the token lacks it — honest FAIL receipt is the designed outcome.
- P2: selftest reproduces 54/54 asserts, 0 escapes, byte-identical verdict to the publish-time receipt.
- P3: the receipts branch `codespace-run/<ts>` exists after the codespace reaches Available, containing RECEIPT.md + install.log + selftest.log + run.log.

## Layout

- `.devcontainer/devcontainer.json` — image + node feature + `postCreateCommand`
- `.codespace/run-experiment.sh` — the honest worker script (fail-open, always pushes)
- `.codespace/receipts/` — empty on main; receipts live on `codespace-run/*` branches
