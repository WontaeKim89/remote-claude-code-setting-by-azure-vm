#!/usr/bin/env bash
# ai-news-brief.sh
#
# 매일 아침 (default 07:00 KST) 실행.
# - Hacker News top stories 50개 fetch + AI 키워드 필터
# - Reddit r/MachineLearning, r/LocalLLaMA, r/OpenAI, r/Anthropic top day 합산
# - litellm-proxy (gpt-5.5) 호출하여 한국어 brief (10개 선별 + 한 줄 요약)
# - Telegram 으로 발송
#
# 의존: curl, jq, python3 (urllib), litellm-proxy (127.0.0.1:4000), notifier.env

set -euo pipefail

NOTIFIER_ENV="${HOME}/.config/claude-remote/notifier.env"
LITELLM_BASE="http://127.0.0.1:4000"
LITELLM_KEY="sk-local-claude-code-proxy"
MODEL="gpt-5.5"

# AI 키워드 (대소문자 무시).
AI_KEYWORDS_RE='ai|llm|gpt|claude|gemini|openai|anthropic|hugging|transformer|diffusion|sora|stable|llama|mistral|cohere|deepmind|copilot|inference|fine-tune|rag|agent'

if [[ -f "$NOTIFIER_ENV" ]]; then
    # shellcheck disable=SC1090
    . "$NOTIFIER_ENV"
fi
if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
    echo "TELEGRAM creds 없음" >&2
    exit 1
fi

UA="vivi-ai-brief/1.0"

# ── 1. Hacker News fetch ────────────────────────────────────
HN_ITEMS=$(
    curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" \
    | jq '.[:50][]' \
    | while read -r id; do
        curl -s "https://hacker-news.firebaseio.com/v0/item/${id}.json"
    done \
    | jq -s "[.[] | select(.title and (.title | test(\"${AI_KEYWORDS_RE}\"; \"i\"))) | {source:\"HN\", title, url: (.url // \"https://news.ycombinator.com/item?id=\(.id)\"), score, comments:.descendants, by, time}]"
)

# ── 2. Reddit fetch (4 subs, top day) ───────────────────────
REDDIT_SUBS=(MachineLearning LocalLLaMA OpenAI Anthropic ChatGPT ClaudeAI ArtificialIntelligence)
REDDIT_ITEMS="[]"
for sub in "${REDDIT_SUBS[@]}"; do
    items=$(
        curl -s -A "$UA" "https://www.reddit.com/r/${sub}/top.json?t=day&limit=10" \
        | jq "[.data.children[].data | {source:\"r/${sub}\", title, url: (\"https://reddit.com\" + .permalink), score, comments:.num_comments, by:.author, time:.created_utc}]"
    )
    REDDIT_ITEMS=$(jq -s 'add' <(echo "$REDDIT_ITEMS") <(echo "$items"))
    sleep 1   # rate limit
done

# ── 3. Merge + dedupe + sort by score ───────────────────────
ALL_ITEMS=$(jq -s 'add | unique_by(.title) | sort_by(-.score)' <(echo "$HN_ITEMS") <(echo "$REDDIT_ITEMS"))
TOP_30=$(echo "$ALL_ITEMS" | jq '.[:30]')

# ── 4. LLM brief (litellm) ──────────────────────────────────
LLM_PROMPT=$(cat <<EOF
다음은 오늘 새벽 사이 영미권 기술 커뮤니티 (Hacker News + Reddit AI 서브) 의 AI 관련 인기글 30개다.
이 중 가장 흥미롭고 의미 있는 10개를 선별하고, 각각을 한국어 한 줄 (40자 이내) 로 요약해라.
형식:
  1. [출처] 제목 한국어 요약 (점수↑/댓글💬)
     URL

원문 데이터:
${TOP_30}

선별 기준 (우선순위):
  - 새 모델/논문 출시
  - 의미 있는 벤치마크/기술 발표
  - LLM 응용/도구 (claude code, agent, RAG 등)
  - 한국 사용자에게 실용적
  - 단순 의견/논쟁/일반 뉴스는 제외
EOF
)

REPORT=$(curl -s -X POST "${LITELLM_BASE}/chat/completions" \
    -H "Authorization: Bearer ${LITELLM_KEY}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg model "$MODEL" --arg p "$LLM_PROMPT" \
        '{model:$model, messages:[{role:"user", content:$p}], max_tokens:1500}')" \
    | jq -r '.choices[0].message.content')

# ── 5. Telegram 발송 ────────────────────────────────────────
DATE_KR=$(date '+%Y-%m-%d (%a)')
HEADER="🤖 <b>AI 데일리 브리프</b> · ${DATE_KR}"
BODY="${HEADER}

${REPORT}

<i>출처: Hacker News + Reddit AI subs</i>"

python3 - <<PY
import os, urllib.request, urllib.parse
data = urllib.parse.urlencode({
    "chat_id": os.environ["TELEGRAM_CHAT_ID"],
    "parse_mode": "HTML",
    "disable_web_page_preview": "true",
    "text": """$BODY"""[:4000],
}).encode()
try:
    urllib.request.urlopen(
        f"https://api.telegram.org/bot{os.environ['TELEGRAM_BOT_TOKEN']}/sendMessage",
        data=data, timeout=15,
    ).read()
    print("AI brief sent")
except Exception as e:
    print(f"send failed: {e}")
PY
