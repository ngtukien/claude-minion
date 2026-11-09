# shellcheck shell=bash
# minion init / login / doctor / workers

cmd_init() {
  if [[ -f $MINION_CONFIG && ${1:-} != "--force" ]]; then
    log "config đã có: $MINION_CONFIG (dùng --force để ghi đè)"
    return 0
  fi
  mkdir -p "$(dirname "$MINION_CONFIG")"
  cp "$MINION_HOME/config.example" "$MINION_CONFIG"
  log "đã tạo $MINION_CONFIG"
  echo "Tiếp theo: sửa WORKERS trong file trên, rồi 'minion login 1' và 'minion doctor'."
}

cmd_workers() {
  load_config
  printf '%-7s %-9s %-22s %s\n' WORKER BACKEND MODEL "TÀI KHOẢN (HOME)"
  local i
  for (( i=1; i<=${#WORKERS[@]}; i++ )); do
    resolve_worker "$i"
    printf '%-7s %-9s %-22s %s\n' "$i" "$W_BACKEND" "${W_MODEL:-default}" "${W_ACCOUNT:-mặc định (\$HOME)}"
  done
  echo
  echo "Chạy song song tối đa: $MAX_PARALLEL · Retry: $MAX_RETRY · Timeout/task: ${TASK_TIMEOUT}s"
  echo "Backend có sẵn: $(cd "$MINION_BACKENDS_DIR" && ls ./*.sh | sed 's|^\./||; s|\.sh$||' | grep -v '^_' | tr '\n' ' ')"
}

cmd_login() {
  load_config
  local n="${1:?cần số worker, vd: minion login 2}"
  resolve_worker "$n"
  local bfile; bfile="$(backend_file "$W_BACKEND")"
  [[ -n $W_ACCOUNT ]] && mkdir -p "$W_ACCOUNT"
  export ACCOUNT_HOME="$W_ACCOUNT" MODEL="$W_MODEL"
  log "đăng nhập worker $n (backend=$W_BACKEND, HOME=${W_ACCOUNT:-$HOME})"
  # shellcheck source=/dev/null
  source "$bfile"
  if declare -F login_backend >/dev/null; then
    login_backend
  else
    die "backend '$W_BACKEND' không hỗ trợ login tương tác"
  fi
}

cmd_doctor() {
  local ok=1
  pass() { printf '  \033[32m✔\033[0m %s\n' "$*"; }
  fail() { printf '  \033[31m✘\033[0m %s\n' "$*"; ok=0; }
  warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

  echo "Môi trường:"
  if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 3) )); then
    pass "bash $BASH_VERSION"; else fail "bash $BASH_VERSION (cần >= 4.3)"; fi
  command -v git >/dev/null && pass "git $(git --version | awk '{print $3}')" || fail "chưa cài git"
  [[ -n $(timeout_cmd) ]] && pass "timeout ($(timeout_cmd))" || warn "không có 'timeout' — task sẽ không bị giới hạn thời gian (macOS: brew install coreutils)"
  command -v claude >/dev/null && pass "claude (orchestrator)" || warn "chưa thấy lệnh 'claude' (Claude Code)"

  echo "Config:"
  if [[ -f $MINION_CONFIG ]]; then pass "$MINION_CONFIG"; else fail "chưa có config — chạy 'minion init'"; fi
  load_config --optional

  echo "Worker:"
  local i bfile seen=" "
  for (( i=1; i<=${#WORKERS[@]}; i++ )); do
    resolve_worker "$i"
    if ! bfile="$(backend_file "$W_BACKEND" 2>/dev/null)"; then
      fail "worker $i: không có backend '$W_BACKEND'"; continue
    fi
    if ( export ACCOUNT_HOME="$W_ACCOUNT" MODEL="$W_MODEL"
         # shellcheck source=/dev/null
         source "$bfile"; check_backend ) >/dev/null 2>&1; then
      local acc_msg=""
      if ( export ACCOUNT_HOME="$W_ACCOUNT"
           # shellcheck source=/dev/null
           source "$bfile"; declare -F check_account >/dev/null && ! check_account ) >/dev/null 2>&1; then
        warn "worker $i: $W_BACKEND/${W_MODEL:-default} — chưa thấy đăng nhập ở ${W_ACCOUNT:-\$HOME} → 'minion login $i'"
      else
        [[ -n $W_ACCOUNT ]] && acc_msg=" @ $W_ACCOUNT"
        pass "worker $i: $W_BACKEND/${W_MODEL:-default}$acc_msg"
      fi
    else
      fail "worker $i: chưa cài CLI cho backend '$W_BACKEND'"
    fi
    [[ $seen == *" ${W_ACCOUNT:-HOME} "* ]] || seen+="${W_ACCOUNT:-HOME} "
  done
  local nacc; nacc=$(wc -w <<<"$seen")
  echo "  → ${#WORKERS[@]} worker, $nacc tài khoản, song song tối đa $MAX_PARALLEL"

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Repo hiện tại:"
    if git rev-parse --verify -q HEAD >/dev/null; then pass "$(git rev-parse --show-toplevel)"
    else fail "repo chưa có commit nào"; fi
  fi
  echo
  (( ok )) && echo "Sẵn sàng." || { echo "Có lỗi cần sửa ở trên."; return 1; }
}
