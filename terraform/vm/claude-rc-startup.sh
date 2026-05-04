#!/usr/bin/env bash
# claude-rc-startup.sh
#
# 부팅 시 1회 실행. ~/.config/claude-remote/sessions.json 에 등록된
# 모든 라벨에 대해 claude-rc@<label>.service 를 start 시킨다.
# registry 가 비어있으면 default 라벨 'main' 을 추가하고 시작.

set -euo pipefail

REG="${HOME}/.config/claude-remote/sessions.json"
mkdir -p "$(dirname "$REG")"

# registry 가 없거나 비어있으면 default entry 만든다 (첫 배포용).
if [[ ! -f "$REG" ]] || ! python3 -c "
import json, sys
try:
    with open('$REG') as f: d = json.load(f)
    sys.exit(0 if d.get('sessions') else 1)
except Exception:
    sys.exit(1)
"; then
    cat > "$REG" <<EOF
{
  "sessions": [
    {"label": "main", "session_id": null}
  ]
}
EOF
fi

# label 목록 추출
LABELS=$(python3 - <<PY
import json
with open("$REG") as f:
    d = json.load(f)
for s in d.get("sessions", []):
    label = s.get("label")
    if label:
        print(label)
PY
)

UID_=$(id -u)
for L in $LABELS; do
    echo "[claude-rc-startup] starting claude-rc@${L}.service"
    XDG_RUNTIME_DIR="/run/user/${UID_}" systemctl --user start "claude-rc@${L}.service" || true
done
