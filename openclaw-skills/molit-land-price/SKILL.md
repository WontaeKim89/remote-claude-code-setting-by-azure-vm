---
name: molit-land-price
description: |
  국토부 개별공시지가 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 토지의 ㎡당 공시지가,
  (2) 연도별 공시지가 변화,
  (3) 보유세/취득세 추정 (공시지가 기반),
  (4) 토지 시세 vs 공시지가 비교,
  (5) 양도세/상속세 계산용 기초 자료.
  관련 키워드: "공시지가", "개별공시지가", "땅값", "지가", "보유세 기준".
metadata:
  openclaw:
    emoji: "💵"
    requires:
      anyBins: ["curl", "jq"]
---

# 개별공시지가 API

국토부 부동산 종합공부시스템 (KRAS). 매년 1월 1일 기준 공시.

## 의도/목적

- 세금 계산의 기초가 되는 정부 공식 가격.
- 공시지가는 시세보다 낮음 (보통 60~70%). 시세 비교 분석.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "이 땅 공시지가 얼마" | 단일 PNU 조회 |
| "강남 테헤란로 공시지가" | 주소 → PNU → 조회 |
| "공시지가 5년 변화" | 연도별 |
| "보유세 추정용 공시지가" | 최근 공시 |
| "이 땅의 ㎡당 공시 단가" | indvdLndprc |
| "공시가 기준으로 양도세 계산" | indvdLndprc + 면적 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15044329/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

PNU="1168010300108250000"
STDR_YEAR="2026"   # 기준연도

curl -s -G "https://apis.data.go.kr/1611000/nsdi/IndvdLandPriceService/attr/getIndvdLandPriceAttr" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "pnu=${PNU}" \
    --data-urlencode "stdrYear=${STDR_YEAR}" \
    --data-urlencode "_type=json" | jq
```

주요 필드:
- `pblntfPclnd`: ㎡당 공시지가 (원)
- `lndcgrCodeNm`: 지목명 (대/전/답/임야 등)
- `lndcgrAr`: 면적 (㎡)
- `stdrYear`/`stdrMt`: 기준연도/월

## 응답 포맷

```
💵 공시지가 ({stdrYear})
주소: {lnmAdr}
지목: {lndcgrCodeNm}
면적: {lndcgrAr} ㎡
㎡당 공시: {pblntfPclnd:,}원
총 공시가: {pblntfPclnd × lndcgrAr:,}원
```

## 주의

- 매년 1월 공시 갱신. 5월 신고. 기준연도 잘못 넣으면 데이터 없음.
- 시세 ≠ 공시지가. 시세는 실거래가 (molit-realestate skill) 참조.
- 토지 (대지/전/답)만 해당. 건물은 별도 (공동주택공시가격, molit-apt-price).
