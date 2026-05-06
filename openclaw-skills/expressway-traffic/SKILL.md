---
name: expressway-traffic
description: |
  한국도로공사 고속도로 교통량/소통 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 고속도로 구간의 실시간 교통 흐름,
  (2) 출발 전 정체 구간 확인,
  (3) 특정 노선 (경부/서해안/중부 등) 의 평균 통행 속도,
  (4) 사고/공사로 인한 정체 정보,
  (5) 명절 또는 주말 차량 행렬 추이.
  관련 키워드: "고속도로", "정체", "교통량", "고속도로 막혀", "경부선", "서해안선".
metadata:
  openclaw:
    emoji: "🛣️"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 한국도로공사 ITS API

실시간 교통류/소통/돌발 상황. 무료.

## 의도/목적

- 장거리 운전 출발 전 / 운전 중 결정 지원.
- 고속도로 노선 단위 + 영업소 기준 검색.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "지금 경부고속도로 정체 구간" | trafficSpeedInfo |
| "서해안고속도로 부산 방향 흐름" | route 필터 |
| "추석 연휴 고속도로 어때" | trafficVolume + 시간 |
| "사고/공사 정보 알려줘" | accidentInfo |
| "최근 1시간 영동고속도로 평균 속도" | trafficSpeedInfo + 평균 |
| "수도권 외곽순환 정체" | route=4001 필터 |

## 자격증명

공공데이터포털 인증키 (`DATA_GO_KR_KEY`) 재사용.

활용신청: https://www.data.go.kr/data/15050291/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 노선별 실시간 교통속도
ROUTE="0010"   # 경부선
curl -s -G "http://data.ex.co.kr/openapi/trafficapi/trafficSpeedInfoApi" \
    --data-urlencode "key=${DATA_GO_KR_KEY}" \
    --data-urlencode "type=json" \
    --data-urlencode "routeNo=${ROUTE}" | jq '.list'

# 노선 코드 일부:
#   0010 경부선  ·  0150 서해안선  ·  0500 중부선  ·  0550 평택제천선
#   0250 영동선  ·  0010 경부 ·  4001 수도권제1순환  ·  0100 호남
#   0520 중부내륙선  ·  0030 남해선

# 돌발 상황 (사고/공사)
curl -s -G "http://data.ex.co.kr/openapi/odsearch/inforaccident" \
    --data-urlencode "key=${DATA_GO_KR_KEY}" \
    --data-urlencode "type=json" | jq '.list'

# 휴게소 검색 (편의)
curl -s -G "http://data.ex.co.kr/openapi/business/serviceAreaInfo" \
    --data-urlencode "key=${DATA_GO_KR_KEY}" \
    --data-urlencode "type=json" \
    --data-urlencode "serviceAreaName=죽전휴게소" | jq
```

## 응답 포맷

```
🛣️ {노선명} {YYYY-MM-DD HH:MM}
구간 / 평균 속도
1. 서울TG~기흥 : 78 km/h (양호)
2. 기흥~수원북 : 32 km/h (정체)
3. ...

🚨 돌발: 경부선 신갈JC 부근 사고 (08:15 발생, 1차로 통제)
```

## 주의

- 노선 코드 별도 조회. 사용자 발화 → 노선명 → 코드 mapping 필요.
- API 호출 한도: 일 10K (일반인증키).
- 영동/서울외곽 등은 시간대별 패턴 학습 후 brief 가능.
- 휴게소 정보 API 별개. 메뉴/유가는 다른 endpoint.
