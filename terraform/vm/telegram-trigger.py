#!/usr/bin/env python3
"""
Telegram 봇 long-poll 리스너 + multi-session manager.

지원 명령 (등록된 chat_id 만 처리, 그 외는 무시):
  /list (또는 /sessions)  - 등록된 세션 목록 + 마지막 활동 시각 + active 여부 + URL
                            출력 후 60초 내 일반 메시지(번호/라벨)를 selection 으로 해석
  /new <label>            - 새 세션 추가 + 즉시 시작 + URL 발송
  /kill <label>           - 세션 종료 + registry 에서 제거
  /url <label>            - 특정 라벨의 현재 URL 다시 발송
  /help                   - 도움말

직접 메시지(번호 / 라벨) 처리:
  /list 응답 윈도우(60s) 안에서 들어온 텍스트 → 해당 세션 선택 → URL 발송
  비활성 세션이면 자동 시작.
"""

from __future__ import annotations

import json
import os
import pathlib
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.request

# ── 경로/상수 ─────────────────────────────────────────────────
HOME = pathlib.Path.home()
REG_PATH = HOME / ".config/claude-remote/sessions.json"
STATE_PATH = HOME / ".local/share/claude-remote/.tg-state.json"
LOG_DIR = HOME / ".local/share/claude-remote"
PROJECT_LOG_DIR = HOME / ".claude/projects/-home-azureuser-project"

SELECTION_TIMEOUT = 60   # /list 응답 대기 윈도우 (초)
START_WAIT = 30          # 세션 시작 후 URL 잡힐 때까지 대기 (초)

URL_RE = re.compile(
    r"https://claude\.ai/code(\?environment=[A-Za-z0-9_-]+|/session_[A-Za-z0-9]+)"
)
LABEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$")

TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")
API_BASE = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
    print("TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID 환경변수가 비어있다.", file=sys.stderr)
    sys.exit(1)


# ── registry / state I/O ─────────────────────────────────────
def load_registry() -> dict:
    if not REG_PATH.exists():
        return {"sessions": []}
    try:
        return json.loads(REG_PATH.read_text())
    except Exception:
        return {"sessions": []}


def save_registry(d: dict) -> None:
    REG_PATH.parent.mkdir(parents=True, exist_ok=True)
    REG_PATH.write_text(json.dumps(d, indent=2))


def load_state() -> dict:
    if not STATE_PATH.exists():
        return {}
    try:
        return json.loads(STATE_PATH.read_text())
    except Exception:
        return {}


def save_state(d: dict) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    STATE_PATH.write_text(json.dumps(d))


# ── Telegram API helpers ─────────────────────────────────────
def tg_send(text: str) -> None:
    data = urllib.parse.urlencode(
        {
            "chat_id": TELEGRAM_CHAT_ID,
            "parse_mode": "HTML",
            "text": text,
            "disable_web_page_preview": "true",
        }
    ).encode()
    try:
        urllib.request.urlopen(f"{API_BASE}/sendMessage", data=data, timeout=10).read()
    except Exception as e:
        print(f"tg_send failed: {e}", file=sys.stderr)


def tg_get_updates(offset: int) -> list[dict]:
    url = f"{API_BASE}/getUpdates?offset={offset}&timeout=30"
    try:
        with urllib.request.urlopen(url, timeout=35) as r:
            d = json.loads(r.read())
        return d.get("result", []) if d.get("ok") else []
    except Exception as e:
        print(f"getUpdates failed: {e}", file=sys.stderr)
        return []


# ── systemd helpers ──────────────────────────────────────────
def sd(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["systemctl", "--user", *args], capture_output=True, text=True
    )


def sd_start(label: str) -> None:
    sd("start", f"claude-rc@{label}.service")


def sd_stop(label: str) -> None:
    sd("stop", f"claude-rc@{label}.service")


def sd_active(label: str) -> bool:
    return sd("is-active", f"claude-rc@{label}.service").stdout.strip() == "active"


# ── session 정보 조회 ────────────────────────────────────────
def get_label_url(label: str) -> str | None:
    log = LOG_DIR / f"rc-{label}.log"
    if not log.exists():
        return None
    try:
        text = log.read_text(errors="ignore")
    except Exception:
        return None
    m = URL_RE.search(text)
    return m.group() if m else None


def get_label_jsonl_mtime(reg_entry: dict) -> float | None:
    sid = reg_entry.get("session_id")
    if not sid:
        return None
    p = PROJECT_LOG_DIR / f"{sid}.jsonl"
    return p.stat().st_mtime if p.exists() else None


def time_ago(seconds: float) -> str:
    if seconds < 60:
        return f"{int(seconds)}초 전"
    if seconds < 3600:
        return f"{int(seconds / 60)}분 전"
    if seconds < 86400:
        return f"{int(seconds / 3600)}시간 전"
    return f"{int(seconds / 86400)}일 전"


