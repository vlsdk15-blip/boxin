# 박스인 (BoxIn)

여러 크로스핏·하이록스 센터가 함께 쓰는 **출석·예약·회원권 관리 앱**입니다.
Flutter 코드 하나로 iOS, Android, 웹(PC)에 동시에 내놓습니다.

- 현재 버전: **v0.1.0** (프로젝트 뼈대 + DB 스키마)
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
  features/              화면별 코드 (home, kiosk, ...)
supabase/
  migrations/            DB 스키마 (SQL)
test/
```

## 실행 방법

### 1. 준비물

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 포함)
- [Supabase CLI](https://supabase.com/docs/guides/cli) — DB 마이그레이션 적용용
- Git, VS Code(Flutter 확장)

### 2. 처음 한 번만

`android/`, `ios/`, `web/` 플랫폼 폴더는 아직 저장소에 없습니다. Flutter 설치 후 프로젝트 폴더에서 한 번 생성합니다.

```bash
flutter create --org com.boxin --project-name boxin --platforms=android,ios,web .
flutter pub get
```

### 3. Supabase 연결

1. https://supabase.com 에서 프로젝트 생성
2. `.env.example`을 `.env`로 복사하고 Project URL과 anon key 입력 (`.env`는 커밋되지 않습니다)
3. DB 스키마 적용

```bash
supabase link --project-ref <프로젝트 ref>
supabase db push
```

### 4. 앱 실행

```bash
flutter run -d chrome --dart-define-from-file=.env    # 웹
flutter run --dart-define-from-file=.env              # 연결된 기기·에뮬레이터
flutter test
```

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
회원이 직접 하는 출석·예약·결제는 서버 함수로만 처리할 예정이라 v0.1에서는 아직 열려 있지 않습니다.

## 변경 이력

### v0.1.0 — 2026-10-11

- Flutter 프로젝트 뼈대 (`lib/`, 라우터, `/kiosk` 주소, Supabase 초기화)
- MVP DB 스키마: 테이블 13개, 센터별 RLS 정책
- 가입 시 프로필 자동 생성·전화번호 연결 트리거, 수업 예약 수 자동 집계 트리거
- 서버 함수 `create_center`(센터 생성), `register_member`(코치가 회원 등록)
- README 작성

### 다음 버전 예정

- 로그인(전화번호 인증) → 센터 선택·설정
- 수업 예약 함수(정원 확인, 대기), 출석 함수(앱·위치·키오스크 공통)
- 회원권 만료 알림(pg_cron), PortOne 테스트 결제
