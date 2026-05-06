---
name: korail-train
description: |
  코레일 (KORAIL) 열차 정보 API skill (KTX/SRT/ITX/무궁화 검색).
  Use this skill whenever the user wants to:
  (1) 두 역 사이의 열차 시간표 검색,
  (2) KTX 잔여석 조회,
  (3) 특정 열차의 정차역 / 도착시간,
  (4) 운임 (편도/왕복/할인) 확인,
  (5) 역 코드 / 역명 검색.
  Note: 공식 코레일 Open API 는 예매 자체는 지원하지 않음 (조회/시간표만).
  실제 예매는 코레일톡 앱 또는 letskorail.com 별도.
  관련 키워드: "기차", "KTX", "SRT", "코레일", "열차", "기차 시간", "기차표 잔여석".
metadata:
  openclaw:
    emoji: "🚆"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 코레일 열차 정보 API

공공데이터포털 → 한국철도공사 (KORAIL) 열차정보. 무료.

## 의도/목적

- 출발/도착 역, 날짜, 시간 기준 열차 검색.
- 조회 only — 결제 없음. 예매는 사용자에게 코레일톡 안내.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | endpoint |
|------|------|
| "내일 서울 → 부산 KTX 시간표" | getStrtpntAlocFndTrainInfo |
| "오늘 오후 5시 이후 천안 → 광주" | 시간 필터 |
| "용산역 코드 뭐야" | getStationCdList |
| "이 열차 (#108) 정차역 알려줘" | getTrainSttnList |
| "동대구에서 부산까지 ITX" | trainGradeCode 필터 |
| "서울 → 부산 토요일 일찍" | depPlandTime 정렬 |
| "주말 오송 → 서울 잔여석" | (잔여석은 별도 endpoint 또는 코레일톡 안내) |

## 자격증명

`~/.openclaw/credentials/data-go-kr.env` 의 `DATA_GO_KR_KEY` 재사용.

활용신청: https://www.data.go.kr/data/15098918/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 출발역/도착역 시간표 검색
DEP_STATION="NAT010000"   # 서울역 (역 코드 — 별도 조회)
ARR_STATION="NAT014445"   # 부산역
DEP_DATE="20260507"       # YYYYMMDD

curl -s -G "https://apis.data.go.kr/1613000/TrainInfoService/getStrtpntAlocFndTrainInfo" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "depPlaceId=${DEP_STATION}" \
    --data-urlencode "arrPlaceId=${ARR_STATION}" \
    --data-urlencode "depPlandTime=${DEP_DATE}" \
    --data-urlencode "numOfRows=20" \
    --data-urlencode "_type=json" | jq '.response.body.items.item'

# 역 코드 검색
curl -s -G "https://apis.data.go.kr/1613000/TrainInfoService/getStnAlocFndTrainInfo" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "stationName=서울" \
    --data-urlencode "_type=json" | jq

# 열차 등급 (trainGradeCode):
#   00=KTX, 01=새마을, 02=무궁화, 03=통근, 04=누리로, 05=AREX, 06=KTX-산천,
#   07=ITX-새마을, 08=ITX-청춘, 09=공항철도, 10=동해선, 11=경의중앙선
```

## 응답 포맷

```
🚆 {DEP} → {ARR}, {DATE}
1. KTX #108  06:00 → 08:38  56,400원
2. KTX-산천 #112  06:30 → 09:12  56,400원
3. ITX-새마을 #1004  07:00 → 10:30  39,800원
...
예매: 코레일톡 앱 또는 https://www.letskorail.com
```

## 주의

- API key + 활용신청 후 1~2일 승인 필요.
- 응답에 잔여석 정보 미포함 (예매는 코레일 자체 시스템). 잔여석은 코레일톡 앱 안내.
- 역 코드는 5자리 영숫자 (예: NAT010000=서울). 자주 쓰는 역 코드 mapping cache 권장.
- 응답 JSON/XML 둘 다 가능 (`_type=json` 권장).
