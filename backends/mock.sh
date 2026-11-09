# shellcheck shell=bash
# Backend giả lập — không gọi AI. Dùng để thử hệ thống, chạy CI, demo.
# - Ghi file mock-output/<TASK_ID>.txt trong worktree.
# - Nếu nội dung task có "MOCK_FAIL_ONCE": lần đầu lỗi, lần sau thành công (thử retry).
# - Nếu có "MOCK_FAIL_ALWAYS": luôn lỗi.
# - MOCK_DELAY (giây, mặc định 1) để thấy chạy song song.

check_backend() { return 0; }
check_account() { return 0; }

run_backend() {
  sleep "${MOCK_DELAY:-1}"
  if grep -q MOCK_FAIL_ALWAYS "$PROMPT_FILE"; then
    echo "mock: lỗi giả lập" >&2; return 1
  fi
  if grep -q MOCK_FAIL_ONCE "$PROMPT_FILE" && [[ ! -f $PROMPT_FILE.mock-failed ]]; then
    : >"$PROMPT_FILE.mock-failed"
    echo "mock: 429 RESOURCE_EXHAUSTED (giả lập rate-limit)" >&2; return 1
  fi
  mkdir -p mock-output
  {
    echo "task=$TASK_ID model=${MODEL:-default} account=${ACCOUNT_HOME:-default}"
    echo "prompt_lines=$(wc -l <"$PROMPT_FILE")"
  } >"mock-output/$TASK_ID.txt"
  cat <<EOF
Mock worker đã xử lý task $TASK_ID.

## REPORT
- Files changed: mock-output/$TASK_ID.txt
- What I did: ghi file giả lập
- Verification: none (mock)
- Open issues: none
EOF
}
