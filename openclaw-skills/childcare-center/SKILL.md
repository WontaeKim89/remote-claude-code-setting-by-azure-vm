---
name: childcare-center
description: |
  보건복지부 육아종합지원센터 API skill (어린이집/지원센터/보육 정보).
  Use this skill whenever the user wants to:
  (1) 거주 지역 어린이집 검색 (위치/정원/대기),
  (2) 국공립/민간/가정 등 유형 비교,
  (3) 평가인증 등급,
  (4) 육아종합지원센터 위치/프로그램,
  (5) 보육료 지원 정보.
  관련 키워드: "어린이집", "보육", "아이돌봄", "육아지원", "유치원" (별개).
metadata:
  openclaw:
    emoji: "👶"
    requires:
      anyBins: ["curl", "jq"]
---

# 육아종합지원센터 / 어린이집 정보

공공데이터포털 제공. 무료.

## 의도/목적

- 신혼/육아 가구 거주지 결정 또는 입소 신청 전 자료 수집.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "강남구 어린이집 알려줘" | sido=서울 + sigungu=강남구 |
| "근처 국공립 어린이집" | 유형=국공립 + 좌표 |
| "평가 A등급 어린이집" | 평가등급 |
| "육아종합지원센터 위치" | center 검색 |
| "이 어린이집 정원 / 현원" | 시설별 capacity |
| "장애아 통합 어린이집" | 특수 유형 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15074829/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 어린이집 검색
SIDO="서울특별시"
SIGUNGU="강남구"

curl -s -G "https://apis.data.go.kr/B552468/iccare/getInfoCcaInfo" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "sido=${SIDO}" \
    --data-urlencode "sigungu=${SIGUNGU}" \
    --data-urlencode "pageNo=1" \
    --data-urlencode "numOfRows=20" \
    --data-urlencode "_type=json" | jq

# 육아종합지원센터 위치 (별도 endpoint)
curl -s -G "https://apis.data.go.kr/B552468/CenterInfo/getCenterInfo" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "_type=json" | jq
```

주요 필드:
- `crname`: 어린이집명
- `crtype`: 유형 (국공립/사회복지법인/민간/가정/직장/협동)
- `craddr`: 주소
- `crtelno`: 전화
- `crchcnt`: 정원
- `crcanno`: 현원
- `crevltscoreds`: 평가등급 (A/B/C 등)
- `crfcdcnt`: 영아반 / 유아반 수

## 응답 포맷

```
👶 {sido} {sigungu} 어린이집 ({N}건)
1. {crname} ({crtype})
   📍 {craddr}
   📞 {crtelno}
   정원/현원: {crchcnt}/{crcanno}
   평가: {crevltscoreds}
2. ...
```

## 주의

- 정원/현원 데이터 갱신 주기 다소 지연. 정확한 대기는 어린이집 직접 문의.
- 민간 어린이집의 경우 평가등급 미공개.
- 입소대기 시스템 (i-사랑) 은 별도 → 사용자에게 안내.
