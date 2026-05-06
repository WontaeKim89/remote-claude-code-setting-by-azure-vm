---
name: claude-remote-control
description: |
  Manage long-running Claude Code "remote-control" sessions on this Azure VM.
  Use this skill whenever the user wants to:
  (1) clone a GitHub repo and open Claude Code on it,
  (2) open Claude Code remotely on a specific local directory,
  (3) list, restart, or kill existing remote-control sessions,
  (4) get the URL to access a session from mobile (claude.ai/code).
  Each session is bound to a label and a working directory. The user accesses
  sessions from mobile via URLs of the form https://claude.ai/code/session_<id>
  which the launch script sends to Telegram automatically when a session starts.
  This skill MUST always confirm the working directory with the user before
  starting any new session.
metadata:
  openclaw:
    emoji: "🎛️"
    requires:
      anyBins: ["claude", "git", "systemctl"]
---

# Claude Remote Control session manager

이 VM 위에서 돌아가는 long-running `claude --remote-control` instance 들을 라벨
단위로 관리한다. 사용자는 모바일/웹 (claude.ai/code) 에서 그 URL 로 접속해 코드
작업을 한다.

## 인프라 위치 (참고용)

- registry: `~/.config/claude-remote/sessions.json`
  ```json
  {
    "sessions": [
      {"label": "main",  "session_id": "<uuid>", "workdir": "/home/azureuser/project"},
      {"label": "frontend", "session_id": null, "workdir": "/home/azureuser/projects/frontend"}
    ]
  }
  ```
- systemd unit (라벨별 인스턴스): `claude-rc@<label>.service`
- pane log: `~/.local/share/claude-remote/rc-<label>.log`
- launch script: `~/.local/bin/claude-rc-launch.sh <label>` — service 가 호출

## 핵심 규칙 (반드시 지킬 것)

세션을 **새로 시작하거나 작업 디렉토리를 바꿀 때마다** 사용자에게 다음을 명시
확인하고 승인받는다.

1. **라벨** (label)
   - 사용자가 명시 안 했으면 repo 이름이나 작업 주제에서 짧고 의미있는 라벨 제안
2. **작업 디렉토리** (workdir, 절대 경로)
   - default 후보: 새 repo 면 `~/projects/<label>`, 기존 라벨이면 registry 의 workdir
   - 사용자가 "그냥 열어줘"라고 해도 디렉토리는 한 번 명시 확인
3. registry 에 같은 라벨이 이미 있으면 덮어쓰기 여부도 묻는다

확인 메시지 예시:
> "라벨 `frontend` 으로 `/home/azureuser/projects/frontend` 에서 Claude Remote
> Control 세션을 새로 열까요? (Y/n)"

## 명령 매핑

### `list` — 등록된 세션 + 활성 상태

```bash
echo "=== registry ==="
cat ~/.config/claude-remote/sessions.json | python3 -m json.tool 2>&1
echo "=== systemd ==="
systemctl --user list-units --no-pager 'claude-rc@*' 2>&1 | head -20
```

각 라벨에 대해:
- `systemctl --user is-active claude-rc@<label>.service` 로 active 여부
- `~/.claude/projects/-home-azureuser-project/<session_id>.jsonl` 의 mtime 으로
  마지막 활동 시각

### `clone <repo-url>` — repo clone + 새 세션

1. **사용자에게 확인** (라벨, clone 위치, workdir).
2. 실행:
   ```bash
   LABEL="<label>"
   WORKDIR="<workdir>"
   REPO="<repo-url>"

   mkdir -p "$(dirname "$WORKDIR")"
   if [ ! -d "$WORKDIR/.git" ]; then
       git clone "$REPO" "$WORKDIR"
   fi

   python3 - <<PY
   import json, pathlib
   p = pathlib.Path("$HOME/.config/claude-remote/sessions.json")
   d = json.loads(p.read_text()) if p.exists() else {"sessions": []}
   labels = [s.get("label") for s in d.get("sessions", [])]
   if "$LABEL" not in labels:
       d.setdefault("sessions", []).append({
           "label": "$LABEL",
           "session_id": None,
           "workdir": "$WORKDIR",
       })
   else:
       for s in d["sessions"]:
           if s.get("label") == "$LABEL":
               s["workdir"] = "$WORKDIR"
   p.write_text(json.dumps(d, indent=2))
   PY

   systemctl --user start "claude-rc@${LABEL}.service"
   ```
