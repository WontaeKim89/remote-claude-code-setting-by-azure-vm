#!/usr/bin/env bash
# claude-token-refresh.sh
#
# Claude Code OAuth access_token을 만료 전에 비대화형으로 갱신한다.
# RFC 6749 "Refresh Token" grant_type 을 Anthropic /v1/oauth/token endpoint 에 직접 호출.
# `claude --remote-control` 이 idle 동안 자체 refresh 를 트리거하지 않는 문제를 회피하기 위함.
#
# 동작:
#   1. ~/.claude/.credentials.json 에서 refresh_token 로드
#   2. POST https://api.anthropic.com/v1/oauth/token (grant_type=refresh_token)
#   3. 응답으로 받은 새 access_token + refresh_token 을 credentials.json 에 원자적으로 write
#   4. 실패 시 Telegram 알림 (notifier.env)
#
# 사용:
#   claude-token-refresh.sh [HEADROOM_SEC]
#     HEADROOM_SEC: 만료까지 이 시간 미만이면 갱신 수행 (default 3600 = 1h)
#     큰 값(예: 99999)을 주면 강제 trigger 가능 → dry-run 용도.
#
# 위험:
#   - 비공식 endpoint. Anthropic 정책 변경 시 깨질 수 있음.
#   - refresh_token 은 rotation 되므로 응답을 반드시 저장해야 다음 호출 가능.
set -euo pipefail

CRED="$HOME/.claude/.credentials.json"
LOCK="$HOME/.claude/.credentials.lock"
LOG="$HOME/.local/share/claude-remote/token-refresh.log"
NOTIFIER_ENV="$HOME/.config/claude-remote/notifier.env"

CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"
TOKEN_URL="https://api.anthropic.com/v1/oauth/token"
EXPIRE_HEADROOM_SEC="${1:-3600}"

mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date -Iseconds)] $*" >> "$LOG"; }

notify_fail() {
    [[ -f "$NOTIFIER_ENV" ]] || return 0
    # shellcheck disable=SC1090
    . "$NOTIFIER_ENV"
    [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]] && return 0
    MSG_VAR="$1" TG_TOKEN="$TELEGRAM_BOT_TOKEN" TG_CHAT="$TELEGRAM_CHAT_ID" python3 - <<'PY' || true
import os, urllib.request, urllib.parse
data = urllib.parse.urlencode({
    "chat_id": os.environ["TG_CHAT"],
    "parse_mode": "HTML",
    "text": (
        "⚠️ <b>Claude token refresh failed</b>\n"
        f"<code>{os.environ['MSG_VAR']}</code>\n\n"
        "수동 조치: ssh claude-vm → claude → /login → 1 → 'c' 키로 URL 복사 → 인증"
    ),
}).encode()
try:
    urllib.request.urlopen(
        f"https://api.telegram.org/bot{os.environ['TG_TOKEN']}/sendMessage",
        data=data, timeout=10,
    ).read()
except Exception:
    pass
PY
}

# credentials.json 동시 접근 방지
exec 9>"$LOCK"
flock -w 5 9 || { log "lock timeout"; exit 1; }

REFRESH_TOKEN=$(python3 -c '
import json
d = json.load(open("'"$CRED"'"))
o = d.get("claudeAiOauth", d)
print(o["refreshToken"])
')

CURRENT_EXP=$(python3 -c '
import json
d = json.load(open("'"$CRED"'"))
o = d.get("claudeAiOauth", d)
print(o["expiresAt"])
')
NOW_MS=$(( $(date +%s) * 1000 ))
REMAINING_MS=$(( CURRENT_EXP - NOW_MS ))
HEADROOM_MS=$(( EXPIRE_HEADROOM_SEC * 1000 ))

if (( REMAINING_MS > HEADROOM_MS )); then
    log "skip: remaining=$(( REMAINING_MS / 1000 ))s > headroom=${EXPIRE_HEADROOM_SEC}s"
    exit 0
fi

log "refresh start: remaining=$(( REMAINING_MS / 1000 ))s"

RESP=$(curl -sS -o /dev/stdout -w '%{http_code}' \
    -X POST "$TOKEN_URL" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "grant_type=refresh_token" \
    --data-urlencode "refresh_token=$REFRESH_TOKEN" \
    --data-urlencode "client_id=$CLIENT_ID" || echo '000')
HTTP_CODE="${RESP: -3}"
BODY="${RESP::-3}"

if [[ "$HTTP_CODE" != "200" ]]; then
    log "refresh fail: http=$HTTP_CODE body=$BODY"
    notify_fail "HTTP $HTTP_CODE: ${BODY:0:200}"
    exit 1
fi

python3 - <<PY
import json, os, time, sys
resp = json.loads('''$BODY''')
if 'access_token' not in resp:
    print(f'missing access_token: {resp}', file=sys.stderr)
    sys.exit(1)
CRED = "$CRED"
cred = json.load(open(CRED))
key = 'claudeAiOauth' if 'claudeAiOauth' in cred else None
target = cred[key] if key else cred
target['accessToken'] = resp['access_token']
if 'refresh_token' in resp:
    target['refreshToken'] = resp['refresh_token']
target['expiresAt'] = int((time.time() + resp.get('expires_in', 28800)) * 1000)
tmp = CRED + '.tmp'
json.dump(cred, open(tmp, 'w'))
os.chmod(tmp, 0o600)
os.replace(tmp, CRED)
print(f"new expiresAt={target['expiresAt']}")
PY

log "refresh ok"
