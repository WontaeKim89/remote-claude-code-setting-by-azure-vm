---
name: kosis-stat
description: |
  통계청 KOSIS (국가통계포털) Open API skill.
  Use this skill whenever the user wants to:
  (1) 인구·고용·물가·GDP 등 국가 통계,
  (2) 시계열 데이터 (월/분기/연도별),
  (3) 통계지표 추이 비교,
  (4) 인구 동향 (출생/사망/혼인),
  (5) 산업/경제 macro 지표.
  관련 키워드: "통계청", "KOSIS", "통계", "인구", "출생률", "고용률", "물가", "GDP".
metadata:
  openclaw:
    emoji: "📈"
    requires:
      anyBins: ["curl", "jq"]
---

# KOSIS Open API

국가통계포털. 한국 모든 공공 통계의 종합 hub.

## 의도/목적

- 매크로 데이터 1차 출처 (한국은행 ECOS는 금융 중심, KOSIS는 전반).
- 인구·산업·노동·교육 등 광역 지표.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "한국 출생률 최근 10년" | 인구동향조사 |
| "20대 실업률" | 경제활동인구조사 |
| "소비자물가지수 최근" | CPI |
| "GDP 분기별" | 국민계정 |
| "혼인 / 이혼 통계" | 인구동향 |
| "청년 고용률" | 경활조사 + 연령별 |

## 자격증명

`~/.openclaw/credentials/kosis.env`:
```
KOSIS_API_KEY=...
```

발급 ★ KOSIS 별도:
- https://kosis.kr/openapi/index/index.jsp → 회원가입 → 인증키 신청 → 즉시 발급.

## 명령 매핑

KOSIS 는 통계표 ID 기반. **자료조회 API** + **목록조회 API** 두 가지.

```bash
. "$HOME/.openclaw/credentials/kosis.env"

# 통계표 검색 (목록조회)
curl -s -G "https://kosis.kr/openapi/statisticsList.do" \
    --data-urlencode "method=getList" \
    --data-urlencode "apiKey=${KOSIS_API_KEY}" \
    --data-urlencode "vwCd=MT_ZTITLE" \
    --data-urlencode "parentListId=A_1" \
    --data-urlencode "format=json" \
    --data-urlencode "jsonVD=Y" | jq

# 통계자료 조회 (특정 표 ID)
ORG_ID="101"      # 통계청
TBL_ID="DT_1B040A3"   # 인구동향조사
ITEM_CODE="T20"   # 지표 (출생아 수)

curl -s -G "https://kosis.kr/openapi/statisticsData.do" \
    --data-urlencode "method=getList" \
    --data-urlencode "apiKey=${KOSIS_API_KEY}" \
    --data-urlencode "format=json" \
    --data-urlencode "jsonVD=Y" \
    --data-urlencode "orgId=${ORG_ID}" \
    --data-urlencode "tblId=${TBL_ID}" \
    --data-urlencode "itmId=${ITEM_CODE}" \
    --data-urlencode "objL1=ALL" \
    --data-urlencode "prdSe=Y" \
    --data-urlencode "startPrdDe=2015" \
    --data-urlencode "endPrdDe=2026" | jq
```

자주 쓰는 통계표:
- 인구: orgId=101, tblId=DT_1B040A3 (인구동향)
- CPI: orgId=101, tblId=DT_1J17001 (소비자물가지수)
- 고용: orgId=101, tblId=DT_1DA7001 (경활조사)
- GDP: orgId=301, tblId=DT_111Y004 (국민계정)

## 응답 포맷

```
📈 {지표명} {기간}
2020: {값} ({단위})
2021: {값}
2022: {값}
2023: {값}
2024: {값}
2025: {값}
전년비: ±X%
```

## 주의

- KOSIS 통계표 ID 가 비직관적 → KOSIS 웹 검색 후 코드 추출 권장.
- 첫 호출 시 통계표 검색 → 코드 cache → 이후 데이터 조회.
- 일별/월별/연별 (`prdSe`): D=일, M=월, Q=분기, Y=연도.
- 응답 JSON. 단 `jsonVD=Y` 안 넣으면 XML.
