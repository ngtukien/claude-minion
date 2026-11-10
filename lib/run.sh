# shellcheck shell=bash
# minion run: xếp hàng + chạy song song. minion worker: chạy 1 task.

DEFAULT_PREAMBLE='You are a MINION worker agent in an orchestrated team. An orchestrator (Gru / Claude Code) gave you ONE task and will review your work.
Rules:
- Work ONLY inside the current directory (it is an isolated git worktree). Never modify files outside it.
- Do exactly this task. Do not refactor or reformat unrelated code.
- Do not run git commit, git push or change branches; the orchestrator handles git.
- If something is ambiguous, make the most reasonable choice and say so in your report.
- Verify your work (build, run tests, lint) when the task gives a way to do it.
- Finish your reply with a section titled "## REPORT" containing: files changed, what you did, how you verified it, and any open issues.'

cmd_run() {
  require_bash
  load_config
  init_minion_dir
  git -C "$ROOT" rev-parse --verify -q HEAD >/dev/null || die "repo chưa có commit nào — hãy commit ít nhất 1 lần"
  if [[ -n $(git -C "$ROOT" status --porcelain --untracked-files=no) ]]; then
    log "cảnh báo: có thay đổi chưa commit trong repo chính — worker chỉ thấy code tại HEAD"
  fi

  local tasks=() id f
  if [[ ${1:-} == "--todo" ]]; then
    while IFS= read -r f; do
      id="$(task_id_of "$f")"
      [[ $(status_get "$MINION_DIR/out/$id.status" status) == ok ]] || tasks+=("$f")
    done < <(find "$MINION_DIR/tasks" -maxdepth 1 -name '*.md' | sort -V)
    (( ${#tasks[@]} )) || { log "mọi task đều đã ok"; return 0; }
  elif (( $# )); then
    for id in "$@"; do
      f="$MINION_DIR/tasks/${id%.md}.md"
      [[ -f $f ]] || die "không thấy task $f"
      tasks+=("$f")
    done
  else
    while IFS= read -r f; do tasks+=("$f"); done < <(find "$MINION_DIR/tasks" -maxdepth 1 -name '*.md' | sort -V)
  fi
  (( ${#tasks[@]} )) || die "không có task nào trong $MINION_DIR/tasks/"

  local nworkers=${#WORKERS[@]}
  log "${#tasks[@]} task · $nworkers worker · tối đa $MAX_PARALLEL chạy song song"

  declare -gA SLOT_PID=()
  declare -A TASK_PID=()
  trap 'log "dừng — huỷ các worker"; kill $(jobs -p) 2>/dev/null; exit 130' INT TERM

  local want running s pid
  for f in "${tasks[@]}"; do
    id="$(task_id_of "$f")"
    want="$(task_meta "$f" worker)"
    if [[ -n $want ]] && ! [[ $want =~ ^[0-9]+$ && $want -ge 1 && $want -le $nworkers ]]; then
      die "task $id: 'worker: $want' không hợp lệ (1..$nworkers)"
    fi
    # Chờ tới khi có slot trống (và đúng slot nếu task chỉ định).
    while :; do
      running=0
      for s in "${!SLOT_PID[@]}"; do
        pid=${SLOT_PID[$s]}
        if kill -0 "$pid" 2>/dev/null; then running=$((running+1)); else unset 'SLOT_PID[$s]'; fi
      done
      SLOT=""
      if (( running < MAX_PARALLEL )); then
        for (( s=1; s<=nworkers; s++ )); do
          [[ -n $want && $s != "$want" ]] && continue
          [[ -z ${SLOT_PID[$s]:-} ]] && { SLOT=$s; break; }
        done
      fi
      [[ -n $SLOT ]] && break
      sleep 1
    done
    "$MINION_BIN" worker "$f" "$SLOT" >"$MINION_DIR/logs/$id.log" 2>&1 &
    SLOT_PID[$SLOT]=$!
    TASK_PID[$id]=$!
    log "▶ $id → worker $SLOT"
  done

  local failed=0 rc
  for id in "${!TASK_PID[@]}"; do
    rc=0; wait "${TASK_PID[$id]}" || rc=$?
    if (( rc == 0 )); then log "✔ $id xong"; else log "✘ $id thất bại (xem .minion/logs/$id.log)"; failed=$((failed+1)); fi
  done
  trap - INT TERM
  echo
  cmd_status "${tasks[@]##*/}"
  (( failed == 0 )) || { log "$failed task thất bại"; return 1; }
}

cmd_worker() {
  require_bash
  local task="$1" slot="${2:-1}"
  load_config
  init_minion_dir
  [[ -f $task ]] || die "không thấy task $task"

  local id; id="$(task_id_of "$task")"
  resolve_worker "$slot"
  local backend model account
  backend="$(task_meta "$task" backend)"; backend="${backend:-$W_BACKEND}"
  model="$(task_meta "$task" model)";     model="${model:-$W_MODEL}"
  account="$W_ACCOUNT"
  local bfile; bfile="$(backend_file "$backend")"

  local out="$MINION_DIR/out/$id.md" err="$MINION_DIR/out/$id.err" st="$MINION_DIR/out/$id.status"
  local wt="$MINION_DIR/wt/$id" br="minion/$id" prompt="$MINION_DIR/prompts/$id.txt"

  # Worktree: tạo mới từ HEAD, hoặc giữ lại nếu task đang chạy vòng sửa (feedback).
  if [[ ! -d $wt ]]; then
    git -C "$ROOT" worktree prune
    git -C "$ROOT" worktree add -q -B "$br" "$wt" HEAD
    git -C "$ROOT" rev-parse HEAD >"$MINION_DIR/out/$id.base"
  fi
  local base start
  base="$(cat "$MINION_DIR/out/$id.base")"
  start="$(git -C "$wt" rev-parse HEAD)"

  # Prompt = preamble + nội dung task.
  {
    if [[ -n $WORKER_PREAMBLE_FILE && -f ${WORKER_PREAMBLE_FILE/#\~/$HOME} ]]; then
      cat "${WORKER_PREAMBLE_FILE/#\~/$HOME}"
    else
      printf '%s\n' "$DEFAULT_PREAMBLE"
    fi
    printf '\n===== TASK %s =====\n' "$id"
    task_body "$task"
  } >"$prompt"

  write_status() {
    {
      echo "status=$1"; echo "backend=$backend"; echo "model=${model:-default}"
      echo "worker=$slot"; echo "account=${account:-default}"; echo "attempts=$attempt"
      echo "seconds=$(( $(date +%s) - t0 ))"; echo "branch=$br"; echo "base=$base"
      echo "changed_files=$(git -C "$wt" diff --name-only "$base" 2>/dev/null | wc -l | tr -d ' ')"
      echo "updated=$(date '+%F %T')"
    } >"$st"
  }

  local t0 attempt=0 rc=1 tcmd
  t0=$(date +%s)
  tcmd="$(timeout_cmd)"
  write_status running

  export PROMPT_FILE="$prompt" MODEL="$model" ACCOUNT_HOME="$account" WORKDIR="$wt" TASK_ID="$id"
  # shellcheck source=/dev/null
  ( source "$bfile"; check_backend ) || { echo "backend '$backend' chưa sẵn sàng (xem minion doctor)" >"$err"; write_status fail; die "$id: backend '$backend' chưa sẵn sàng"; }

  log "$id: backend=$backend model=${model:-default} worker=$slot account=${account:-default}"
  for (( attempt=1; attempt<=MAX_RETRY; attempt++ )); do
    if (( attempt > 1 )); then
      git -C "$wt" reset -q --hard "$start"; git -C "$wt" clean -qfd
    fi
    rc=0
    if [[ -n $tcmd ]]; then
      "$tcmd" "$TASK_TIMEOUT" bash -c 'source "$1"; cd "$WORKDIR"; run_backend' _ "$bfile" >"$out" 2>"$err" || rc=$?
    else
      bash -c 'source "$1"; cd "$WORKDIR"; run_backend' _ "$bfile" >"$out" 2>"$err" || rc=$?
    fi
    (( rc == 0 )) && break
    local wait_s=$(( RETRY_BACKOFF * attempt ))
    if grep -qiE '429|quota|rate.?limit|RESOURCE_EXHAUSTED' "$err"; then
      wait_s=$(( wait_s * 3 )); log "$id: bị rate-limit (lần $attempt)"
    elif (( rc == 124 )); then
      log "$id: quá thời gian ${TASK_TIMEOUT}s (lần $attempt)"
    else
      log "$id: lỗi rc=$rc (lần $attempt)"
    fi
    (( attempt < MAX_RETRY )) && { log "$id: thử lại sau ${wait_s}s"; sleep "$wait_s"; }
  done
  (( attempt > MAX_RETRY )) && attempt=$MAX_RETRY

  # Commit thay đổi của worker vào nhánh minion/<id> để orchestrator diff/merge.
  git -C "$wt" add -A
  if ! git -C "$wt" diff --cached --quiet; then
    local git_user git_email
    git_user="$(git -C "$ROOT" config user.name 2>/dev/null || true)"
    git_email="$(git -C "$ROOT" config user.email 2>/dev/null || true)"
    git_user="${git_user:-ngtukien}"
    git_email="${git_email:-144638414+ngtukien@users.noreply.github.com}"
    git -C "$wt" -c user.name="$git_user" -c user.email="$git_email" \
      commit -q --no-verify -m "minion($id): $backend/${model:-default} attempt $attempt"
  fi

  if (( rc == 0 )); then write_status ok; log "$id: OK"; return 0; fi
  write_status fail; log "$id: FAIL sau $attempt lần"; return 1
}
