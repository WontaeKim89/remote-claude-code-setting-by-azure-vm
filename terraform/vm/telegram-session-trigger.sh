#!/usr/bin/env bash
# telegram-session-trigger.sh
#
# 역할: Telegram 봇을 long-polling 으로 듣고 있다가, 등록된 chat_id 가
#       특정 명령(/new, /session, /url, /restart)을 보내면 VM 의
#       claude-remote-control + url-notifier 서비스를 재기동하여
#       새 Remote Control URL 을 다시 발송한다.
#
# 보안:
#   - notifier.env 에 정의된 TELEGRAM_CHAT_ID 와 일치하는 메시지만 처리.
#     다른 사용자가 봇을 알아내고 명령을 보내도 무시한다.
#
# 충돌 회피:
#   - Telegram 은 update 를 단일 consumer 에게만 전달한다.
#     따라서 claude 의 telegram plugin(MCP)도 같은 토큰으로 polling 하면
#     update 가 두 곳으로 분산되는 race 가 발생한다.
#   - 본 레포는 이런 충돌을 막기 위해 telegram plugin 을 사용하지 않는다.
#     (URL → 브라우저 워크플로우로 충분하기 때문)
#
# 운영:
#   - systemd user service `claude-telegram-trigger.service` 가 본 스크립트를
#     simple 타입으로 호출. 실패 시 5초 후 재시작.
#   - getUpdates timeout=30 long-poll 사용 → 트래픽/배터리 소모 최소.

set -euo pipefail

OFFSET_FILE="${HOME}/.local/share/claude-remote/.tg-offset"
mkdir -p "$(dirname "$OFFSET_FILE")"

OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null || echo 0)

# notifier.env 에서 TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID 주입.
# (systemd unit 의 EnvironmentFile 로도 들어오지만, 직접 실행/디버깅 시 대비해
#  스크립트 안에서도 source 한다.)
if [[ -f "${HOME}/.config/claude-remote/notifier.env" ]]; then
    # shellcheck disable=SC1091
    . "${HOME}/.config/claude-remote/notifier.env"
fi

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 가 비어있다." >&2
    exit 1
fi

# 헬퍼: Telegram 으로 짧은 ack 메시지 전송
send_ack() {
    local text="$1"
    curl -fsS -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "parse_mode=HTML" \
        -d "text=${text}" >/dev/null || true
}

# 헬퍼: 새 Remote Control 세션 생성 (claude-remote-control + url-notifier 재시작)
trigger_new_session() {
    : > "${HOME}/.local/share/claude-remote/rc.log"
    systemctl --user restart claude-remote-control.service
    # claude 가 URL 을 찍는데 보통 3~5초.
    sleep 5
    systemctl --user restart claude-url-notifier.service
}

echo "[telegram-session-trigger] start, offset=${OFFSET}"

while true; do
    # long-poll 30s. 네트워크 일시 단절 등으로 실패하면 5초 후 재시도.
    RESP=$(curl -fsS --max-time 35 \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getUpdates?offset=${OFFSET}&timeout=30" \
        || echo '{"ok":false,"result":[]}')

    LAST_UPDATE_ID=$(printf '%s' "$RESP" | python3 - <<PY
import json, os, sys, subprocess

resp = json.loads(sys.stdin.read() or '{"ok":false,"result":[]}')
if not resp.get("ok"):
    print("")
    sys.exit(0)

allowed_chat_id = str(os.environ.get("TELEGRAM_CHAT_ID", ""))
last_id = ""

TRIGGER_CMDS = {"/new", "/session", "/url", "/restart"}

for u in resp.get("result", []):
    last_id = str(u["update_id"])
    msg = u.get("message") or u.get("edited_message") or {}
    chat = msg.get("chat", {})
    chat_id = str(chat.get("id", ""))
    text = (msg.get("text") or "").strip()
    text_lower = text.lower().split("@")[0]  # /new@botname 같은 형태도 대응

    if chat_id != allowed_chat_id:
        # 권한 없는 사용자. 무시.
        continue

    if text_lower in TRIGGER_CMDS:
        print(f"TRIGGER:{text_lower}", file=sys.stderr)
        # 부모 bash 가 잡을 수 있도록 stdout 에 표시
        sys.stdout.write(f"TRIGGER\n")
        sys.stdout.flush()

print(last_id)
PY
)

    # python 출력 마지막 줄이 last_update_id, 그 이전 라인에 TRIGGER 가 있으면 트리거.
    if echo "$LAST_UPDATE_ID" | grep -q "^TRIGGER$"; then
        echo "[telegram-session-trigger] new-session 요청 수신"
        send_ack "🔄 새 Remote Control 세션 생성 중... 잠시만 기다려라."
        trigger_new_session || true
        # url-notifier 가 실제 URL 메시지를 별도로 보낸다 (notify-remote-url.sh).
    fi

    # 마지막 update_id 업데이트
    NEXT_OFFSET=$(echo "$LAST_UPDATE_ID" | tail -1)
    if [[ -n "$NEXT_OFFSET" && "$NEXT_OFFSET" =~ ^[0-9]+$ ]]; then
        OFFSET=$((NEXT_OFFSET + 1))
        echo "$OFFSET" > "$OFFSET_FILE"
    fi
done
