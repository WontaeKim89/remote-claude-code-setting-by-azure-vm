---
name: hacker-news
description: |
  Hacker News (news.ycombinator.com) Public API skill.
  Use this skill whenever the user wants to:
  (1) 기술/스타트업 트렌드 파악 (top stories, ask HN, show HN, jobs),
  (2) AI/Claude/GPT/LLM 등 키워드 인기글 모니터링,
  (3) 특정 주제의 글에 달린 댓글 토론 요약,
  (4) Show HN/Ask HN 으로 최신 프로젝트 발굴,
  (5) 한국 시간 자정~아침에 미국 개발자 커뮤니티 동향 파악.
  관련 키워드: "해커뉴스", "hn", "hacker news", "기술 트렌드", "ycombinator".
metadata:
  openclaw:
    emoji: "🟧"
    requires:
      anyBins: ["curl", "jq"]
---

# Hacker News Firebase API

무료, 인증 불필요, 무제한.

## 의도/목적

- 기술 커뮤니티의 가장 빠른 신호 소스. 한국 시간으로 자정~새벽이 미국 prime time.
- AI 관련 글이 매일 다수 올라옴 → daily AI brief 의 1차 소스.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "오늘 해커뉴스 톱 10" | topstories |
| "최근 Show HN 보여줘" | showstories |
| "HN 에 GPT 관련 인기글" | topstories + filter |
| "이 글의 댓글 요약해줘 https://news.ycombinator.com/item?id=..." | item endpoint |
| "Ask HN 에서 LLM 질문" | askstories + filter |
| "지금 HN 1면 (front page)" | topstories[:30] |
| "Y Combinator 채용공고" | jobstories |

## 명령 매핑

```bash
# top stories ID 목록 (최대 500)
curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" | jq '.[:30]'

# 각 ID 의 상세 (title, url, by, score, time, kids, descendants)
ITEM_ID=12345
curl -s "https://hacker-news.firebaseio.com/v0/item/${ITEM_ID}.json" | jq

# top 10 with title + score + url
curl -s "https://hacker-news.firebaseio.com/v0/topstories.json" | jq '.[:10][]' | \
  while read id; do
    curl -s "https://hacker-news.firebaseio.com/v0/item/${id}.json" | \
      jq '{title, score, url, by, time, descendants}'
  done

# 다른 endpoint:
#   newstories.json  : 최신
#   beststories.json : 베스트
#   askstories.json  : Ask HN
#   showstories.json : Show HN
#   jobstories.json  : Jobs
```

## 응답 포맷

```
🟧 Hacker News Top {N}
1. {title} ({score}↑ · {descendants}💬)
   {url}
   {hostname}
2. ...
```

## 주의

- 인증 불필요. 단 `time` 은 unix epoch — 한국시간 변환 필요.
- `url` 이 null 이면 self-post (Ask HN 등). `https://news.ycombinator.com/item?id=<id>` 로 fallback.
- AI 키워드 필터: title 안에 `ai|llm|gpt|claude|gemini|openai|anthropic|hugging|model|transformer` 등 매칭.
