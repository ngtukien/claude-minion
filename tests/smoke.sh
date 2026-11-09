#!/usr/bin/env bash
# Smoke test toàn bộ luồng với backend mock (không gọi AI, không cần mạng).
#   bash tests/smoke.sh
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINION="$HERE/bin/minion"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export MINION_CONFIG="$TMP/config" MOCK_DELAY=1
cat >"$MINION_CONFIG" <<'EOF'
DEFAULT_BACKEND=mock
WORKERS=( "mock|flash|" "mock|flash|" "mock|pro|" )
MAX_RETRY=2
RETRY_BACKOFF=0
EOF

fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$TMP" && git init -q repo && cd repo
git config user.email ci@example.com && git config user.name ci
echo base >README.md && git add . && git commit -qm init

mkdir -p .minion/tasks
for i in 1 2 3 4; do printf 'Task %s\n' "$i" >".minion/tasks/0$i-task.md"; done
printf -- '---\nmodel: special\nworker: 3\n---\nretry MOCK_FAIL_ONCE\n' >.minion/tasks/05-retry.md

"$MINION" doctor >/dev/null || fail "doctor"
"$MINION" run || fail "run"

for i in 1 2 3 4; do
  [[ $(sed -n 's/^status=//p' ".minion/out/0$i-task.status") == ok ]] || fail "task 0$i not ok"
done
grep -q '^attempts=2$' .minion/out/05-retry.status || fail "retry did not happen"
grep -q '^model=special$' .minion/out/05-retry.status || fail "model override"
grep -q '^worker=3$' .minion/out/05-retry.status || fail "worker pin"
[[ -z $(git status --porcelain) ]] || fail ".minion leaked into git status"

"$MINION" diff 01-task --stat | grep -q mock-output || fail "diff"
"$MINION" merge --ok || fail "merge"
[[ $(ls mock-output | wc -l) -eq 5 ]] || fail "merge did not bring all files"

printf 'MOCK_FAIL_ALWAYS\n' >.minion/tasks/06-bad.md
if "$MINION" run 06-bad >/dev/null 2>&1; then fail "failing task reported success"; fi
grep -q '^status=fail$' .minion/out/06-bad.status || fail "fail status"

"$MINION" run --todo >/dev/null 2>&1 || true
"$MINION" clean >/dev/null
[[ -z $(git branch --list 'minion/*') ]] || fail "clean left branches"

echo "smoke test: OK"
