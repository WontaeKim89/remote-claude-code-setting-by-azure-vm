---
name: molit-bldg-ledger
description: |
  국토교통부 건축물대장 API skill.
  Use this skill whenever the user wants to:
  (1) 특정 건물의 면적·층수·구조·연식,
  (2) 주거 vs 근린생활 vs 업무시설 등 용도 확인,
  (3) 사용승인일 (준공일) 조회,
  (4) 위반건축물 여부,
  (5) 매매 전 실사 / 임대차 전 점검.
  관련 키워드: "건축물대장", "건축물 정보", "건물 연식", "준공일", "사용승인", "용도".
metadata:
  openclaw:
    emoji: "🏗️"
    requires:
      anyBins: ["curl", "jq", "xmllint"]
---

# 건축물대장 정보 API

국토부 건축행정시스템 세움터 데이터. 무료.

## 의도/목적

- 매매·임대 계약 전 건물 자체 정보 사실 확인.
- 사용승인 X 면 미준공 → 거래 위험.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "이 건물 언제 지어졌어 (주소)" | 사용승인일 |
| "건축물대장 등본 같은 정보 알려줘" | 표제부 |
| "면적이랑 용도 확인" | mainAtchGbCd 등 |
| "위반건축물 여부 확인" | violYN |
| "이 빌라 몇 가구야" | hhldCnt |
| "엘리베이터 있어?" | etcStrct (구조 정보) |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15044713/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 표제부 (건축물 기본정보)
SIGUNGU_CD="11680"   # 강남구
BJDONG_CD="10300"    # 역삼동 (법정동)
PLAT_GB_CD="0"       # 0=대지, 1=산
BUN="0825"           # 본번
JI="0000"            # 부번

curl -s -G "https://apis.data.go.kr/1613000/BldRgstService_v2/getBrTitleInfo" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "sigunguCd=${SIGUNGU_CD}" \
    --data-urlencode "bjdongCd=${BJDONG_CD}" \
    --data-urlencode "platGbCd=${PLAT_GB_CD}" \
    --data-urlencode "bun=${BUN}" \
    --data-urlencode "ji=${JI}" \
    --data-urlencode "_type=json" | jq

# 다른 endpoint:
#   getBrBasisOulnInfo  : 기본개요
#   getBrFlrOulnInfo    : 층별개요 (각 층 면적/용도)
#   getBrRecapTitleInfo : 총괄표제부 (단지)
#   getBrAtchJibunInfo  : 부속지번
#   getBrExposPubuseAreaInfo : 전유공용면적
```

주요 필드:
- `bldNm`: 건물명
- `mainAtchGbCdNm`: 주/부속 구분
- `mainPurpsCdNm`: 주용도 (예: "공동주택", "단독주택", "근린생활시설", "업무시설")
- `useAprDay`: 사용승인일 (YYYYMMDD)
- `totArea`: 연면적
- `grndFlrCnt`/`ugrndFlrCnt`: 지상/지하 층수
- `hhldCnt`: 세대수
- `pmsDay`: 허가일자
- `violYn`: 위반건축물 여부
- `strctCdNm`: 구조 (철근콘크리트/철골 등)

## 응답 포맷

```
🏗️ {bldNm} ({주소})
용도: {mainPurpsCdNm}
사용승인: {useAprDay} (연식 {YYYY-current_year}년)
연면적: {totArea} ㎡
층수: 지상 {grndFlrCnt}층 / 지하 {ugrndFlrCnt}층
세대수: {hhldCnt}
구조: {strctCdNm}
위반: {violYn}
```

## 주의

- `sigunguCd`/`bjdongCd` 5자리 법정동 코드 필요. 사용자 발화 → 도로명주소 (jusoapi-roadname) → 법정동 코드 변환 chain.
- 응답 XML/JSON. `_type=json` 권장.
- 본번/부번 0-padding 4자리 (`0825-0000`).
- 일 호출 한도 10,000.
