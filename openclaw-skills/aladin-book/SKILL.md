---
name: aladin-book
description: |
  알라딘 Open API skill (한국 도서 검색/시세/할인/재고).
  Use this skill whenever the user wants to:
  (1) 한국에서 출판된 책 검색 (제목/저자/ISBN),
  (2) 신간 / 베스트셀러 / 추천 도서 리스트,
  (3) 책의 정가·할인가·중고가·적립금 비교,
  (4) ISBN 으로 상세 정보 + 표지 이미지,
  (5) 분야별 추천 (인문/IT/소설 등).
  관련 키워드: "책", "도서", "알라딘", "베스트셀러", "신간", "ISBN".
metadata:
  openclaw:
    emoji: "📚"
    requires:
      anyBins: ["curl", "jq"]
---

# 알라딘 Open API

한국 도서 시장 1차 reference. 무료, 무제한 (TTBKey).

## 의도/목적

- 한국 책 검색은 알라딘이 대중적이고 메타데이터 풍부.
- 신간/베스트셀러 큐레이션. 중고가 정보로 가격 의사결정.

## 자연어 트리거 예시

| 사용자 발화 | endpoint |
|------|------|
| "클로드 코드 책 추천해줘" | ItemSearch |
| "최근 한 달 IT 베스트셀러" | ItemList (Bestseller) |
| "이 책 ISBN 9788932473901 가격 얼마" | ItemLookUp (ISBN) |
| "데이비드 그레이버 책 다 알려줘" | ItemSearch (저자) |
| "신간 인문 분야 5개" | ItemList (NewBook + CategoryId) |
| "동물농장 중고가" | ItemSearch + UsedList |

## 자격증명

`~/.openclaw/credentials/aladin.env`:
```
ALADIN_TTB_KEY=ttb...
```

발급: https://blog.aladin.co.kr/openapi → 회원가입 → TTBKey 발급 (무료, 즉시).

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/aladin.env"

# 검색 (Search)
QUERY="<검색어>"
QUERY_TYPE="Title"   # Title | Author | Publisher | Keyword

curl -s -G "https://www.aladin.co.kr/ttb/api/ItemSearch.aspx" \
    --data-urlencode "ttbkey=${ALADIN_TTB_KEY}" \
    --data-urlencode "Query=${QUERY}" \
    --data-urlencode "QueryType=${QUERY_TYPE}" \
    --data-urlencode "MaxResults=10" \
    --data-urlencode "start=1" \
    --data-urlencode "SearchTarget=Book" \
    --data-urlencode "Output=js" \
    --data-urlencode "Version=20131101" | jq '.item[]'

# 베스트셀러
curl -s -G "https://www.aladin.co.kr/ttb/api/ItemList.aspx" \
    --data-urlencode "ttbkey=${ALADIN_TTB_KEY}" \
    --data-urlencode "QueryType=Bestseller" \
    --data-urlencode "MaxResults=10" \
    --data-urlencode "SearchTarget=Book" \
    --data-urlencode "Output=js" \
    --data-urlencode "Version=20131101" | jq '.item[]'

# ISBN 으로 상세
ISBN13="<ISBN13>"
curl -s -G "https://www.aladin.co.kr/ttb/api/ItemLookUp.aspx" \
    --data-urlencode "ttbkey=${ALADIN_TTB_KEY}" \
    --data-urlencode "ItemIdType=ISBN13" \
    --data-urlencode "ItemId=${ISBN13}" \
    --data-urlencode "Output=js" \
    --data-urlencode "Version=20131101" | jq '.item[0]'
```

각 항목 주요 필드:
- `title`, `author`, `publisher`, `pubDate`
- `priceStandard` (정가), `priceSales` (판매가)
- `isbn13`, `cover` (표지 url), `link` (알라딘 상품 url)
- `customerReviewRank` (별점 1~10)

## 응답 포맷

```
📚 알라딘 검색: "{query}"
1. 《{title}》 — {author} · {publisher} ({pubDate})
   판매가 {priceSales:,}원 (정가 {priceStandard:,}원)
   ⭐ {customerReviewRank}/10
   {link}
2. ...
```

## 주의

- TTBKey 는 1개당 도메인/일 호출제한 거의 없음 (개인 사용엔 무제한 수준).
- `SearchTarget=Foreign` 으로 외서 / `=DVD` 등으로 다른 미디어 검색 가능.
- 카테고리 ID (CategoryId) 로 필터링 가능 (예: 50 = IT/컴퓨터).
