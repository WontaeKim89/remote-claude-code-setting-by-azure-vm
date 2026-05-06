---
name: bokjiro-welfare
description: |
  복지로 복지서비스 API skill (정부 복지 사업 검색).
  Use this skill whenever the user wants to:
  (1) 자신·가족이 받을 수 있는 복지 서비스,
  (2) 청년·신혼·노인·장애인 등 대상별 지원,
  (3) 주거·의료·교육·고용 등 분야별,
  (4) 부처·지자체별 사업 비교,
  (5) 신청방법·자격요건·지원금액.
  관련 키워드: "복지", "지원금", "보조금", "혜택", "청년 지원", "주거 지원", "복지로".
metadata:
  openclaw:
    emoji: "🤲"
    requires:
      anyBins: ["curl", "jq"]
---

# 복지로 복지서비스 API

보건복지부 운영. 공공데이터포털 제공.

## 의도/목적

- "내가 받을 수 있는 정부 지원 뭐 있어?" 의 1차 답.
- 청년/노인/장애/주거 등 카테고리별 검색.

## 자연어 트리거 예시 (5+)

| 사용자 발화 | 매핑 |
|------|------|
| "내가 받을 수 있는 청년 지원금" | 대상=청년 |
| "신혼부부 주거 지원" | 신혼+주거 |
| "노인 의료 지원" | 노인+의료 |
| "장애인 활동지원" | 장애 카테고리 |
| "월세 지원 받을 수 있어?" | 주거+월세 |
| "교육비 지원" | 교육 |

## 자격증명

`DATA_GO_KR_KEY` 재사용. 활용신청: https://www.data.go.kr/data/15083323/openapi.do

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/data-go-kr.env"

# 복지서비스 목록 검색
KEYWORD="청년 주거"

curl -s -G "https://apis.data.go.kr/B554287/NationalWelfareInformationsV001/NationalWelfarelistV001" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "callTp=L" \
    --data-urlencode "pageNo=1" \
    --data-urlencode "numOfRows=10" \
    --data-urlencode "searchKeyword=${KEYWORD}" \
    --data-urlencode "lifeArray=" \
    --data-urlencode "trgterIndvdlArray=" \
    --data-urlencode "intrsThemaArray=" | jq

# 상세 조회
SERVICE_ID="WLF00000001"
curl -s -G "https://apis.data.go.kr/B554287/NationalWelfareInformationsV001/NationalWelfaredetailedV001" \
    --data-urlencode "serviceKey=${DATA_GO_KR_KEY}" \
    --data-urlencode "callTp=D" \
    --data-urlencode "servId=${SERVICE_ID}" | jq
```

주요 필드:
- `servNm`: 서비스명
- `jurMnofNm`: 소관부처
- `servDgst`: 서비스 한줄 설명
- `tgtrDtlCn`: 대상 상세
- `slctCritCn`: 선정기준
- `aplyMtdCn`: 신청방법
- `servDtlLink`: 복지로 상세 url
- `intrsThemaArray`: 관심주제 (생애주기/관심분야)

## 응답 포맷

```
🤲 "{keyword}" 매칭 복지 {N}건
1. {servNm} (담당: {jurMnofNm})
   {servDgst}
   대상: {tgtrDtlCn 50자}
   신청: {aplyMtdCn 30자}
   상세: {servDtlLink}
2. ...
```

## 주의

- 키워드 매칭이 정확도 낮을 수 있음. 핵심 단어 (청년/주거/육아 등)로 좁히기.
- 자격요건 디테일 (소득기준 등) 은 상세 조회 후 LLM 이 평가.
- 지자체별 별도 사업은 별도 endpoint 또는 정부24 (gov.kr) API 활용.
