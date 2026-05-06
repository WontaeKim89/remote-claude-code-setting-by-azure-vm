---
name: frankfurter-fx
description: |
  Frankfurter (frankfurter.app) 무료 환율 API skill (key 없음, 무제한).
  Use this skill whenever the user wants to:
  (1) 실시간/최신 환율 ("1 USD 얼마"),
  (2) 통화 변환 (환산 금액),
  (3) 과거 환율 조회 (특정 날짜),
  (4) 두 시점 사이의 환율 추이 (timeseries),
  (5) ECB (유럽중앙은행) 기준 환율 (영업일 16:00 CET 발표).
  관련 키워드: "환율", "달러", "유로", "엔", "원화", "환산", "frankfurter", "fx".
metadata:
  openclaw:
    emoji: "💶"
    requires:
      anyBins: ["curl", "jq"]
---

# Frankfurter API

ECB 기준 환율. **무료 무제한 + key 불필요** (가성비 최고).

## 의도/목적

- ExchangeRate-API 의 free 한도 (1500/월) 보다 훨씬 여유. 일상 변환에 1순위.
- ECB 영업일 데이터라 한국 공휴일 환율은 직전 영업일 값. 실시간 시세 X.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "1 달러 원화 얼마" | latest USD→KRW |
| "100 엔 한국돈으로" | latest JPY×100 → KRW |
| "유로 환율" | latest EUR base |
| "어제 달러 환율" | history (특정날짜) |
| "1월 1일부터 오늘까지 USD/KRW 추이" | timeseries |
| "1000 USD = 몇 EUR" | latest USD→EUR ×1000 |

## 명령 매핑

```bash
# 최신 환율 (USD 기준 → KRW)
curl -s "https://api.frankfurter.app/latest?from=USD&to=KRW" | jq

# 변환 (1000 USD → KRW)
curl -s "https://api.frankfurter.app/latest?amount=1000&from=USD&to=KRW" | jq

# 특정 날짜 (YYYY-MM-DD)
curl -s "https://api.frankfurter.app/2026-01-15?from=USD&to=KRW" | jq

# 기간 조회 (timeseries)
curl -s "https://api.frankfurter.app/2026-01-01..2026-05-01?from=USD&to=KRW" | jq

# 지원 통화 목록
curl -s "https://api.frankfurter.app/currencies" | jq
```

응답 예:
```json
{
  "amount": 1.0,
  "base": "USD",
  "date": "2026-05-06",
  "rates": {"KRW": 1378.42}
}
```

## 응답 포맷

```
💶 환율 ({date})
1 {from} = {rate} {to}
1000 {from} = {rate*1000} {to}
```

## 주의

- 인증 불필요. key 발급 사이트 없음. 그냥 호출하면 됨.
- 토/일은 ECB 휴장 → 직전 영업일 환율 반환.
- 한국 시중은행 환율 (송금/현찰) 과 다름. 시중은행 정확한 값 필요시 KEB하나/우리은행 별도 API.
- Bitcoin/암호화폐 X (CoinGecko 사용).
