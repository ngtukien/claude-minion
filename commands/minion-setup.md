---
description: Cài lệnh `minion` vào PATH, tạo config và kiểm tra worker cho claude-minion
---

Set up claude-minion for the user. Reply in the user's language.

1. Find the plugin folder: use `${CLAUDE_PLUGIN_ROOT}` if it is set and contains `install.sh`; otherwise locate it with
   `find ~/.claude/plugins -name install.sh -path '*claude-minion*' 2>/dev/null | head -1`.
2. Run `bash <plugin_folder>/install.sh` (it links `minion` into `~/.local/bin` and creates `~/.config/claude-minion/config` if missing). Do not pass `--with-skill`: the plugin already provides the skill.
3. Run `minion doctor` and explain the result.
4. Tell the user the remaining manual steps, which need an interactive terminal:
   - Edit `~/.config/claude-minion/config` (WORKERS: backend|model|account_home per line).
   - Log in each worker account: `minion login <n>` (Antigravity: sign in with Google in the browser that opens).
   - Then use `/orchestrate <request>` inside any git repo.
   If `~/.local/bin` is not on PATH, show the line to add to their shell rc file.
