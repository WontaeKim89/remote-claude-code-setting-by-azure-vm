#!/bin/bash

###############################################################
# setup.sh - Azure VM Claude 원격 개발 환경 최초 셋업 (원클릭)
#
# 팀원이 이 스크립트 하나만 실행하면 아래가 모두 자동 처리된다:
#  1) 로컬 필수 도구 확인 (az CLI, terraform)
#  2) Azure 로그인
#  3) Terraform으로 VM 생성 (이미 있으면 스킵)
#  4) SSH 키 설정 + ~/.ssh/config 자동 등록
#  5) VM 내부 패키지 설치 (Node.js, Claude Code, tmux, Bun)
#  6) Claude Code 로그인
#  7) 완료 안내 (이후 start-remote.sh로 매일 사용)
#
# 사용법: bash setup.sh
# 소요시간: 약 5~10분 (VM 생성 포함)
###############################################################

set -e

# ── 설정값 ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/terraform"
SSH_KEY_DIR="$SCRIPT_DIR/.ssh"
SSH_HOST_ALIAS="claude-vm"
VM_USER="azureuser"
PROJECT_DIR="\$HOME/project"

# ── 색상 ───────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'
C='\033[0;36m'; B='\033[0;34m'; NC='\033[0m'

log()  { echo -e "${G}[OK]${NC} $1"; }
warn() { echo -e "${Y}[!]${NC} $1"; }
err()  { echo -e "${R}[X]${NC} $1" >&2; }
info() { echo -e "${C}[>]${NC} $1"; }

# ══════════════════════════════════════════════════════════════
#  Step 1: 로컬 필수 도구 확인
#  - az CLI: Azure 리소스 관리 (VM 생성, 로그인)
#  - terraform: 인프라 코드 실행 (VM, 네트워크, NSG 생성)
# ══════════════════════════════════════════════════════════════
check_local_tools() {
    info "Step 1/7 : 로컬 필수 도구 확인"

    local missing=0

    if ! command -v az &>/dev/null; then
        err "  az CLI가 설치되어 있지 않다."
        err "  설치: brew install azure-cli"
        missing=1
    else
        log "  az CLI 확인 ($(az version --query '\"azure-cli\"' -o tsv 2>/dev/null))"
    fi

    if ! command -v terraform &>/dev/null; then
        err "  terraform이 설치되어 있지 않다."
        err "  설치: brew install terraform"
        missing=1
    else
        log "  terraform 확인 ($(terraform version -json 2>/dev/null | grep terraform_version | head -1 | tr -d '", ' | cut -d: -f2))"
    fi

    if [ "$missing" -eq 1 ]; then
        err "누락된 도구를 설치 후 다시 실행해라."
        exit 1
    fi
}

# ══════════════════════════════════════════════════════════════
#  Step 2: Azure 로그인
#  - az login: 브라우저가 열리고 Azure 계정으로 인증
#  - 이미 로그인 상태면 스킵
# ══════════════════════════════════════════════════════════════
azure_login() {
    info "Step 2/7 : Azure 로그인 확인"

    if az account show &>/dev/null; then
        local account_name
        account_name=$(az account show --query "name" -o tsv 2>/dev/null)
        log "  이미 로그인됨: $account_name"
    else
        info "  Azure 로그인이 필요하다. 브라우저가 열린다."
        az login
        log "  Azure 로그인 완료"
    fi
}

# ══════════════════════════════════════════════════════════════
#  Step 3: Terraform으로 VM 생성
#  - terraform.tfvars가 없으면 사용자에게 subscription ID 입력받아 생성
#  - terraform init → plan → apply 순서로 실행
#  - 이미 VM이 존재하면 no changes로 스킵됨
# ══════════════════════════════════════════════════════════════
provision_vm() {
    info "Step 3/7 : Azure VM 프로비저닝 (Terraform)"

    cd "$TF_DIR"

    # tfvars 없으면 생성
    if [ ! -f "terraform.tfvars" ]; then
        info "  terraform.tfvars를 생성한다."

        local sub_id
        sub_id=$(az account show --query "id" -o tsv 2>/dev/null)

        if [ -z "$sub_id" ]; then
            err "  Azure Subscription ID를 가져올 수 없다."
            exit 1
        fi

        info "  현재 Subscription: $sub_id"
        read -rp "  이 Subscription을 사용할까? [y/n]: " use_current

        if [ "$use_current" != "y" ] && [ "$use_current" != "Y" ]; then
            read -rp "  Subscription ID 입력: " sub_id
        fi

        cat > terraform.tfvars << EOF
subscription_id = "$sub_id"
EOF
        log "  terraform.tfvars 생성 완료"
    fi

    # terraform init
    info "  terraform init..."
    terraform init -input=false > /dev/null 2>&1
    log "  init 완료"

    # terraform plan
    info "  terraform plan..."
    local plan_output
    plan_output=$(terraform plan -detailed-exitcode 2>&1) || true
    # exit code 0: no changes, 1: error, 2: changes exist
    if echo "$plan_output" | grep -q "No changes"; then
        log "  VM이 이미 존재한다. 생성 스킵."
    else
        info "  VM을 생성한다. (약 2~3분 소요)"
        terraform apply -auto-approve
        log "  VM 생성 완료"
    fi

    cd "$SCRIPT_DIR"
}

