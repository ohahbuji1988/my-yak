# My Yak 상용 배포 전 QA 실행 지시서

> 프로젝트: 우리아이 안심 복약 앱 (My Yak)  
> 대상: FastAPI 백엔드 + Flutter 프론트엔드 + Gemini AI  
> 목적: 소아 의학 안전성, 복약량 계산, 다자녀 상태 분리, 장애 대응 및 UX를 상용 배포 전 검증

---

## 0. AI 에이전트 작업 원칙

너는 시니어 풀스택 아키텍트이자 QA 엔지니어다. 본 프로젝트는 영유아 복약 안전과 관련되므로, 단순한 기능 정상 동작보다 **잘못된 약품 인식·용량 계산·복약 안내를 방지하는 것**을 최우선으로 한다.

반드시 다음 원칙을 지켜라.

1. 작업 시작 전에 프로젝트 구조와 관련 소스코드를 전체적으로 확인한다.
2. 현재 동작을 임의로 추측하지 않는다. 실제 코드, 테스트, 실행 결과를 근거로 판단한다.
3. 수정 전에 Git 상태를 확인하고, 가능하면 별도 브랜치 또는 커밋을 생성한다.
4. 의료 기준을 임의로 만들어 적용하지 않는다.
5. 공식 의약품 허가사항 또는 검증된 임상 기준을 확인하지 못하면 `확인 필요` 상태로 처리한다.
6. AI의 confidence 점수를 의학적·약학적 정확도 보증으로 간주하지 않는다.
7. OCR 또는 약품 식별이 실패한 경우 임의의 데모 약품·용량·복용 횟수·복용 일수를 생성하지 않는다.
8. 코드 수정 후 관련 테스트, 정적 분석, 서버 기동 및 빌드 검증을 실행한다.
9. 테스트를 실행하지 못한 경우 성공으로 보고하지 말고, 실행하지 못한 이유를 명시한다.
10. 각 작업 단계에서 변경 파일, 변경 이유, 테스트 결과, 남은 위험을 보고한다.
11. 위험한 복약 안내를 자동 확정하지 말고, 불확실한 경우 명확한 사용자 확인 및 의료진·약사 상담 안내를 제공한다.
12. 기존 데이터를 삭제하거나 기존 기능을 크게 변경하기 전에 영향 범위를 설명하고 백업 또는 마이그레이션 계획을 제시한다.

---

## 1. 작업 모드 및 진행 순서

### Phase 0 — READ-ONLY 진단

먼저 코드 수정 없이 다음을 수행한다.

- 디렉터리 구조 확인
- FastAPI 엔트리포인트 확인
- Flutter 엔트리포인트 확인
- 약품 데이터 모델 및 저장 구조 확인
- OCR → 약품 매칭 → AI 보정 → 용량 계산 → 결과 표시 전체 흐름 추적
- 복약 이력 및 다자녀 프로필 데이터 흐름 추적
- 기존 테스트 및 실행 스크립트 확인
- 잠재적 Critical/High 이슈 목록화

진단 결과를 다음 형식으로 보고한다.

| ID | 파일/함수 | 재현 조건 | 실제 영향 | 위험도 | 수정 계획 |
|---|---|---|---|---|---|

READ-ONLY 진단과 계획 보고가 끝난 후에만 코드 수정에 들어간다.

---

# 2. Critical 안전성 수정 항목

## MED-01. OCR 실패 시 임의 데이터 생성 금지

### 점검 대상

- OCR 결과가 빈 배열인 경우
- OCR API timeout
- 이미지 손상 또는 지원하지 않는 MIME type
- OCR 결과의 필드 누락
- 약품명이 불명확하거나 confidence가 낮은 경우
- 이미지에서 약품명·함량·제형을 식별하지 못한 경우

### 금지 사항

다음과 같은 fallback을 사용하지 않는다.

```python
if not extracted_drugs_raw:
    extracted_drugs_raw = [
        {
            "scanned_name": "코미시럽",
            "dose_unit": 4.0,
            "freq_per_day": 3,
            "days": 3,
        }
    ]
```

### 요구 사항

- OCR 실패를 성공 분석으로 처리하지 않는다.
- 분석 상태를 `OCR_EXTRACTION_FAILED` 또는 이에 준하는 명확한 상태로 반환한다.
- 사용자에게 재촬영 또는 직접 입력을 안내한다.
- OCR 실패와 약품 미확인, API 장애를 서로 다른 오류 코드로 구분한다.
- 실패 시 약품·용량·횟수·일수를 임의로 생성하지 않는다.
- 실패 상태가 Flutter UI에서 위험하지 않게 표시되는지 테스트한다.

