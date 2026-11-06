# 서버와 플랫폼 연결

## 인증과 데이터

설치 식별값은 `hex(SHA256(UTF8("flake-chicken-identity-v1\0") || salt[32] || SPKI_P256_public_key))`입니다.
서버는 salt·공개키·해시를 저장하며 하드웨어 ID를 사용하지 않습니다. salt 자체는 인증 비밀이 아닙니다.
2분짜리 일회성 challenge를 개인키로 서명해야 30분 세션을 발급합니다. Android DER·웹 P1363 서명을 검증합니다.
Android 개인키는 Keystore에 두고 백업을 비활성화했습니다. 웹은 IndexedDB에 비추출 CryptoKey를 저장하며
동시 첫 실행 탭은 원자적 삽입으로 하나의 키를 사용합니다. 데이터 삭제나 새 브라우저·기기는 별개 사용자입니다.

Android는 메모리의 Bearer 토큰을, 웹은 Secure·HttpOnly·SameSite=Strict 쿠키를 사용합니다.
서버 DB에는 세션 토큰 해시만 남깁니다. 웹 변경 요청은 정확한 Origin을 검사합니다.
현재 구조는 설치 인증이며 한 사람이 여러 설치를 만드는 것을 막는 본인 인증은 아닙니다.

SQLite WAL·트랜잭션으로 약속·참여·취소·알림 발송 대기열을 함께 저장합니다.
작성자만 수정하며 수정 충돌은 version으로 차단합니다. 생성 요청은 requestId로 중복 방지합니다.
전원 선택 조건은 `참여자 수 >= 2 && 선택 수 == 참여자 수`입니다. 취소는 한 번만 확정하며 되돌릴 수 없습니다.
응답에는 본인의 선택·이름·출발지만 포함합니다. 전원 동의 전 선택 이벤트는 본인의 연결에만 전달합니다.
삭제는 본인의 목록에서 숨기며 다른 참여자와 이미 확정된 결과는 유지합니다.

## 지도

서버 전용 키로 Routes API `TRANSIT`·`arrivalTime=약속 UTC 시간`을 요청합니다.
필드는 `routes.duration,routes.polyline.encodedPolyline`만 요청합니다.
Maps Static에 전체 경로와 출발·도착 마커를 전달해 자동으로 전체 영역을 맞춥니다.
이미지는 잘라내지 않고 표시하며 Google 제공자 표시를 유지합니다. 별도 Google 문구를 붙이지 않습니다.
지도·경로·이동시간은 DB·로컬 환경설정에 저장하지 않습니다.

대중교통 조회 기간은 제공사 기준 과거 7일·미래 100일입니다. 서비스 지역·시간표에 따라 응답이 없을 수 있습니다.
기본 한도는 서버 전체에서 UTC 하루 Routes 100회·Static 100회이며 SQLite에 사용 횟수를 기록합니다.
`MAPS_DAILY_LIMIT`으로 조절합니다. 실패한 공급자 요청도 한도를 소비해 재시도에 따른 비용을 제한합니다.
Maps 키는 VM 고정 IP와 Routes·Maps Static API로 제한했습니다. 브라우저·APK에는 전달하지 않습니다.

## 행정안전부 도로명주소 모바일 팝업