def list_sessions_meta() -> list[dict]:
    reg = load_registry()
    out = []
    now = time.time()
    for s in reg.get("sessions", []):
        label = s.get("label")
        if not label:
            continue
        active = sd_active(label)
        mtime = get_label_jsonl_mtime(s)
        ago = time_ago(now - mtime) if mtime else "이력 없음"
        url = get_label_url(label) if active else None
        out.append({"label": label, "active": active, "ago": ago, "url": url})
    return out


def render_list(sessions: list[dict]) -> str:
    if not sessions:
        return (
            "📋 등록된 세션 없음.\n"
            "새 세션 만들기: <code>/new &lt;라벨&gt;</code>"
        )
    lines = ["📋 <b>등록된 세션</b>\n"]
    for i, s in enumerate(sessions, 1):
        dot = "🟢" if s["active"] else "⚪"
        lines.append(f"<b>{i}.</b> {dot} <code>{s['label']}</code> · {s['ago']}")
    lines.append("")
    lines.append("어떤 내용의 세션으로 연결해드릴까요?")
    lines.append("<i>번호(예: 1) 또는 라벨로 답해. /new &lt;라벨&gt; 로 새로 추가.</i>")
    return "\n".join(lines)


# ── 명령 처리 ───────────────────────────────────────────────
def ensure_session_started(label: str, force_restart: bool = False) -> str | None:
    """
    label service 가동 보장 + URL 추출.
    - force_restart=True : 항상 stop → start (옛 URL 무효화 + 새 URL 발급).
      claude.ai 측에서 environment 가 삭제됐을 때 stale URL 을 잡지 않게 하려는 용도.
    - force_restart=False: active 면 그대로 두고 URL 만 다시 읽음.
    """
    if force_restart:
        sd_stop(label)
        # tmux 세션 + launch.sh 종료 대기 (race 방지)
        for _ in range(5):
            if not sd_active(label):
                break
            time.sleep(1)
        sd_start(label)
    elif not sd_active(label):
        sd_start(label)
    url = None
    for _ in range(START_WAIT):
        time.sleep(1)
        url = get_label_url(label)
        if url:
            break
    return url


def cmd_list(state: dict) -> None:
    sessions = list_sessions_meta()
    tg_send(render_list(sessions))
    state["awaiting_selection_until"] = time.time() + SELECTION_TIMEOUT
    save_state(state)


def cmd_new(args: str) -> None:
    label = args.strip().split()[0] if args.strip() else f"session-{int(time.time()) % 10000}"
    if not LABEL_RE.match(label):
        tg_send("❌ 라벨은 영숫자/하이픈/밑줄/마침표 32자 이내. 예: <code>/new frontend</code>")
        return
    reg = load_registry()
    if any(s.get("label") == label for s in reg.get("sessions", [])):
        tg_send(f"ℹ️ <code>{label}</code> 이미 존재. /list 로 확인.")
    else:
        reg.setdefault("sessions", []).append({"label": label, "session_id": None})
        save_registry(reg)
    tg_send(f"⏳ <code>{label}</code> 시작 중...")
    url = ensure_session_started(label)
    if url:
        # claude-rc-launch.sh 가 자체로 URL 메시지 보낸다. 여기서는 ack 만.
        tg_send(f"✅ <code>{label}</code> 준비 완료.")
    else:
        tg_send(
            f"❌ <code>{label}</code> 시작 실패.\n"
            f"<code>systemctl --user status claude-rc@{label}.service</code> 로 확인."
        )


def cmd_kill(args: str) -> None:
    label = args.strip()
    if not label:
        tg_send("❌ 라벨 필요. 예: <code>/kill frontend</code>")
        return
    sd_stop(label)
    reg = load_registry()
    reg["sessions"] = [s for s in reg.get("sessions", []) if s.get("label") != label]
    save_registry(reg)
    tg_send(f"💀 <code>{label}</code> 종료 + registry 제거.")


def cmd_url(args: str) -> None:
    label = args.strip()
    if not label:
        tg_send("❌ 라벨 필요. 예: <code>/url frontend</code>")
        return
    if not sd_active(label):
        tg_send(f"❌ <code>{label}</code> 비활성. <code>/list</code> 또는 <code>/new {label}</code>")
        return
    url = get_label_url(label)
    if url:
        tg_send(f"🚀 <b>{label}</b>\n{url}")
    else:
        tg_send(f"❌ <code>{label}</code> URL 못 찾음. status 확인.")


def cmd_restart(args: str) -> None:
    """
    /restart <label> - 강제로 service 재시작 → 새 URL 발급.
    모바일에서 environment 를 삭제했거나 stale URL 의심될 때 사용.
    """
    label = args.strip()
    if not label:
        tg_send("❌ 라벨 필요. 예: <code>/restart main</code>")
        return
    reg = load_registry()
    if not any(s.get("label") == label for s in reg.get("sessions", [])):
        tg_send(f"❌ <code>{label}</code> registry 에 없음. <code>/list</code>")
        return
    tg_send(f"🔄 <code>{label}</code> 재시작 중 (새 URL 발급)...")
    url = ensure_session_started(label, force_restart=True)
    if url:
        tg_send(f"🚀 <b>{label}</b>\n{url}")
    else:
        tg_send(f"❌ <code>{label}</code> URL 못 잡음.")


