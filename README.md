# Flake Chicken

Flutter Android·웹 약속 관리 앱과 GCP e2-micro VM 한 대의 Go·SQLite 서버입니다.

- 앱: <https://35.212.249.154/>
- iPhone 설치용 QR: <https://35.212.249.154/install.html>
- 상태 확인: <https://35.212.249.154/healthz>
- 요구사항: [REQUIREMENTS.md](REQUIREMENTS.md)
- 서버·인증·알림 운영: [docs/backend.md](docs/backend.md)

약속 작성자만 수정할 수 있습니다. 참여자가 **2명 이상**이고 전원이 파토를 선택하면 취소가 확정됩니다.
그 전에는 본인 선택만 볼 수 있으며, 다른 참여자의 선택에 따른 이벤트도 전송하지 않습니다.
파토난 약속의 삭제는 본인 목록에만 적용됩니다. GMG 모드는 이후 생성·참여하는 약속에만 적용됩니다.

표시 이름 3개와 출발 주소 3개는 기기에 자동 저장합니다. 생성·참여 시 선택한 값의 사본만 서버에 전달합니다.
설치별 공개키와 최초 생성한 랜덤 salt를 SHA-256으로 해시해 식별하며, 개인키 서명으로 인증합니다.
Android Keystore와 브라우저 WebCrypto의 비공개 키를 사용합니다. 기기·브라우저마다 별개 사용자이며 계정 복구는 없습니다.

Google Routes API에 약속 시간을 도착 시간으로 전달해 대중교통 이동시간을 구합니다.
Maps Static 이미지에는 경로 전체와 제공자 표시가 포함됩니다. 지도·이동시간은 메모리에만 보관합니다.
조회 불가 지역·날짜·한도 초과 시 가짜 경로 대신 빈 지도 아이콘이 표시됩니다.

알림은 환경설정에서 켤 수 있으며 시스템 알림만 사용합니다. Android는 FCM, 웹은 Web Push·VAPID를 사용합니다.
iPhone·iPad는 Safari에서 **공유 → 홈 화면에 추가**한 웹앱에서 알림을 켜야 합니다.
앱이 열려 있으면 SSE로 변경을 반영하며, 재연결·복귀 시에도 새로 조회합니다.

## 개발과 검증

Flutter 3.47.9, Go 1.26 이상, JDK 21 환경입니다.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
flutter build web --release --no-wasm-dry-run
(cd server && go test ./...)
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`. ADB 주소는 `adb devices`로 확인합니다.
Android Firebase 공개 설정은 `android/app/google-services.json`에 있습니다. 서버 Maps 키·개인키는 포함하지 않습니다.
APK는 현재 개발용 서명입니다.

기본 앱은 실제 서버에 연결합니다. 테스트에서 주입하는 `AppStore.load(MemoryStorage())`만 오프라인 샘플을 사용합니다.
로컬 서버가 필요하면 `DEVELOPMENT=1 PUBLIC_ORIGIN=http://localhost:8080 DATABASE_PATH=/tmp/flake-dev.db go run .`로 실행합니다.
웹 기기 인증·푸시는 HTTPS 또는 localhost 보안 컨텍스트가 필요합니다. 미리보기 서버는 확인 후 종료해주세요.

## 배포

`deploy/server.env.example`을 참고해 비밀값을 **Git에 포함하지 않는** `build/deploy/server.env`에 작성합니다.
VM과 고정 IP·HTTPS·FCM 발송용 서비스 계정이 준비된 상태에서:

```bash
GO_BIN=/path/to/go deploy/gcp.sh
```

기존 `ctf-cloud-508223` 프로젝트의 `flake-chicken-api` (`us-west1-b`, e2-micro, Debian 12, pd-standard 10GB)에 배포합니다.
서버 DB는 `/var/lib/flake-chicken/app.db`, 서버 환경변수는 `/etc/flake-chicken/server.env`입니다.
배포 시 DB를 백업하고 웹·서버를 교체합니다. 고정 Standard IPv4는 `35.212.249.154`이며 공개 포트는 80·443입니다.
FCM 권한만 부여한 VM 서비스 계정으로 발송하며 다운로드한 서비스 계정 키는 사용하지 않습니다.
IP 인증서는 자동 갱신 타이머가 관리합니다. VM·IPv4·Maps 사용량에는 각 서비스의 과금 정책이 적용됩니다.

```bash
gcloud compute ssh flake-chicken-api --zone=us-west1-b \
  --command='sudo journalctl -u flake-chicken -n 40 --no-pager'
```