### 권장 예시

```python
if not extracted_drugs_raw:
    raise HTTPException(
        status_code=422,
        detail={
            "code": "OCR_EXTRACTION_FAILED",
            "message": (
                "약품 정보를 정확히 읽지 못했습니다. "
                "약봉투 또는 처방전을 다시 촬영해 주세요."
            ),
        },
    )
```

---

## MED-02. Gemini AI 자동 보정 안전성

### 점검 대상

- `deduce_drug_with_gemini`
- `suggested_db_key`
- AI confidence 처리
- 자동 보정 버튼 및 결과 저장 로직
- AI가 생성한 약품명·성분·함량·제형·용량 처리

### 요구 사항

1. AI 추론 결과를 공식 약품 식별 결과로 자동 확정하지 않는다.
2. 다음 항목을 독립적으로 검증한다.
   - 약품명
   - 주성분
   - 함량
   - 제형
   - 공식 허가 데이터 식별자
   - 제조사 또는 품목 정보가 필요한 경우 해당 정보
3. AI confidence 값만으로 `EXACT`, `VERIFIED`, `SAFE` 등의 상태를 부여하지 않는다.
4. 공식 데이터 검증 전에는 용량 분석을 확정하지 않는다.
5. 불확실한 약품은 `IDENTIFICATION_REQUIRED` 또는 `UNVERIFIED_DRUG` 상태로 처리한다.
6. 자동 보정 시 원본 입력의 다음 값을 절대 임의로 변경하지 않는다.
   - 원래 약품명
   - 1회 용량
   - 1일 횟수
   - 복용 일수
   - 복용 시간
7. AI가 용량·횟수·복용 일수를 임의로 생성하지 못하게 한다.
8. 자동 보정 전후의 변경 내역을 사용자에게 보여주고 명시적 확인을 받는다.
9. 사용자가 확인하지 않은 보정 결과는 복약 분석에 확정 데이터로 사용하지 않는다.

### 금지 예시

```dart
ScannedDrugItem(
  scannedName: targetName,
  doseUnit: 1.0,
  freqPerDay: 2,
  days: 3,
)
```

### 권장 원칙

```dart
ScannedDrugItem(
  scannedName: verifiedTargetName,
  doseUnit: originalDoseUnit,
  freqPerDay: originalFreqPerDay,
  days: originalDays,
)
```

단, 원본 값을 보존하는 것만으로 충분하지 않다. `verifiedTargetName`이 실제 공식 약품 데이터와 일치하는지 반드시 별도 검증한다.

---

## MED-03. 소아 용량 계산 엔진

### 점검 대상

- `dosage_engine.py`
- `DrugInfo`
- `child_min_mg_kg`
- `child_max_mg_kg`
- `child_daily_limit_mg_kg`
- 1회 용량 및 1일 누적량 계산
- 연령·체중·제형·적응증별 예외

### 반드시 분리할 검증 항목

- 연령 범위
- 체중 범위
- 1회 권장 용량
- 1회 최대 절대량
- 1일 권장 용량
- 1일 최대 절대량
- mg/kg 기준
- 최대 투여 횟수
- 최소 투여 간격
- 제형 및 농도
- 적응증
- 금기 및 주의사항
- 처방전 용법과의 일치 여부

### 요구 사항

1. 1회 용량과 1일 누적량을 별도로 계산한다.
2. 단순한 `mg/kg` 값만으로 안전성을 확정하지 않는다.
3. 공식 기준이 없거나 데이터가 불완전하면 `확인 필요` 상태로 처리한다.
4. 120% 초과 경고를 모든 약품에 무조건 적용하지 않는다.
5. 120% 기준의 근거, 적용 대상, 단위 및 반올림 방식을 문서화한다.
6. 120% 초과는 임상적 독성 판정과 동일한 의미로 표현하지 않는다.
7. 0 이하 또는 비정상적으로 큰 체중·용량·횟수·일수 입력을 거부한다.
8. 부동소수점 및 반올림으로 인해 경계값 판정이 바뀌지 않도록 테스트한다.
9. 계산 결과에 기준 데이터 버전 또는 출처를 추적할 수 있도록 한다.

### 권장 모델 예시

