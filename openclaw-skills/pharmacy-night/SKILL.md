---
name: pharmacy-night
description: |
  공공데이터 야간/공휴일 약국 정보 skill.
  Use this skill whenever the user wants to:
  (1) 야간 (밤 10시 이후) 운영 약국 위치,
  (2) 공휴일/일요일 운영 약국,
  (3) 응급 시 가장 가까운 약국 위치,
  (4) 특정 시·구의 24시 약국 검색,
  (5) 약국 전화번호 + 주소 + 운영시간.
  관련 키워드: "야간 약국", "당직 약국", "휴일 약국", "24시 약국", "지금 문 연 약국".
metadata:
  openclaw:
    emoji: "💊"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 공공데이터 약국 정보 API

응급의료포털 (E-Gen) 약국 정보. 무료, 공공데이터포털 인증키 사용.

## 의도/목적

- 야간/공휴일에 약 필요할 때 1순위 reference.
- 위치 (시도/시군구) + 시각 기반 필터링.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 검색 조건 |
|------|------|
| "지금 문 연 약국 알려줘 (강남구)" | 현재시각 운영 + 강남구 |
| "오늘이 일요일인데 약국 어디 열어?" | 휴일 운영 |
| "근처 24시 약국" | 24시 + 위치 |
| "송파구 야간 약국" | Q1 = 서울특별시 / Q2 = 송파구 + 야간 |
| "지금 가까운 약국 (위도/경도)" | 좌표 기반 + 운영중 |
| "내일 공휴일에 여는 약국" | 다음날 공휴일 운영 |

## 자격증명

`~/.openclaw/credentials/data-go-kr.env`:
```
DATA_GO_KR_KEY=공공데이터포털_decoded_key
```
(복지로/약국/도로공사 등 다수 공공데이터포털 API 가 같은 key 공유. 한 번 발급 후 재사용.)

발급: https://www.data.go.kr → 회원가입 → 마이페이지 → 인증키 발급 → **decoded** 키 복사.

활용신청: https://www.data.go.kr/data/15000563/openapi.do (응급의료기관 + 약국 자동 활용)

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 약국 운영시간 정보 (시도/시군구 기준)
Q1="서울특별시"
Q2="강남구"

curl -s -G "https://apis.data.go.kr/B552657/ErmctInsttInfoInqireService/getParmacyListInfoInqire" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "Q0=${Q1}" \
    --data-urlencode "Q1=${Q2}" \
    --data-urlencode "pageNo=1" \
    --data-urlencode "numOfRows=20" | \
  xmllint --xpath "//item" -

# 주요 필드:
#   dutyName    : 약국명
#   dutyAddr    : 주소
#   dutyTel1    : 전화
#   dutyTime1s/c : 월요일 시작/종료 (HHMM)
#   dutyTime2s/c : 화 ... dutyTime8s/c : 공휴일
#   wgs84Lat/Lon: 좌표
```

## 응답 포맷

```
💊 약국 검색: {Q1} {Q2}
1. {dutyName}
   📍 {dutyAddr}
   📞 {dutyTel1}
   ⏰ 평일 {dutyTime1s}-{dutyTime1c}, 토 {dutyTime7s}-{dutyTime7c}, 일/공휴 {dutyTime8s}-{dutyTime8c}
2. ...
```

## 주의

- 응답 XML. xmllint 로 파싱 또는 python ElementTree.
- 시간 코드 의미: 1=월, 2=화, ..., 7=토, 8=일/공휴일.
- "지금 문 연" 필터는 client-side 시각 비교로 구현 (서버 측 X).
- 좌표 (wgs84Lat/Lon) 활용해 사용자 현재 위치 기준 거리 정렬 가능.
- 급할 때 `dutyTel1` 직접 전화 권장 (DB 갱신 누락 가능).
