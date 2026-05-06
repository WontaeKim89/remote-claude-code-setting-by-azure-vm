---
name: molit-realestate
description: |
  국토교통부 부동산 실거래가 공개시스템 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 아파트/빌라/오피스텔의 최근 실거래가 조회,
  (2) 시·군·구 단위의 평균 실거래가 트렌드,
  (3) 매매/전월세 거래 추이,
  (4) 동일 단지의 면적별 가격 비교,
  (5) 부동산 의사결정용 1차 reference.
  관련 키워드: "실거래가", "아파트 가격", "부동산", "전세", "매매".
metadata:
  openclaw:
    emoji: "🏢"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 국토부 실거래가 API

무료, 무제한 (공공데이터포털 인증키). 응답 XML.

## 의도/목적

- 한국 부동산 의사결정의 객관 자료 (호가가 아니라 실거래).
- 사용자가 "강남 시세" 같이 두루뭉술 발화해도 시·군·구 → 법정동 코드 매핑 후 조회.

## 자연어 트리거 예시

| 사용자 발화 | endpoint |
|------|------|
| "강남구 아파트 이번달 실거래" | 아파트매매 실거래 자료 |
| "송파구 전세가 최근 3개월" | 아파트전월세 자료 |
| "은마아파트 84제곱미터 최근 거래" | 아파트매매 + 단지명 필터 |
| "서울 오피스텔 매매 평균" | 오피스텔매매 자료 |
| "분당구 신도시 실거래" | 아파트매매 (sigunguCd=4136X) |

## 자격증명

`~/.openclaw/credentials/molit.env`:
```
MOLIT_SERVICE_KEY=공공데이터포털_일반인증키(decoded)
```

발급: https://www.data.go.kr/data/15057511/openapi.do → "활용신청" → 1~2일 승인.

## 법정동 코드 (LAWD_CD) 매핑

5자리 시군구 코드. 예시:
- 11680 강남구  ·  11650 서초구  ·  11710 송파구
- 11140 중구  ·  11680 강남구
- 41135 성남시 분당구  ·  41136 성남시 수정구
- 26230 부산 해운대구

전체 목록: https://www.code.go.kr/stdcode/regCodeL.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/molit.env"

LAWD_CD="11680"        # 시군구코드
DEAL_YMD="$(date +%Y%m)"  # 거래년월 YYYYMM

# 아파트 매매 실거래
curl -s -G "https://apis.data.go.kr/1613000/RTMSDataSvcAptTradeDev/getRTMSDataSvcAptTradeDev" \
    --data-urlencode "serviceKey=${MOLIT_SERVICE_KEY}" \
    --data-urlencode "LAWD_CD=${LAWD_CD}" \
    --data-urlencode "DEAL_YMD=${DEAL_YMD}" \
    --data-urlencode "numOfRows=20" \
    --data-urlencode "pageNo=1" | xmllint --xpath "//item" -

# 아파트 전월세
curl -s -G "https://apis.data.go.kr/1613000/RTMSDataSvcAptRent/getRTMSDataSvcAptRent" \
    --data-urlencode "serviceKey=${MOLIT_SERVICE_KEY}" \
    --data-urlencode "LAWD_CD=${LAWD_CD}" \
    --data-urlencode "DEAL_YMD=${DEAL_YMD}" \
    --data-urlencode "numOfRows=20" | xmllint --xpath "//item" -

# 오피스텔 매매: getRTMSDataSvcOffiTrade
# 빌라/연립 매매: getRTMSDataSvcRHTrade
```

각 item 주요 필드:
- 아파트명 / 전용면적(평) / 거래금액(만원) / 거래일 / 층 / 건축년도

## 응답 포맷

```
🏢 강남구 (11680) {YYYY-MM} 아파트 매매 실거래
1. 은마아파트 · 84.43㎡ · 12층 · 26억 5,000만원 · 2026-05-04
2. ...
```

## 주의

- 응답 XML 이라 jq 직접 못 씀. xmllint 또는 python xml.etree 사용.
- 정부 인증키는 **decoded** 버전 써야 함 (URL 인코딩된 키 아님).
- 매월 새 데이터 적재. 당월 데이터는 월말~익월 초까지 일부 누락.
- 단지명으로 필터링은 client-side. 서버측 검색 X.