```python
@dataclass
class PediatricDoseRule:
    min_age_months: int | None
    max_age_months: int | None
    min_weight_kg: float | None
    max_weight_kg: float | None

    recommended_single_mg_kg: float | None
    max_single_mg: float | None
    max_daily_mg: float | None
    max_daily_mg_kg: float | None

    max_doses_per_day: int | None
    interval_hours: float | None
    formulation: str
    indication: str
```

---

## MED-04. 해열제 교차복용 계산기

### 점검 대상

- `antipyretic_calculator.py`
- 동일 성분 및 동일 계열 간격
- 이종 성분 간격
- 1일 최대량
- 실제 복용 이력
- 복합 감기약 및 성분 중복
- 일반형·서방형·시럽·정제 구분

### 요구 사항

1. 시간 간격을 모든 약품에 고정값으로 적용하지 않는다.
2. 성분·제형·연령·허가사항에 따른 기준을 구분한다.
3. 실제 복용 이력을 기반으로 당일 누적량을 계산한다.
4. 다른 보호자가 투여한 기록 등 누락 가능성을 고려한다.
5. 동일 성분의 다른 브랜드 또는 복합제 중복을 탐지한다.
6. 1회 용량, 당일 누적량, 다음 가능 시각을 별도 계산한다.
7. 실제 복용 기록이 누락된 경우 안전한 결과로 확정하지 않는다.
8. 단순히 2시간 또는 4시간이 지났다는 이유만으로 자동 복용을 권장하지 않는다.
9. 추가 복용이 적절한지 여부와 단순 시간 계산을 구분한다.
10. 과다 복용 가능성이 있으면 추가 투여를 중단하고 의료진·약사 또는 적절한 의료기관에 확인하도록 안내한다.
11. 응급 증상 안내는 의학적으로 검토된 문구를 사용한다.

### 권장 모델 예시

```python
@dataclass
class DoseEvent:
    drug_id: str
    child_id: str
    ingredient: str
    formulation: str
    dose_mg: float
    administered_at: datetime
```

```python
@dataclass
class DoseSafetyResult:
    allowed: bool
    severity: str
    reasons: list[str]
    next_allowed_at: datetime | None
    daily_total_mg: float
    daily_limit_mg: float | None
```

---

# 3. 아키텍처 및 신뢰성

## ARCH-01. 다자녀 프로필 데이터 격리

### 테스트 프로필

- 하준이: 9.2kg
- 서아: 14.5kg

### 점검 대상

- `didUpdateWidget`
- `initState`
- `setState`
- 프로필 선택 상태
- 복약 일정
- 복약 완료 여부
- 처방 목록
- 복용 이력
- AI 분석 결과
- 캐시 및 로컬 저장소
- API 요청의 `childId`

### 요구 사항

1. 이름 기반 하드코딩을 제거한다.
2. 모든 복약 데이터에 안정적인 `childId`를 포함한다.
3. 프로필 전환 시 이전 아이의 상태가 표시되지 않도록 한다.
4. 체중 변경 시 관련 계산 결과를 무효화하거나 재계산한다.
5. 복약 완료 상태를 다음과 같이 분리한다.

```text
childId + medicationId + scheduledAt
```

6. `didUpdateWidget`에서 필요한 상태를 모두 갱신한다.
7. 비동기 요청이 이전 아이의 결과를 현재 선택된 아이에게 덮어쓰지 못하게 한다.
8. 화면이 dispose된 이후 `setState`가 호출되지 않도록 한다.
9. 프로필 전환 중 로딩·오류·빈 상태를 명확히 표시한다.

### 권장 모델 예시

```dart
class MedicationRecord {
  final String id;
  final String childId;
  final String drugId;
  final double dose;
  final int frequency;
  final DateTime scheduledAt;
  final bool isCompleted;
}
```

---

## ARCH-02. FastAPI 비동기 및 부분 실패 처리

### 점검 대상

- `asyncio.gather`
- Gemini API 호출
- OCR 호출
- 병렬 약품 분석
- 예외 전파
- 요청 취소 및 타임아웃

### 요구 사항

1. 개별 약품 분석 실패와 전체 요청 실패를 구분한다.
2. 부분 결과를 반환할 경우 누락된 약품을 명확히 표시한다.
3. 불완전한 분석 결과를 정상 완료로 표시하지 않는다.
4. 예외 유형을 다음과 같이 구분한다.
   - timeout
   - connection error
   - rate limit
   - invalid response
   - authentication error
   - validation error
   - unknown error
5. `asyncio.gather` 사용 시 예외 처리 정책을 명시한다.
6. 실패 약품, 오류 코드, 재시도 가능 여부를 기록한다.
7. 로그에 개인정보·처방전 이미지·민감한 약품 정보를 불필요하게 남기지 않는다.

