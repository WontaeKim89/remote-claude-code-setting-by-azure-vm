#!/usr/bin/env bash
# notify-remote-url.sh — rc.log에서 첫 번째 https:// URL을 찾아 Telegram으로 전송.
# 호출 컨텍스트: systemd --user (claude-url-notifier.service) 에서 1회 실행.
# 필요한 환경변수(notifier.env에서 systemd가 주입):
#   TELEGRAM_BOT_TOKEN : BotFather가 발급한 봇 토큰
#   TELEGRAM_CHAT_ID   : 수신자 chat_id (본인 Telegram 계정 ID)

set -euo pipefail

LOG_FILE="${HOME}/.local/share/claude-remote/rc.log"

# remote-control 서비스가 rc.log를 만들 때까지 최대 60초 대기
for _ in {1..60}; do
  [[ -f "$LOG_FILE" ]] && break
  sleep 1
done

if [[ ! -f "$LOG_FILE" ]]; then
  echo "rc.log를 찾지 못했습니다: $LOG_FILE" >&2
  exit 1
fi

# tail -F로 파일 스트리밍 중 claude.ai/code 환경 URL만 매칭.
# 문서 링크(code.claude.com/docs/...) 같은 노이즈는 무시.
# grep -m1: 1회 매칭 후 종료 → tail도 SIGPIPE로 자연 종료.
URL=$(tail -F "$LOG_FILE" 2>/dev/null | grep -m1 -oE 'https://claude\.ai/code\?environment=[A-Za-z0-9_-]+' || true)

if [[ -z "$URL" ]]; then
  echo "URL을 찾지 못했습니다." >&2
  exit 1
fi

# Telegram Bot API sendMessage (HTML 포맷으로 링크 클릭 가능)
MESSAGE="🚀 <b>Claude Remote Control 준비 완료</b>%0A${URL}"
curl -fsS -X POST \
  "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "parse_mode=HTML" \
  -d "text=${MESSAGE}" > /dev/null

echo "Telegram 전송 완료: ${URL}"
