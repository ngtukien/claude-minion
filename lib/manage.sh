# shellcheck shell=bash
# minion status / diff / merge / clean

cmd_status() {
  init_minion_dir
  local ids=() f id
  if (( $# )); then
    for id in "$@"; do ids+=("${id%.md}"); done
  else
    while IFS= read -r f; do ids+=("$(task_id_of "$f")"); done < <(find "$MINION_DIR/tasks" -maxdepth 1 -name '*.md' | sort -V)
  fi
  (( ${#ids[@]} )) || { echo "(chưa có task nào trong .minion/tasks/)"; return 0; }

  printf '%-28s %-8s %-8s %-22s %-7s %-6s %-6s\n' TASK STATUS BACKEND MODEL WORKER LẦN FILES
  local st status
  for id in "${ids[@]}"; do
    st="$MINION_DIR/out/$id.status"
    status="$(status_get "$st" status)"; status="${status:-pending}"
    printf '%-28s %-8s %-8s %-22s %-7s %-6s %-6s\n' "$id" "$status" \
      "$(status_get "$st" backend)" "$(status_get "$st" model)" "$(status_get "$st" worker)" \
      "$(status_get "$st" attempts)" "$(status_get "$st" changed_files)"
  done
  echo
  echo "Output: .minion/out/<task>.md · Lỗi: .minion/out/<task>.err · Diff: minion diff <task>"
}

cmd_diff() {
  init_minion_dir
  local id="${1:?cần task-id}"; id="${id%.md}"; shift
  local base="$MINION_DIR/out/$id.base"
  [[ -f $base ]] || die "task $id chưa chạy"
  git -C "$ROOT" diff "$(cat "$base")" "minion/$id" "$@"
}

cmd_merge() {
  init_minion_dir
  local ids=() id f
  if [[ ${1:-} == "--ok" ]]; then
    while IFS= read -r f; do
      id="$(task_id_of "$f")"
      [[ $(status_get "$MINION_DIR/out/$id.status" status) == ok ]] && ids+=("$id")
    done < <(find "$MINION_DIR/tasks" -maxdepth 1 -name '*.md' | sort -V)
  else
    for id in "$@"; do ids+=("${id%.md}"); done
  fi
  (( ${#ids[@]} )) || die "không có task nào để merge"
  [[ -z $(git -C "$ROOT" status --porcelain --untracked-files=no) ]] || die "repo chính có thay đổi chưa commit — commit/stash trước khi merge"

  for id in "${ids[@]}"; do
    git -C "$ROOT" rev-parse --verify -q "minion/$id" >/dev/null || die "không có nhánh minion/$id"
    if git -C "$ROOT" merge-base --is-ancestor "minion/$id" HEAD; then
      log "$id: không có gì mới để merge"; continue
    fi
    if git -C "$ROOT" merge --no-ff -q -m "minion: merge $id" "minion/$id"; then
      log "✔ đã merge $id"
    else
      log "✘ conflict khi merge $id — sửa conflict rồi 'git commit', hoặc 'git merge --abort'"
      return 1
    fi
  done
}

cmd_clean() {
  init_minion_dir
  local all=0; [[ ${1:-} == "--all" ]] && all=1
  local wt id
  for wt in "$MINION_DIR"/wt/*; do
    [[ -d $wt ]] || continue
    id="$(basename "$wt")"
    git -C "$ROOT" worktree remove --force "$wt" 2>/dev/null || rm -rf "$wt"
    git -C "$ROOT" branch -q -D "minion/$id" 2>/dev/null || true
  done
  git -C "$ROOT" worktree prune
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  if (( all )); then
    rm -rf "$MINION_DIR"/{tasks,out,prompts,logs,wt}
    log "đã xoá sạch .minion (trừ archive)"
  else
    mkdir -p "$MINION_DIR/archive/$ts"
    for d in tasks out prompts logs; do
      [[ -d $MINION_DIR/$d ]] && mv "$MINION_DIR/$d" "$MINION_DIR/archive/$ts/"
    done
    rm -rf "$MINION_DIR/wt"
    log "đã gỡ worktree/nhánh; lưu task + output vào .minion/archive/$ts"
  fi
}
