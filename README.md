# Flake Chicken

Flutter Android 카운터와 작은 GCP 서버.

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
