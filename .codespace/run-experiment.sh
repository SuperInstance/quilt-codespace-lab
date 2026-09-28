#!/bin/bash
# ============================================================
# CODESPACE AS EPHEMERAL HONEST WORKER — postCreate self-push
# ------------------------------------------------------------
# Doctrine (fleet law):
#   - The codespace is a worker, not a home. It runs ONE
#     experiment during provisioning and pushes its own
#     receipts to a unique branch. Then it may be deleted.
#   - Receipts-first: the receipt is pushed even when the
#     experiment FAILS. Honest FAIL > silent success.
#   - Zero-extraction: nothing leaves GitHub's boundary.
#   - The token lives in $GITHUB_TOKEN (codespace-provided).
#     It is NEVER printed, NEVER written to disk.
# Experiment E-CS52-1: consume @superinstance/qthe from the
#   GitHub Package Registry inside this codespace and run its
#   sealed 54-assert selftest. Registry -> consumer -> receipt
#   loop, closed entirely inside the GitHub boundary.
# ============================================================
set +e
set +x
cd "$CODESPACE_VSCODE_FOLDER" || cd "$(dirname "$0")/.."

TS=$(date -u +%Y%m%dT%H%M%SZ)
BRANCH="codespace-run/$TS"
OUT=".codespace/receipts/$TS"
mkdir -p "$OUT"

log() { echo "[$(date -u +%H:%M:%S)] $*" >> "$OUT/run.log"; }

log "codespace experiment E-CS52-1 begin"
{ uname -a; echo "node: $(node -v 2>&1)"; echo "npm: $(npm -v 2>&1)"; } >> "$OUT/run.log" 2>&1

VERDICT="FAIL"
# --- step 1: install the published package from GitHub Packages ---
mkdir -p /tmp/consumer && cd /tmp/consumer
npm init -y >/dev/null 2>&1
log "npm install @superinstance/qthe --registry=https://npm.pkg.github.com"
NPM_CONFIG_ALWAYS_AUTH=true npm install @superinstance/qthe \
  --registry=https://npm.pkg.github.com \
  >> "$OUT/install.log" 2>&1
INSTALL_RC=$?
log "install rc=$INSTALL_RC"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum node_modules/@superinstance/qthe/*.mjs >> "$OUT/run.log" 2>/dev/null
fi

# --- step 2: run its sealed selftest ---
if [ $INSTALL_RC -eq 0 ]; then
  log "running consumer selftest (expect 54/54 per published receipt)"
  node node_modules/@superinstance/qthe/selftest.mjs \
    > "$OUT/selftest.log" 2>&1
  SELFTEST_RC=$?
  log "selftest rc=$SELFTEST_RC"
  if [ $SELFTEST_RC -eq 0 ]; then VERDICT="PASS"; fi
else
  echo "install failed — receipting honestly" > "$OUT/selftest.log"
  tail -40 "$OUT/install.log" >> "$OUT/selftest.log"
fi

# --- step 3: write the receipt ---
cat > "$OUT/RECEIPT.md" <<EOF
# Codespace experiment receipt E-CS52-1
- date (UTC): $TS
- codespace: $CODESPACE_NAME
- repo: $GITHUB_REPOSITORY
- experiment: consume @superinstance/qthe@0.1.0 from GitHub Package Registry, run sealed selftest
- install rc: $INSTALL_RC
- selftest rc: $SELFTEST_RC (0 = 54/54 asserts, 0 escapes)
- VERDICT: $VERDICT
- doctrine: receipt pushed even on FAIL; codespace deleted after push (zero-extraction)
EOF
log "receipt written, verdict=$VERDICT"

# --- step 4: push own receipts to a unique branch ---
cd "$CODESPACE_VSCODE_FOLDER" || exit 0
git config user.name  "SuperInstance codespace worker"
git config user.email "agents@superinstance.local"
git checkout -b "$BRANCH" >> "$OUT/run.log" 2>&1
git add .codespace/receipts >> "$OUT/run.log" 2>&1
git commit -m "codespace receipt E-CS52-1: verdict=$VERDICT (self-pushed postCreate)" \
  >> "$OUT/run.log" 2>&1
PUSH_RC=1
if [ -n "$GITHUB_TOKEN" ]; then
  git -c http.extraheader="AUTHORIZATION: bearer $GITHUB_TOKEN" \
      push origin "$BRANCH" >> "$OUT/run.log" 2>&1 && PUSH_RC=0
fi
if [ $PUSH_RC -ne 0 ]; then
  git push origin "$BRANCH" >> "$OUT/run.log" 2>&1 && PUSH_RC=0
fi
log "push rc=$PUSH_RC branch=$BRANCH (default-credential-helper path = the codespace-as-tool proof itself)"
echo "E-CS52-1 done verdict=$VERDICT push_rc=$PUSH_RC branch=$BRANCH" >> "$OUT/run.log"
exit 0
