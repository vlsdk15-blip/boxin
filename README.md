# 박스인 (BoxIn)

여러 크로스핏·하이록스 센터가 함께 쓰는 **출석·예약·회원권 관리 앱**입니다.
Flutter 코드 하나로 iOS, Android, 웹(PC)에 동시에 내놓습니다.

- 현재 버전: **v0.4.0** (수업 시간표, 예약·대기)
- 설계서: https://claude.ai/code/artifact/2aea7b9f-a71f-474e-a6f4-6095bec74ec6

## 사용자

| 역할 | 하는 일 |
| --- | --- |
| 회원 | 출석, 수업 예약, 회원권 조회·구매, 일시정지 요청 |
| 코치 | 수업 운영, 회원 관리, 회원권 판매, 일시정지 승인·직접 설정 |
| 관리자(헤드코치·센터장) | 코치 권한 전부 + 회원권 상품·가격, 다른 지점에 상품 전달, 코치 초대, 키오스크 등록 |
| 키오스크 기기 | 센터 태블릿·PC 브라우저(`/kiosk`)에서 전화번호 뒷자리로 출석 |

한 사람이 여러 센터에 속할 수 있고, 역할은 센터마다 따로 주어집니다.

## 기술 스택

| 영역 | 선택 |
| --- | --- |
| 앱·웹 | Flutter (iOS / Android / Web) |
| 서버·DB | Supabase (PostgreSQL, 센터별 RLS) |
| 실시간 | Supabase Realtime (수업 잔여석) |
| 예약 작업 | Supabase Edge Functions + pg_cron |
| 푸시 알림 | Firebase Cloud Messaging |
| 결제 | PortOne (테스트 모드로 먼저 개발) |

## 폴더 구조

```
lib/
  main.dart              앱 시작점 (Supabase 초기화)
  app.dart               라우터, 테마
  config/env.dart        빌드 시 주입되는 설정
  data/                  Supabase 조회·호출
  features/              화면별 코드 (auth, centers, members, classes, home, kiosk)
supabase/
  config.toml            로컬 개발용 Supabase 설정
  migrations/            DB 스키마 (SQL)
test/
```

## 실행 방법

