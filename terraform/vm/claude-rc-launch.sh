#!/usr/bin/env bash
# claude-rc-launch.sh <label>
#
# - tmux 세션 'rc-<label>' 안에서 claude --remote-control 을 띄운다
#   (이미 같은 이름의 세션이 있으면 정리 후 재생성)
# - tmux pipe-pane 으로 pane 출력을 LOG 파일에 append → URL 추출 가능
# - sessions.json registry 의 session_id 가 있으면 --resume, 없으면 새로 시작
# - 시작 후 백그라운드로 LOG 를 watch 해서 URL 발견 시 Telegram 으로 발송 +
#   새 jsonl 파일 등장 시 registry 에 session_id 자동 등록
# - 본 스크립트 자체는 tmux 세션이 살아있는 동안 forever loop 으로 살아있어
#   systemd 가 main process 를 정상적으로 추적하게 한다.

set -euo pipefail

LABEL="${1:?label required}"

REG="${HOME}/.config/claude-remote/sessions.json"
LOG="${HOME}/.local/share/claude-remote/rc-${LABEL}.log"
PROJECT_LOG_DIR="${HOME}/.claude/projects/-home-azureuser-project"
NOTIFIER_ENV="${HOME}/.config/claude-remote/notifier.env"
TMUX_SESSION="rc-${LABEL}"

mkdir -p "$(dirname "$LOG")" "$(dirname "$REG")"

if [[ -f "$NOTIFIER_ENV" ]]; then
    # shellcheck disable=SC1090
    . "$NOTIFIER_ENV"
fi

# Telegram 으로 URL 발송 (한국어/특수문자 안전 인코딩 위해 python 사용).
send_url() {
    local url="$1"
    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        return 0
    fi
    LABEL_VAR="$LABEL" URL_VAR="$url" \
    TG_TOKEN="$TELEGRAM_BOT_TOKEN" TG_CHAT="$TELEGRAM_CHAT_ID" \
    python3 - <<'PY' || true
import os, urllib.request, urllib.parse
data = urllib.parse.urlencode({
    "chat_id": os.environ["TG_CHAT"],
    "parse_mode": "HTML",
    "disable_web_page_preview": "true",
    "text": f"🚀 <b>Remote Control</b> · <code>{os.environ['LABEL_VAR']}</code>\n{os.environ['URL_VAR']}",
}).encode()
try:
    urllib.request.urlopen(
        f"https://api.telegram.org/bot{os.environ['TG_TOKEN']}/sendMessage",
        data=data, timeout=10,
    ).read()
except Exception as e:
    print(f"send_url failed: {e}")
PY
}

# registry I/O
get_session_id() {
    [[ -f "$REG" ]] || return 0
    python3 - "$REG" "$LABEL" <<'PY'
import json, sys
path, label = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        d = json.load(f)
    for s in d.get("sessions", []):
        if s.get("label") == label:
            print(s.get("session_id") or "")
            break
except Exception:
    pass
PY
}

update_session_id() {
    local sid="$1"
    python3 - "$REG" "$LABEL" "$sid" <<'PY'
import json, pathlib, sys
path, label, sid = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(path)
p.parent.mkdir(parents=True, exist_ok=True)
d = {"sessions": []}
if p.exists():
    try: d = json.loads(p.read_text())
    except: d = {"sessions": []}
labels = [s.get("label") for s in d.get("sessions", [])]
if label in labels:
    for s in d["sessions"]:
        if s.get("label") == label:
            s["session_id"] = sid
else:
    d.setdefault("sessions", []).append({"label": label, "session_id": sid})
p.write_text(json.dumps(d, indent=2))
PY
}

# 0. 기존 동명 tmux session 정리
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
: > "$LOG"

# 1. claude command 결정
# --permission-mode bypassPermissions: 모든 permission prompt 자동 수락. 모바일에서
#   매번 "이 명령 허용?" 묻지 않게 함. VM 은 사용자 단독 격리 환경이라 안전.
#   (= --dangerously-skip-permissions 와 동등 효과)
PERMISSION_FLAG="--permission-mode bypassPermissions"

SID="$(get_session_id || true)"
if [[ -n "$SID" && -f "${PROJECT_LOG_DIR}/${SID}.jsonl" ]]; then
    echo "[claude-rc-launch:${LABEL}] resuming session ${SID} (bypass mode)" >&2
    CLAUDE_CMD="cd '${HOME}/project' && exec claude --remote-control ${PERMISSION_FLAG} --resume '$SID' --name '$LABEL'"
else
    echo "[claude-rc-launch:${LABEL}] starting fresh session (bypass mode)" >&2
    CLAUDE_CMD="cd '${HOME}/project' && exec claude --remote-control ${PERMISSION_FLAG} --name '$LABEL'"
fi

# 2. 새 jsonl 등장 감지를 위한 snapshot
SNAP_FILE="$(mktemp)"
trap 'rm -f "$SNAP_FILE"' EXIT
ls -t "$PROJECT_LOG_DIR"/*.jsonl 2>/dev/null > "$SNAP_FILE" || true

# 3. tmux detached session 안에서 claude 실행
tmux new-session -d -s "$TMUX_SESSION" -c "${HOME}/project" "$CLAUDE_CMD"

# 4. pane 출력을 LOG 파일에 pipe (-o = on, default no append; -O = append)
# tmux 의 pipe-pane 은 매번 호출 시 toggle. -o off 안전 처리 후 다시 on.
tmux pipe-pane -t "$TMUX_SESSION" 'cat >> '"$LOG"

# 5. 백그라운드 watcher: bypass 동의 자동 입력 + URL 발송 + registry 등록
(
    BYPASS_ACKED=""
    URL_SENT=""
    SID_SAVED="$SID"
    DEADLINE=$(($(date +%s) + 90))
    while [[ $(date +%s) -lt $DEADLINE ]]; do
        sleep 2

        # bypassPermissions 첫 실행 시 동의 prompt 자동 처리.
        # tmux capture-pane 으로 prompt 텍스트 보이면 "2" + Enter 보내서 'Yes, I accept'.
        if [[ -z "$BYPASS_ACKED" ]]; then
            if tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | grep -q "I accept"; then
                tmux send-keys -t "$TMUX_SESSION" "2" Enter
                BYPASS_ACKED="yes"
            fi
        fi

        if [[ -z "$URL_SENT" ]]; then
            U=$(grep -oE "https://claude\.ai/code(\?environment=[A-Za-z0-9_-]+|/session_[A-Za-z0-9]+)" "$LOG" 2>/dev/null | head -1 || true)
            if [[ -n "$U" ]]; then
                send_url "$U"
                URL_SENT="$U"
            fi
        fi
        if [[ -z "$SID_SAVED" ]]; then
            LATEST=$(ls -t "$PROJECT_LOG_DIR"/*.jsonl 2>/dev/null | head -1 || true)
            if [[ -n "$LATEST" ]] && ! grep -qx "$LATEST" "$SNAP_FILE"; then
                NEW_SID=$(basename "$LATEST" .jsonl)
                update_session_id "$NEW_SID"
                SID_SAVED="$NEW_SID"
            fi
        fi
        if [[ -n "$URL_SENT" && -n "$SID_SAVED" ]]; then
            break
        fi
    done
) &

# 6. tmux 세션이 죽을 때까지 대기 (systemd 가 본 프로세스를 main pid 로 추적)
while tmux has-session -t "$TMUX_SESSION" 2>/dev/null; do
    sleep 5
done

echo "[claude-rc-launch:${LABEL}] tmux session ended, exiting" >&2
