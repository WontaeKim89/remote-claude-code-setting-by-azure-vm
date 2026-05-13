#!/bin/bash

###############################################################
# start-remote.sh - Azure VM Claude Remote 환경 원클릭 구성
#
# 사용법:
#   bash start-remote.sh <github-repo-url> [project-path]
#
# 예시:
#   bash start-remote.sh git@github.com:owner/repo.git
#   bash start-remote.sh git@github.com:owner/repo.git ~/work
#
# 이 스크립트 한 번 실행으로 아래가 모두 자동 처리됩니다:
#  1) SSH 접속 가능 여부 확인
#  2) VM 내 필수 패키지 설치 (tmux, Node.js, Bun, Claude Code)
#  3) Claude Code 로그인 상태 확인 → 미로그인 시 안내
#  4) VM에 GitHub용 ed25519 SSH key 생성 + 공개키 출력
#     (사용자가 GitHub에 등록 후 Enter를 누르면 진행)
#  5) 지정한 GitHub repo를 ~/project (또는 인자로 받은 경로)에 clone
#  6) Telegram 봇 토큰/chat_id 입력 → notifier.env 배포 (권한 0600)
#  7) ~/.claude.json pre-seed (workspace trust + remote-control prompt 미리 수락)
#  8) systemd user service 2종 + notifier 스크립트 scp 배포
#  9) 서비스 기동 → Telegram으로 Remote Control URL 알림 도착
#
# 사전 요구사항:
#  - terraform apply 완료 (VM·NSG·Public IP 생성됨)
#  - ~/.ssh/config에 claude-vm 호스트가 등록되어 있어야 함
#    Host claude-vm
#        HostName <Public IP>
#        User azureuser
#        IdentityFile <terraform 산출 .pem>
#  - VM에 한 번 SSH 접속하여 `claude` 실행 후 OAuth 로그인 완료
#  - Telegram 봇 1개 (BotFather에서 발급)
###############################################################

set -e

# ── 설정값 ─────────────────────────────────────────────────────
SSH_HOST="${SSH_HOST:-claude-vm}"

# 첫 번째 인자: GitHub repo URL (필수)
REPO_URL="${1:-}"
# 두 번째 인자: VM 내부 프로젝트 경로 (기본: ~/project)
REMOTE_PROJECT="${2:-~/project}"

# 로컬 레포에서 VM으로 배포할 systemd unit / notifier 스크립트의 경로
VM_ASSETS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terraform/vm"

# tmux 세션 이름
TMUX_SESSION_RC="remote-control"

# VM에 생성할 GitHub deploy용 SSH key 이름
VM_GH_KEY_NAME="claude_remote_github"

# ── 색상 ──────────────────────────────────────────────────────
G='\033[0;32m'   # 성공
Y='\033[1;33m'   # 경고
R='\033[0;31m'   # 에러
C='\033[0;36m'   # 정보
B='\033[0;34m'   # 배너
NC='\033[0m'

log()  { echo -e "${G}[OK]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[X]${NC} $1" >&2; }
info() { echo -e "${C}[>]${NC} $1"; }

# ── SSH 헬퍼 ──────────────────────────────────────────────────
vm_run() { ssh "$SSH_HOST" "$@"; }
vm_run_interactive() { ssh -t "$SSH_HOST" "$@"; }

