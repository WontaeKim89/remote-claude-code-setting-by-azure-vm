---
name: papago-translate
description: |
  NAVER Papago 번역 API skill (한국어 특화).
  Use this skill whenever the user wants to:
  (1) 한국어 → 일본어 / 중국어 (DeepL 보다 더 자연스럽게),
  (2) 한국어 → 영어 (DeepL 과 비교 검증),
  (3) Papago 만의 한국어 어색한 표현 교정,
  (4) 한글-한자 혼용 문장 번역,
  (5) DeepL 한도 초과 시 fallback.
  관련 키워드: "파파고", "papago", "번역 (한국어 강조)".
metadata:
  openclaw:
    emoji: "🇰🇷"
    requires:
      anyBins: ["curl", "jq"]
---

# NAVER Papago Translate

한국어 ↔ 동아시아 (일본어/중국어/베트남어/태국어/인도네시아어) 강함.
무료 한도: 1만 자/일.

## 의도/목적

- DeepL 은 유럽어 강하고 Papago 는 한국어/동아시아 강함.
- 한국어 사용자 본인이 쓴 문장의 어색한 부분 교정에도 사용.
- "deepl 말고 파파고로" 같은 명시 발화에 응답.

## 자연어 트리거 예시

| 사용자 발화 | src → tgt |
|------|------|
| "이 문장 일본어로 파파고 번역해줘" | KO → JA |
| "중국어로 번역: 안녕하세요" | KO → ZH-CN |
| "파파고로 영어 번역" | KO → EN |
| "베트남어로 번역해줘" | KO → VI |
| "이 일본어 문장 한국어로" | JA → KO |
| "deepl 말고 파파고 결과 비교" | (양쪽 다 호출) |

## 자격증명

`~/.openclaw/credentials/papago.env`:
```
NAVER_CLIENT_ID=...
NAVER_CLIENT_SECRET=...
```

NAVER Search API 와 같은 클라이언트 발급 가능 (Papago NMT API 권한 추가 체크).

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/papago.env"

TEXT="<번역할_텍스트>"
SOURCE="ko"   # ko / en / ja / zh-CN / zh-TW / vi / id / th / de / ru / es / it / fr
TARGET="en"

curl -s -X POST "https://openapi.naver.com/v1/papago/n2mt" \
    -H "X-Naver-Client-Id: ${NAVER_CLIENT_ID}" \
    -H "X-Naver-Client-Secret: ${NAVER_CLIENT_SECRET}" \
    --data-urlencode "source=${SOURCE}" \
    --data-urlencode "target=${TARGET}" \
    --data-urlencode "text=${TEXT}" | jq '.message.result.translatedText'
```

## 응답 포맷

```
🇰🇷 Papago [{src} → {tgt}]
{translated_text}
```

## 주의

- 1만 자/일 한도. 길면 DeepL 로 fallback.
- Papago API 는 한국 IP/한국 대상 번역 품질이 좋음.
