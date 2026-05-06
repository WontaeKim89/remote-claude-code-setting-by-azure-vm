---
name: jusoapi-roadname
description: |
  행정안전부 도로명주소 API skill (한국 주소 표준화 + 우편번호 + 좌표).
  Use this skill whenever the user wants to:
  (1) 어렴풋한 한국 주소를 정확한 도로명주소로 변환,
  (2) 우편번호 조회,
  (3) 옛 지번 주소 → 도로명 주소 매핑,
  (4) 주소 입력 폼/배송 데이터 정규화,
  (5) 좌표 (위도/경도) 부수 조회 (검색 결과 일부에 포함).
  관련 키워드: "주소", "우편번호", "도로명", "지번", "address".
metadata:
  openclaw:
    emoji: "🏠"
    requires:
      anyBins: ["curl", "jq"]
---

# 행정안전부 도로명주소 API

무료, 무제한 (정부 공공 API). 인증키 1개 필요.

## 의도/목적

- 한국 주소는 도로명/지번 혼재. 사용자 발화의 약식 주소를 정규 형태로.
- 배송/지도/공공 데이터 결합 전 1차 표준화.

## 자연어 트리거 예시

| 사용자 발화 | 동작 |
|------|------|
| "삼성역 우편번호 알려줘" | 검색 → zipNo |
| "강남구 테헤란로 152 정확한 주소로" | 검색 → roadAddr |
| "이 주소 도로명으로 바꿔: 서울시 강남구 역삼동 825" | 검색 (지번) → roadAddr |
| "광화문 광장 우편번호" | 검색 |
| "테헤란로 152 좌표 알려줘" | 검색 (좌표 포함) |

## 자격증명

`~/.openclaw/credentials/jusoapi.env`:
```
JUSOAPI_KEY=devU01TX0FVVEh...
```

발급: https://business.juso.go.kr/addrlink/openApi/apiExprn.do → 신청 (무료 승인 1일 내).

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/jusoapi.env"

KEYWORD="<사용자_발화의_주소_핵심_키워드>"

curl -s -G "https://business.juso.go.kr/addrlink/addrLinkApi.do" \
    --data-urlencode "confmKey=${JUSOAPI_KEY}" \
    --data-urlencode "currentPage=1" \
    --data-urlencode "countPerPage=5" \
    --data-urlencode "keyword=${KEYWORD}" \
    --data-urlencode "resultType=json" | jq '.results.juso[]'
```

각 항목 주요 필드:
- `roadAddr`: 도로명주소 (전체)
- `roadAddrPart1`: 도로명주소 (상세번호 전)
- `jibunAddr`: 지번주소
- `zipNo`: 우편번호 (5자리)
- `bdNm`: 건물명
- `siNm`/`sggNm`/`emdNm`: 시/구/동

## 응답 포맷

```
🏠 "{keyword}" 매칭 {N}건:
1. {roadAddr}
   지번: {jibunAddr}
   우편번호: {zipNo}
   건물: {bdNm}
2. ...
```

## 주의

- key 는 도메인/IP 등록 절차 없이 주피터 노트북 같은 데서도 작동 (편의 ↑).
- 검색 결과 0 이면 keyword 단순화/시도. 너무 길면 매칭 안 될 수 있음.
- 건물명만으로 검색해도 됨 (예: "롯데월드타워").
