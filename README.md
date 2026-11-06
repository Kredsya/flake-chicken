# Flake Chicken

Flutter Android/iOS 카운터와 작은 GCP 서버.

요구사항은 [REQUIREMENTS.md](REQUIREMENTS.md)에 작성합니다.

화면 중앙의 28dp `+` 버튼을 누르면 바로 아래 숫자가 `0 → 1 → 2…`로 증가합니다.
터치 영역은 48dp입니다. 숫자는 앱 메모리에만 있고, 앱을 완전히 다시 실행하면 0으로 돌아갑니다.
현재 카운터는 서버 통신 없이 동작합니다. 서버는 후속 기능을 위한 상태 확인 API만 제공합니다.

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

## iOS (Codemagic)

WSL에서는 iOS를 빌드할 수 없으므로 Codemagic의 macOS 빌드 머신을 사용합니다.
저장소 루트의 `codemagic.yaml`에 `ios-build` 워크플로가 있습니다.
Flutter 버전은 로컬과 같은 `3.47.9`로 고정했습니다.

1. Codemagic에 이 저장소를 연결하고 `master` 브랜치를 선택합니다.
2. **Check for configuration file**을 눌러 설정 파일을 검색합니다.
3. **Start new build**에서 `ios-build` 워크플로를 실행합니다.
4. 의존성 설치, 정적 분석, 테스트, 서명 없는 iOS release 빌드를 순서대로 실행합니다.
5. 성공하면 Artifacts에서 `ios-unsigned.zip`을 다운로드할 수 있습니다.

이 워크플로는 컴파일 확인용입니다. 산출물은 서명되지 않은 `Runner.app`이며,
iPhone 설치나 TestFlight 업로드용 IPA가 아닙니다.
현재 Bundle ID는 `dev.flakechicken.flakeChicken`입니다.

실제 기기 배포나 TestFlight를 사용하려면 Apple Developer Program 가입 후,
Bundle ID 등록과 서명 인증서·프로비저닝 프로파일을 Codemagic에 설정해야 합니다.
TestFlight에는 App Store Connect 앱 등록 및 업로드 인증 설정도 필요합니다.
그 단계에서 서명된 IPA 빌드와 배포 워크플로를 추가합니다.

설정 참고: [Codemagic Flutter 가이드](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/).

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

현재 상태 확인 주소: <http://35.212.249.154:8080/healthz>

```bash
PROJECT_ID=ctf-cloud-508223 bash deploy/gcp.sh
```

Go가 다른 위치에 있으면 `GO_BIN=/path/to/go`를 지정합니다.
스크립트는 `flake-chicken-api` VM과 해당 태그 전용 TCP 8080 방화벽 규칙을 만들고,
바이너리를 전송해 systemd 서비스로 실행합니다. 재실행하면 같은 VM에 배포합니다.
SSH 접속이 가능한 VPC가 필요하며, 기본값은 현재 프로젝트의 `default` 네트워크입니다.

- 리전/존: `us-west1-b` (Oregon)
- 머신: `e2-micro`, 일반 VM 1대
- 부팅 디스크: `pd-standard` 10GB, Debian 12
- 네트워크: Standard tier 외부 IPv4
- VM 서비스 계정 없음, 서비스 메모리 한도 128MB
- 상태 확인: 배포 후 출력되는 `http://<외부 IP>:8080/healthz`
- 숫자 저장, 로그인, TLS는 아직 추가하지 않았습니다.

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
