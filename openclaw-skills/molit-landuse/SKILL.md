---
name: molit-landuse
description: |
  국토부 토지이용계획 정보 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 토지의 용도지역 (주거/상업/공업/녹지),
  (2) 용도지구·용도구역 (개발제한/문화재 등),
  (3) 도시계획시설 (도로/공원/학교 예정지),
  (4) 토지 매입 전 활용 가능 여부,
  (5) 건축 계획 전 법적 제한 확인.
  관련 키워드: "토지이용계획", "용도지역", "그린벨트", "주거지역", "상업지역", "도시계획".
metadata:
  openclaw:
    emoji: "🗺️"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 토지이용계획 정보 API

국토부 토지이용규제정보서비스 (LURIS). 공공데이터포털 제공.

## 의도/목적

- "이 땅에 무엇을 지을 수 있나" 의 1차 답.
- 매수/투자 전 그린벨트/문화재보호구역 같은 제약 확인.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "이 주소 용도지역 뭐야" | landUseAttr |
| "여기 그린벨트야?" | 개발제한구역 여부 |
| "주거지역인지 상업지역인지" | 용도지역 |
| "이 땅에 카페 차릴 수 있어?" | 1차/2차 근린생활 가능 여부 |
| "도시계획시설 (예정 도로 등) 있어?" | 도시계획 |
| "용도지구 다 알려줘" | landUseAttr 전체 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15057511/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# PNU (토지 고유번호 19자리) 기반 조회
PNU="1168010300108250000"   # 시군구(5)+법정동(5)+산여부(1)+본번(4)+부번(4)

curl -s -G "https://apis.data.go.kr/1611000/nsdi/LandUseService/attr/getLandUseAttr" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "pnu=${PNU}" \
    --data-urlencode "_type=json" | jq

# 또는 시군구/법정동/지번 분리 형태 endpoint 도 존재 (getLandUseInfo).
```

주요 필드 (`landUseAttr` 응답):
- `landUseNm`: 용도지역명 (예: "제3종일반주거지역")
- `cnflcAt`: 저촉여부 (Y/N)
- `regstrSeNm`: 등록구분 (지정/저촉)
- `lnmAdr`: 지번주소

## 응답 포맷

```
🗺️ 토지이용계획: {주소}
PNU: {pnu}
용도지역:
  - {landUseNm}
용도지구:
  - 도시계획시설(도로) 저촉 (일부)
  - 학교환경위생정화구역
구역:
  - 일반상업지역 (50% 저촉)
```

## 주의

- PNU 19자리. 도로명주소만으로는 안 됨 → jusoapi-roadname → 지번 → PNU 변환 chain.
- 다중 결과 가능 (한 필지에 여러 용도지구 중첩).
- 응답 XML/JSON. `_type=json` 권장.
- 변경 가능성 있는 정보 (도시계획변경 등). 정밀 매수 결정엔 시군구 도시계획과 직접 확인.
