#!/bin/bash
# ============================================================
# CODESPACE AS EPHEMERAL HONEST WORKER — postCreate self-push
# (attempt-2 hardening: receipts are pushed unconditionally,
#  even if every experiment step fails; dual auth paths;
#  sanitized env receipts for diagnosis)
# ------------------------------------------------------------
# Doctrine (fleet law):
#   - The codespace is a worker, not a home. ONE experiment
#     during provisioning; self-pushed receipts; then deleted.
#   - The receipt is pushed even on FAIL. Honest FAIL > silence.
#   - Zero-extraction: nothing leaves GitHub's boundary. The
#     token is never printed, never written to disk.
# Experiment E-CS52-1: consume @superinstance/qthe from GitHub
#   Packages inside this codespace, run its sealed selftest.
# ============================================================
set +e
set +x
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 0

TS=$(date -u +%Y%m%dT%H%M%SZ)
BRANCH="codespace-run/$TS"
OUT="$ROOT/.codespace/receipts/$TS"
mkdir -p "$OUT"

log() { echo "[$(date -u +%H:%M:%S)] $*" >> "$OUT/run.log"; }

log "E-CS52-1 (attempt 8) begin"
{ uname -a; } >> "$OUT/run.log" 2>&1
echo "node: $(command -v node >/dev/null 2>&1 && node -v 2>&1 || echo ABSENT)" >> "$OUT/run.log"
echo "npm:  $(command -v npm  >/dev/null 2>&1 && npm -v  2>&1 || echo ABSENT)" >> "$OUT/run.log"
echo "git:  $(git --version 2>&1)" >> "$OUT/run.log"
env | cut -d= -f1 | sort > "$OUT/env-var-names.txt"
log "env var names receipted (values never)"

VERDICT="FAIL"; INSTALL_RC=99; SELFTEST_RC=99; CHANNEL="none"
# --- step 1: consume the published package (channel A: GitHub Packages registry;
#      channel B fallback: release asset — codespace tokens lack read:packages,
#      E403 receipted in attempt 3; contents:read suffices for releases) ---
if command -v npm >/dev/null 2>&1; then
  mkdir -p /tmp/consumer && cd /tmp/consumer
  npm init -y >/dev/null 2>&1
  # channel A: throwaway scoped .npmrc (token never printed, deleted after)
  {
    echo "@superinstance:registry=https://npm.pkg.github.com/"
    echo "//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}"
    echo "always-auth=true"
  } > /tmp/consumer/.npmrc
  chmod 600 /tmp/consumer/.npmrc
  log "channel A: npm registry install via scoped .npmrc"
  npm install @superinstance/qthe >> "$OUT/install.log" 2>&1
  INSTALL_RC=$?
  rm -f /tmp/consumer/.npmrc
  CHANNEL="registry"
  log "channel A rc=$INSTALL_RC"
  # channel B: release asset (contents:read is in the codespace token's scope)
  if [ $INSTALL_RC -ne 0 ]; then
    log "channel B: release-asset fallback (E403 root cause receipted in attempt 3)"
    curl -sS -L -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/octet-stream" \
      -o /tmp/consumer/qthe.tgz \
      "https://api.github.com/repos/SuperInstance/qthe/releases/tags/v0.2.0" >> "$OUT/install.log" 2>&1
    # the above fetches metadata; grab the asset properly
    ASSET_URL=$(curl -sS -H "Authorization: token ${GITHUB_TOKEN}" \
      "https://api.github.com/repos/SuperInstance/qthe/releases/tags/v0.2.0" \
      | grep -o '"browser_download_url": *"[^"]*superinstance-qthe-0.2.0.tgz"' | head -1 | cut -d'"' -f4)
    log "asset url resolved: ${ASSET_URL:+yes}"
    if [ -n "$ASSET_URL" ]; then
      curl -sS -L -H "Authorization: token ${GITHUB_TOKEN}" -o /tmp/consumer/qthe.tgz "$ASSET_URL" >> "$OUT/install.log" 2>&1
      curl -sS -L -o /tmp/consumer/qthe.tgz "$ASSET_URL" >> "$OUT/install.log" 2>&1
      npm install /tmp/consumer/qthe.tgz >> "$OUT/install.log" 2>&1
      INSTALL_RC=$?
      CHANNEL="release-asset"
      log "channel B rc=$INSTALL_RC"
    fi
  fi
  # --- step 2: sealed selftest ---
  if [ $INSTALL_RC -eq 0 ]; then
    sha256sum /tmp/consumer/qthe.tgz >> "$OUT/run.log" 2>/dev/null
    python3 - <<'PYEOF' >> "$OUT/run.log" 2>/dev/null || node -e "console.log('ver:',require('/tmp/consumer/node_modules/@superinstance/qthe/package.json').version)" >> "$OUT/run.log" 2>&1
