# Troubleshooting

## SSH 접속 관련

### SSH timeout (Connection timed out)
- VPN이 켜져있으면 outbound 22번 포트가 차단될 수 있다. VPN OFF 후 재시도.
- VM이 Stopped 상태인지 확인: Azure Portal > VM > Overview > Status
- 포트 확인: `nc -zv <IP> 22 -w 5`

### Permission denied (publickey)
- SSH 키 파일을 지정하지 않은 경우: `ssh -i ~/.ssh/vm_claude_remote_key.pem azureuser@<IP>`
- 키 파일 권한 문제: `chmod 600 ~/.ssh/vm_claude_remote_key.pem`
- ~/.ssh/config에 IdentityFile이 올바른 경로인지 확인

## Claude Code 관련

### Workspace not trusted
- 해당 디렉토리에서 `claude`를 먼저 실행하여 trust 승인 필요
- `cd ~/project && claude` → trust 승인 → `/exit` → 다시 remote-control 실행

### 로그인 URL이 잘리는 문제
- 터미널에 `c to copy` 안내가 있으면 `c` 키를 눌러 클립보드에 전체 URL 복사
- 또는 `claude login --url-only`로 URL만 출력

### 잘못된 OAuth 요청 (redirect_uri 누락)
- URL이 줄바꿈으로 잘려 복사된 것이 원인. 전체 URL을 정확히 복사해야 한다.

## VM 관련

### VM이 자동으로 꺼짐
- 포털 > VM > Activity log에서 "Deallocate Virtual Machine" 이벤트 확인
- Initiated by가 "Azure Lab Services"면 조직 정책에 의한 종료
- Operations > Auto-shutdown 설정 확인 후 Off로 변경
- 자동 복구: systemd 서비스 등록 (Obsidian 문서 참고)

### VM 재시작 후 tmux 세션이 사라짐
- tmux 세션은 메모리에서만 존재하므로 VM 재시작 시 소멸
- 재시작 후 수동: `tmux new-session -s remote-control` → `claude remote-control`
- 자동화: systemd 서비스 등록

## npm 설치 관련

### EACCES: permission denied
- `sudo npm install -g @anthropic-ai/claude-code`로 설치 (sudo 필요)

### unzip is required to install bun
- `sudo apt install -y unzip` 후 Bun 재설치
