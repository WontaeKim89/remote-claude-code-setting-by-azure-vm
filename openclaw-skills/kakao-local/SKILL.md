---
name: kakao-local
description: |
  Kakao Map / Local API skill (한국 지도/장소 검색/길찾기/좌표).
  Use this skill whenever the user wants to:
  (1) 한국 장소 검색 ("강남역 근처 카페"),
  (2) 주소 ↔ 좌표 변환 (geocoding / reverse),
  (3) 두 지점 간 거리/도보·자동차 길찾기 (Mobility API),
  (4) 카테고리별 검색 (FD6 음식점, CE7 카페, CS2 편의점 등),
  (5) 한국 내 지도 표시 데이터 조립.
  관련 키워드: "지도", "길찾기", "근처 ~", "좌표", "위치", "카카오".
metadata:
  openclaw:
    emoji: "🗺️"
    requires:
      anyBins: ["curl", "jq"]
---

# Kakao Local API

한국 지도/장소 1순위. 무료 30만 호출/일.

## 의도/목적

- 한국 지명/맛집/매장은 Google Maps 보다 Kakao 가 정확.
- 좌표 ↔ 주소 양방향 표준화.
- "근처 OO" 같은 위치 기반 추천에 핵심.

## 자연어 트리거 예시

| 사용자 발화 | endpoint |
|------|------|
| "강남역 근처 카페 5개" | keyword 검색 (CE7 카테고리) |
| "이 주소 좌표 알려줘: 서울 강남구 테헤란로 152" | address → coord |
| "위도 37.5012 경도 127.0396 어디야" | reverse geocode |
| "강남역에서 코엑스까지 도보로 몇 분" | mobility/directions (도보) |
| "지금 위치 근처 편의점" | category (CS2) + 좌표 |
| "역삼동 맛집 추천" | keyword |
| "이 주소 우편번호" | address |

## 자격증명

`~/.openclaw/credentials/kakao.env`:
```
KAKAO_REST_KEY=...
```

발급: https://developers.kakao.com → 내 애플리케이션 → 앱 추가 → REST API 키 복사.
`내 애플리케이션 → 제품 설정 → 카카오맵 → ON` 활성화 필요.

## 명령 매핑

### 키워드 검색

```bash
. "$HOME/.openclaw/credentials/kakao.env"

QUERY="<검색어>"
LAT="37.5665"   # optional center
LON="126.9780"
RADIUS="1000"   # m

curl -s -G "https://dapi.kakao.com/v2/local/search/keyword.json" \
    --data-urlencode "query=${QUERY}" \
    --data-urlencode "x=${LON}" \
    --data-urlencode "y=${LAT}" \
    --data-urlencode "radius=${RADIUS}" \
    --data-urlencode "size=10" \
    -H "Authorization: KakaoAK ${KAKAO_REST_KEY}" | jq '.documents[]'
```

각 document 필드: `place_name`, `category_name`, `address_name`, `road_address_name`, `phone`, `x` (lon), `y` (lat), `place_url`, `distance` (m).

### 주소 → 좌표

```bash
ADDRESS="<도로명_또는_지번>"
curl -s -G "https://dapi.kakao.com/v2/local/search/address.json" \
    --data-urlencode "query=${ADDRESS}" \
    -H "Authorization: KakaoAK ${KAKAO_REST_KEY}" | jq '.documents[0]'
```

### 좌표 → 주소 (reverse)

```bash
curl -s -G "https://dapi.kakao.com/v2/local/geo/coord2address.json" \
    --data-urlencode "x=${LON}" \
    --data-urlencode "y=${LAT}" \
    -H "Authorization: KakaoAK ${KAKAO_REST_KEY}" | jq '.documents[0]'
```

### 카테고리 검색

`category_group_code`: MT1 대형마트, CS2 편의점, PS3 어린이집, SC4 학교, AC5 학원, PK6 주차장, OL7 주유소, SW8 지하철역, BK9 은행, CT1 문화시설, AG2 중개업소, PO3 공공기관, AT4 관광명소, AD5 숙박, FD6 음식점, CE7 카페, HP8 병원, PM9 약국.

```bash
CAT="CE7"  # 카페
curl -s -G "https://dapi.kakao.com/v2/local/search/category.json" \
    --data-urlencode "category_group_code=${CAT}" \
    --data-urlencode "x=${LON}" --data-urlencode "y=${LAT}" \
    --data-urlencode "radius=500" \
    -H "Authorization: KakaoAK ${KAKAO_REST_KEY}" | jq '.documents[]'
```

## 응답 포맷

```
🗺️ "{query}" 검색 결과:
1. {place_name} ({category_name})
   📍 {road_address_name}
   📞 {phone}
   거리 {distance}m
   링크 {place_url}
2. ...
```

## 주의

- key 는 `KakaoAK` prefix 필수. 그냥 키만 쓰면 401.
- 키워드 검색 + 좌표/반경 같이 주면 거리 정렬 가능.
- 길찾기 (Mobility/Directions) 는 **별도 KakaoMobility 비즈니스 API** 라 free 한도가 다름. 일반 Local API 한도와 다름 — 길찾기 자주 쓸 거면 별도 신청 필요.
