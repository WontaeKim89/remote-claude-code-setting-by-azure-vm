---
name: molit-apt-price
description: |
  국토부 공동주택 공시가격 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 아파트 단지·동·호의 공시가격,
  (2) 보유세/재산세 추정,
  (3) 1세대 1주택 비과세 한도 (12억) 비교,
  (4) 종합부동산세 대상 여부 확인,
  (5) 시세 vs 공시 비율 분석.
  관련 키워드: "공시가", "공동주택 공시가격", "아파트 공시", "보유세", "종부세".
metadata:
  openclaw:
    emoji: "🏠"
    requires:
      anyBins: ["curl", "jq"]
---

# 공동주택 공시가격 API

국토부 부동산 종합공부시스템 (KRAS). 아파트/연립/다세대 대상.

## 의도/목적

- 1주택자 종부세 (12억 초과) / 다주택 누진 판단.
- 매수 전 보유세 추정용.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "이 아파트 공시가격" | 단지·동·호 |
| "보유세 추정 (84A)" | 공시가 → 누진 계산 |
| "종부세 대상이야?" | 공시 12억 초과 여부 |
| "5년 공시가 추이" | 연도별 |
| "84제곱 공시 vs 시세" | 비교 |
| "다주택자 합산 공시" | 다건 합 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15044393/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 공동주택 가격 단건 조회
PNU="1168010300108250000"
DONG="101"
HO="1502"
STDR_YEAR="2026"

curl -s -G "https://apis.data.go.kr/1611000/nsdi/ApartmentPriceService/attr/getApartmentPriceAttr" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "pnu=${PNU}" \
    --data-urlencode "dongNm=${DONG}" \
    --data-urlencode "hoNm=${HO}" \
    --data-urlencode "stdrYear=${STDR_YEAR}" \
    --data-urlencode "_type=json" | jq
```

주요 필드:
- `pblntfPc`: 공시가격 (원)
- `bldNm`: 단지명
- `bldDongNm`/`bldHoNm`: 동/호
- `excArea`: 전용면적 (㎡)
- `stdrYear`: 기준연도

## 응답 포맷

```
🏠 {bldNm} {dongNm}동 {hoNm}호 ({stdrYear})
전용면적: {excArea} ㎡
공시가격: {pblntfPc:,}원

추정 세금:
  - 재산세 (단순): {pblntfPc × 0.001 :,}원
  - 종부세 대상: {Y/N} (12억 초과 시)
```

## 주의

- 매년 4월 말 공시. 5~6월 이의신청.
- 공시가격은 시세 60~75% 수준. 정확한 세금은 세무사 상담.
- 단지명/동/호는 내부 표기와 다를 수 있음 (예: 101동 vs A동).
