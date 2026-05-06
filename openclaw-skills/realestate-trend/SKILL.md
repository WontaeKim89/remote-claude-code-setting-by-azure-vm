---
name: realestate-trend
description: |
  국토부 부동산 가격동향 (KAB 한국부동산원) API skill.
  Use this skill whenever the user wants to:
  (1) 전국/시도/시군구 단위의 매매·전세·월세 가격 변동률,
  (2) 주간/월간 부동산 가격 동향,
  (3) 아파트/단독/연립 유형별 추이,
  (4) 지역별 시세 상승·하락 비교,
  (5) 부동산 시장 분위기 brief.
  관련 키워드: "부동산 시세", "가격 동향", "집값", "전세", "매매가", "한국부동산원".
metadata:
  openclaw:
    emoji: "📈"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 국토부 부동산 가격동향 API

한국부동산원 (구 한국감정원) 발표 통계. 공공데이터포털 제공. 무료.

## 의도/목적

- 단지·면적 단위가 아닌 **지역 + 유형 + 기간** 단위 매크로 트렌드.
- 실거래가 (단건) + 가격 동향 (지수) 조합으로 입체 분석.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "전국 아파트 매매가 이번 달 동향" | 전국 + 매매 + 월간 |
| "서울 강남 4구 전세 변동률" | 서울 + 전세 + 시군구 |
| "최근 3개월 수도권 매매가 추이" | 수도권 + 매매 + 90일 |
| "지방 부동산 시장 분위기" | 지방 + 종합 |
| "오피스텔 vs 아파트 가격 비교" | 유형 비교 |
| "단독주택 가격 변동" | 단독 + 매매 + 동향 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15077384/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 월간 아파트 매매가격지수 (전국/시도/시군구)
RESEARCH_DATE="202604"  # YYYYMM
REGION_CD="11"          # 서울특별시 (00=전국, 11=서울, 26=부산, 27=대구, ...)

curl -s -G "https://apis.data.go.kr/1613000/RTMSDataSvcAptTradeDevApi/getRTMSDataSvcAptTradeDev" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "RESEARCH_DATE=${RESEARCH_DATE}" \
    --data-urlencode "RESEARCH_LV1=${REGION_CD}" \
    --data-urlencode "_type=json" | jq

# 주간 매매·전세 변동률 (한국부동산원 R-ONE 통계)
# 별도 endpoint: getMonthlyHousePriceIndex / getWeeklyApartmentPrice
```

지역 코드 (RESEARCH_LV1):
- 00 전국 / 11 서울 / 26 부산 / 27 대구 / 28 인천 / 29 광주 / 30 대전 / 31 울산
- 36 세종 / 41 경기 / 42 강원 / 43 충북 / 44 충남 / 45 전북 / 46 전남 / 47 경북 / 48 경남 / 50 제주

## 응답 포맷

```
📈 {지역} {기간} 부동산 동향
매매가격지수: 100.3 (전월 대비 +0.2%)
전세가격지수: 99.8 (전월 대비 -0.1%)
주요 변동 시·군·구 TOP 3:
  1. 강남구  매매 +0.5%
  2. 서초구  매매 +0.3%
  3. 송파구  매매 +0.2%
```

## 주의

- 주간/월간 통계 별도 endpoint. 발표 주기 다름.
- 부동산 의사결정 시 **실거래가 (molit-realestate skill) + 가격동향 (이 skill) 조합**이 더 정확.
- 응답 XML/JSON. `_type=json` 추천.
