---
name: deepl-translate
description: |
  DeepL Free API 번역 skill (한국어 ↔ 영어/일본어/중국어 등 30개 언어).
  Use this skill whenever the user wants to:
  (1) 한국어 텍스트를 자연스러운 영어로 번역 (논문/메일/PR description),
  (2) 영어 문서/에러 메시지를 한국어로 풀어 설명,
  (3) Papago/Google 번역보다 더 자연스러운 결과가 필요할 때 (일반적으로 DeepL 이 강함),
  (4) 긴 코드 주석·문서 일괄 번역,
  (5) 영어 LLM 응답을 한글로 옮길 때.
  관련 키워드: "번역", "translate", "영어로", "한국어로", "deepl".
metadata:
  openclaw:
    emoji: "🌐"
    requires:
      anyBins: ["curl", "jq"]
---

# DeepL Free API

무료 한도: 50만 자/월.

## 의도/목적

- 자연스러운 번역 품질이 핵심. 단순 단어 → 단어가 아닌 문맥/문체 보존.
- 기술 문서 영문 ↔ 한국어 변환에 특히 강함.

## 자연어 트리거 예시

| 사용자 발화 | source / target |
|------|------|
| "이 문장 영어로 번역해줘: 안녕하세요" | KO → EN |
| "이 에러 메시지 한국어로 해석: TypeError: ..." | EN → KO |
| "내 PR description 영어로 다듬어" | KO → EN |
| "일본어로 번역: 감사합니다" | KO → JA |
| "이 영어 문장 더 자연스러운 영어로 다시 써" | EN → EN (DeepL Write 별개 API) |

## 자격증명

`~/.openclaw/credentials/deepl.env`:
```
DEEPL_AUTH_KEY=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx:fx
```

발급: https://www.deepl.com/pro-api → Free 플랜 가입 → API key. `:fx` 가 free 표식.

## 명령 매핑

```bash
. "$HOME/.openclaw/credentials/deepl.env"

TEXT="<번역할_텍스트>"
TARGET_LANG="EN"   # KO / EN / JA / ZH / FR / DE / ES ...
SOURCE_LANG="KO"   # 생략 시 자동 감지

# Free 는 api-free.deepl.com (Pro 는 api.deepl.com)
curl -s -X POST "https://api-free.deepl.com/v2/translate" \
    -H "Authorization: DeepL-Auth-Key ${DEEPL_AUTH_KEY}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "text=${TEXT}" \
    --data-urlencode "target_lang=${TARGET_LANG}" \
    --data-urlencode "source_lang=${SOURCE_LANG}" | jq '.translations[0].text'
```

## 응답 포맷

```
🌐 [{src} → {tgt}]
{translated_text}
```

## 주의

- 한 번에 큰 덩어리 보내면 효율 좋음. 50만/월이라 평소엔 여유.
- Free 와 Pro 의 endpoint 가 다름 (api-free vs api). key 끝에 `:fx` 있으면 Free.
- 코드 블록 안의 영어는 번역하지 말 것 (사용자에게 번역할 부분 명시 요청).
