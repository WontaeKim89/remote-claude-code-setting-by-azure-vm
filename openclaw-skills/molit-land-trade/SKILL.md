---
name: molit-land-trade
description: |
  국토부 토지 거래내역 API skill (아파트가 아닌 토지 매매 실거래).
  Use this skill whenever the user wants to:
  (1) 특정 시·군·구의 토지 매매 거래 사례,
  (2) 지목별 (대지/전/답/임야) 평균 거래가,
  (3) 토지 시세 트래킹 (개발 호재 지역 등),
  (4) 농지 거래 추이,
  (5) 임야 매매 동향.
  관련 키워드: "토지 실거래가", "땅값 거래", "농지 매매", "임야 매매", "택지".
metadata:
  openclaw:
    emoji: "🌄"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 토지 매매 실거래가 API

국토부 RTMS 데이터 중 토지 부분.

## 의도/목적

- 아파트/오피스텔이 아닌 **순수 토지** 거래 데이터.
- 호재 예상 지역 (그린벨트 해제, 신도시) 매물 추이 모니터링.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "강남구 이번달 토지 거래" | LAWD_CD + DEAL_YMD |
| "최근 6개월 분당 토지 매매" | 시군구 + 6개월 합산 |
| "용인 농지 거래 사례" | 지목 = 답/전 필터 |
| "임야 거래 평균" | 지목 = 임 |
| "공장용지 매매" | 지목 = 공장 |
| "택지 거래" | 지목 = 대 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15056343/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

LAWD_CD="11680"            # 강남구
DEAL_YMD="$(date +%Y%m)"   # YYYYMM

curl -s -G "https://apis.data.go.kr/1613000/RTMSDataSvcLandTrade/getRTMSDataSvcLandTrade" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "LAWD_CD=${LAWD_CD}" \
    --data-urlencode "DEAL_YMD=${DEAL_YMD}" \
    --data-urlencode "numOfRows=20" | xmllint --xpath "//item" -
```

주요 필드:
- `법정동`, `지목`, `용도지역`, `거래면적` (㎡)
- `거래금액` (만원), `거래일`
- `지분구분` (지분/일반)

## 응답 포맷

```
🌄 {시군구} {YYYY-MM} 토지 거래
1. {법정동} · {지목} · {거래면적}㎡ · {거래금액}만원 · {거래일}
2. ...
평균 ㎡당 단가: {avg:,}원
지목별 분포: 대 N건 · 전 M건 · 답 K건
```

## 주의

- LAWD_CD 5자리 (시군구). 법정동 코드와 다름.
- 거래 0건 가능 (소규모 시·군). 그 경우 다른 시군구 추천.
- 도로/하천/공원 같은 비매매 토지 제외.
