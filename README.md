# 내 주식 대시보드 (stock_app) v0.6.0

네이버 금융을 파싱해 관심 종목의 시세를 모바일에서 확인하고,
목표가 도달 시 로컬 알림을 받는 개인용 Flutter 앱입니다.

## v0.6.0 주요 변경 (2026-07-20)

- **종목 검색 하이브리드 개편**
  - `assets/stocks.csv` 번들 스냅샷으로 초기 검색 즉시 동작 (오프라인 지원)
  - 앱 첫 실행/주 1회 KRX 공식 상장법인목록 자동 갱신
  - 검색 다이얼로그에 “마지막 갱신 시각” 표시 + 수동 갱신 버튼
  - 폐기된 3개 네이버 API 경로 제거

## 주요 기능

- **관심 종목 관리**
  - 6자리 코드 검색 (예: `005930`)
  - 종목명 부분일치 검색 (예: `삼성`, `카카오`)
  - KRX 갱신으로 신규 상장 종목 자동 반영
- **10초 폴링 실시간 시세** (앱 켜짐 상태)
  - 백그라운드 진입 시 자동 중지 → 배터리 절약
- **가격 알림**
  - 상승 / 하락 도달 조건 선택
  - 앱 종료 상태에서도 WorkManager 15분 주기 체크
- **관련 뉴스**
  - Google News RSS 기반 UTF-8 뉴스
  - 인앱 브라우저로 원문 열기 (네이버 앱 딥링크 회피)
  - 읽음 처리, NEW 뱃지, 키워드 필터

## 스택

- Flutter 3.24 / Dart 3.3+
- SQLite (sqflite)
- flutter_local_notifications, workmanager
- url_launcher, shared_preferences

## 빌드

```bash
flutter pub get
flutter build apk --release
```

GitHub Actions로 자동 빌드도 지원합니다 (`.github/workflows/build-apk.yml`).

## 프로젝트 구조

```
lib/
├── main.dart               # 진입점 (알림·카탈로그·백그라운드 초기화)
├── models.dart             # Ticker / PricePoint / AlertDirection
├── db.dart                 # SQLite v4 (watchlist/prices/stocks)
├── stock_catalog.dart      # 카탈로그: 번들 CSV + KRX 갱신
├── scraper.dart            # 시세 크롤러 + 검색 파사드
├── notification_service.dart
├── background_tasks.dart   # WorkManager 15분 주기
├── news_service.dart       # Google News RSS
├── read_history_store.dart
├── news_section.dart
├── ticker_list_page.dart
└── detail_page.dart
assets/
└── stocks.csv              # 초기 종목 목록 스냅샷
```

## 주의사항

- 네이버 금융 시세는 공식 API가 아니므로 개인 학습/모니터링 용도로만 사용하세요.
- 앱 종료 상태의 알림은 Android WorkManager 특성상 최소 15분 주기입니다.
- 실시간 초 단위 알림은 폰이 켜져 있고 앱이 포그라운드일 때만 동작합니다.
- iOS 지원은 별도 macOS + Apple Developer 계정이 필요합니다.