def cmd_help() -> None:
    tg_send(
        "🤖 <b>Claude Remote Sessions</b>\n\n"
        "<code>/list</code> — 세션 목록 + 어디로 연결할지 선택 (선택 시 자동 새 URL 발급)\n"
        "<code>/new &lt;라벨&gt;</code> — 새 세션 추가 + 시작\n"
        "<code>/kill &lt;라벨&gt;</code> — 세션 종료 + 제거\n"
        "<code>/url &lt;라벨&gt;</code> — 현재 캐시된 URL 다시 보기 (재시작 X)\n"
        "<code>/restart &lt;라벨&gt;</code> — 강제 재시작 + 새 URL 발급 (모바일에서 환경 삭제했을 때)\n"
        "<code>/help</code> — 도움말\n\n"
        "<i>/list 후 60초 안에 번호 또는 라벨로 답하면 그 세션을 새 URL 로 띄워준다.\n"
        "기존 conversation 은 디스크에서 --resume 으로 자동 이어감.</i>"
    )


def handle_selection(text: str, state: dict) -> None:
    sessions = list_sessions_meta()
    sel = None
    if text.isdigit():
        idx = int(text) - 1
        if 0 <= idx < len(sessions):
            sel = sessions[idx]
    else:
        for s in sessions:
            if s["label"].lower() == text.lower():
                sel = s
                break
    if not sel:
        tg_send(
            f"❌ <code>{text}</code> 매칭 안됨. <code>/list</code> 다시."
        )
        state["awaiting_selection_until"] = 0
        save_state(state)
        return
    label = sel["label"]
    state["awaiting_selection_until"] = 0
    save_state(state)
    # 모바일에서 옛 environment 를 삭제했어도 fresh URL 을 받게 하려고
    # 선택 시 항상 service 를 restart 한다.
    # conversation history 는 jsonl 에 보존되고 launch.sh 가 --resume 으로 이어감.
    tg_send(f"⏳ <code>{label}</code> 연결 중 (새 URL 발급)...")
    url = ensure_session_started(label, force_restart=True)
    if url:
        tg_send(f"🚀 <b>{label}</b>\n{url}")
    else:
        tg_send(
            f"❌ <code>{label}</code> URL 못 잡음.\n"
            f"<code>systemctl --user status claude-rc@{label}.service</code>"
        )


# ── 메인 루프 ───────────────────────────────────────────────
def main() -> None:
    state = load_state()
    # 토큰이 바뀌면 옛 봇의 update_id 와 새 봇의 update_id 가 호환되지 않으므로
    # 저장된 offset 을 무시하고 0 부터 시작한다 (새 봇은 가장 최근 1건만 반환).
    saved_token_hash = state.get("token_hash", "")
    import hashlib
    cur_token_hash = hashlib.sha256(TELEGRAM_BOT_TOKEN.encode()).hexdigest()[:16]
    if saved_token_hash != cur_token_hash:
        print(
            f"[telegram-trigger] token changed (was={saved_token_hash[:8]}, now={cur_token_hash[:8]}), reset offset",
            flush=True,
        )
        state = {"offset": 0, "token_hash": cur_token_hash}
        save_state(state)
    offset = int(state.get("offset", 0))
    print(f"[telegram-trigger] start, offset={offset}", flush=True)

    while True:
        updates = tg_get_updates(offset)
        for u in updates:
            # 무조건 다음 update_id 로 진행 (max() 제거: 잘못된 큰 값이 박혀있으면 무한 루프).
            offset = u["update_id"] + 1
            state["offset"] = offset
            save_state(state)

            msg = u.get("message") or u.get("edited_message") or {}
            chat_id = str(msg.get("chat", {}).get("id", ""))
            if chat_id != TELEGRAM_CHAT_ID:
                continue
            text = (msg.get("text") or "").strip()
            if not text:
                continue
            head = text.split(maxsplit=1)
            cmd = head[0].lower().split("@")[0]
            args = head[1] if len(head) > 1 else ""

            if cmd in ("/list", "/sessions"):
                cmd_list(state)
            elif cmd == "/new":
                cmd_new(args)
            elif cmd == "/kill":
                cmd_kill(args)
            elif cmd == "/url":
                cmd_url(args)
            elif cmd == "/restart":
                cmd_restart(args)
            elif cmd in ("/help", "/start"):
                cmd_help()
            else:
                # selection 윈도우 안이면 selection 으로 해석
                until = float(state.get("awaiting_selection_until", 0) or 0)
                if time.time() < until:
                    handle_selection(text, state)
                # 그 외 일반 메시지는 무시 (스팸/오타 방지)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
