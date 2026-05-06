---
name: seoul-subway
description: |
  서울 지하철 실시간 도착정보 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 역에 곧 도착할 열차 (몇 분 후, 몇 정거장 전),
  (2) 출퇴근 시간 plan ("강남역 5분 안에 도착하는 열차"),
  (3) 환승역 어느 쪽 빠른지,
  (4) 막차/첫차 시간 (역사 시간표 별도지만 API 결합),
  (5) 특정 노선의 모든 역 도착 정보.
  관련 키워드: "지하철", "전철", "도착정보", "강남역", "몇 분", "분 후".
metadata:
  openclaw:
    emoji: "🚇"
    requires:
      anyBins: ["curl", "jq"]
---

# 서울 지하철 실시간 도착정보

서울 열린데이터광장 (data.seoul.go.kr) 제공. 무료.
공공데이터포털 인증키와 별개로 **서울 열린데이터광장 인증키** 필요.

## 의도/목적

- 출퇴근 출발 시각 결정.
- "지금 강남역에 5분 안에 들어오는 열차" 같은 자연어 즉답.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "강남역 도착정보" | statnNm=강남 |
| "지금 잠실역에 곧 들어오는 열차" | 잠실 + 가까운 시간순 |
| "9호선 신논현 도착정보" | 신논현 + 9호선 필터 |
| "삼성역 코엑스 방향 다음 열차" | 삼성 + 상행/하행 |
| "막차 몇 시까지 (시청역)" | 시청 + 마지막 도착 |
| "2호선 순환 강남 → 잠실 평균 분" | 2호선 + 시간 분석 |

## 자격증명

`~/.openclaw/credentials/seoul-data.env`:
```
SEOUL_DATA_KEY=seoul_open_data_key
```

발급: https://data.seoul.go.kr → 회원가입 → 인증키 신청 (즉시 발급).
활용신청: https://data.seoul.go.kr/dataList/OA-12764/A/1/datasetView.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/seoul-data.env"

STATION="강남"   # 한글 역명
# URL 인코딩 위해 jq @uri
STATION_ENC=$(printf '%s' "$STATION" | jq -sRr @uri)

curl -s "http://swopenAPI.seoul.go.kr/api/subway/${SEOUL_DATA_KEY}/json/realtimeStationArrival/0/10/${STATION_ENC}" | \
  jq '.realtimeArrivalList'
```

응답 주요 필드:
- `subwayId`: 1001(1호선), 1002(2호선), 1003(3호선), ..., 1009(9호선), 1063(경의중앙), 1065(공항철도), 1067(경춘), 1075(수인분당), 1077(신분당), 1093(서해), 1094(김포골드), 1095(신림)
- `trainLineNm`: 행선지 (예: "잠실행 - 잠실")
- `barvlDt`: 도착 예정시간 (초)
- `arvlMsg2`: 사람 친화 메시지 ("3분 후 도착", "이번역 진입")
- `arvlMsg3`: 현 위치 ("교대역 진입중")
- `bstatnNm`: 종착역
- `updnLine`: 상행/하행

## 응답 포맷

```
🚇 강남역 실시간 도착
[2호선 외선순환]
  1. 잠실행 — 3분 후 (역삼역 진입중)
  2. 잠실행 — 7분 후
[2호선 내선순환]
  1. 사당행 — 1분 후 (이번역 진입)
[신분당선 강남방면]
  1. 강남행 — 4분 후
```

## 주의

- 인증키 일 호출 1,000회 (일반키), 5,000회 (인증키). 더 필요 시 운영기관 문의.
- `barvlDt=0` 이면 "곧 도착" / `arvlMsg2` 의 한국어 메시지가 LLM 활용 시 더 자연스러움.
- 평일 첫차는 ~05:30, 막차는 24:00 ~ 24:30 (노선/방향마다 상이). 운영시간 외엔 결과 비어있음.
- 환승역의 경우 같은 station 다른 line 다수 응답 → line 으로 grouping.
