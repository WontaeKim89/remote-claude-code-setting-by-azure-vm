---
name: naver-search
description: |
  NAVER 검색 API (Search API) 호출 skill.
  Use this skill whenever the user wants to:
  (1) 한국 뉴스/블로그/카페/책/쇼핑/지식인을 검색,
  (2) 한국 시장에서의 트렌드·여론·후기를 빠르게 파악,
  (3) 외부 LLM 의 잘 모르는 한국 시사·인물·맛집·상품을 조사,
  (4) 한글 키워드로 깊게 뒤져야 하는 RAG 데이터 수집,
  (5) 너무 최신이라 LLM 학습 시점 이후의 한국 정보가 필요할 때.
  관련 키워드: "검색", "찾아봐", "네이버", "뉴스", "블로그", "후기", "최근".
metadata:
  openclaw:
    emoji: "🟢"
    requires:
      anyBins: ["curl", "jq"]
---

# NAVER Search API

한국 시장 정보의 1순위 출처. 무료 한도 25,000 req/일.

## 의도/목적

- LLM 이 모르는 한국 최신/지역 정보를 사용자 발화로부터 곧장 가져온다.
- 카테고리: news, blog, cafearticle, book, shop, kin, encyc, doc, image, webkr.

## 자연어 트리거 예시

| 사용자 발화 | category |
|------|----------|
| "오늘 IT 뉴스 5개 요약해줘" | news |
| "강남 맛집 후기 찾아봐" | blog |
| "맥북 M5 가격 비교해줘" | shop |
| "네이버 카페에서 클로드 코드 사용기 검색" | cafearticle |
| "지식인에서 Azure VM 비용 절감 답변 찾아줘" | kin |
| "이 사람 누구야? 네이버에서 찾아봐" | encyc 또는 webkr |
| "이 책 리뷰 알라딘 말고 네이버 블로그에서" | blog |

## 자격증명 (one-time setup)

`~/.openclaw/credentials/naver-search.env` (권한 0600):
```
NAVER_CLIENT_ID=your_client_id
NAVER_CLIENT_SECRET=your_client_secret
```

발급: https://developers.naver.com/apps → 애플리케이션 등록 → "검색" 사용 API 체크.

## 명령 매핑

```bash
# 환경 로드
. "$HOME/.openclaw/credentials/naver-search.env"

# 검색 (category 는 발화 의도에 맞게 LLM 이 선택)
QUERY="<사용자가_검색하려는_키워드>"
CATEGORY="news"   # news | blog | cafearticle | shop | kin | encyc | book | webkr | image
DISPLAY=10        # 1~100

curl -s -G "https://openapi.naver.com/v1/search/${CATEGORY}.json" \
    --data-urlencode "query=${QUERY}" \
    --data-urlencode "display=${DISPLAY}" \
    --data-urlencode "sort=date" \
    -H "X-Naver-Client-Id: ${NAVER_CLIENT_ID}" \
    -H "X-Naver-Client-Secret: ${NAVER_CLIENT_SECRET}" | jq '.items'
```

## 응답 포맷 (사용자에게)

```
🔍 NAVER {카테고리} 검색: "{query}"
1. {title (HTML 태그 제거)} — {pubDate or postdate}
   {description 80자 이내}
   링크: {originallink or link}
2. ...
```

`<b>...</b>` 태그가 들어오니 `sed 's/<[^>]*>//g'` 로 제거 후 출력.

## 주의

- `query` 한글이라 `--data-urlencode` 필수 (수동 % 인코딩 금물).
- `sort=date` 최신순, `sort=sim` 정확도순. 발화에 "최근" 들어오면 date.
- 일 25,000 호출 한도. 모니터링 필요 시 NAVER Developers Portal Dashboard 확인.
