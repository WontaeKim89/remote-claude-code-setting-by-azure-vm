---
name: kipris-patent
description: |
  특허청 KIPRIS Plus API skill (한국 특허/실용신안/디자인/상표 검색).
  Use this skill whenever the user wants to:
  (1) 키워드 / 출원인 / 발명자로 특허 검색,
  (2) 특허 등록 상태 / 권리 만료일,
  (3) 동종업계 특허 트렌드,
  (4) 본인/회사 출원 진행 상황,
  (5) 상표 / 디자인 등록 검색.
  관련 키워드: "특허", "출원", "특허청", "KIPRIS", "상표", "디자인", "지식재산권".
metadata:
  openclaw:
    emoji: "📜"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# KIPRIS Plus Open API

특허청 운영 한국 IP 검색 시스템. 무료, 별도 사이트.

## 의도/목적

- 한국 특허/상표/디자인/실용신안 1차 검색.
- 글로벌 특허 (Google Patents 등) 와는 별개. 한국 IP 한정.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "삼성전자 최근 특허 검색" | 출원인 |
| "OLED 관련 특허 트렌드" | 키워드 |
| "내 특허 출원 상태" | 출원번호 / 출원인 |
| "이 발명자 특허 다 보여줘" | 발명자명 |
| "상표 'OpenClaw' 등록 여부" | 상표 검색 |
| "이 회사 디자인 출원" | 디자인 + 출원인 |

## 자격증명

`~/.openclaw/credentials/kipris.env`:
```
KIPRIS_API_KEY=...
```

발급 ★ KIPRIS Plus 별도 사이트:
- https://www.kipris.or.kr → KIPRIS Plus → 회원가입 → 활용신청 → 1~2일 승인.
- 일 10,000 호출.

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/kipris.env"

# 특허/실용신안 키워드 검색
QUERY="OLED"
curl -s -G "http://plus.kipris.or.kr/kipo-api/kipi/patUtiModInfoSearchSevice/getWordSearch" \
    --data-urlencode "ServiceKey=${KIPRIS_API_KEY}" \
    --data-urlencode "word=${QUERY}" \
    --data-urlencode "numOfRows=10" \
    --data-urlencode "pageNo=1" | xmllint --xpath "//item" -

# 출원인 검색
APPLICANT="삼성전자"
curl -s -G "http://plus.kipris.or.kr/kipo-api/kipi/patUtiModInfoSearchSevice/getApplicantNameSearch" \
    --data-urlencode "ServiceKey=${KIPRIS_API_KEY}" \
    --data-urlencode "applicant=${APPLICANT}" \
    --data-urlencode "numOfRows=10" | xmllint --xpath "//item" -

# 상표 검색 (별도 endpoint)
curl -s -G "http://plus.kipris.or.kr/kipo-api/kipi/trademarkInfoSearchService/getWordSearch" \
    --data-urlencode "ServiceKey=${KIPRIS_API_KEY}" \
    --data-urlencode "word=OpenClaw" | jq
```

주요 필드:
- `inventionTitle`: 발명의 명칭
- `applicantName`: 출원인
- `applicationNumber`: 출원번호
- `registerStatus`: 등록 상태 (출원/등록/거절/포기)
- `applicationDate`/`registerDate`: 출원일/등록일
- `astrtCont`: 요약
- `ipcNumber`: 국제특허분류

## 응답 포맷

```
📜 "{keyword}" 특허 매칭 {N}건
1. {inventionTitle}
   출원인: {applicantName}
   출원번호: {applicationNumber}  ({applicationDate})
   상태: {registerStatus}
   IPC: {ipcNumber}
   요약: {astrtCont 150자}
2. ...
```

## 주의

- 응답 XML. xmllint 또는 python ElementTree.
- KIPRIS Plus 와 KIPRIS (검색 사이트) 별개. API 는 Plus만.
- 일 10K 호출. 검색 결과 캐시 권장.
- 실제 특허 권리 분석은 변리사 상담 필수.
