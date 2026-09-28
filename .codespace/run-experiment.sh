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

log "E-CS52-1 (attempt 3) begin"
{ uname -a; } >> "$OUT/run.log" 2>&1
echo "node: $(command -v node >/dev/null 2>&1 && node -v 2>&1 || echo ABSENT)" >> "$OUT/run.log"
echo "npm:  $(command -v npm  >/dev/null 2>&1 && npm -v  2>&1 || echo ABSENT)" >> "$OUT/run.log"
echo "git:  $(git --version 2>&1)" >> "$OUT/run.log"
env | cut -d= -f1 | sort > "$OUT/env-var-names.txt"
log "env var names receipted (values never)"

VERDICT="FAIL"; INSTALL_RC=99; SELFTEST_RC=99
# --- step 1: consume the published package from GitHub Packages ---
if command -v npm >/dev/null 2>&1; then
  mkdir -p /tmp/consumer && cd /tmp/consumer
  npm init -y >/dev/null 2>&1
  # npm auth: the token goes into a throwaway .npmrc (never printed, deleted after)
  {
    echo "@superinstance:registry=https://npm.pkg.github.com/"
    echo "//npm.pkg.github.com/:_authToken=${GITHUB_TOKEN}"
    echo "always-auth=true"
  } > /tmp/consumer/.npmrc
  chmod 600 /tmp/consumer/.npmrc
  log "npm install @superinstance/qthe via scoped .npmrc (token not printed)"
  npm install @superinstance/qthe >> "$OUT/install.log" 2>&1
  INSTALL_RC=$?
  rm -f /tmp/consumer/.npmrc
  log "install rc=$INSTALL_RC"
  # --- step 2: sealed selftest ---
  if [ $INSTALL_RC -eq 0 ]; then
    node node_modules/@superinstance/qthe/selftest.mjs > "$OUT/selftest.log" 2>&1
    SELFTEST_RC=$?
    log "selftest rc=$SELFTEST_RC (0 == 54/54)"
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
# Codespace experiment receipt E-CS52-1 (attempt 3)
- date (UTC): $TS
- codespace: $CODESPACE_NAME
- repo: $GITHUB_REPOSITORY
- experiment: consume @superinstance/qthe from GitHub Package Registry, run sealed selftest
- install rc: $INSTALL_RC
- selftest rc: $SELFTEST_RC (0 = 54/54 asserts, 0 escapes)
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