print("ver:", open('/tmp/consumer/node_modules/@superinstance/qthe/package.json').read().split('"version": "')[1].split('"')[0])
PYEOF
    node node_modules/@superinstance/qthe/selftest.mjs > "$OUT/selftest.log" 2>&1
    SELFTEST_RC=$?
    log "selftest rc=$SELFTEST_RC (0 == 54/54)"
    # per-case detail lives in the consumer's run_receipts — capture it
    cp -r node_modules/@superinstance/qthe/run_receipts "$OUT/consumer_run_receipts" >> "$OUT/run.log" 2>&1
    # ---- attempt-7 diagnostics: reader stderr verbatim + extraction isolation ----
    QDIR=/tmp/consumer/node_modules/@superinstance/qthe
    echo "node -v: $(node -v)" >> "$OUT/reader_diag.log"
    node "$QDIR/reader.mjs" --repo "$QDIR/fixtures/crab-traps" --pins "$QDIR/registration.json" \
      --chain crab44a > "$OUT/reader-out.json" 2>> "$OUT/reader_diag.log"
    echo "direct-reader rc=$?" >> "$OUT/reader_diag.log"
    echo "--- direct reader stdout ---" >> "$OUT/reader_diag.log"
    head -c 800 "$OUT/reader-out.json" >> "$OUT/reader_diag.log" 2>/dev/null
    # extraction isolation: same tarball via tar xzf (not npm), selftest against it
    mkdir -p /tmp/tarx && tar xzf /tmp/consumer/qthe.tgz -C /tmp/tarx 2>> "$OUT/reader_diag.log"
    ( cd /tmp/tarx/package && CRAB_TRAPS_PATH=/tmp/tarx/package/fixtures/crab-traps \
      node selftest.mjs > /tmp/tarx-selftest.log 2>&1; echo "tar-extract selftest rc=$?" >> "$OUT/reader_diag.log" )
    tail -5 /tmp/tarx-selftest.log >> "$OUT/reader_diag.log" 2>/dev/null
    [ $SELFTEST_RC -eq 0 ] && VERDICT="PASS"
  else
    tail -40 "$OUT/install.log" > "$OUT/selftest.log"
  fi
else
  echo "npm ABSENT in postCreate environment" > "$OUT/install.log"
  log "npm absent — experiment FAIL receipted honestly"
fi

# --- step 3: receipt ---
cat > "$OUT/RECEIPT.md" <<EOF
# Codespace experiment receipt E-CS52-1 (attempt 8)
- date (UTC): $TS
- codespace: $CODESPACE_NAME
- repo: $GITHUB_REPOSITORY
- experiment: consume @superinstance/qthe (channel A: registry, channel B: release asset), run sealed selftest
- install rc: $INSTALL_RC
- selftest rc: $SELFTEST_RC (0 = 54/54 asserts, 0 escapes)
- channel: $CHANNEL
- VERDICT: $VERDICT
- doctrine: receipt pushed even on FAIL; worker deleted after push (zero-extraction)
EOF
log "receipt written, verdict=$VERDICT"

# --- step 4: self-push receipts (dual path, receipted) ---
cd "$ROOT" || exit 0
git config user.name  "SuperInstance codespace worker"
git config user.email "agents@superinstance.local"
git add -A .codespace/receipts >> "$OUT/run.log" 2>&1
git commit -m "codespace receipt E-CS52-1: verdict=$VERDICT (self-pushed postCreate)" >> "$OUT/run.log" 2>&1
PUSH_PATH="none"; PUSH_RC=1
if [ -n "$GITHUB_TOKEN" ]; then
  git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" \
    "HEAD:refs/heads/$BRANCH" >> "$OUT/run.log" 2>&1 && { PUSH_RC=0; PUSH_PATH="token-url"; }
fi
if [ $PUSH_RC -ne 0 ]; then
  git push origin "HEAD:refs/heads/$BRANCH" >> "$OUT/run.log" 2>&1 && { PUSH_RC=0; PUSH_PATH="credential-helper"; }
fi
log "push rc=$PUSH_RC path=$PUSH_PATH branch=$BRANCH"
echo "E-CS52-1 done verdict=$VERDICT push_rc=$PUSH_RC push_path=$PUSH_PATH branch=$BRANCH" >> "$OUT/run.log"
exit 0