3. URL 추출 + 사용자 메시지:
   ```bash
   for i in $(seq 1 20); do
       URL=$(grep -oE 'https://claude\.ai/code(\?environment=[A-Za-z0-9_-]+|/session_[A-Za-z0-9]+)' "$HOME/.local/share/claude-remote/rc-${LABEL}.log" 2>/dev/null | head -1)
       [ -n "$URL" ] && break
       sleep 1
   done
   ```
   `URL` 을 사용자에게 메시지로 답한다 (`openclaw message send` 또는 그냥 응답).

### `open <label>` — 기존/신규 라벨 세션 열기

1. registry 에 라벨이 있으면 등록된 workdir 보여주고 변경 여부 묻기.
2. 라벨이 없으면 사용자에게 workdir 묻고 registry 에 새로 등록.
3. `systemctl --user restart claude-rc@<label>.service` (이미 active 여도 재시작
   해서 새 URL 발급 — 모바일 측 environment 가 stale 일 수 있음).
4. URL 추출 + 응답.

### `restart <label>` — 강제 새 URL 발급

`open` 과 동일하게 동작.

### `kill <label>` — 종료 + 제거

```bash
systemctl --user stop "claude-rc@${LABEL}.service"
python3 - <<PY
import json, pathlib
p = pathlib.Path("$HOME/.config/claude-remote/sessions.json")
d = json.loads(p.read_text())
d["sessions"] = [s for s in d.get("sessions", []) if s.get("label") != "$LABEL"]
p.write_text(json.dumps(d, indent=2))
PY
```

### `url <label>` — 현재 캐시된 URL 다시 보기 (재시작 X)

```bash
grep -oE 'https://claude\.ai/code(\?environment=[A-Za-z0-9_-]+|/session_[A-Za-z0-9]+)' "$HOME/.local/share/claude-remote/rc-${LABEL}.log" | head -1
```

## 자연어 → 명령 매핑 가이드

| 사용자 발화 | 매핑 |
|------|------|
| "이 레포 clone 떠 / 받아 / 가져와줘" | `clone <repo-url>` |
| "claude code 열어 / 띄워 / 시작" | `open <label>` (라벨 없으면 직전 clone 한 라벨 또는 기본 main) |
| "내 세션 / 어떤 세션 있어 / 목록 / 리스트" | `list` |
| "다시 / 새 URL / 재시작" | `restart <label>` |
| "닫아 / 종료 / 지워" | `kill <label>` |
| "URL 다시 / 링크" | `url <label>` |

## 응답 포맷

세션 시작 후 사용자에게 답할 때:
```
🚀 <label> 준비 완료
workdir: <workdir>
url: <url>
```

failed 시:
```
❌ <label> 시작 실패
원인: <stderr 마지막 5줄 또는 systemctl status 요약>
```

## 주의

- 라벨 정규식: `^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$`. 위반 시 사용자에게 재요청.
- workdir 은 항상 절대 경로. `~/...` 받으면 `$HOME` 으로 expand 후 저장.
- claude-rc 인스턴스는 `--permission-mode bypassPermissions` 로 떠 있어 모바일에
  서 명령 실행 시 별도 승인 prompt 없음. 사용자에게 그 사실 알려도 됨.
- `~/.local/share/claude-remote/rc-<label>.log` 가 시작 후 5~10초 안에 URL 을 찍는
  다. 20초 폴링해서 못 찾으면 service 죽었거나 prompt 막힌 케이스 → status 보고.
