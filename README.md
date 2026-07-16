# 내 주식 대시보드 (독립형 Android 앱)

폰이 **직접** 네이버 금융을 조회해서 SQLite 에 저장하고 그리는
**서버 필요 없는** Flutter 앱입니다.

- ✅ 설치 후 인터넷만 있으면 바로 동작 (PC / 서버 필요 없음)
- ✅ 관심종목 추가·삭제, 1분 자동 갱신, pull-to-refresh, 상세 차트
- ⚠️ **Android 전용** (iOS `.ipa` 는 macOS + Apple 개발자 계정이 필요)
- ⚠️ 네이버 금융은 공식 API 가 아니며 개인 학습/모니터링 용도

---

## 1. APK 를 얻는 3가지 방법

### 방법 A — 로컬에서 직접 빌드 (Flutter SDK 설치되어 있는 경우)

```bash
# 1) Flutter 프로젝트 초기화 파일 자동 생성 (한 번만)
flutter create --platforms=android .

# 2) 의존성 설치
flutter pub get

# 3) 릴리스 APK 빌드
flutter build apk --release

# → build/app/outputs/flutter-apk/app-release.apk
```

`app-release.apk` 를 폰에 옮겨서 설치하면 끝.

### 방법 B — GitHub Actions 로 클라우드 빌드 ⭐ 추천

Flutter SDK 를 로컬에 설치하지 않아도 됩니다.

1. 이 프로젝트를 GitHub 리포지토리에 그대로 push
   (Private / Public 상관 없음)
2. GitHub 웹 → **Actions 탭** → `Build Android APK` 워크플로 선택 →
   **"Run workflow"** 버튼 클릭
3. 5~10 분 뒤 완료되면 실행 상세 페이지의 **Artifacts** 섹션에서
   `app-release-apk.zip` 다운로드 → 압축 풀면 `app-release.apk` 가 있음
4. 폰으로 옮겨 설치

이 리포에 이미 `.github/workflows/build-apk.yml` 이 포함되어 있어 별도 설정 필요 없음.

### 방법 C — 남이 빌드해준 APK 를 받기

주변에 Flutter 개발 환경이 세팅된 사람에게 이 프로젝트를 넘겨 방법 A 로 빌드 부탁.

---

## 2. 폰에 APK 설치하기

`app-release.apk` 를 폰에 옮긴 뒤 파일 앱에서 탭.
"출처를 알 수 없는 앱 설치 허용" 을 한 번 켜줘야 함
(설정 → 앱 → 특별 액세스 → 알 수 없는 앱 설치).

---

## 3. 사용법

- 처음 실행 시 **삼성전자 / SK하이닉스 / 카카오** 3종목이 시드로 등록됨
- 오른쪽 하단 **+** 버튼 → 종목코드 6자리(예: `035420`) 입력 → 🔍 → 확인되면 **추가**
- 리스트 항목을 **왼쪽으로 스와이프** → 삭제
- 항목 탭 → 상세 화면 (현재가 + 시계열 라인차트)
- 앱 열어둔 상태에서 **1분마다 자동 새로고침**, 언제든 pull-to-refresh 가능

---

## 4. 프로젝트 구조

```
lib/
├── main.dart                # 앱 진입점
├── models.dart              # Ticker / PricePoint 데이터 클래스
├── scraper.dart             # 네이버 금융 HTML 파서 (Dart)
├── db.dart                  # sqflite 저장소 (watchlist + prices)
├── ticker_list_page.dart    # 관심종목 리스트 (홈)
└── detail_page.dart         # 종목 상세 + 차트

android/                     # 안드로이드 네이티브 설정 (Gradle, Manifest 등)
.github/workflows/           # 클라우드 자동 APK 빌드 워크플로
```

---

## 5. 알려진 제약

| 항목 | 상태 |
|---|---|
| 앱 종료 후 백그라운드 수집 | ❌ (Android 배터리 최적화로 불안정) |
| iOS | ❌ (Apple 개발자 계정 없이 배포 불가) |
| 네이버 금융 HTML 구조 변경 | ⚠️ scraper.dart 의 정규식을 수정해야 함 |
| 대량/고빈도 요청 | ⚠️ IP 차단 가능. 개인 용도로만 사용 |

향후 확장하고 싶다면 `scraper.dart` 만 교체해서 한국투자증권 KIS Open API
등 공식 소스로 갈아끼우면 나머지(DB / UI) 는 그대로 재사용 가능합니다.
