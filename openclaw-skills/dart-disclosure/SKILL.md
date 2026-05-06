---
name: dart-disclosure
description: |
  금융감독원 DART (전자공시시스템) Open API skill.
  Use this skill whenever the user wants to:
  (1) 상장기업의 재무제표 (손익/재무상태/현금흐름),
  (2) 사업보고서·반기·분기 공시 검색,
  (3) 주요사항보고서 (유상증자/합병 등) 트래킹,
  (4) 임원/대주주 변동,
  (5) 기업 비교 (동종업계 매출/이익).
  관련 키워드: "DART", "전자공시", "재무제표", "공시", "사업보고서", "기업 정보".
metadata:
  openclaw:
    emoji: "📊"
    requires:
      anyBins: ["curl", "jq"]
---

# DART Open API

금감원 전자공시 직접 제공. 무료, 일 10K 호출.

## 의도/목적

- 한국 상장기업/공시 의무 비상장기업 정보 1차 출처.
- 투자 의사결정·동종업계 비교의 raw data.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "삼성전자 최근 사업보고서" | list (corp_code) |
| "현대차 재무제표 (연결)" | fnlttSinglAcntAll (CFS) |
| "카카오 분기 매출 추이" | 분기보고서 + 손익 |
| "이번주 주요공시 알려줘" | list (전체) |
| "오리온 임원 변동" | 임원/주주 보고 |
| "삼성전자 ↔ SK하이닉스 영업이익 비교" | 양 기업 fnlttSinglAcntAll |

## 자격증명

`~/.openclaw/credentials/dart.env`:
```
DART_API_KEY=...
```

발급 ★ DART 별도 사이트 (공공데이터포털 X):
- https://opendart.fss.or.kr → 회원가입 → 인증키 신청 → **즉시 발급**.
- 일 10,000 호출. 더 필요 시 사유 제출.

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/dart.env"

# 0. 회사 → corp_code (DART 고유번호) 매핑
# 전체 목록은 zip 파일로 한 번 다운로드 후 cache:
curl -s "https://opendart.fss.or.kr/api/corpCode.xml?crtfc_key=${DART_API_KEY}" -o /tmp/corpCodes.zip
# unzip 후 CORPCODE.xml 에서 corp_name → corp_code 검색

# 1. 공시검색
curl -s -G "https://opendart.fss.or.kr/api/list.json" \
    --data-urlencode "crtfc_key=${DART_API_KEY}" \
    --data-urlencode "corp_code=00126380" \
    --data-urlencode "bgn_de=20260101" \
    --data-urlencode "end_de=$(date +%Y%m%d)" \
    --data-urlencode "page_count=20" | jq

# 2. 재무제표 - 단일회사 전체 계정
CORP="00126380"   # 삼성전자
YEAR="2025"
RPT_CODE="11011"  # 11011 사업, 11012 반기, 11013 1분기, 11014 3분기

curl -s -G "https://opendart.fss.or.kr/api/fnlttSinglAcntAll.json" \
    --data-urlencode "crtfc_key=${DART_API_KEY}" \
    --data-urlencode "corp_code=${CORP}" \
    --data-urlencode "bsns_year=${YEAR}" \
    --data-urlencode "reprt_code=${RPT_CODE}" \
    --data-urlencode "fs_div=CFS" | jq '.list[] | select(.account_nm | test("매출|영업이익|당기순이익"))'
```

## 응답 포맷

```
📊 {corp_name} {YEAR} 재무 ({CFS})
매출액      : {매출액:,} (전년 +X%)
영업이익    : {영업이익:,} (전년 ±X%)
당기순이익  : {순이익:,}
영업이익률  : {%}
```

## 주의

- corp_code 8자리 숫자. 사용자 발화 → 회사명 검색 → corp_code 변환 chain.
- CFS=연결 / OFS=별도. LLM 이 어느 거 원하는지 모호하면 사용자에게 확인.
- 재무 데이터 출처가 분기/반기/연간으로 다름. reprt_code 정확히.
- 일 10K 호출 한도. 매분 200 이내 권장 (rate limit).