# ══════════════════════════════════════════════════════════════
#  Step 4: SSH 설정
#  - Terraform output에서 VM Public IP 가져오기
#  - SSH 키 권한 설정 (600)
#  - ~/.ssh/config에 호스트 자동 등록 (이미 있으면 스킵)
# ══════════════════════════════════════════════════════════════
setup_ssh() {
    info "Step 4/7 : SSH 설정"

    cd "$TF_DIR"

    # Terraform output에서 IP 가져오기
    local vm_ip
    vm_ip=$(terraform output -raw vm_public_ip 2>/dev/null)

    if [ -z "$vm_ip" ]; then
        err "  VM IP를 가져올 수 없다. terraform apply가 정상 완료되었는지 확인해라."
        exit 1
    fi
    log "  VM IP: $vm_ip"

    # SSH 키 권한 설정
    local key_path="$SSH_KEY_DIR/vm_claude_remote_key.pem"
    if [ -f "$key_path" ]; then
        chmod 600 "$key_path"
        log "  SSH 키 권한 설정 완료"
    else
        err "  SSH 키 파일이 없다: $key_path"
        err "  terraform apply가 정상 완료되었는지 확인해라."
        exit 1
    fi

    # ~/.ssh/config에 등록 (이미 있으면 스킵)
    local ssh_config="$HOME/.ssh/config"
    if grep -q "Host $SSH_HOST_ALIAS" "$ssh_config" 2>/dev/null; then
        warn "  ~/.ssh/config에 $SSH_HOST_ALIAS가 이미 등록되어 있다. 스킵."
    else
        mkdir -p "$HOME/.ssh"
        cat >> "$ssh_config" << EOF

# Azure VM - Claude Remote Dev (자동 생성됨)
Host $SSH_HOST_ALIAS
    HostName $vm_ip
    User $VM_USER
    IdentityFile $key_path
    ServerAliveInterval 60
EOF
        chmod 600 "$ssh_config"
        log "  ~/.ssh/config에 $SSH_HOST_ALIAS 등록 완료"
    fi

    cd "$SCRIPT_DIR"
}

# ══════════════════════════════════════════════════════════════
#  Step 5: SSH 접속 대기
#  - VM이 방금 생성되었으면 cloud-init이 실행 중일 수 있다
#  - SSH 접속 가능할 때까지 최대 2분 대기
# ══════════════════════════════════════════════════════════════
wait_for_ssh() {
    info "Step 5/7 : VM SSH 접속 대기"

    local max_try=12
    for i in $(seq 1 $max_try); do
        if ssh -o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
            "$SSH_HOST_ALIAS" "echo ok" &>/dev/null; then
            log "  SSH 접속 확인 완료"
            return 0
        fi
        info "  접속 대기 중... ($i/$max_try)"
        sleep 10
    done

    err "  SSH 접속 실패. VM 상태를 확인해라."
    err "  수동 테스트: ssh $SSH_HOST_ALIAS"
    exit 1
}

