# shellcheck shell=bash
# Backend: Google Gemini CLI (https://github.com/google-gemini/gemini-cli)
# LƯU Ý: từ 18/6/2026 Google ngừng phục vụ Gemini CLI cho tài khoản cá nhân
# free / AI Pro / Ultra. Backend này chỉ còn hữu ích với GEMINI_API_KEY
# (nếu còn được hỗ trợ). Dùng subscription → dùng backend "antigravity".
#
# Biến có sẵn: PROMPT_FILE MODEL ACCOUNT_HOME WORKDIR TASK_ID
# Thư mục hiện tại khi run_backend chạy = WORKDIR (worktree của task).

# Tuỳ chọn thêm cho gemini, đặt trong config: GEMINI_EXTRA_ARGS="--checkpointing"
GEMINI_BIN="${GEMINI_BIN:-gemini}"

check_backend() {
  command -v "$GEMINI_BIN" >/dev/null 2>&1
}

# Có thông tin đăng nhập trong HOME của worker chưa?
check_account() {
  local h="${ACCOUNT_HOME:-$HOME}"
  [[ -n ${GEMINI_API_KEY:-} ]] && return 0
  [[ -d $h/.gemini ]] && compgen -G "$h/.gemini/*" >/dev/null
}

run_backend() {
  local args=(--yolo)
  [[ -n $MODEL ]] && args+=(-m "$MODEL")
  # shellcheck disable=SC2206
  [[ -n ${GEMINI_EXTRA_ARGS:-} ]] && args+=($GEMINI_EXTRA_ARGS)
  HOME="${ACCOUNT_HOME:-$HOME}" "$GEMINI_BIN" "${args[@]}" -p "$(cat "$PROMPT_FILE")"
}

# minion login <n>: mở gemini tương tác để đăng nhập ("Login with Google"), xong gõ /quit.
login_backend() {
  echo "Trong Gemini CLI chọn 'Login with Google', đăng nhập đúng tài khoản cho worker này, xong gõ /quit."
  echo "Mẹo: dùng cửa sổ ẩn danh hoặc đăng xuất tài khoản cũ để không đăng nhập nhầm."
  HOME="${ACCOUNT_HOME:-$HOME}" "$GEMINI_BIN"
}
