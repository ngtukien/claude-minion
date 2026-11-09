# shellcheck shell=bash
# MẪU BACKEND — copy thành backends/<tên>.sh (vd: codex.sh, qwen.sh), sửa 3 hàm dưới.
# Sau đó trong config dùng: WORKERS=( "<tên>|<model>|<account_home>" )
#
# Biến môi trường có sẵn khi các hàm chạy:
#   PROMPT_FILE   file chứa prompt đầy đủ (preamble + task)
#   MODEL         tên model (có thể rỗng = để CLI tự chọn mặc định)
#   ACCOUNT_HOME  thư mục HOME riêng cho tài khoản của worker (có thể rỗng = $HOME)
#   WORKDIR       git worktree riêng của task; run_backend đã được cd vào đây
#   TASK_ID       id của task
#
# Hợp đồng:
#   run_backend   in kết quả ra stdout; exit 0 = thành công, khác 0 = lỗi (sẽ retry).
#                 Được phép sửa file trong WORKDIR. KHÔNG cần commit — minion tự commit.
#   check_backend exit 0 nếu CLI đã cài.
#   check_account (tuỳ chọn) exit 0 nếu tài khoản đã đăng nhập.
#   login_backend (tuỳ chọn) mở CLI tương tác để đăng nhập (dùng cho 'minion login').

MYCLI_BIN="${MYCLI_BIN:-mycli}"

check_backend() {
  command -v "$MYCLI_BIN" >/dev/null 2>&1
}

check_account() {
  [[ -d ${ACCOUNT_HOME:-$HOME}/.mycli ]]
}

run_backend() {
  local args=()
  [[ -n $MODEL ]] && args+=(--model "$MODEL")
  HOME="${ACCOUNT_HOME:-$HOME}" "$MYCLI_BIN" "${args[@]}" --non-interactive <"$PROMPT_FILE"
}

login_backend() {
  HOME="${ACCOUNT_HOME:-$HOME}" "$MYCLI_BIN" login
}
