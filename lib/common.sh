# shellcheck shell=bash
# Hàm dùng chung cho claude-minion.

MINION_VERSION="0.2.0"
MINION_CONFIG="${MINION_CONFIG:-${FLEET_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-minion/config}}"
MINION_BACKENDS_DIR="$MINION_HOME/backends"

die() { echo "minion: $*" >&2; exit 1; }
log() { printf '[minion %s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

require_bash() {
  if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    die "cần bash >= 4.3 (đang dùng $BASH_VERSION). macOS: brew install bash"
  fi
}

# Nạp config với giá trị mặc định.
load_config() {
  DEFAULT_BACKEND="antigravity"
  DEFAULT_MODEL=""
  MAX_PARALLEL=""
  MAX_RETRY=3
  RETRY_BACKOFF=20
  TASK_TIMEOUT=1800
  WORKER_PREAMBLE_FILE=""
  WORKERS=()
  if [[ -f $MINION_CONFIG ]]; then
    # shellcheck source=/dev/null
    source "$MINION_CONFIG"
  elif [[ ${1:-} != "--optional" ]]; then
    die "chưa có config ($MINION_CONFIG). Chạy: minion init"
  fi
  (( ${#WORKERS[@]} )) || WORKERS=("||")
  [[ -n $MAX_PARALLEL ]] || MAX_PARALLEL=${#WORKERS[@]}
  (( MAX_PARALLEL > ${#WORKERS[@]} )) && MAX_PARALLEL=${#WORKERS[@]}
  return 0
}

# Giải spec của worker thứ N (1-based) -> W_BACKEND W_MODEL W_ACCOUNT
resolve_worker() {
  local n=$1 spec
  (( n >= 1 && n <= ${#WORKERS[@]} )) || die "worker $n không tồn tại (có ${#WORKERS[@]} worker)"
  spec="${WORKERS[$((n-1))]}"
  IFS='|' read -r W_BACKEND W_MODEL W_ACCOUNT <<<"$spec"
  W_BACKEND="${W_BACKEND:-$DEFAULT_BACKEND}"
  W_MODEL="${W_MODEL:-$DEFAULT_MODEL}"
  W_ACCOUNT="${W_ACCOUNT/#\~/$HOME}"
}

backend_file() {
  local b=$1
  [[ $b =~ ^[A-Za-z0-9_-]+$ ]] || die "tên backend không hợp lệ: '$b'"
  local f="$MINION_BACKENDS_DIR/$b.sh"
  [[ -f $f ]] || die "không có backend '$b' (tìm $f)"
  echo "$f"
}

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "phải chạy trong một git repo"
}

# Thiết lập biến đường dẫn .minion cho repo hiện tại.
init_minion_dir() {
  ROOT="$(repo_root)"
  MINION_DIR="$ROOT/.minion"
  mkdir -p "$MINION_DIR"/{tasks,out,wt,prompts,logs}
  local exclude
  exclude="$(git -C "$ROOT" rev-parse --git-common-dir)/info/exclude"
  [[ $exclude == /* ]] || exclude="$ROOT/$exclude"
  mkdir -p "$(dirname "$exclude")"
  grep -qxF '.minion/' "$exclude" 2>/dev/null || echo '.minion/' >>"$exclude"
}

# Đọc một khóa trong YAML frontmatter của file task.
task_meta() {
  awk -v key="$2" -v q="'" '
    NR==1 { if ($0 ~ /^---[[:space:]]*$/) { fm=1; next } else exit }
    fm && /^---[[:space:]]*$/ { exit }
    fm {
      i = index($0, ":"); if (!i) next
      k = substr($0, 1, i-1); v = substr($0, i+1)
      gsub(/^[ \t]+|[ \t]+$/, "", k)
      sub(/[ \t]+#.*$/, "", v)
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub("^[\"" q "]|[\"" q "]$", "", v)
      if (k == key) { print v; exit }
    }' "$1"
}

# Nội dung task, bỏ frontmatter.
task_body() {
  awk 'NR==1 && /^---[[:space:]]*$/ { fm=1; next }
       fm==1 && /^---[[:space:]]*$/ { fm=2; next }
       fm!=1 { print }' "$1"
}

task_id_of() { local b; b="$(basename "$1")"; echo "${b%.md}"; }

# Đọc giá trị trong file status (key=value).
status_get() { [[ -f $1 ]] && sed -n "s/^$2=//p" "$1" | head -n1; return 0; }

timeout_cmd() {
  if command -v timeout >/dev/null; then echo timeout
  elif command -v gtimeout >/dev/null; then echo gtimeout
  fi
}
