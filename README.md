# Flake Chicken

Flutter Android/웹 약속 관리 앱과 작은 GCP 서버.

요구사항은 [REQUIREMENTS.md](REQUIREMENTS.md)에 작성합니다.

현재는 서버 연결 없이 동작하는 UI 구현 단계입니다. 약속 목록, 생성·수정, 코드 참여,
프로필과 GMG 모드를 로컬 데이터로 확인할 수 있습니다. 약속과 프로필 변경은 기기에 저장됩니다.
지도 경로·이동시간·초대 조회는 샘플이며, 실제 약속 동기화와 시스템 알림은 아직 연결하지 않았습니다.
자세한 확인 방법은 [UI 미리보기 안내](docs/ui-preview.md)를 참고하세요.

## Android

```bash
flutter pub get
flutter run -d 192.168.219.68:35429
```

ADB 주소가 바뀌면 `flutter devices`에 표시되는 기기 ID를 사용합니다.

```bash
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
```

APK: `build/app/outputs/flutter-apk/app-debug.apk`

## 웹 앱 · iPhone 홈 화면 추가

Codemagic이나 Apple 개발자 계정 없이 Flutter 웹 앱을 서버에서 제공합니다.
iOS 네이티브 프로젝트와 Codemagic 설정은 제거했습니다.

```bash
flutter build web --release
# 로컬 확인 (Chrome 설치 없이 브라우저에서 접속)
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8081
```

`build/web`이 배포 산출물입니다. 로컬 Go 서버로 확인하려면 Go 1.22 이상에서:

```bash
cd server
WEB_DIR="$PWD/../build/web" go run .
```

GCP 배포는 아래의 `deploy/gcp.sh`가 웹 빌드와 Go 서버를 함께 배포합니다.
접속 주소는 `http://35.212.249.154:8080/`입니다.
QR 전용 페이지는 `http://35.212.249.154:8080/install.html`입니다.
QR 파일은 `web/install-qr.svg`이며 서버 외부 IP가 바뀌면 QR의 주소도 갱신해야 합니다.

1. 이 주소를 담은 QR 코드를 iPhone 카메라로 스캔합니다.
2. Safari에서 열고 **공유 → 홈 화면에 추가 → 추가**를 선택합니다.
3. **웹 앱으로 열기** 옵션이 표시되면 켜둡니다.
4. 홈 화면 아이콘으로 앱을 실행합니다.

매니페스트의 `display: standalone`과 Apple 웹 앱 메타 태그를 설정했습니다.
HTTP 접속 방식이며 오프라인 캐시와 서비스 워커는 추가하지 않았습니다.
따라서 실행 시 네트워크 연결이 필요하며, 보안 컨텍스트가 필요한 웹 API는 사용할 수 없습니다.
약속과 프로필은 브라우저의 로컬 저장소에 보관하며, 다른 기기나 브라우저와 공유되지 않습니다.

참고: [Flutter 웹 배포](https://docs.flutter.dev/deployment/web),
[Apple 홈 화면 추가 안내](https://support.apple.com/guide/iphone/iphea86e5236/ios).

## 서버

Go 1.22 이상이 필요합니다. 외부 Go 패키지나 별도 DB는 없습니다.

```bash
cd server
go run .
curl http://localhost:8080/healthz
# {"service":"flake-chicken","status":"ok"}
```

`LISTEN_ADDR`로 리슨 주소를 변경할 수 있습니다. 기본값은 `:8080`입니다.

## GCP 배포

현재 웹 앱 주소: <http://35.212.249.154:8080/>

현재 상태 확인 주소: <http://35.212.249.154:8080/healthz>

```bash
PROJECT_ID=ctf-cloud-508223 bash deploy/gcp.sh
```

Go가 다른 위치에 있으면 `GO_BIN=/path/to/go`를 지정합니다.
Flutter 경로는 `FLUTTER_BIN=/path/to/flutter`로 지정할 수 있습니다.
스크립트는 `flake-chicken-api` VM과 해당 태그 전용 TCP 8080 방화벽 규칙을 만들고,
웹 빌드와 바이너리를 전송해 systemd 서비스로 실행합니다. 재실행하면 같은 VM에 배포합니다.
SSH 접속이 가능한 VPC가 필요하며, 기본값은 현재 프로젝트의 `default` 네트워크입니다.

- 리전/존: `us-west1-b` (Oregon)
- 머신: `e2-micro`, 일반 VM 1대
- 부팅 디스크: `pd-standard` 10GB, Debian 12
- 네트워크: Standard tier 외부 IPv4
- VM 서비스 계정 없음, 서비스 메모리 한도 128MB
- 상태 확인: 배포 후 출력되는 `http://<외부 IP>:8080/healthz`
- 웹 주소: 배포 후 출력되는 `http://<외부 IP>:8080/`
- 약속 동기화, 로그인, 실제 경로 조회와 시스템 알림은 아직 연결하지 않았습니다.

[GCP 무료 한도](https://docs.cloud.google.com/free/docs/free-cloud-features#compute) 내에서는
미국 지정 리전의 e2-micro 월 1대분과 표준 디스크 30GB-month까지 무료입니다.
한도는 결제 계정 전체에서 공유됩니다.
[외부 IPv4 요금](https://cloud.google.com/vpc/network-pricing#ipaddress)은 시간당 $0.005로,
730시간 기준 월 약 $3.65입니다. 트래픽 초과분과 세금은 별도입니다.
임시 외부 IP라 VM을 중지했다가 켜면 주소가 바뀔 수 있습니다.

```bash
# 서비스 로그
gcloud compute ssh flake-chicken-api --project=ctf-cloud-508223 --zone=us-west1-b \
  --command='sudo journalctl -u flake-chicken.service -n 50 --no-pager'

# 사용을 끝내고 VM 및 부팅 디스크 삭제
gcloud compute instances delete flake-chicken-api \
  --project=ctf-cloud-508223 --zone=us-west1-b --delete-disks=boot

gcloud compute firewall-rules delete flake-chicken-api-8080 --project=ctf-cloud-508223
```