[공식 API 목록](https://business.juso.go.kr/jst/jstAddressApiList)의 도로명주소 **모바일 팝업 API**를 사용합니다.
`JUSO_API_KEY`를 서버 환경 파일에 설정하며, 앱 바이너리나 저장소에는 포함하지 않습니다.
공식 팝업 호출 시 서버가 생성한 폼에 승인키를 넣어 제공사로 POST합니다.
웹은 클릭 시 바로 새 창을 확보하고 Android는 별도 WebView Activity를 엽니다.
웹과 Android 모두 `https://business.juso.go.kr/addrlink/addrMobileLinkUrl.do`를 사용합니다.
공식 모바일 화면에 맞는 모바일 팝업 전용 승인키를 설정합니다.

인증된 `POST /api/address-popup`이 임의 ID와 비밀 토큰을 발급합니다.
`/address-popup/{id}/{token}`이 공식 팝업을 열고 동일 주소에서 선택 결과 POST를 받습니다.
공식 서비스 Origin·비밀 토큰·유효시간·주소 길이를 검사하며, 첫 번째 완료 결과만 저장합니다.
주소 문자열을 HTML·실행 스크립트에 삽입하지 않습니다.
원래 앱이 본인 세션으로 `GET /api/address-popup/{id}`를 조회해 결과를 받습니다.
따라서 모바일 브라우저에서 opener 전달이 안 되어도 앱 복귀 후 결과를 받을 수 있습니다.
선택 후 `DELETE /api/address-popup/{id}`로 삭제하고, 중단된 검색도 최대 10분 뒤 정리합니다.
주소 검색 창과 임시 결과는 SQLite의 `address_popups` 테이블에서 관리합니다.
기존 프로필·다른 약속의 주소 사본은 변경하지 않습니다.

## 시스템 알림

Android는 Firebase Messaging SDK를 사용합니다. 앱이 열려 있어도 Android NotificationManager로만 표시합니다.
백그라운드에서는 FCM notification payload로 표시합니다. 토큰 갱신은 네트워크 조건의 WorkManager 작업으로 서버에 반영합니다.
웹은 Push API·VAPID·자체 서비스 워커(`/push-sw.js`)를 사용하며 앱이 닫혀도 시스템 알림을 표시합니다.
지원 브라우저와 사용자 권한이 필요합니다. iOS 16.4 이상은 홈 화면에 설치한 웹앱에서 지원합니다.
앱 내부 알림 창·토스트·취소 배너는 없습니다. 환경설정에서 권한 상태를 확인하고 알림을 켭니다.

취소 트랜잭션은 참여자별 고유 알림과 발송 작업을 저장합니다. 서버 재시작 뒤에도 작업이 유지되며,
일시 실패는 지수 간격으로 최대 24시간 재시도합니다. 푸시 서비스 수락을 기록하고 같은 OS notification tag를 사용합니다.
분산 네트워크 특성상 전달 횟수·도착 시각 자체를 정확히 보장하지는 않습니다.
Web Push endpoint는 허용한 Google·Mozilla·Apple·Microsoft HTTPS 주소로 제한합니다.

VM에는 `flake-chicken-push@ctf-cloud-508223.iam.gserviceaccount.com`을 연결했고
`roles/firebasecloudmessaging.admin`만 부여했습니다. FCM은 메타데이터에서 단기 OAuth 자격증명을 받습니다.
개인 서비스 계정 JSON 키는 발급하지 않았습니다.

## HTTPS와 운영

기존 외부 IP를 `flake-chicken-api-ip`로 예약했습니다. Caddy가 80·443을 받고 API는 loopback 8080에서만 실행합니다.
Let's Encrypt IP 인증서를 Certbot shortlived 프로필로 발급하며 `flake-certificate-renew.timer`가 3시간마다 갱신 여부를 확인합니다.
배포 훅은 인증서를 Caddy 읽기 권한으로 복사하고 reload합니다. IP 접속의 SNI 부재는 Caddy `default_sni`로 처리합니다.
새 VM 설정은 root 권한으로 `deploy/setup-https.sh`를 실행합니다. 80번 ACME 경로는 유지해야 합니다.

```bash
# VM에서 확인
sudo systemctl status flake-chicken caddy
sudo systemctl list-timers flake-certificate-renew.timer
sudo /opt/flake-certbot/bin/certbot renew --dry-run
sudo sqlite3 /var/lib/flake-chicken/app.db 'PRAGMA integrity_check;'
```

서비스는 DynamicUser·StateDirectory·ProtectSystem=strict로 실행하고 메모리는 최대 192MB입니다.
DB 파일은 0600, 상태 디렉터리는 0700입니다. Maps 키가 들어간 환경 파일은 root 0600입니다.
배포 직전 백업은 `/var/backups/flake-chicken/before-deploy.db`에 덮어씁니다.
이 백업은 같은 VM 안에 있으므로 VM·디스크 손실에 대한 외부 백업은 아닙니다.

## 확인한 범위 (2026-11-07)

Flutter 정적 검사와 20개 테스트, Go 서버 테스트·vet를 통과했습니다.
실제 HTTPS 서버에서 두 설치의 인증·참여·전원 취소·개인별 삭제를 확인했습니다.
Google API의 도착 시간 지정·실제 경로 PNG·이동시간을 확인했습니다.
연결된 Android에서 앱 실행 중·백그라운드 FCM 시스템 알림을 수신했습니다.
같은 실기기의 Chrome에서도 Web Push 공급자를 거쳐 서비스 워커가 시스템 알림을 표시하는 것을 확인했습니다.
브라우저 키의 재실행 유지·비추출 속성과 쿠키 인증도 확인했습니다.
IP 인증서 갱신 dry-run과 DB integrity_check를 통과했습니다. 테스트용 약속·알림은 제거했습니다.

참고: [Android 기기 식별](https://developer.android.com/identity/user-data-ids),
[Android Keystore](https://developer.android.com/privacy-and-security/keystore),
[대중교통 경로](https://developers.google.com/maps/documentation/routes/transit-route),
[Routes 정책](https://developers.google.com/maps/documentation/routes/policies),
[Maps Static](https://developers.google.com/maps/documentation/maps-static/start),
[iOS Web Push](https://webkit.org/blog/13878/web-push-for-web-apps-on-ios-and-ipados/),
[IP 인증서](https://letsencrypt.org/2026/03/11/shorter-certs-certbot).
