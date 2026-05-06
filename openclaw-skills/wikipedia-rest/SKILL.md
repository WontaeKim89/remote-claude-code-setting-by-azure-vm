---
name: wikipedia-rest
description: |
  Wikipedia REST API 호출 skill (한국어/영어 위키).
  Use this skill whenever the user wants to:
  (1) 인물·사건·개념의 정의/요약을 빠르게 확인,
  (2) LLM 답변의 사실 검증 (출처 확인),
  (3) 대중 지식 (역사·과학·예술·지리) 1차 reference,
  (4) 영어/한국어 동시 검색 (다국어 비교),
  (5) RAG 파이프라인의 무료 지식 소스.
  관련 키워드: "위키", "정의", "어떤 사람", "사실 확인", "공식 정보", "요약".
metadata:
  openclaw:
    emoji: "📖"
    requires:
      anyBins: ["curl", "jq"]
---

# Wikipedia REST API

무료, 인증 불필요, 무제한.

## 의도/목적

- 사용자 질문이 일반적·역사적 사실/개념일 때 LLM 환각 방지용 출처 fetch.
- 한국어 위키 (`ko.wikipedia.org`) 와 영어 위키 (`en.wikipedia.org`) 둘 다 fallback.
- 검색 + summary + 본문 + 관련 페이지 link 모두 가능.

## 자연어 트리거 예시

| 사용자 발화 | endpoint |
|------|----------|
| "LangGraph 위키에 뭐라고 나와있어" | summary |
| "베르사유 조약 요약해줘" | summary |
| "도로명주소 제도 언제 시작했어 (위키 기준)" | summary |
| "Adam optimizer 설명 위키에서 가져와" | summary (영문) |
| "이순신 장군 1차 자료 위키 링크" | page url |
| "Claude Code 정의 영어 위키에서" | summary (en) |

## 명령 매핑

```bash
# 한국어 위키 페이지 요약
TITLE="<페이지_제목>"
LANG="ko"  # 또는 en

# 1) 검색해서 정확한 title 찾기 (사용자가 약식으로 말한 경우)
curl -s "https://${LANG}.wikipedia.org/w/api.php?action=opensearch&format=json&limit=5&search=$(printf '%s' "$TITLE" | jq -sRr @uri)" | jq '.[1]'

# 2) summary 가져오기
TITLE_URLENC=$(printf '%s' "$TITLE" | jq -sRr @uri)
curl -s "https://${LANG}.wikipedia.org/api/rest_v1/page/summary/${TITLE_URLENC}" | \
  jq '{title: .title, extract: .extract, url: .content_urls.desktop.page, thumbnail: .thumbnail.source}'
```

## 응답 포맷

```
📖 위키({lang}): {title}
{extract 200자 이내}
출처: {url}
```

## 주의

- 한국어 페이지 없으면 영어 fallback 시도.
- `summary` endpoint 는 짧은 요약 (1~3문장). 더 긴 본문 필요하면 `page/html/{title}` 사용.
- 인증 불필요지만 User-Agent 헤더 권장: `-H "User-Agent: openclaw-vivi/1.0"`.
