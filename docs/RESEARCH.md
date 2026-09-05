# 구현 근거 / 2026-09-05

- [OpenAI Codex non-interactive](https://learn.chatgpt.com/docs/non-interactive-mode): 저장된 인증을 활용하는 exec, ephemeral, schema, JSON 출력. developers.openai.com/codex/noninteractive에서 공식 리다이렉트 확인.
- [Claude Code CLI](https://code.claude.com/docs/en/cli-reference): print, tools 비활성화, JSON schema. 실행 전에 설치된 CLI help에서 필수 옵션 지원 여부를 검사한다.
- [Apple MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra): 메뉴 막대 상주 및 window 스타일 SwiftUI 패널.
- [Apple 알림 권한](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications): 권한을 요청하고 시스템 설정을 존중한다.

로컬 검증: Swift6.3.3 / Apple Silicon / macOS26, deployment target macOS13. Codex0.148.0, Claude Code2.1.212. Codex 합성 입력 실호출 성공. Claude 인증 오류 안내 확인; 실제 분석 성공은 미검증. 로그 JSONL은 안정적인 공개 API가 아니므로 두 Codex 레코드 형식과 Claude 사용자 레코드를 합성 fixture로 검증한다.

제품 판단: 내부 점수0–100은 언어 신호에 기반한 지표이며 실제 감정의 확률이 아니다. 화면에서는36.5–100°C 또는97.7–212°F로 표시한다. 5분 반감기와 표현별5–50점은 초기 휴리스틱으로, 사용자가 기준표에서 조정한다. 의학적 효과나 정확도를 검증했다는 주장은 하지 않는다.
