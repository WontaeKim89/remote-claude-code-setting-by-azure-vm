---
name: loan-rate-compare
description: |
  금융감독원 대출금리 비교 API skill (은행별 가계대출 금리).
  Use this skill whenever the user wants to:
  (1) 주담대 / 신용대출 / 전세자금대출 은행별 금리,
  (2) 고정금리 vs 변동금리,
  (3) 신용등급별 금리 변동,
  (4) 한국 주요 은행 (신한/국민/우리/하나/농협 등) 비교,
  (5) 금리 인하 시점 모니터링.
  관련 키워드: "대출금리", "주담대", "신용대출", "전세자금", "은행 금리 비교".
metadata:
  openclaw:
    emoji: "💰"
    requires:
      anyBins: ["curl", "jq"]
---

# 금감원 대출금리 비교

금감원 + 은행권 통합 금리 비교 데이터. 공공데이터포털 제공.

## 의도/목적

- 주요 은행 동시 비교 → 가장 유리한 곳 선택.
- 정기 갱신 → 금리 인하 시점 잡기.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "주담대 금리 은행별 비교" | mortgage |
| "전세자금대출 금리" | jeonse loan |
| "신용대출 1금융권 평균" | personal loan |
| "5대 시중은행 금리" | bank 필터 |
| "고정 vs 변동 금리 차이" | fixed vs variable |
| "이번 달 가계대출 금리 추이" | timeseries |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15030010/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 가계대출 금리 (월별)
DCLS_MONTH="202604"

curl -s -G "https://finlife.fss.or.kr/finlifeapi/mortgageLoanProductsSearch.json" \
    --data-urlencode "auth=${DATA_GO_KR_KEY}" \
    --data-urlencode "topFinGrpNo=020000" \
    --data-urlencode "pageNo=1" | jq '.result.baseList'

# topFinGrpNo:
#   020000 은행
#   030200 여신전문 (캐피탈)
#   030300 저축은행
#   050000 보험사
#   060000 금융투자

# 신용대출
curl -s -G "https://finlife.fss.or.kr/finlifeapi/creditLoanProductsSearch.json" \
    --data-urlencode "auth=${DATA_GO_KR_KEY}" \
    --data-urlencode "topFinGrpNo=020000" \
    --data-urlencode "pageNo=1" | jq

# 전세자금대출 (rentHouseLoanProductsSearch.json)
```

주요 필드:
- `kor_co_nm`: 은행명
- `fin_prdt_nm`: 상품명
- `lend_rate_min`/`lend_rate_max`/`lend_rate_avg`: 최저/최고/평균 금리 (%)
- `lend_rate_type_nm`: 고정/변동/혼합
- `loan_lmt`: 한도
- `dcls_month`: 공시월

## 응답 포맷

```
💰 주담대 금리 비교 ({YYYY-MM} 기준)
1. {bank} {prdt} (변동) {min}~{max}% (평균 {avg}%)
2. ...
```

## 주의

- 매월 갱신. 최신 dcls_month 자동 추론.
- 실제 신청 시 적용 금리는 신용등급/담보 등에 따라 다름.
- finlife.fss.or.kr 도메인 — 공공데이터포털과 동일 key 사용 가능 여부 확인 필요 (별도 신청 권장).
