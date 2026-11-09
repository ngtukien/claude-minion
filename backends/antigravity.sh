# shellcheck shell=bash
# Backend: Google Antigravity CLI (lệnh `agy`) — thay thế Gemini CLI từ 18/6/2026.
# Dùng chung tài khoản Google (Google AI Pro/Ultra) với Antigravity app.
# Cài: curl -fsSL https://antigravity.google/cli/install.sh | bash   rồi chạy `agy` để đăng nhập.
#
# Biến có sẵn: PROMPT_FILE MODEL ACCOUNT_HOME WORKDIR TASK_ID
# run_backend chạy với thư mục hiện tại = WORKDIR (worktree của task).
#
# Tên model: xem bằng `agy models`, ví dụ "Gemini 3.5 Flash" (có dấu cách cũng được).
# Tuỳ chọn trong config:
#   AGY_BIN=agy
#   AGY_PERMISSION="--dangerously-skip-permissions"   # hoặc "--mode=accept-edits" (worker không tự chạy lệnh shell)
#   AGY_EXTRA_ARGS=""

AGY_BIN="${AGY_BIN:-agy}"
AGY_PERMISSION="${AGY_PERMISSION:---dangerously-skip-permissions}"

check_backend() {
  command -v "$AGY_BIN" >/dev/null 2>&1
}

# agy có thể lưu đăng nhập trong keyring hệ thống, nên đây chỉ là kiểm tra gần đúng.
check_account() {
  local h="${ACCOUNT_HOME:-$HOME}"
  [[ -n ${GEMINI_API_KEY:-} ]] && return 0
  [[ -d $h/.gemini/antigravity-cli ]]
}

run_backend() {
  local args=()
  # shellcheck disable=SC2206
  [[ -n $AGY_PERMISSION ]] && args+=($AGY_PERMISSION)
  [[ -n $MODEL ]] && args+=(--model "$MODEL")
  # shellcheck disable=SC2206
  [[ -n ${AGY_EXTRA_ARGS:-} ]] && args+=($AGY_EXTRA_ARGS)
  HOME="${ACCOUNT_HOME:-$HOME}" "$AGY_BIN" "${args[@]}" -p "$(cat "$PROMPT_FILE")"
}

login_backend() {
  echo "Antigravity CLI sẽ mở đăng nhập Google. Đăng nhập đúng tài khoản có subscription, xong gõ /quit (hoặc Ctrl+C)."
  echo "Kiểm tra model khả dụng sau đó bằng: agy models"
  HOME="${ACCOUNT_HOME:-$HOME}" "$AGY_BIN"
}