### 권장 검토 예시

```python
results = await asyncio.gather(
    *tasks,
    return_exceptions=True,
)

for result in results:
    if isinstance(result, Exception):
        # 해당 약품을 실패 상태로 기록하고
        # 전체 분석의 완전성을 false로 처리
        ...
```

`return_exceptions=True`를 적용하더라도 실패한 약품을 누락한 채 정상 분석으로 표시하지 않는다.

---

## ARCH-03. Gemini API timeout, retry 및 fallback

### 요구 사항

1. 연결 및 응답 timeout을 명확히 설정한다.
2. 재시도 가능한 오류와 재시도하면 안 되는 오류를 구분한다.
3. 지수 백오프와 최대 재시도 횟수를 적용한다.
4. 무한 재시도를 금지한다.
5. API rate limit 및 quota 초과를 처리한다.
6. AI 장애 시 임의의 약품 또는 용량을 생성하지 않는다.
7. AI 장애 시 공식 데이터 기반 기능과 AI 의존 기능을 구분한다.
8. 실패 상태와 재시도 가능 여부를 UI에 전달한다.
9. API 키 및 민감정보가 로그에 노출되지 않도록 한다.
10. 장애 발생률, timeout 횟수, 응답 지연을 관찰할 수 있도록 한다.

---

## ARCH-04. Python import, 타입 및 런타임 오류

### 우선 점검

- `List`, `Dict`, `Optional`, `Any` 등 타입 import
- Pydantic 모델과 실제 JSON 응답의 타입 일치
- `None` 처리
- 날짜·시간대 처리
- 숫자형 문자열 파싱
- 빈 배열 및 빈 객체
- 예외 발생 시 응답 스키마
- 실제 모듈 import 및 서버 기동

### 예시

```python
from typing import Optional, Dict, Any, List
```

### 실행해야 할 검증

```bash
python -m compileall .
python -c "import <실제_모듈>"
```

프로젝트에 존재하는 실제 실행 명령을 먼저 확인하고, 해당 명령으로 서버를 기동한다.

---

# 4. Flutter UI/UX 및 접근성

## UX-01. 급박한 상황의 시각적 계층 구조

### 요구 사항

위험 또는 확인 불가 상태에는 다음 세 요소가 있어야 한다.

1. 현재 상태
2. 상태의 이유
3. 사용자가 취해야 할 행동

색상만으로 상태를 구분하지 않는다. 텍스트, 아이콘, 접근성 라벨을 함께 제공한다.

### 상태 예시

- 확인 완료
- 추가 확인 필요
- 약품 식별 불가
- 용량 계산 불가
- 과다 복용 가능성
- 의료진·약사 확인 필요
- 응급 증상 안내

`SAFE`, `WARNING`, `HIGH`, `LOW`, `UNKNOWN` 같은 내부 상태값을 사용자에게 그대로 노출하지 말고, 검토된 한국어 안내로 변환한다.

---

## UX-02. 오늘의 복약 일정

### 점검 사항

- 실제 처방 데이터와 화면 일정의 연결 여부
- 사용자가 입력한 일정과 앱이 계산한 일정의 구분
- 복용 완료 체크의 저장 및 복구
- 아이 전환 시 완료 상태 분리
- 중복 클릭 방지
- 오프라인 상태에서의 처리
- 서버 동기화 충돌
- 시간대 및 날짜 변경
- 자정 전후 일정 처리
- 처방 변경 시 기존 일정 처리

### 요구 사항

1. 하드코딩된 데모 일정은 운영 모드에서 사용하지 않는다.
2. 일정의 출처를 표시한다.
3. 앱이 산정한 일정이 처방 지시를 대체하지 않는다는 점을 명확히 한다.
4. 완료 체크는 서버 또는 로컬 저장 결과를 확인한 후 확정한다.
5. 저장 실패 시 완료된 것처럼 표시하지 않는다.

---

# 5. 우선순위별 버그 분류

## Critical / High

- OCR 실패 시 임의 약품 데이터 생성
- AI 추론 결과의 자동 확정
- AI 자동 보정 중 용량·횟수·일수 임의 변경
- 실제 복용 이력 없는 해열제 누적량 계산
- 동일 성분·복합제 중복 검증 부족
- 소아 연령·제형·적응증별 기준 부족
- 확인되지 않은 약품에 대한 확정적 용량 안내
- 다자녀 간 복약 정보 혼선
- Python import 또는 서버 기동 오류
- 실패한 분석을 정상 완료로 표시

