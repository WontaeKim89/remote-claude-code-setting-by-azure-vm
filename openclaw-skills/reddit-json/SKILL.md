---
name: reddit-json
description: |
  Reddit JSON public API skill (인증 불필요 read-only).
  Use this skill whenever the user wants to:
  (1) 특정 서브레딧의 hot/top/new 게시물,
  (2) 키워드 / 사용자 / multireddit 검색,
  (3) AI/ML 커뮤니티 (r/MachineLearning, r/LocalLLaMA, r/OpenAI, r/Anthropic) 동향,
  (4) 한국 관련 서브 (r/korea, r/hanguk) 트렌드,
  (5) 댓글 트리/upvote 추세 분석.
  관련 키워드: "레딧", "reddit", "서브레딧", "r/...", "subreddit".
metadata:
  openclaw:
    emoji: "🟦"
    requires:
      anyBins: ["curl", "jq"]
---

# Reddit JSON API

URL 끝에 `.json` 만 붙이면 JSON 응답. 인증 불필요 (read-only).
무료, 60 req/분 정도 권장 (User-Agent 명시 필수).

## 의도/목적

- 하위 서브레딧별 하이라이트로 다양한 도메인 트렌드 분석.
- AI brief 의 보조 소스 (HN 과 결합하면 영미권 거의 커버).
- API key 없이 곧장 사용 가능 (curl 한 줄).

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "r/MachineLearning 핫글 10개" | /r/MachineLearning/hot.json |
| "r/LocalLLaMA 오늘 top" | /r/LocalLLaMA/top.json?t=day |
| "r/OpenAI 새 글 5개" | /r/OpenAI/new.json |
| "Reddit 에서 'Claude Sonnet 5' 검색" | /search.json?q=... |
| "r/korea 인기글 알려줘" | /r/korea/hot.json |
| "r/Anthropic 이번 주 top" | /r/Anthropic/top.json?t=week |

## 명령 매핑

```bash
UA="vivi-openclaw/1.0 by zzang891014"  # User-Agent 필수

# 서브 hot
SUB="MachineLearning"
LIMIT=10
curl -s -A "$UA" "https://www.reddit.com/r/${SUB}/hot.json?limit=${LIMIT}" | \
  jq '.data.children[] | .data | {title, score, num_comments, url, permalink, author, created_utc}'

# top (시간 범위: hour/day/week/month/year/all)
curl -s -A "$UA" "https://www.reddit.com/r/${SUB}/top.json?t=day&limit=${LIMIT}" | \
  jq '.data.children[] | .data | {title, score, num_comments, permalink}'

# 키워드 검색
QUERY="claude sonnet"
curl -s -A "$UA" -G "https://www.reddit.com/search.json" \
    --data-urlencode "q=${QUERY}" \
    --data-urlencode "sort=new" \
    --data-urlencode "limit=10" | \
  jq '.data.children[].data | {title, subreddit, score, permalink}'

# 특정 글의 댓글
PERMALINK="/r/MachineLearning/comments/abcdef/title_here/"
curl -s -A "$UA" "https://www.reddit.com${PERMALINK}.json?limit=10" | \
  jq '.[1].data.children[].data | {body, score, author}'
```

## 응답 포맷

```
🟦 r/{sub} {sort}
1. {title} ({score}↑ · {num_comments}💬)
   reddit.com{permalink}
2. ...
```

## 주의

- `User-Agent` 안 보내면 429 자주 받음. 의미있는 식별자 권장.
- AI 관련 sub 추천: MachineLearning, LocalLLaMA, OpenAI, Anthropic, ArtificialIntelligence, ChatGPT, ClaudeAI, singularity, MLQuestions.
- `created_utc` 는 unix epoch (UTC).
- 정치/논란 sub 은 NSFW/논란 게시물 포함될 수 있음 → daily brief 에선 ML/AI 위주 추천.
