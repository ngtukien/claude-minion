# claude-minion 🍌

**Claude làm Gru (Orchestrator), dàn AI CLI làm Minions cày việc song song.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v0.2.0-blue.svg)](https://github.com/ngtukien/claude-minion/releases/tag/v0.2.0)

> **Ý tưởng cốt lõi**: Claude Code là bộ não kiến trúc sư (Gru) nhận yêu cầu lớn → phân rã thành các task độc lập. Các AI CLI nhỏ gọn, tốc độ cao (Minions — mặc định là Antigravity CLI `agy` chạy Gemini Flash/Pro) được thả vào từng **git worktree** riêng biệt để làm việc song song. Gru kiểm tra nghiệm thu từng dòng code, chạy test, yêu cầu sửa nếu chưa đạt, rồi tự tay merge code sạch vào nhánh chính.

```
                  ┌───────────────── Bạn ─────────────────┐
                  │       claude                           │
                  │       > /orchestrate <yêu cầu lớn>     │
                  └───────────────────┬────────────────────┘
                                      │
                                      ▼
                      ┌───────────────────────────────┐
                      │    Claude Code (Gru)          │
                      │   - Phân tích & chia task     │ ──► .minion/tasks/*.md
                      │   - Nghiệm thu, diff, test    │ ◄── .minion/out/*.md
                      │   - Đóng mộng & merge         │
                      └───────────────┬───────────────┘
                                      │
                               minion run (hàng đợi, retry, timeout)
            ┌─────────────────┬───────┴────────┬─────────────────┐
            ▼                 ▼                ▼                 ▼
      Minion #1 (Bob)   Minion #2 (Kevin) Minion #3 (Stuart) Minion #4 (Dave)
       backend: agy      backend: agy     backend: agy      backend: codex...
      wt: .minion/wt/01 wt: .minion/wt/02 wt: .minion/wt/03 wt: .minion/wt/04
      branch: minion/01 branch: minion/02 branch: minion/03 branch: minion/04
```

---

## ✨ Điểm nổi bật

- **Tăng tốc x4 - x10 lần**: Các task độc lập (viết model, migration, router, unit test, tài liệu...) được thực thi song song cùng lúc.
- **An toàn tuyệt đối với Git Worktree**: Mỗi minion chỉ được làm việc trong worktree riêng biệt. Nhánh chính của bạn hoàn toàn sạch sẽ cho đến khi Claude nghiệm thu và merge.
- **Tiết kiệm chi phí**: Dùng Claude cho việc planning và review cao cấp; dùng các model giá rẻ hoặc subscription sẵn có (như Gemini qua Antigravity CLI `agy`) để gõ code.
- **Vòng lặp phản hồi (Feedback Loop)**: Nếu minion làm sai hoặc fail test, Claude tự động chỉ ra lỗi tại `file:line`, bắt minion sửa tiếp trong worktree đó (tối đa 2 vòng).
- **Cấu hình linh hoạt**: Hỗ trợ nhiều tài khoản, nhiều model (`Gemini 3.5 Flash`, `Gemini 3.5 Pro`...), dễ dàng mở rộng sang các backend khác (Codex, Qwen...).

---

## 📦 Yêu cầu hệ thống

1. **Hệ điều hành**: Linux hoặc macOS (Bash ≥ 4.3; trên macOS: `brew install bash coreutils`).
2. **Git**: Đã cài đặt và đang ở trong một repo có ít nhất 1 commit.
3. **[Claude Code](https://docs.claude.com/en/docs/claude-code)**: Bộ não điều phối (`claude`).
4. **Worker CLI** (mặc định: **Antigravity CLI** `agy`):
   ```bash
   curl -fsSL https://antigravity.google/cli/install.sh | bash
   agy  # Chạy thử 1 lần để đăng nhập Google
   ```

---

## 🚀 Cài đặt

### Cách 1: Cài đặt trực tiếp từ Git (Khuyên dùng)

```bash
git clone git@github.com:ngtukien/claude-minion.git ~/tools/claude-minion
cd ~/tools/claude-minion
./install.sh --with-skill
```

Lệnh này sẽ:
- Link thực thi `minion` (và alias `fleet`) vào `~/.local/bin/`.
- Tạo file cấu hình mẫu tại `~/.config/claude-minion/config`.
- Cài đặt skill `/orchestrate` vào Claude Code (`~/.claude/skills/orchestrate`).

*(Đảm bảo `~/.local/bin` đã có trong `$PATH` của bạn).*

### Cách 2: Cài đặt dạng Claude Code Plugin

Trong terminal của Claude Code (lệnh 1 bước trên Claude Code 2.1.275+):
```
/plugin install minion --marketplace ngtukien/claude-minion
/minion-setup
```

Hoặc 2 bước truyền thống:
```
/plugin marketplace add ngtukien/claude-minion
/plugin install minion@ngtukien
/minion-setup
```

---

## ⚙️ Cấu hình Minions (Workers)

Mở file cấu hình để xem và chỉnh sửa:
```bash
minion workers                    # Xem danh sách worker hiện tại
nano ~/.config/claude-minion/config
```

Mỗi dòng trong `WORKERS` định nghĩa 1 minion theo định dạng `backend|model|account_home`:

```bash
WORKERS=(
  "antigravity||"                       # Minion 1: model mặc định, tài khoản $HOME
  "antigravity||"                       # Minion 2: model mặc định
  "antigravity|Gemini 3.5 Pro|"         # Minion 3: model Pro xử lý task phức tạp
  "antigravity||"                       # Minion 4: model mặc định
)

MAX_PARALLEL=4                          # Số minion chạy đồng thời tối đa
MAX_RETRY=3                             # Tự động retry khi gặp lỗi / rate-limit
```

- Để trống cột model: CLI sẽ dùng model mặc định của backend (thường là Flash). Xem danh sách model khả dụng bằng `agy models`.
- Để trống `account_home`: Dùng chung thông tin đăng nhập trong `$HOME`.

### Kiểm tra sẵn sàng:
```bash
minion login 1       # Đăng nhập cho minion (nếu chưa từng đăng nhập agy)
minion doctor        # Khám sức khỏe toàn bộ hệ thống
```

---

## 📖 Hướng dẫn sử dụng

### 1. Sử dụng tự động qua Claude Code

Đây là cách dùng chính. Chỉ cần vào bất kỳ thư mục git nào của bạn:

```bash
claude
```

Và gõ lệnh:
```text
> /orchestrate Viết REST API quản lý người dùng bằng Go: models, handlers, JWT auth và unit tests
```

#### Quy trình tự động diễn ra:
1. **Lập kế hoạch (Plan)**: Claude đọc repo, chia yêu cầu thành các task độc lập, ghi vào `.minion/tasks/*.md`.
2. **Triển khai (Run)**: Lệnh `minion run` chạy song song trên các worker. Mỗi task được cấp một git worktree riêng (`.minion/wt/<task-id>`) và một nhánh riêng (`minion/<task-id>`).
3. **Thẩm định (Review)**: Claude xem diff (`minion diff`), đọc output, chạy test thử trong từng worktree, chấm **PASS** hoặc **FAIL**.
4. **Sửa lỗi (Feedback)**: Task nào **FAIL** sẽ được Claude gửi phản hồi chi tiết vào file task và cho minion chạy sửa lại ngay trên worktree đó.
5. **Tích hợp (Merge)**: Claude chạy `minion merge --ok`, kiểm tra test tổng thể trên nhánh chính và báo cáo kết quả hoàn chỉnh cho bạn!

---

### 2. Bảng tra cứu lệnh CLI `minion`

Bạn hoàn toàn có thể sử dụng lệnh `minion` độc lập bằng tay trong terminal:

| Lệnh | Mô tả |
| :--- | :--- |
| `minion init` | Khởi tạo file cấu hình mẫu tại `~/.config/claude-minion/config` |
| `minion workers` | Liệt kê danh sách minion, backend, model và tài khoản |
| `minion login <n>` | Mở giao diện đăng nhập cho minion thứ `n` |
| `minion doctor` | Kiểm tra môi trường (bash, git, backend, tài khoản, repo) |
| `minion run [id...]` | Chạy toàn bộ task trong `.minion/tasks/` (hoặc chỉ định ID) |
| `minion run --todo` | Chỉ chạy những task chưa hoàn thành (`status != ok`) |
| `minion status` | Xem bảng tiến độ, trạng thái (ok/fail/pending), model, thời gian |
| `minion diff <id>` | Xem git diff chi tiết những thay đổi minion đã thực hiện |
| `minion merge <id...>`| Merge nhánh của minion vào nhánh hiện tại |
| `minion merge --ok` | Tự động merge tất cả các task đã đạt chuẩn (`ok`) |
| `minion clean` | Dọn dẹp worktrees và các nhánh `minion/*`, lưu trữ task vào `.minion/archive/` |
| `minion clean --all` | Xóa sạch toàn bộ thư mục `.minion/` |

---

### 3. Cấu trúc thư mục `.minion/`

Trong quá trình chạy, một thư mục `.minion/` sẽ xuất hiện trong repo của bạn:

```
.minion/
├── tasks/     # Các file mô tả công việc (01-user-model.md, 02-jwt-auth.md...)
├── out/       # Output kết quả, stderr, và file trạng thái (.status, .base)
├── wt/        # Git worktrees độc lập cho từng minion đang thi công
├── prompts/   # Toàn bộ prompt thực tế kèm preamble gửi cho AI CLI
├── logs/      # Log chi tiết của từng lượt chạy worker
└── archive/   # Lịch sử các đợt chạy trước đó (sau khi chạy minion clean)
```

> [!NOTE]
> Thư mục `.minion/` tự động được thêm vào `.git/info/exclude` của Git repo, đảm bảo không bao giờ bị dính vào git tracking hay làm bẩn nhánh làm việc của bạn.

---

### 4. Cú pháp định nghĩa Task

Bạn (hoặc Claude) có thể chỉ định model hoặc worker riêng cho từng task thông qua frontmatter:

```markdown
---
model: Gemini 3.5 Pro    # Chỉ định model mạnh hơn cho task phức tạp
backend: antigravity     # Chỉ định backend
worker: 3                # Ghim cố định vào minion số 3
---

# Goal
Tạo model User và phương thức HashPassword bằng bcrypt.

# Files
- Create/modify: internal/models/user.go
- Do not touch: internal/router/router.go

# Acceptance criteria
- [ ] Định nghĩa struct User (ID, Username, PasswordHash)
- [ ] Chạy lệnh kiểm tra: `go test ./internal/models/...`

# Output
Kết thúc bằng phần "## REPORT" tóm tắt các file đã sửa và kết quả tự test.
```

---

## 🧪 Chạy thử nghiệm giả lập (Mock Test)

Bạn có thể chạy thử toàn bộ vòng đời mà không tốn 1 token AI nào qua mock test:

```bash
bash tests/smoke.sh
```

Hoặc đổi `DEFAULT_BACKEND=mock` trong config để làm quen với quy trình điều phối của Claude.

---

## 🔌 Thêm Backend AI CLI mới

Bạn muốn tích hợp thêm Codex CLI, Qwen CLI hay bất kỳ AI tool nào khác? Rất đơn giản:

1. Copy file mẫu:
   ```bash
   cp backends/_template.sh backends/codex.sh
   ```
2. Mở `backends/codex.sh` và triển khai 3 hàm cơ bản:
   - `check_backend`: Kiểm tra CLI đã được cài chưa (`command -v codex`).
   - `run_backend`: Lệnh thực thi CLI với file prompt `$PROMPT_FILE`.
   - `login_backend`: Lệnh mở phiên đăng nhập tương tác.
3. Khai báo minion mới trong config:
   ```bash
   WORKERS+=("codex|gpt-4.5|")
   ```

---

## 🗑️ Gỡ cài đặt

```bash
./install.sh --uninstall
```
*(Nếu muốn xóa sạch cấu hình: `rm -rf ~/.config/claude-minion`).*

---

## 🌐 English Summary

**claude-minion** empowers Claude Code to act as **Gru** (the mastermind orchestrator), coordinating a team of lightweight, high-speed **Minions** (AI CLI workers such as Google's Antigravity CLI `agy` running Gemini Flash/Pro) running in parallel across isolated Git worktrees.

- **Orchestration**: Claude plans, writes task specs, and launches workers via `minion run`.
- **Parallel Worktrees**: Minions implement features in separate git worktrees and branches (`minion/<id>`) without touching each other or the main branch.
- **Review & Integrate**: Claude reviews every diff, verifies acceptance tests, provides feedback for retries if needed, and cleanly merges passing work.

Run `bash tests/smoke.sh` for an instant zero-AI smoke test.

---

## 📄 License

Phát hành dưới giấy phép [MIT](LICENSE). Bản quyền thuộc về © 2026 Nguyễn Tự Kiên.