## Medium

- `asyncio.gather` 부분 실패 처리 부족
- Gemini timeout·retry·backoff 부족
- API 응답 타입 검증 부족
- 복약 일정의 출처 표시 부족
- 복약 완료 상태 동기화 부족
- 로그 및 모니터링 부족
- 접근성 라벨 및 색상 외 상태 표시 부족

## Low

- 문구 및 시각적 일관성
- 내부 상태 코드의 사용자 친화적 변환
- 테스트 커버리지 확대
- 개발 문서 및 변경 이력 정리

---

# 6. 테스트 계획

## 6.1 백엔드 테스트

최소한 다음 테스트를 작성하고 실행한다.

- 정상 OCR 결과
- 빈 OCR 결과
- OCR timeout
- OCR 필드 누락
- 미등록 약품
- AI confidence가 높은 오인식
- AI API 장애
- 공식 약품 데이터 검증 실패
- 0 또는 음수 체중
- 비정상 용량
- 1회 상한 초과
- 1일 누적량 초과
- 경계값 및 반올림
- 복합제 성분 중복
- 복용 이력 누락
- 다자녀 `childId` 분리
- API 응답 타입 불일치
- 부분 분석 실패

## 6.2 Flutter 테스트

- 프로필 전환
- 체중 변경
- 비동기 요청 중 프로필 전환
- 이전 아이의 결과가 현재 아이에게 표시되는지 여부
- 복약 완료 저장·복구
- 저장 실패
- OCR 실패 UI
- 약품 미확인 UI
- AI 보정 승인·취소
- 위험 상태의 접근성 라벨
- 화면 dispose 이후 비동기 응답 처리

## 6.3 통합 테스트

다음 전체 흐름을 테스트한다.

```text
이미지 업로드
  → OCR
  → 약품 식별
  → 공식 데이터 검증
  → 복약량 계산
  → 안전성 판정
  → Flutter 표시
  → 사용자 확인
  → 복약 일정 및 이력 저장
```

어느 단계에서든 실패하면 임의의 성공 결과를 생성하지 않아야 한다.

---

# 7. 완료 조건 / Definition of Done

작업을 완료했다고 보고하려면 다음 조건을 모두 충족해야 한다.

- [ ] Critical 이슈에 대한 코드 수정 완료
- [ ] 관련 테스트 작성 또는 기존 테스트 보강
- [ ] 백엔드 정적 분석 통과
- [ ] 백엔드 테스트 통과
- [ ] FastAPI 서버 기동 성공
- [ ] Flutter `analyze` 통과
- [ ] Flutter 테스트 통과
- [ ] Flutter 빌드 검증
- [ ] OCR 실패 fallback 제거
- [ ] AI 자동 보정의 원본 데이터 보존
- [ ] 공식 데이터 미검증 약품의 확정 분석 차단
- [ ] 실제 복용 이력 기반 누적량 검증
- [ ] 다자녀 데이터 격리 검증
- [ ] timeout 및 네트워크 장애 테스트
- [ ] 개인정보 및 API 키 로그 노출 점검
- [ ] 의료 전문가 검토가 필요한 항목 별도 목록화
- [ ] 테스트하지 못한 항목과 남은 위험 명시

---

# 8. 최종 보고서 형식

모든 작업이 끝난 후 다음 형식으로 보고한다.

## A. 수정 요약

| 파일 | 변경 내용 | 이유 |
|---|---|---|

## B. 테스트 결과

| 명령 | 결과 | 비고 |
|---|---|---|

## C. 발견된 잔여 이슈

| ID | 내용 | 위험도 | 권장 조치 |
|---|---|---|---|

## D. 의료 검토 필요 항목

- 공식 의약품 기준 확인 필요 항목
- 소아 용량 기준 확인 필요 항목
- 해열제 간격·누적량 기준 확인 필요 항목
- UI 문구 및 응급 안내 검토 필요 항목

## E. 배포 판단

다음 중 하나로 명확히 보고한다.

- `BLOCKED`: Critical 또는 High 위험으로 배포 차단
- `CONDITIONAL`: 기술 검증은 일부 완료했으나 의료·운영 검토 필요
- `READY FOR EXTERNAL REVIEW`: 기술 검증 완료, 외부 의료 검토 대기

의료 전문가 검토가 완료되지 않은 경우 최종 상용 배포 승인으로 표현하지 않는다.