# ══════════════════════════════════════════════════════════════
# Step 0: 인자 검증
# ══════════════════════════════════════════════════════════════
validate_args() {
    if [ -z "$REPO_URL" ]; then
        err "GitHub repo URL이 필요합니다."
        echo ""
        echo "사용법:"
        echo "  bash start-remote.sh <github-repo-url> [project-path]"
        echo ""
        echo "예시:"
        echo "  bash start-remote.sh git@github.com:owner/repo.git"
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════
# Step 1: SSH 접속 확인
# ══════════════════════════════════════════════════════════════
check_ssh() {
    info "Step 1/9 : VM 접속 확인 중... ($SSH_HOST)"

    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" "echo ok" &>/dev/null; then
        err "VM에 접속할 수 없습니다."
        err "확인사항:"
        err "  1. VM이 Running 상태인지 확인 (Azure Portal 또는 az vm show)"
        err "  2. VPN이 켜져있으면 SSH 포트가 차단될 수 있음 → VPN OFF"
        err "  3. ssh $SSH_HOST 으로 수동 접속 테스트"
        err "  4. ~/.ssh/config에 claude-vm 호스트가 등록되어 있는지 확인"
        exit 1
    fi

    log "VM 접속 확인 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 2: VM 필수 패키지 설치 (tmux/node/claude/bun/git)
# ══════════════════════════════════════════════════════════════
install_vm_packages() {
    info "Step 2/9 : VM 필수 패키지 확인 및 설치 중..."

    # tmux/git/unzip + claude remote-control sandbox 의존성(bubblewrap, socat).
    # bubblewrap/socat이 없으면 모바일 새 세션 생성 시 "Allocating sandbox" 단계에서 무한 대기.
    if ! vm_run "command -v tmux && command -v bwrap && command -v socat" &>/dev/null; then
        info "  필수 패키지 설치 중 (tmux/git/unzip/bubblewrap/socat)..."
        vm_run "sudo apt-get update -qq && sudo apt-get install -y -qq tmux unzip git bubblewrap socat" &>/dev/null
        log "  tmux/git/unzip/bubblewrap/socat 설치 완료"
    else
        log "  tmux/bubblewrap/socat 이미 설치됨"
    fi

    # bwrap 용 AppArmor profile (Ubuntu 24.04 unprivileged userns 정책 우회).
    # 미적용 시 bwrap 가 'setting up uid map: Permission denied' 로 실패 → 모바일 sandbox hang.
    if ! vm_run "[ -f /etc/apparmor.d/bwrap ]" &>/dev/null; then
        info "  bwrap AppArmor profile 적용 중..."
        vm_run "sudo tee /etc/apparmor.d/bwrap >/dev/null <<'APPARMOR'
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,
  include if exists <local/bwrap>
}
APPARMOR
sudo systemctl reload apparmor"
        log "  bwrap AppArmor profile 적용 완료"
    else
        log "  bwrap AppArmor profile 이미 적용됨"
    fi

    if ! vm_run "command -v node" &>/dev/null; then
        info "  Node.js 22.x 설치 중..."
        vm_run "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && \
                sudo apt-get install -y -qq nodejs" &>/dev/null
        log "  Node.js 설치 완료"
    else
        log "  Node.js 이미 설치됨 ($(vm_run 'node -v'))"
    fi

    if ! vm_run "command -v claude" &>/dev/null; then
        info "  Claude Code 설치 중..."
        vm_run "sudo npm install -g @anthropic-ai/claude-code" &>/dev/null
        log "  Claude Code 설치 완료"
    else
        log "  Claude Code 이미 설치됨 ($(vm_run 'claude --version 2>/dev/null | head -1'))"
    fi

    if ! vm_run "command -v bun" &>/dev/null; then
        info "  Bun 설치 중..."
        vm_run "curl -fsSL https://bun.sh/install | bash" &>/dev/null
        log "  Bun 설치 완료"
    else
        log "  Bun 이미 설치됨"
    fi

    log "VM 패키지 확인 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 3: Claude Code 로그인 상태 확인
# - .credentials.json이 존재하면 OAuth 토큰이 있다고 간주
# - 미로그인 시 사용자에게 직접 SSH 후 `claude` 실행을 안내하고 종료
#   (스크립트 내부에서 OAuth 흐름을 자동화하기 어렵기 때문)
# ══════════════════════════════════════════════════════════════
check_claude_login() {
    info "Step 3/9 : Claude Code 로그인 상태 확인 중..."

    if vm_run "[ -s ~/.claude/.credentials.json ]" 2>/dev/null; then
        log "Claude Code 로그인 확인 완료"
        return 0
    fi

    err "Claude Code가 로그인되어 있지 않습니다."
    err "VM에 직접 접속해서 한 번 로그인을 완료해주세요:"
    err "  ssh $SSH_HOST"
    err "  claude    # → '/login' 또는 안내되는 OAuth URL을 따라 로그인"
    err ""
    err "로그인 완료 후 이 스크립트를 다시 실행하세요."
    exit 1
}

# ══════════════════════════════════════════════════════════════
# Step 4: GitHub용 SSH key 생성 + 사용자에게 등록 안내
# - ed25519 키를 VM에 생성한다 (~/.ssh/<KEY_NAME>).
# - 공개키를 출력하고 GitHub Settings → SSH keys 또는 repo Deploy keys에
#   추가하라고 안내한다.
# - ssh config에 'github-claude-remote' 호스트 alias를 추가해서 키를 강제 사용.
# - 이미 존재하면 새로 만들지 않는다 (멱등).
# ══════════════════════════════════════════════════════════════
setup_github_ssh_key() {
    info "Step 4/9 : GitHub용 VM SSH key 준비 중..."

    local key_path="\$HOME/.ssh/${VM_GH_KEY_NAME}"

    vm_run "mkdir -p ~/.ssh && chmod 700 ~/.ssh
        if [ ! -f ${key_path} ]; then
            ssh-keygen -t ed25519 -f ${key_path} -N '' -C 'claude-remote-github' >/dev/null
            chmod 600 ${key_path} ${key_path}.pub
        fi
        # ssh config alias (idempotent)
        if ! grep -q 'Host github-claude-remote' ~/.ssh/config 2>/dev/null; then
            cat >> ~/.ssh/config <<EOF

Host github-claude-remote
    HostName github.com
    User git
    IdentityFile ${key_path}
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
EOF
            chmod 600 ~/.ssh/config
        fi"

    local pub_key
    pub_key=$(vm_run "cat ${key_path}.pub")

    # GitHub 인증 가능한 상태인지 먼저 확인 (이미 등록돼있을 수 있음)
    if vm_run "ssh -T -o BatchMode=yes -o ConnectTimeout=8 -i ${key_path} -o IdentitiesOnly=yes git@github.com 2>&1 | grep -qi 'successfully authenticated'"; then
        log "GitHub SSH key 이미 등록됨"
        return 0
    fi

    echo ""
    echo -e "${Y}┌─────────────────────────────────────────────────────────┐${NC}"
    echo -e "${Y}│  GitHub에 아래 공개키를 등록해야 repo clone이 가능합니다.│${NC}"
    echo -e "${Y}└─────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e "${C}1. https://github.com/settings/keys 이동${NC}"
    echo -e "${C}   (조직 정책으로 deploy key가 막혔다면 개인 SSH key로 등록)${NC}"
    echo -e "${C}2. 'New SSH key' 클릭${NC}"
    echo -e "${C}3. Title: claude-vm-azure (자유)${NC}"
    echo -e "${C}4. Key 본문에 아래를 통째로 복사:${NC}"
    echo ""
    echo "${pub_key}"
    echo ""
    read -rp "$(echo -e ${G})등록 끝나면 Enter${NC}: "

    # 재확인
    if ! vm_run "ssh -T -o BatchMode=yes -o ConnectTimeout=8 -i ${key_path} -o IdentitiesOnly=yes git@github.com 2>&1 | grep -qi 'successfully authenticated'"; then
        err "GitHub SSH 인증에 실패했습니다."
        err "공개키가 정확히 등록됐는지, 또는 조직 SSO authorize가 필요한지 확인하세요."
        exit 1
    fi
    log "GitHub SSH key 등록 확인 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 5: 프로젝트 repo clone (또는 갱신)
# - REMOTE_PROJECT 디렉토리에 REPO_URL을 clone한다.
# - 디렉토리가 이미 git repo면 origin URL을 검증하고 fetch만 수행.
# - origin URL은 GIT_SSH_COMMAND를 통해 VM에서 만든 키로 강제.
# ══════════════════════════════════════════════════════════════
clone_project_repo() {
    info "Step 5/9 : repo clone/갱신 중... ($REMOTE_PROJECT)"

    local key_path="\$HOME/.ssh/${VM_GH_KEY_NAME}"

    vm_run "set -e
        TARGET=\"${REMOTE_PROJECT}\"
        # ~ 확장
        eval TARGET=\"\$TARGET\"

        if [ -d \"\$TARGET/.git\" ]; then
            echo '  기존 repo 감지 → fetch만 수행'
            cd \"\$TARGET\"
            GIT_SSH_COMMAND='ssh -i ${key_path} -o IdentitiesOnly=yes' git fetch --all --prune
        else
            # 빈 디렉토리면 rmdir, 비어있지 않으면 에러 처리
            [ -d \"\$TARGET\" ] && rmdir \"\$TARGET\" 2>/dev/null || true
            if [ -d \"\$TARGET\" ]; then
                echo \"디렉토리에 이미 파일이 있습니다: \$TARGET\" >&2
                exit 1
            fi
            GIT_SSH_COMMAND='ssh -i ${key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new' \\
                git clone '${REPO_URL}' \"\$TARGET\"
            cd \"\$TARGET\"
            # 이후 모든 git 작업이 키를 강제하도록 origin URL을 alias 형태로 변환
            ORIGIN=\$(git remote get-url origin)
            ALIAS_URL=\$(echo \"\$ORIGIN\" | sed -E 's|^git@github.com:|github-claude-remote:|')
            git remote set-url origin \"\$ALIAS_URL\"
        fi
        echo '  HEAD: '\$(git -C \"\$TARGET\" log -1 --oneline)"

    log "repo 준비 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 6: Telegram notifier.env 배포
# - 비밀값이므로 Git/Terraform에 절대 저장하지 않는다.
# - 이미 존재하면 스킵 (재설정이 필요하면 VM에서 해당 파일 rm 후 재실행).
# ══════════════════════════════════════════════════════════════
setup_telegram_notifier() {
    info "Step 6/9 : Telegram notifier 설정 중..."

    if vm_run "[ -f ~/.config/claude-remote/notifier.env ]"; then
        log "notifier.env 이미 존재. 건너뜀."
        return
    fi

    echo ""
    info "  Telegram 봇 토큰 (BotFather 발급, 예: 1234567890:ABCDE...)"
    read -rp "  TELEGRAM_BOT_TOKEN: " bot_token

    if [ -z "$bot_token" ]; then
        err "토큰이 비어있습니다."
        exit 1
    fi

    echo ""
    info "  chat_id 확인 방법 (둘 중 택1):"
    echo -e "    ${C}A.${NC} 본인 봇에 메시지 1개 전송 → 아래 URL 접속해서 chat.id 복사"
    echo -e "       https://api.telegram.org/bot${bot_token}/getUpdates"
    echo -e "    ${C}B.${NC} 'userinfobot' 같은 봇에 /start 후 표시되는 'Id'"
    echo ""
    read -rp "  TELEGRAM_CHAT_ID: " chat_id

    if [ -z "$chat_id" ]; then
        err "chat_id가 비어있습니다."
        exit 1
    fi

    vm_run "mkdir -p ~/.config/claude-remote && cat > ~/.config/claude-remote/notifier.env <<EOF
TELEGRAM_BOT_TOKEN=${bot_token}
TELEGRAM_CHAT_ID=${chat_id}
EOF
chmod 600 ~/.config/claude-remote/notifier.env"

    log "notifier.env 배포 완료 (권한 0600)"
}

# ══════════════════════════════════════════════════════════════
# Step 7: ~/.claude.json pre-seed
# - 다음 첫 실행 시 prompt가 안 뜨도록 미리 수락 상태를 박는다:
#     hasTrustDialogAccepted = true   (workspace 신뢰 다이얼로그)
#     remoteControlSpawnMode = same-dir
#     remoteDialogSeen = true
# - claude.json이 없으면 생성, 있으면 해당 키만 갱신 (멱등).
# ══════════════════════════════════════════════════════════════
preseed_claude_config() {
    info "Step 7/9 : ~/.claude.json pre-seed 중..."

    # ~ 확장된 절대 경로를 VM 쪽에서 계산
    local abs_project
    abs_project=$(vm_run "eval echo ${REMOTE_PROJECT}")

    vm_run "python3 - <<PY
import json, os
p = os.path.expanduser('~/.claude.json')
d = {}
if os.path.exists(p):
    with open(p) as f:
        try: d = json.load(f)
        except: d = {}
d.setdefault('projects', {})
d['projects']['${abs_project}'] = {
    'allowedTools': [],
    'mcpContextUris': [],
    'mcpServers': {},
    'enabledMcpjsonServers': [],
    'disabledMcpjsonServers': [],
    'hasTrustDialogAccepted': True,
    'projectOnboardingSeenCount': 1,
    'hasClaudeMdExternalIncludesApproved': False,
    'hasClaudeMdExternalIncludesWarningShown': False,
    'exampleFiles': []
}
d['remoteControlSpawnMode'] = 'same-dir'
d['remoteDialogSeen'] = True
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
print('preseeded for ${abs_project}')
PY"

    log "claude.json pre-seed 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 8: systemd unit + notifier 스크립트를 VM에 배포
# - cloud-init.yaml은 "최초 부팅"에서만 실행된다.
#   이미 프로비저닝된 VM은 cloud-init이 재실행되지 않으므로,
#   레포의 terraform/vm/ 아래 unit 파일과 notify-remote-url.sh를 scp로 직접 배포한다.
# - 멱등: 동일 내용이면 사실상 no-op.
# ══════════════════════════════════════════════════════════════
deploy_vm_services() {
    info "Step 8/9 : systemd unit / notifier 스크립트 VM 배포 중..."

    if [ ! -d "$VM_ASSETS_DIR" ]; then
        err "로컬에서 배포 소스를 찾지 못했습니다: $VM_ASSETS_DIR"
        err "레포 루트에서 이 스크립트를 실행하고 있는지 확인하세요."
        exit 1
    fi

    vm_run "mkdir -p ~/.config/systemd/user ~/.local/share/claude-remote ~/.local/bin ~/.config/claude-remote"

    # systemd unit 5종 (multi-session + token refresh 구조):
    #   - claude-rc@.service              : 라벨별 instance template. 라벨당 tmux 세션 1개 + claude --remote-control
    #   - claude-rc-startup.service       : 부팅 시 sessions.json 따라 모든 라벨 service 를 start
    #   - claude-telegram-trigger.service : Telegram /list /new /kill /url 처리 (multi-session manager)
    #   - claude-token-refresh.service    : OAuth access_token 비대화형 갱신 (oneshot)
    #   - claude-token-refresh.timer      : 4시간마다 token-refresh 발동 (TTL 8h 의 절반)
    # (obsolete: claude-remote-control.service / claude-url-notifier.service — 단일 session 구조)
    scp -q "$VM_ASSETS_DIR/claude-rc@.service" \
           "$VM_ASSETS_DIR/claude-rc-startup.service" \
           "$VM_ASSETS_DIR/claude-telegram-trigger.service" \
           "$VM_ASSETS_DIR/claude-token-refresh.service" \
           "$VM_ASSETS_DIR/claude-token-refresh.timer" \
           "$SSH_HOST:~/.config/systemd/user/"

    scp -q "$VM_ASSETS_DIR/claude-rc-launch.sh" \
           "$VM_ASSETS_DIR/claude-rc-startup.sh" \
           "$VM_ASSETS_DIR/claude-token-refresh.sh" \
           "$VM_ASSETS_DIR/telegram-trigger.py" \
           "$SSH_HOST:~/.local/bin/"
    vm_run "chmod +x ~/.local/bin/claude-rc-launch.sh ~/.local/bin/claude-rc-startup.sh ~/.local/bin/claude-token-refresh.sh ~/.local/bin/telegram-trigger.py"

    local uid
    uid=$(vm_run "id -u azureuser")

    # 과거 버전이 enable 해둔 obsolete service / script 정리
    vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user disable \
        claude-telegram.service claude-remote-control.service claude-url-notifier.service 2>/dev/null || true
        rm -f ~/.config/systemd/user/claude-telegram.service \
              ~/.config/systemd/user/claude-remote-control.service \
              ~/.config/systemd/user/claude-url-notifier.service \
              ~/.local/bin/notify-remote-url.sh \
              ~/.local/bin/telegram-session-trigger.sh"

    vm_run "sudo loginctl enable-linger azureuser"
    vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user daemon-reload"
    vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user enable \
        claude-rc-startup.service claude-telegram-trigger.service claude-token-refresh.timer" &>/dev/null
    # token-refresh timer 즉시 활성화 (--now 대신 명시적 start 로 idempotent 보장)
    vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user start claude-token-refresh.timer" &>/dev/null || true

    log "systemd unit / notifier 스크립트 배포 완료"
}

# ══════════════════════════════════════════════════════════════
# Step 9: 서비스 기동 (또는 재시작 여부 사용자에게 확인)
# ══════════════════════════════════════════════════════════════
start_or_restart_services() {
    info "Step 9/9 : systemd user service 기동 중..."

    local uid
    uid=$(vm_run "id -u azureuser")

    local rc_active
    rc_active=$(vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user is-active claude-rc@main.service 2>/dev/null" || echo "unknown")

    if [ "$rc_active" = "active" ]; then
        warn "claude-rc@main.service 가 이미 실행 중입니다."
        echo ""
        echo "  1) 유지 (현재 세션 그대로)"
        echo "  2) 재시작 (tmux 세션 kill → 새 URL 발급)"
        echo "  3) 취소"
        read -rp "선택 [1/2/3]: " choice
        case "$choice" in
            1) info "현재 세션을 유지합니다." ;;
            2)
                vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user restart claude-rc@main.service"
                log "main 세션 재시작 완료. 잠시 후 Telegram 에 새 URL 도착."
                ;;
            3) info "취소합니다."; exit 0 ;;
            *) err "잘못된 입력입니다."; exit 1 ;;
        esac
    else
        # claude-rc-startup 이 sessions.json 의 모든 라벨에 대해 service 를 start 한다.
        # registry 가 비었으면 startup 이 'main' 을 default 로 추가한다.
        vm_run "XDG_RUNTIME_DIR=/run/user/${uid} systemctl --user start claude-telegram-trigger.service claude-rc-startup.service"
        log "systemd user service 기동 완료 (main 자동 시작)"
    fi
}

# ══════════════════════════════════════════════════════════════
# 완료 안내
# ══════════════════════════════════════════════════════════════
show_status() {
    echo ""
    echo -e "${B}=====================================================${NC}"
    echo -e "${B}  Claude Remote Environment - 구성 완료${NC}"
    echo -e "${B}=====================================================${NC}"
    echo ""
    echo -e "  ${Y}[모바일 접속]${NC}"
    echo -e "  잠시 후 Telegram 봇으로 Remote Control URL이 DM으로 전송됩니다."
    echo -e "  알림이 오지 않으면 아래 'URL 재전송' 명령을 실행하세요."
    echo ""
    echo -e "  ${C}[동작 확인]${NC}"
    echo -e "  서비스 상태   : ssh $SSH_HOST 'systemctl --user status claude-remote-control.service claude-url-notifier.service'"
    echo -e "  tmux 세션 목록: ssh $SSH_HOST 'tmux ls'"
    echo -e "  URL 재전송    : ssh $SSH_HOST 'systemctl --user restart claude-url-notifier.service'"
    echo ""
    echo -e "  ${G}[tmux attach가 필요할 때]${NC}"
    echo -e "  Remote Control: ssh $SSH_HOST -t 'tmux attach -t $TMUX_SESSION_RC'"
    echo -e "  세션 빠져나오기: Ctrl+B → D (프로세스는 계속 실행됨)"
    echo ""
    echo -e "${B}=====================================================${NC}"
    echo ""
}

main() {
    echo ""
    echo -e "${B}=====================================================${NC}"
    echo -e "${B}  Claude Remote Environment Setup${NC}"
    echo -e "${B}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${B}=====================================================${NC}"
    echo ""

    validate_args
    check_ssh
    install_vm_packages
    check_claude_login
    setup_github_ssh_key
    clone_project_repo
    setup_telegram_notifier
    preseed_claude_config
    deploy_vm_services
    start_or_restart_services
    show_status
}

main
