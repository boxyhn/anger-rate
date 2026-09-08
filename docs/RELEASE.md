# AngerRate 배포 절차

`scripts/package.sh`는 SwiftPM release 실행 파일을 macOS 앱 번들로 묶고 DMG를 만듭니다. 기본 빌드는 ad-hoc 서명이므로 개인 테스트에는 쓸 수 있지만 일반 배포용 Developer ID 서명이나 Apple 공증을 대신하지 않습니다.

## 로컬 패키지

```sh
./scripts/package.sh
```

결과:

- `dist/AngerRate.app`
- `dist/AngerRate-0.1.2.dmg`

앱 번들은 `app.angerrate.desktop`, 버전 `0.1.2`(빌드 `3`), 최소 macOS `13.0`, 메뉴 막대 전용 `LSUIElement` 설정으로 생성됩니다.

## Developer ID 서명

Apple Developer 계정과 Keychain에 설치된 `Developer ID Application` 인증서가 필요합니다. 정확한 인증서 이름을 환경 변수로 넘기면 패키징 단계에서 hardened runtime과 타임스탬프를 적용합니다.

```sh
SIGNING_IDENTITY="Developer ID Application: Example Name (TEAMID)" ./scripts/package.sh
codesign --verify --deep --strict --verbose=2 dist/AngerRate.app
codesign -dv --verbose=4 dist/AngerRate.app
```

인증서와 계정은 저장소나 스크립트에 넣지 않습니다.

## Apple 공증

공증에는 외부 Apple 자격 증명이 필요합니다. `notarytool` 프로필은 로컬 Keychain에 한 번 저장합니다.

```sh
xcrun notarytool store-credentials "AngerRate-notary" \
  --apple-id "APPLE_ID" \
  --team-id "TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"

xcrun notarytool submit dist/AngerRate-0.1.2.dmg \
  --keychain-profile "AngerRate-notary" \
  --wait

xcrun stapler staple dist/AngerRate-0.1.2.dmg
xcrun stapler validate dist/AngerRate-0.1.2.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 dist/AngerRate-0.1.2.dmg
```

`APPLE_ID`, Team ID, 앱 암호는 예시 자리표시자입니다. 실제 값은 셸 기록이나 저장소에 남기지 않는 방식으로 입력해야 합니다. 공증이 성공하고 stapling 검증까지 통과하기 전에는 공증된 배포본으로 안내하지 않습니다.

## 배포 전 확인

```sh
swift test
swift build -c release
dist/AngerRate.app/Contents/MacOS/AngerRate --smoke-test
```

추가로 깨끗한 macOS 13 이상 Apple Silicon 사용자 계정에서 첫 실행, 알림 권한, Codex·Claude Code 세션 감지, 첫 진단 취소·실패·적용, 동기화 폴더 연결을 확인합니다. Intel 소스 빌드는 현재 검증 범위에 포함되지 않습니다.
