#!/usr/bin/env bash
# Cài claude-minion: link lệnh `minion` vào ~/.local/bin, tạo config.
#   ./install.sh               cài CLI + config (dùng khi đã cài plugin)
#   ./install.sh --with-skill  cài thêm skill /orchestrate vào ~/.claude/skills (cài thủ công, không qua plugin)
#   ./install.sh --uninstall   gỡ link và skill (giữ config)
set -euo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SKILL_DIR="$HOME/.claude/skills/orchestrate"
CFG="${MINION_CONFIG:-${FLEET_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-minion/config}}"

with_skill=0; uninstall=0
for a in "$@"; do
  case "$a" in
    --with-skill) with_skill=1 ;;
    --uninstall)  uninstall=1 ;;
    -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
    *) echo "tham số lạ: $a" >&2; exit 2 ;;
  esac
done

if (( uninstall )); then
  rm -f "$BIN_DIR/minion" "$BIN_DIR/fleet"
  rm -rf "$SKILL_DIR"
  echo "Đã gỡ $BIN_DIR/minion và $SKILL_DIR (config giữ nguyên ở $CFG)."
  exit 0
fi

chmod +x "$HERE/bin/minion" "$HERE/install.sh" "$HERE/tests/"*.sh 2>/dev/null || true
mkdir -p "$BIN_DIR"
ln -sf "$HERE/bin/minion" "$BIN_DIR/minion"
ln -sf "$HERE/bin/minion" "$BIN_DIR/fleet" 2>/dev/null || true
echo "✔ đã link $BIN_DIR/minion → $HERE/bin/minion"

if [[ ! -f $CFG ]]; then
  mkdir -p "$(dirname "$CFG")"
  cp "$HERE/config.example" "$CFG"
  echo "✔ đã tạo config $CFG"
else
  echo "• config đã có: $CFG (giữ nguyên)"
fi

if (( with_skill )); then
  mkdir -p "$SKILL_DIR"
  cp "$HERE/skills/orchestrate/SKILL.md" "$SKILL_DIR/SKILL.md"
  echo "✔ đã cài skill vào $SKILL_DIR (gọi bằng /orchestrate trong Claude Code)"
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo
     echo "! $BIN_DIR chưa có trong PATH. Thêm dòng này vào ~/.bashrc hoặc ~/.zshrc:"
     echo "    export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo
echo "Tiếp theo:"
echo "  1. Sửa WORKERS trong $CFG"
echo "  2. minion login 1       # đăng nhập tài khoản cho worker 1 (lặp lại nếu nhiều tài khoản)"
echo "  3. minion doctor"
echo "  4. Trong một git repo: claude  →  /orchestrate <yêu cầu>"