### 1. 준비물

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 포함)
- [Supabase CLI](https://supabase.com/docs/guides/cli) — DB 마이그레이션 적용용
- Git, VS Code(Flutter 확장)

### 2. 처음 한 번만

```bash
flutter pub get
```

`.env` 파일이 없으면 실행이 실패하므로 아래 3번을 먼저 진행합니다.

### 3. Supabase 연결

**로컬에서 개발할 때** (Docker Desktop 필요, 실제 문자는 발송되지 않음)

```bash
supabase start      # 로컬 Supabase 실행 + DB 스키마 적용
supabase status     # API URL과 publishable key 확인 → .env 에 입력
supabase stop       # 끝낼 때
```

로컬 테스트 로그인 번호는 `010-1111-0001`, `010-1111-0002`, `010-2222-0003`이고 인증번호는 모두 `123456`입니다(`supabase/config.toml`).

**실제 서버에 연결할 때**

1. https://supabase.com 에서 프로젝트 생성
2. `.env.example`을 `.env`로 복사하고 Project URL과 anon key 입력 (`.env`는 커밋되지 않습니다)
3. DB 스키마 적용

```bash
supabase link --project-ref <프로젝트 ref>
supabase db push
```

### 4. 앱 실행

```bash
flutter run -d edge --dart-define-from-file=.env      # 웹 (Chrome이 있으면 -d chrome)
flutter run --dart-define-from-file=.env              # 연결된 기기·에뮬레이터
flutter test
```

VS Code에서는 실행 및 디버그(F5)에서 `boxin (web)` 또는 `boxin (device)`를 고르면 같은 설정으로 실행됩니다.
Android 앱 빌드에는 Android Studio(Android SDK), iOS 앱 빌드에는 Mac과 Xcode가 필요합니다.

## DB 구조 (v0.1)

`supabase/migrations/20261011000000_mvp_schema.sql`

| 테이블 | 내용 |
| --- | --- |
| `brands` | 체인(브랜드), 대표 관리자 |
| `centers` | 센터. `brand_id`(없으면 단독 센터), 주소, 좌표, 출석 반경 |
| `profiles` | 사람. 이름, 전화번호, 푸시 토큰. 코치가 먼저 등록하고 나중에 가입 시 전화번호로 연결 |
| `memberships` | 센터 소속과 역할(회원/코치/관리자), 회원번호 |
| `pass_products` | 회원권 상품. 기간제/횟수제, 사용 만료, 전달받은 원본 상품 |
| `passes` | 발급된 회원권. 시작·종료일, 남은 횟수, 상태 |
| `pass_holds` | 일시정지 요청·승인 |
| `classes` | 수업. 코치, 시작 시간, 정원, 종류(크로스핏/하이록스), 예약 수 |
| `bookings` | 수업 예약(예약/대기/취소) |
| `attendances` | 출석. 방식(앱/위치/키오스크/코치) |
| `kiosk_devices` | 키오스크 기기 토큰(해시 저장) |
| `payments` | 결제(앱 결제/현장), PG 거래번호, 상태 |
| `product_transfers` | 지점 간 회원권 상품 전달 |

모든 센터 데이터에는 `center_id`가 있고, RLS로 자기 센터 데이터만 보입니다.
회원이 직접 하는 예약은 서버 함수(ook_class)로 처리하고, 출석·결제도 같은 방식으로 추가할 예정입니다.

## 변경 이력

### v0.4.0 — 2026-10-12

- 수업 시간표 화면: 다가오는 수업을 날짜별로 표시, 남은 자리 실시간 반영
- 수업 예약·취소. 정원이 차면 대기로 등록되고, 취소가 생기면 대기 1번이 자동 예약
- 코치·관리자: 수업 추가(날짜·시간·종류·정원·매주 반복), 길게 눌러 삭제
- DB: 예약 함수 `book_class`, `cancel_booking` (정원 확인을 서버 한 곳에서 처리, 회원은 유효한 회원권 필요)
- Android 디버그 빌드 확인
### v0.3.0 — 2026-10-12

- 센터 홈: 역할에 따라 회원 관리(코치·관리자), 센터 설정(관리자) 메뉴 표시
- 센터 설정 화면: 이름, 주소, 위도·경도, 출석 반경
- 회원 관리 화면: 회원 목록, 이름·전화번호로 회원 등록(앱 미가입 표시)
- 실서버(Supabase)에 DB 스키마 적용, VS Code에 실서버 실행 항목 추가
### v0.2.0 — 2026-10-12

- 전화번호 인증 로그인 화면, 로그인 여부에 따른 화면 이동
- 첫 로그인 시 이름 입력
- 센터 선택 화면: 내가 속한 센터와 역할 표시, 센터 만들기(만든 사람이 관리자)
- 로컬 개발용 Supabase 설정(`supabase/config.toml`)과 테스트 로그인 번호
### v0.1.0 — 2026-10-11

- Flutter 프로젝트 뼈대 (`lib/`, 라우터, `/kiosk` 주소, Supabase 초기화)
- Android·iOS·웹 플랫폼 폴더 생성 (앱 ID `com.boxin.boxin`), VS Code 실행 설정
- MVP DB 스키마: 테이블 13개, 센터별 RLS 정책
- 가입 시 프로필 자동 생성·전화번호 연결 트리거, 수업 예약 수 자동 집계 트리거
- 서버 함수 `create_center`(센터 생성), `register_member`(코치가 회원 등록)
- README 작성

### 다음 버전 예정

- 회원권 상품·판매, 내 회원권 화면
- 출석 함수(앱·위치·키오스크 공통), 키오스크 화면
- 회원권 만료 알림(pg_cron), PortOne 테스트 결제
