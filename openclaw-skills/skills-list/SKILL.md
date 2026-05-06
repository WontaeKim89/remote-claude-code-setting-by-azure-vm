---
name: skills-list
description: |
  /skills 명령어 처리 skill — 사용자가 등록한 모든 skill 의 이름과 한 줄 용도를
  깔끔한 형식으로 출력한다.
  Use this skill whenever the user types:
  (1) "/skills" — 슬래시 명령으로 정확히,
  (2) "내가 등록한 스킬 목록" / "skill 리스트" / "어떤 스킬 있어",
  (3) "비비가 뭐 할 줄 알아 / 능력 보여줘",
  (4) "내 비서 능력 / 기능 목록 / 메뉴",
  (5) "사용 가능한 명령 / API 보여줘".
  관련 키워드: "/skills", "스킬 목록", "skill list", "기능 목록", "능력".
metadata:
  openclaw:
    emoji: "📋"
    requires:
      anyBins: ["jq", "ls"]
---

# /skills 명령 처리

사용자가 `/skills` 또는 동등 자연어를 보내면 이 skill 발동.

## 동작

1. `~/.openclaw/workspace/skills/` 디렉토리 순회
2. 각 폴더의 `SKILL.md` frontmatter 에서 `name` + `description` 첫 줄 추출
3. 카테고리별 (이름 prefix 또는 emoji 기준) 묶어서 응답
4. 응답 포맷: 표 또는 리스트

## 명령 매핑

```bash
SKILLS_DIR="${HOME}/.openclaw/workspace/skills"

python3 - <<'PY'
import pathlib, re

skills_dir = pathlib.Path.home() / ".openclaw/workspace/skills"
out = []
for d in sorted(skills_dir.iterdir()):
    skill_md = d / "SKILL.md"
    if not skill_md.exists():
        continue
    text = skill_md.read_text()
    # frontmatter parse (간단)
    m_name = re.search(r"^name:\s*(\S+)", text, re.M)
    m_desc = re.search(r"^description:\s*\|?\s*\n((?:  .*\n)+)", text, re.M)
    if not m_desc:
        m_desc = re.search(r"^description:\s*(.+)", text, re.M)
        first_line = m_desc.group(1).strip() if m_desc else ""
    else:
        first_line = m_desc.group(1).split("\n")[0].strip()
    m_emoji = re.search(r'emoji:\s*["\']([^"\']+)["\']', text)
    emoji = m_emoji.group(1) if m_emoji else "📦"
    out.append({
        "name": m_name.group(1) if m_name else d.name,
        "emoji": emoji,
        "summary": first_line[:80],
    })

print(f"📋 등록된 스킬 ({len(out)}개)\n")
for s in out:
    print(f"{s['emoji']}  {s['name']}")
    print(f"     └─ {s['summary']}")
    print()
PY
```

## 응답 포맷

```
📋 등록된 스킬 (N개)

🎛️  claude-remote-control
     └─ Manage long-running Claude Code "remote-control" sessions...
🟢  naver-search
     └─ NAVER 검색 API (Search API) 호출 skill.
🟧  hacker-news
     └─ Hacker News (news.ycombinator.com) Public API skill.
🟦  reddit-json
     └─ Reddit JSON public API skill (인증 불필요 read-only).
💶  frankfurter-fx
     └─ Frankfurter (frankfurter.app) 무료 환율 API skill...
...
```

## 주의

- `~/.openclaw/workspace/skills/` 외에도 ClawHub 설치 skill 도 노출하려면 `openclaw skills list` 명령 결과 활용.
- description 이 multi-line YAML block scalar 형식이면 첫 줄만 추출.
- 카테고리 grouping 추가 가능: 한국 공공 / 글로벌 / AI / 유틸 등.
