# 내 주식 대시보드 (stock_app)

네이버 금융을 파싱해 관심 종목의 시세를 모바일에서 확인하고,
목표가 도달 시 로컬 알림을 받는 개인용 Flutter 앱입니다.

## 주요 기능

- **관심 종목 관리**
  - 6자리 코드 검색 (예: `005930`)
  - 회사명 검색 (예: `삼성전자`) — 네이버 자동완성 API 사용
- **10초 폴링 실시간 갱신** (앱이 켜져 있을 때만)
  - 백그라운드 진입 시 자동 중지 → 배터리 소모 없음
- **가격 알림**
  - 상승 도달 알림 / 하락 도달 알림 선택
  - 평단가는 참고용 입력 (검증 없음)
  - 앱 종료 상태에서도 WorkManager 15분 주기 체크
- **관련 뉴스 요약**
  - 상세창에서 최근 뉴스 최대 12건 표시
  - 헤드라인 + 상위 키워드 자동 추출
  - 키워드 칩 필터, NEW 뱃지, 읽음 처리, 회색 처리
  - 링크 탭 → 기본 브라우저로 즉시 열기

## 스택

- Flutter 3.24 / Dart 3.3+
- SQLite (sqflite) — 로컬 저장
- `flutter_local_notifications` — 알림
- `workmanager` — 백그라운드 주기 작업
- `url_launcher` — 외부 브라우저 실행
- `shared_preferences` — 뉴스 열람 이력 저장

## 빌드 방법

### 자동 (권장) — GitHub Actions
1. 이 프로젝트를 GitHub 저장소에 push
2. Actions 탭 → **Build Android APK** 워크플로 실행
3. Artifacts 에서 `app-release.apk` 다운로드

### 로컬
```bash
flutter pub get
flutter build apk --release
# 결과: build/app/outputs/flutter-apk/app-release.apk
```

## 프로젝트 구조

```
lib/
├── main.dart               # 앱 진입점 + 초기화
├── models.dart             # Ticker, PricePoint, AlertDirection
├── db.dart                 # SQLite 저장소 (v3)
├── scraper.dart            # 네이버 금융 크롤러 + 자동완성
├── news_service.dart       # 뉴스 파서 + 키워드 추출
├── read_history_store.dart # 뉴스 읽음 이력 (SharedPreferences)
├── notification_service.dart
├── background_tasks.dart   # WorkManager 백그라운드
├── ticker_list_page.dart   # 목록 화면 (실시간 카드)
├── detail_page.dart        # 상세 화면 (가격/알림/뉴스)
└── news_section.dart       # 뉴스 카드 위젯
```

## 주의사항

- 네이버 금융은 **공식 API가 아닙니다**. 개인 학습/모니터링 용도로만 사용하세요.
- 요청은 자동으로 최소 10초 간격으로 이루어져야 합니다.
- 앱 종료 상태의 알림은 Android WorkManager 특성상 **최소 15분 주기**입니다.
- iOS 지원은 별도 macOS + Apple Developer 계정이 필요합니다.

## 라이선스

개인 학습용 프로젝트입니다.