# ══════════════════════════════════════════════════════════════
#  Step 6: VM 내부 패키지 설치
#  - cloud-init 완료 대기 후 설치 상태 확인
#  - 누락된 패키지만 추가 설치
# ══════════════════════════════════════════════════════════════
install_vm_packages() {
    info "Step 6/7 : VM 내부 패키지 확인 및 설치"

    # cloud-init 완료 대기 (VM이 방금 생성된 경우)
    info "  cloud-init 완료 대기 중..."
    ssh "$SSH_HOST_ALIAS" "cloud-init status --wait" &>/dev/null || true
    log "  cloud-init 완료"

    # tmux
    if ! ssh "$SSH_HOST_ALIAS" "command -v tmux" &>/dev/null; then
        info "  tmux 설치 중..."
        ssh "$SSH_HOST_ALIAS" "sudo apt-get update -qq && sudo apt-get install -y -qq tmux unzip" &>/dev/null
        log "  tmux 설치 완료"
    else
        log "  tmux 이미 설치됨"
    fi

    # Node.js
    if ! ssh "$SSH_HOST_ALIAS" "command -v node" &>/dev/null; then
        info "  Node.js 설치 중..."
        ssh "$SSH_HOST_ALIAS" "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && \
                sudo apt-get install -y -qq nodejs" &>/dev/null
        log "  Node.js 설치 완료"
    else
        log "  Node.js 이미 설치됨"
    fi

    # Claude Code
    if ! ssh "$SSH_HOST_ALIAS" "command -v claude" &>/dev/null; then
        info "  Claude Code 설치 중..."
        ssh "$SSH_HOST_ALIAS" "sudo npm install -g @anthropic-ai/claude-code" &>/dev/null
        log "  Claude Code 설치 완료"
    else
        log "  Claude Code 이미 설치됨"
    fi

    # Bun
    if ! ssh "$SSH_HOST_ALIAS" "command -v bun" &>/dev/null; then
        info "  Bun 설치 중..."
        ssh "$SSH_HOST_ALIAS" "curl -fsSL https://bun.sh/install | bash" &>/dev/null
        log "  Bun 설치 완료"
    else
        log "  Bun 이미 설치됨"
    fi

    # 프로젝트 디렉토리 생성
    ssh "$SSH_HOST_ALIAS" "mkdir -p $PROJECT_DIR"
    log "  프로젝트 디렉토리 생성 완료 ($PROJECT_DIR)"
}

# ══════════════════════════════════════════════════════════════
#  Step 7: Claude Code 로그인
#  - 로그인 상태 확인 후, 미로그인 시 대화형 로그인 진행
#  - VM에 브라우저가 없으므로 device code 방식
#    (URL이 출력되면 로컬 브라우저에서 열어 인증)
# ══════════════════════════════════════════════════════════════
claude_login() {
    info "Step 7/7 : Claude Code 로그인"

    local auth_status
    auth_status=$(ssh "$SSH_HOST_ALIAS" "claude auth status 2>&1")

    if echo "$auth_status" | grep -qi "logged in\|authenticated\|active"; then
        log "  이미 로그인됨"
        return 0
    fi

    warn "  Claude Code 로그인이 필요하다."
    info "  URL이 표시되면 브라우저에서 열어 인증해라."
    echo ""

    ssh -t "$SSH_HOST_ALIAS" "claude login"

    # workspace trust 자동 승인
    info "  workspace trust 설정 중..."
    ssh -t "$SSH_HOST_ALIAS" "cd $PROJECT_DIR && claude --print 'hello' --permission-mode auto" &>/dev/null || true
    log "  로그인 + workspace trust 완료"
}

# ══════════════════════════════════════════════════════════════
#  완료 안내
# ══════════════════════════════════════════════════════════════
show_complete() {
    echo ""
    echo -e "${G}=====================================================${NC}"
    echo -e "${G}  셋업 완료${NC}"
    echo -e "${G}=====================================================${NC}"
    echo ""
    echo -e "  VM 접속:"
    echo -e "    ${C}ssh $SSH_HOST_ALIAS${NC}"
    echo ""
    echo -e "  Remote Control 시작 (매일 사용):"
    echo -e "    ${C}bash start-remote.sh${NC}"
    echo ""
    echo -e "  또는 수동으로:"
    echo -e "    ${C}ssh $SSH_HOST_ALIAS${NC}"
    echo -e "    ${C}tmux new-session -s remote-control${NC}"
    echo -e "    ${C}cd ~/project${NC}"
    echo -e "    ${C}claude remote-control --name \"my-project\" --permission-mode auto${NC}"
    echo ""
    echo -e "  모바일 접속:"
    echo -e "    QR코드 스캔 또는 ${C}claude.ai/code${NC} 접속"
    echo ""
    echo -e "${G}=====================================================${NC}"
}

# ══════════════════════════════════════════════════════════════
#  메인
# ══════════════════════════════════════════════════════════════
main() {
    echo ""
    echo -e "${B}=====================================================${NC}"
    echo -e "${B}  Claude Remote Dev Environment - 초기 셋업${NC}"
    echo -e "${B}  $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${B}=====================================================${NC}"
    echo ""

    check_local_tools       # 1. az CLI, terraform 확인
    azure_login             # 2. Azure 로그인
    provision_vm            # 3. Terraform으로 VM 생성
    setup_ssh               # 4. SSH 키 + config 설정
    wait_for_ssh            # 5. SSH 접속 대기
    install_vm_packages     # 6. VM 패키지 설치
    claude_login            # 7. Claude Code 로그인

    show_complete
}

main
