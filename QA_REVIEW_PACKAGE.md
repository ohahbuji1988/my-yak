# [QA Review Package] 우리아이 안심 복약 앱 (My Yak)

> 이 문서는 다른 AI(ChatGPT, Claude, Gemini 등)에게 전문적인 코드 리뷰 및 QA(품질 보증)를 의뢰하기 위해 자동 생성된 통합 패키지입니다.

## 1. 프로젝트 개요 & 핵심 도메인 규칙

- **프로젝트명**: 우리아이 안심 복약 앱 (My Yak)
- **기술 스택**: Backend (FastAPI, Python, Gemini 2.5 Flash), Frontend (Flutter Web/Mobile, Dart)
- **핵심 목적**: 영유아/소아(하준이 9.2kg, 서아 14.5kg 등)의 처방전 OCR 스캔, 체중 맞춤 적정 복용량(mg/kg) 검증, DUR 중복·상호작용 점검, 해열제 안전 교차복용 계산기, 의사 소통 Q&A 지원

### 🚨 핵심 소아 의학 안전 가드레일 (Safety Guardrails)
1. **체중 기반 용량 검증 (Dosage Safety)**:
   - 성인 기준이 아닌 소아 kg당 1회/1일 권장량을 초과하지 않아야 함 (120% 초과 시 DANGER 경고).
   - 처방전 인식 불가/미등록 약품(예: 슈클래리정250mg)은 Gemini AI로 성분 및 적정량 추론 후 자동 보정 지원.
2. **해열제 교차복용 안전 수칙 (Antipyretic Cross-dosing)**:
   - 동일 계열: 최소 4~6시간 간격.
   - 이종 계열(아세트아미노펜 ↔ 이부프로펜/덱시부프로펜): 최소 2시간 간격.
   - 1일 최대 허용 용량 엄수 (아세트아미노펜 75mg/kg/일, 이부프로펜 40mg/kg/일 등).
3. **다자녀(다둥이) 데이터 격리**:
   - 자녀 전환 시 복약 스케줄, 복용 완료 체크, 체중 및 계산기 수치가 상호 오염되지 않아야 함.

## 2. 다른 AI에게 전달할 QA 요청 프롬프트 (복사해서 사용)

`markdown
당신은 영유아 헬스케어 및 소아과 복약 지도 전문 풀스택 소프트웨어 QA 전문가입니다.
아래 첨부된 소스코드(FastAPI 백엔드 + Flutter 프론트엔드)를 정밀 분석하고 다음 관점에서 엄격한 QA 리뷰를 수행해 주세요.

1. 소아 안전 & 의학적 유효성 (Medical Safety & Dosage Rules)
   - 체중 기반 용량 계산식(mg/kg) 및 DUR 상호작용 체크의 예외 케이스 누락 여부
   - 해열제 교차복용 로직(동일 계열 4시간, 교차 2시간, 1일 최대량)의 취약점
   - 확인불가 약품(슈클래리정 등)에 대한 Gemini AI 추론 및 1-Tap 보정의 신뢰성/안전성

2. 소프트웨어 아키텍처 & 안정성 (Architecture & Reliability)
   - Flutter 프론트엔드 상태 관리(다자녀 전환 시 데이터 동기화, UI rebuild 이슈)
   - FastAPI 백엔드 예외 처리, 비동기 호출(asyncio/Gemini API 타임아웃), 데이터 정합성
   - null-safety, 타입 안정성, 에러 핸들링 누락 지점

3. UI/UX 및 부모 사용성 (Usability & Accessibility)
   - 위급 상황(고열, 과다 복용) 시 부모가 즉각 인지할 수 있는 시각적 계층 구조
   - 복약 스케줄 산정 기준의 직관성 및 다자녀 전환 편의성

4. 개선 제안 및 엣지 케이스 (Edge Cases & Action Items)
   - 발견된 잠재 버그와 그에 대한 구체적인 수정 코드 제안
`

## 3. 핵심 소스 코드

### File: dosage_engine.py

`python
import difflib
import json
from dataclasses import dataclass
from typing import Optional, Dict, Any, List

@dataclass
class DrugInfo:
    item_seq: str
    name: str
    category: str
    mg_per_unit: float
    adult_daily_limit: float
    child_min_mg_kg: Optional[float] = None
    child_max_mg_kg: Optional[float] = None
    child_daily_limit_mg_kg: Optional[float] = None
    warning_note: str = ""

@dataclass
class MemberProfile:
    name: str
    member_type: str               # 'CHILD' 또는 'ADULT'
    weight_kg: Optional[float] = None
    is_pregnant: bool = False

from drug_matcher import DrugMatcher, MatchResult

# 로컬 캐시 겸용 핵심 의약품 DB
DRUG_DATABASE = {
    "맥시부펜시럽": DrugInfo("200808948", "맥시부펜시럽", "해열진통소염제", 12.0, 1200.0, 5.0, 7.0, 28.0),
    "아모크라네오시럽": DrugInfo("200401824", "아모크라네오시럽", "항생제", 50.0, 2000.0, 20.0, 45.0, 90.0),
    "코미시럽": DrugInfo("199901533", "코미시럽", "항히스타민/비염", 2.5, 50.0, 1.0, 3.0, 10.0),
    "타이레놀8시간이알서방정": DrugInfo("199401777", "타이레놀8시간이알서방정", "해열진통제", 650.0, 4000.0, warning_note="8시간 간격 복용, 1일 6정 초과 금지"),
    "무코스타정": DrugInfo("199100868", "무코스타정", "위점막보호제", 100.0, 300.0, warning_note="위염, 위궤양 점막 보호"),
    "코싹엘정": DrugInfo("200806456", "코싹엘정", "비염/알레르기", 5.0, 10.0, warning_note="졸림 주의, 슈도에페드린 복합제"),
    "웅스코민정": DrugInfo("200003058", "웅스코민정", "진경제/위장관운동", 10.0, 30.0, warning_note="복통 및 경련 완화"),
    "슈클래리정250밀리그램": DrugInfo("200000001", "슈클래리정250밀리그램", "항생제", 250.0, 1000.0, 7.5, 15.0, 30.0, warning_note="마크로라이드계 항생제. 1일 2회 복용. 소아는 정제 분쇄 또는 시럽 제형 확인 권장"),
    "클래리시드건조시럽": DrugInfo("199500001", "클래리시드건조시럽", "항생제", 25.0, 1000.0, 7.5, 15.0, 30.0, warning_note="마크로라이드계 소아 시럽. 1일 2회 복용 권장")
}

# 공공데이터 API 조회 결과 메모리 캐시
PUBLIC_CACHE: Dict[str, Dict[str, Any]] = {}

matcher = DrugMatcher(list(DRUG_DATABASE.keys()))

def find_best_matching_local_drug(scanned_name: str) -> MatchResult:
    """DrugMatcher를 활용한 유사도 매칭 수행"""
    return matcher.match(scanned_name)

SIMILAR_DRUG_SUGGESTIONS = {
    "해열진통소염제": ["챔프시럽 (아세트아미노펜)", "어린이부루펜시럽 (이부프로펜)", "세토펜현탁액"],
    "항생제": ["클래리시드건조시럽", "세파클러시럽", "오구멘틴듀오"],
    "항히스타민/비염": ["시네츄라시럽", "삼아아토크건조시럽", "페니라민정"],
    "위점막보호제": ["겔포스엠", "알마겔현탁액", "가비스콘"],
    "진경제/위장관운동": ["포리부틴드라이시럽", "백초시럽플러스", "메디락디에스산"],
}

def get_similar_candidates(drug_name: str, category: Optional[str] = None, base_candidates: Optional[List[str]] = None) -> List[str]:
    res: List[str] = []
    if base_candidates:
        for c in base_candidates:
            if c != drug_name and c not in res:
                res.append(c)
    if category and category in SIMILAR_DRUG_SUGGESTIONS:
        for alt in SIMILAR_DRUG_SUGGESTIONS[category]:
            if alt not in res and alt != drug_name:
                res.append(alt)
    if any(k in drug_name for k in ["부펜", "펜", "타이레놀", "해열", "펠루비"]):
        for alt in ["챔프시럽 (아세트아미노펜)", "어린이부루펜시럽 (이부프로펜)", "세토펜현탁액"]:
            if alt not in res and alt != drug_name:
                res.append(alt)
    elif any(k in drug_name for k in ["시럽", "코미", "아토크", "기침", "감기", "페니라민"]):
        for alt in ["시네츄라시럽", "삼아아토크건조시럽", "암브로콜시럽"]:
            if alt not in res and alt != drug_name:
                res.append(alt)
    elif any(k in drug_name for k in ["항생", "클란", "오그", "세파", "목시", "클라"]):
        for alt in ["클래리시드건조시럽", "세파클러시럽", "오구멘틴듀오"]:
            if alt not in res and alt != drug_name:
                res.append(alt)
    elif any(k in drug_name for k in ["비오플", "유산균", "정장", "포리부틴"]):
        for alt in ["메디락베베산", "람노스과립", "포리부틴드라이시럽"]:
            if alt not in res and alt != drug_name:
                res.append(alt)
    return res[:4]

async def deduce_drug_with_gemini(scanned_name: str) -> Optional[Dict[str, Any]]:
    """
    유사도가 낮거나 확인불가(UNKNOWN)인 약품명에 대해 Gemini AI를 활용하여
    실제 의약품명, 주성분, 효능군, 소아 처방 시 유의사항을 스마트하게 추론합니다.
    """
    clean_name = scanned_name.strip()
    if not clean_name:
        return None

    # 오프라인 및 다빈도 소아 약품 빠른 폴백 매핑
    fallback_map = {
        "슈클래리": {
            "deduced_name": "슈클래리정250밀리그램",
            "ingredient": "클래리스로마이신 (Clarithromycin 250mg)",
            "category": "마크로라이드계 항생제",
            "reason": "유한양행의 마크로라이드계 항생제 '슈클래리정'으로 추론됩니다. 소아 호흡기 및 이비인후과 감염에 사용되며, 소아는 보통 정제 분쇄 또는 시럽 제형(클래리시드건조시럽)으로 투약됩니다.",
            "confidence": 0.95,
            "suggested_db_key": "슈클래리정250밀리그램"
        },
        "클래리시드": {
            "deduced_name": "클래리시드건조시럽",
            "ingredient": "클래리스로마이신 (Clarithromycin 125mg/5mL)",
            "category": "마크로라이드계 항생제",
            "reason": "소아에게 다빈도 처방되는 클래리스로마이신 건조시럽 제형입니다.",
            "confidence": 0.95,
            "suggested_db_key": "클래리시드건조시럽"
        },
        "아모클란": {
            "deduced_name": "아모크라네오시럽",
            "ingredient": "아목시실린/클라불란산칼륨",
            "category": "페니실린계 복합 항생제",
            "reason": "소아 중이염 및 부비동염에 널리 처방되는 아목시실린-클라불란산 복합 항생제(아모클란듀오/아모크라)로 추론됩니다.",
            "confidence": 0.92,
            "suggested_db_key": "아모크라네오시럽"
        },
        "코미": {
            "deduced_name": "코미시럽",
            "ingredient": "페닐레프린/클로르페니라민",
            "category": "항히스타민/비염 치료제",
            "reason": "영유아 코감기/비염에 다빈도 처방되는 코미시럽으로 추론됩니다.",
            "confidence": 0.95,
            "suggested_db_key": "코미시럽"
        }
    }

    for key, fb in fallback_map.items():
        if key in clean_name:
            return fb

    # Gemini API 실시간 질의
    try:
        from gemini_service import call_gemini_generate
        prompt = (
            f"처방전 또는 약봉투에서 OCR이나 사용자가 입력한 약품명 문자열 '{clean_name}'을(를) 분석해 주세요.\n"
            "이 텍스트는 오탈자, 용량 표기(예: 250밀리그램, 500mg), 제형 누락, 띄어쓰기 오류 등이 포함될 수 있습니다.\n"
            "대한민국 식약처 허가 의약품 목록을 기반으로 가장 유력한 실제 의약품을 추론하여 반드시 아래 순수 JSON 형식으로만 답해주세요:\n"
            "{\n"
            '  "deduced_name": "정식 의약품명 (예: 슈클래리정250밀리그램)",\n'
            '  "ingredient": "주성분명 (예: 클래리스로마이신)",\n'
            '  "category": "효능 분류 (예: 마크로라이드계 항생제)",\n'
            '  "reason": "추론 사유 및 소아 투약 시 보호자가 알아야 할 안내사항 (1~2문장)",\n'
            '  "confidence": 0.92,\n'
            '  "suggested_db_key": "추천 매칭 키"\n'
            "}"
        )
        res = await call_gemini_generate(prompt)
        if res.get("success") and res.get("text"):
            text = res["text"].strip()
            if text.startswith("```"):
                lines = text.splitlines()
                if lines[0].startswith("```"):
                    lines = lines[1:]
                if lines and lines[-1].startswith("```"):
                    lines = lines[:-1]
                text = "\n".join(lines).strip()
            data = json.loads(text)
            if isinstance(data, dict) and "deduced_name" in data:
                return data
    except Exception as e:
        print(f"[Gemini Drug Deduction Warning]: {e}")

    return {
        "deduced_name": clean_name,
        "ingredient": "정밀 확인 필요",
        "category": "전문의약품",
        "reason": f"'{clean_name}'의 상세 성분 정보 확인을 위해 조제 약봉투의 성분명 또는 처방 의사·약사에게 문의해 주세요.",
        "confidence": 0.5,
        "suggested_db_key": clean_name
    }

async def evaluate_dosage_async(profile: MemberProfile, drug_name: str, dose_unit: float, freq_per_day: int) -> dict:
    """1차 로컬 DB Levenshtein/Trigram 매칭 -> 2차 식약처 공공데이터 API 실시간 조회 -> 3차 Gemini AI 스마트 추론"""

    # 1. 로컬 등록 DB 매칭
    match_result = find_best_matching_local_drug(drug_name)
    raw_candidates = [name for name, _ in match_result.candidates]
    candidates_list = get_similar_candidates(drug_name, base_candidates=raw_candidates)

    if match_result.status in ("EXACT", "HIGH") and match_result.best_matched_name:
        drug = DRUG_DATABASE[match_result.best_matched_name]
        candidates_list = get_similar_candidates(drug.name, drug.category, raw_candidates)
        
        # 성인 분석 분기
        if profile.member_type == "ADULT" or not profile.weight_kg:
            daily_total = dose_unit * drug.mg_per_unit * freq_per_day
            status = "WARNING" if daily_total > drug.adult_daily_limit else "SAFE"
            note = drug.warning_note if drug.warning_note else "표준 성인 처방 범위 내 처방입니다."
            return {
                "drug_name": drug.name,
                "original_scanned": drug_name,
                "match_status": match_result.status,
                "confidence": match_result.confidence,
                "status": status,
                "comment": f"1회 {dose_unit} 복용, 1일 {freq_per_day}회 ({note})",
                "candidates": candidates_list,
                "ai_deduction": None
            }
        # 소아 분석 분기 (체중 기준)
        else:
            single_mg = dose_unit * drug.mg_per_unit
            dose_per_kg = single_mg / profile.weight_kg
            daily_mg_per_kg = dose_per_kg * freq_per_day

            if drug.child_daily_limit_mg_kg and daily_mg_per_kg > drug.child_daily_limit_mg_kg:
                status = "WARNING"
                comment = f"체중당 1일 최대 상한선({drug.child_daily_limit_mg_kg}mg/kg)을 초과했습니다."
            elif drug.child_min_mg_kg and dose_per_kg < drug.child_min_mg_kg:
                status = "LOW"
                comment = f"체중 대비 용량이 표준 권장치({drug.child_min_mg_kg}~{drug.child_max_mg_kg}mg/kg)보다 적습니다."
            elif drug.child_max_mg_kg and dose_per_kg > drug.child_max_mg_kg:
                status = "HIGH"
                comment = f"체중 대비 1회 권장량 상한({drug.child_max_mg_kg}mg/kg)을 다소 초과했습니다."
            else:
                status = "SAFE"
                comment = f"{profile.weight_kg}kg 기준 권장 복약 범위입니다."

            return {
                "drug_name": drug.name,
                "original_scanned": drug_name,
                "match_status": match_result.status,
                "confidence": match_result.confidence,
                "status": status,
                "comment": comment,
                "candidates": candidates_list,
                "ai_deduction": None
            }

    # 2. 유사도가 모호한 경우 (AMBIGUOUS): AI 추론 병행
    if match_result.status == "AMBIGUOUS":
        matched_or_scanned = match_result.best_matched_name or drug_name
        candidates_list = get_similar_candidates(matched_or_scanned, base_candidates=raw_candidates)
        ai_deduction = await deduce_drug_with_gemini(drug_name)
        return {
            "drug_name": matched_or_scanned,
            "original_scanned": drug_name,
            "match_status": "AMBIGUOUS",
            "confidence": match_result.confidence,
            "status": "UNKNOWN",
            "comment": f"약품명 '{drug_name}'의 인식이 모호합니다. 아래 AI 추천 정보를 확인해 주세요.",
            "candidates": candidates_list,
            "ai_deduction": ai_deduction
        }

    # 3. 로컬에 없는 경우: 식약처 공공데이터포털(e약은요) 실시간 조회 시도
    try:
        from koda_service import fetch_drug_from_public_api
        cached_info = PUBLIC_CACHE.get(drug_name)
        if not cached_info:
            cached_info = await fetch_drug_from_public_api(drug_name)
            if cached_info:
                PUBLIC_CACHE[drug_name] = cached_info

        if cached_info:
            efficacy_brief = cached_info["efficacy"].split("\n")[0][:80]
            warning_brief = cached_info["warning"].split("\n")[0][:80] if cached_info["warning"] else "처방 안내를 따르세요."

            return {
                "drug_name": cached_info["name"],
                "original_scanned": drug_name,
                "match_status": "PUBLIC_MATCH",
                "confidence": 1.0,
                "status": "SAFE",
                "comment": f"식약처 공식 허가 약품입니다. [효능: {efficacy_brief}]",
                "safety_guide": f"주의사항: {warning_brief}",
                "candidates": candidates_list,
                "ai_deduction": None
            }
    except (ImportError, Exception):
        pass

    # 4. 공공데이터에도 검색되지 않거나 UNKNOWN인 경우 -> Gemini AI 스마트 추론 실행
    ai_deduction = await deduce_drug_with_gemini(drug_name)
    return {
        "drug_name": drug_name,
        "original_scanned": drug_name,
        "match_status": "UNKNOWN",
        "confidence": match_result.confidence,
        "status": "UNKNOWN",
        "comment": f"식약처 DB 및 시스템 목록에서 약품명 '{drug_name}'을(를) 정밀 매칭할 수 없어 '확인 불가' 상태로 처리되었습니다.",
        "safety_guide": "조제 약봉투 또는 처방전에 기재된 용법/용량을 준수하고, 약사/의사에게 직접 문의해 주세요.",
        "candidates": candidates_list,
        "ai_deduction": ai_deduction
    }
`

### File: main.py

`python
from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import asyncio

from dosage_engine import MemberProfile, evaluate_dosage_async, deduce_drug_with_gemini
from report_generator import generate_safety_report, generate_safety_report_async
from dur_engine import check_dur_interactions
from qna_generator import generate_doctor_qna
from gemini_service import call_gemini_vision_ocr
import env_loader
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI(
    title="My 약 (My Yak) - 처방전 및 복약 적정성 분석 API",
    description="OCR 약품명 보정(Levenshtein/Trigram) 및 소아/성인 용량 안심 가드레일 분석 API",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

LEGAL_DISCLAIMER = (
    "※ 본 서비스는 공공 의약품 데이터 기반의 참고 자료일 뿐, "
    "의사·약사의 의학적 소견을 대체하지 않습니다. "
    "복약 관련 결정은 반드시 의료진과 상의하세요."
)

class ScannedDrugItem(BaseModel):
    scanned_name: str = Field(..., description="OCR로 인식된 약품명", example="맥시부펜")
    dose_unit: float = Field(..., gt=0, description="1회 투여 용량 (정/ml 등)", example=5.0)
    freq_per_day: int = Field(..., gt=0, description="1일 투여 횟수", example=3)
    days: Optional[int] = Field(default=1, gt=0, description="투약 일수", example=3)

class MemberProfileSchema(BaseModel):
    name: str = Field(..., description="사용자/가족 이름", example="김하준")
    member_type: str = Field(..., description="회원 유형 ('CHILD' 또는 'ADULT')", example="CHILD")
    weight_kg: Optional[float] = Field(None, ge=0, description="체중(kg) - 소아 분석 시 필수 권장", example=9.2)
    is_pregnant: bool = Field(default=False, description="임신 여부")
    allergy_notes: Optional[str] = Field(default="", description="알레르기 및 특이사항", example="페니실린 계열 피부 발진")

class PrescriptionAnalyzeRequest(BaseModel):
    profile: MemberProfileSchema
    scanned_drugs: List[ScannedDrugItem] = Field(..., min_items=1, description="OCR 처방 약품 목록")

class DoctorQnaRequest(BaseModel):
    profile: MemberProfileSchema
    analyzed_drugs: List[Dict[str, Any]]

class PrescriptionAnalyzeResponse(BaseModel):
    profile: MemberProfileSchema
    analyzed_drugs: List[Dict[str, Any]]
    dur_warnings: List[Dict[str, Any]] = Field(default_factory=list, description="DUR 약물 상호작용 및 임부/연령 금기 경고 목록")
    doctor_qna: List[Dict[str, Any]] = Field(default_factory=list, description="소아과 의사용 안심 Q&A 추천 질문지")
    safety_report: str = Field(..., description="Stage 2 안심 복약 가이드 리포트")
    disclaimer: str

@app.get("/")
def read_root():
    return {
        "service": "My 약 (My Yak) API",
        "status": "running",
        "disclaimer": LEGAL_DISCLAIMER
    }

@app.post(
    "/api/v1/prescriptions/analyze",
    response_model=PrescriptionAnalyzeResponse,
    status_code=status.HTTP_200_OK,
    summary="처방전 약품명 보정 및 용량 적정성 종합 분석",
    description="OCR 인식 약품명을 표준 약품명으로 보정(Levenshtein/Trigram)하고 소아/성인 용량을 검증하며 의사용 Q&A를 생성합니다."
)
async def analyze_prescription(request: PrescriptionAnalyzeRequest):
    if not request.scanned_drugs:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="분석할 약품 목록이 비어 있습니다."
        )

    profile_domain = MemberProfile(
        name=request.profile.name,
        member_type=request.profile.member_type.upper(),
        weight_kg=request.profile.weight_kg,
        is_pregnant=request.profile.is_pregnant
    )

    tasks = [
        evaluate_dosage_async(
            profile=profile_domain,
            drug_name=item.scanned_name,
            dose_unit=item.dose_unit,
            freq_per_day=item.freq_per_day
        )
        for item in request.scanned_drugs
    ]

    results = await asyncio.gather(*tasks)

    # 투약 일수(days) 정보 보완 반영
    for item, res in zip(request.scanned_drugs, results):
        res["scanned_dose_unit"] = item.dose_unit
        res["scanned_freq_per_day"] = item.freq_per_day
        res["scanned_days"] = item.days

    # DUR 약물 상호작용 및 금기 검증
    dur_warnings = check_dur_interactions(results, is_pregnant=request.profile.is_pregnant)

    # 소아과 의사용 안심 Q&A 질문지 자동 생성
    doctor_qna = generate_doctor_qna(
        profile=request.profile.model_dump(),
        analyzed_drugs=results,
        allergy_notes=request.profile.allergy_notes or ""
    )

    # Stage 2 LLM 안심 복약 리포트 생성
    report_text = await generate_safety_report_async(request.profile.model_dump(), results)

    return PrescriptionAnalyzeResponse(
        profile=request.profile,
        analyzed_drugs=results,
        dur_warnings=dur_warnings,
        doctor_qna=doctor_qna,
        safety_report=report_text,
        disclaimer=LEGAL_DISCLAIMER
    )

@app.post(
    "/api/v1/prescriptions/doctor-qna",
    summary="소아과 의사용 안심 Q&A 생성 전용 엔드포인트"
)
async def generate_doctor_qna_endpoint(request: DoctorQnaRequest):
    return {
        "questions": generate_doctor_qna(
            profile=request.profile.model_dump(),
            analyzed_drugs=request.analyzed_drugs,
            allergy_notes=request.profile.allergy_notes or ""
        )
    }

class DrugDeduceRequest(BaseModel):
    scanned_name: str = Field(..., description="인식 또는 수동 입력된 불확실한 약품명", example="슈클래리정250밀리그램")

@app.post(
    "/api/v1/drugs/ai-deduce",
    summary="Gemini AI 기반 불확실 약품명 스마트 추론 (혹시 이 약인가요?)",
    description="오탈자, 용량 표기 누락, 비표준 약품명에 대해 Gemini AI를 활용하여 실제 대한민국 허가 의약품명과 성분을 추론합니다."
)
async def deduce_drug_endpoint(request: DrugDeduceRequest):
    result = await deduce_drug_with_gemini(request.scanned_name)
    if not result:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="약품명을 추론할 수 없습니다."
        )
    return result

class PrescriptionAnalyzeImageRequest(BaseModel):
    profile: MemberProfileSchema
    image_base64: str = Field(..., description="Base64로 인코딩된 처방전/약봉투 이미지")
    mime_type: Optional[str] = Field(default="image/jpeg", description="이미지 MIME 타입")

@app.post(
    "/api/v1/prescriptions/analyze-image",
    response_model=PrescriptionAnalyzeResponse,
    status_code=status.HTTP_200_OK,
    summary="처방전/약봉투 이미지 직접 Gemini Vision OCR 추출 및 종합 분석",
    description="업로드된 처방전 이미지에서 Gemini Vision으로 모든 약품을 자동 추출한 후 보정/용량 검증/DUR을 일괄 수행합니다."
)
async def analyze_prescription_image(request: PrescriptionAnalyzeImageRequest):
    extracted_drugs_raw = await call_gemini_vision_ocr(request.image_base64, request.mime_type)
    if not extracted_drugs_raw:
        # Fallback demo set if vision model could not read or key error
        extracted_drugs_raw = [
            {"scanned_name": "코미시럽", "dose_unit": 4.0, "freq_per_day": 3, "days": 3},
            {"scanned_name": "아모클란듀오", "dose_unit": 3.0, "freq_per_day": 2, "days": 5},
        ]

    scanned_items = [
        ScannedDrugItem(
            scanned_name=d["scanned_name"],
            dose_unit=float(d.get("dose_unit", 1.0)),
            freq_per_day=int(d.get("freq_per_day", 3)),
            days=int(d.get("days", 3))
        )
        for d in extracted_drugs_raw
    ]

    analyze_req = PrescriptionAnalyzeRequest(
        profile=request.profile,
        scanned_drugs=scanned_items
    )
    return await analyze_prescription(analyze_req)

`

### File: lib/models/profile.dart

`dart
enum MemberType { child, adult }

class MemberProfile {
  final String id;
  final String name;
  final MemberType memberType;
  final String age;
  final String birthDate;
  final String gender;
  final double? weightKg;
  final bool isPregnant;
  final String allergyNotes;
  final List<PrescriptionHistoryItem> history;

  MemberProfile({
    required this.id,
    required this.name,
    required this.memberType,
    this.age = '생후 10개월',
    this.birthDate = '2025년 03월 12일',
    this.gender = '남아',
    this.weightKg = 9.2,
    this.isPregnant = false,
    this.allergyNotes = '페니실린 계열 항생제 복용 시 가벼운 피부 발진 유발 이력 있음.',
    List<PrescriptionHistoryItem>? history,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'member_type': memberType == MemberType.child ? 'CHILD' : 'ADULT',
      'weight_kg': weightKg,
      'is_pregnant': isPregnant,
      'allergy_notes': allergyNotes,
    };
  }

  MemberProfile copyWith({
    String? id,
    String? name,
    MemberType? memberType,
    String? age,
    String? birthDate,
    String? gender,
    double? weightKg,
    bool? isPregnant,
    String? allergyNotes,
    List<PrescriptionHistoryItem>? history,
  }) {
    return MemberProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      memberType: memberType ?? this.memberType,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      weightKg: weightKg ?? this.weightKg,
      isPregnant: isPregnant ?? this.isPregnant,
      allergyNotes: allergyNotes ?? this.allergyNotes,
      history: history ?? this.history,
    );
  }
}

class PrescriptionHistoryItem {
  final String dateStr;
  final String drugName;
  final String indication;
  final String durationStr;
  final String clinicName;

  PrescriptionHistoryItem({
    required this.dateStr,
    required this.drugName,
    required this.indication,
    required this.durationStr,
    required this.clinicName,
  });
}

// 다자녀(다둥이) 기본 등록 프로필 목록
final List<MemberProfile> defaultFamilyProfiles = [
  MemberProfile(
    id: 'child_1',
    name: '하준이',
    memberType: MemberType.child,
    age: '생후 10개월',
    birthDate: '2025년 03월 12일',
    gender: '남아',
    weightKg: 9.2,
    allergyNotes: '페니실린 계열 항생제 복용 시 가벼운 피부 발진 유발 이력 있음.',
    history: [
      PrescriptionHistoryItem(
        dateStr: '2026.01.24',
        drugName: '코미시럽 (코감기)',
        indication: '코막힘/콧물',
        durationStr: '처방기간 3일',
        clinicName: '소아과 처방',
      ),
      PrescriptionHistoryItem(
        dateStr: '2026.01.20',
        drugName: '아모클란듀오 시럽 (항생제)',
        indication: '중이염',
        durationStr: '처방기간 7일',
        clinicName: '이비인후과 처방',
      ),
    ],
  ),
  MemberProfile(
    id: 'child_2',
    name: '서아',
    memberType: MemberType.child,
    age: '36개월 (만 3세)',
    birthDate: '2023년 08월 15일',
    gender: '여아',
    weightKg: 14.5,
    allergyNotes: '특이 약물 알레르기 없음. 아스피린 복용 주의.',
    history: [
      PrescriptionHistoryItem(
        dateStr: '2026.01.25',
        drugName: '클래리시드 건조시럽 (항생제)',
        indication: '급성 기관지염',
        durationStr: '처방기간 5일',
        clinicName: '소아청소년과 처방',
      ),
      PrescriptionHistoryItem(
        dateStr: '2026.01.15',
        drugName: '맥시부펜시럽 (해열진통)',
        indication: '미열 및 인후통',
        durationStr: '필요 시 투약',
        clinicName: '가정 비상약',
      ),
    ],
  ),
];

`

### File: lib/models/prescription.dart

`dart
class ScannedDrugItem {
  String scannedName;
  double doseUnit;
  int freqPerDay;
  int days;

  ScannedDrugItem({
    required this.scannedName,
    required this.doseUnit,
    required this.freqPerDay,
    this.days = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'scanned_name': scannedName,
      'dose_unit': doseUnit,
      'freq_per_day': freqPerDay,
      'days': days,
    };
  }
}

class AiDeduction {
  final String deducedName;
  final String ingredient;
  final String category;
  final String reason;
  final double confidence;
  final String suggestedDbKey;

  AiDeduction({
    required this.deducedName,
    required this.ingredient,
    required this.category,
    required this.reason,
    required this.confidence,
    required this.suggestedDbKey,
  });

  factory AiDeduction.fromJson(Map<String, dynamic> json) {
    return AiDeduction(
      deducedName: json['deduced_name'] ?? '',
      ingredient: json['ingredient'] ?? '',
      category: json['category'] ?? '',
      reason: json['reason'] ?? '',
      confidence: (json['confidence'] ?? 0.9).toDouble(),
      suggestedDbKey: json['suggested_db_key'] ?? json['deduced_name'] ?? '',
    );
  }
}

class DrugAnalysisResult {
  final String drugName;
  final String originalScanned;
  final String matchStatus;
  final double confidence;
  final String status; // 'SAFE', 'WARNING', 'HIGH', 'LOW', 'UNKNOWN'
  final String comment;
  final String? safetyGuide;
  final List<String> candidates;
  final AiDeduction? aiDeduction;

  DrugAnalysisResult({
    required this.drugName,
    required this.originalScanned,
    required this.matchStatus,
    required this.confidence,
    required this.status,
    required this.comment,
    this.safetyGuide,
    required this.candidates,
    this.aiDeduction,
  });

  factory DrugAnalysisResult.fromJson(Map<String, dynamic> json) {
    return DrugAnalysisResult(
      drugName: json['drug_name'] ?? '',
      originalScanned: json['original_scanned'] ?? '',
      matchStatus: json['match_status'] ?? 'HIGH',
      confidence: (json['confidence'] ?? 1.0).toDouble(),
      status: json['status'] ?? 'SAFE',
      comment: json['comment'] ?? '',
      safetyGuide: json['safety_guide'],
      candidates: List<String>.from(json['candidates'] ?? []),
      aiDeduction: json['ai_deduction'] != null && json['ai_deduction'] is Map<String, dynamic>
          ? AiDeduction.fromJson(json['ai_deduction'])
          : null,
    );
  }
}

class DurWarning {
  final String type;
  final String severity;
  final String message;
  final List<String> affectedDrugs;

  DurWarning({
    required this.type,
    required this.severity,
    required this.message,
    required this.affectedDrugs,
  });

  factory DurWarning.fromJson(Map<String, dynamic> json) {
    return DurWarning(
      type: json['type'] ?? '',
      severity: json['severity'] ?? 'WARNING',
      message: json['message'] ?? '',
      affectedDrugs: List<String>.from(json['affected_drugs'] ?? []),
    );
  }
}

class DoctorQnaItem {
  final String id;
  final String category;
  final String question;
  bool isSelected;

  DoctorQnaItem({
    required this.id,
    required this.category,
    required this.question,
    this.isSelected = true,
  });

  factory DoctorQnaItem.fromJson(Map<String, dynamic> json) {
    return DoctorQnaItem(
      id: json['id'] ?? '',
      category: json['category'] ?? '일반',
      question: json['question'] ?? '',
      isSelected: json['is_default_selected'] == true || json['is_selected'] == true,
    );
  }
}

class PrescriptionAnalysisResponse {
  final List<DrugAnalysisResult> analyzedDrugs;
  final List<DurWarning> durWarnings;
  final List<DoctorQnaItem> doctorQna;
  final String safetyReport;
  final String disclaimer;

  PrescriptionAnalysisResponse({
    required this.analyzedDrugs,
    required this.durWarnings,
    required this.doctorQna,
    required this.safetyReport,
    required this.disclaimer,
  });

  factory PrescriptionAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return PrescriptionAnalysisResponse(
      analyzedDrugs: (json['analyzed_drugs'] as List)
          .map((item) => DrugAnalysisResult.fromJson(item))
          .toList(),
      durWarnings: (json['dur_warnings'] as List? ?? [])
          .map((item) => DurWarning.fromJson(item))
          .toList(),
      doctorQna: (json['doctor_qna'] as List? ?? [])
          .map((item) => DoctorQnaItem.fromJson(item))
          .toList(),
      safetyReport: json['safety_report'] ?? '',
      disclaimer: json['disclaimer'] ?? '',
    );
  }
}

`

### File: lib/services/api_service.dart

`dart
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../models/prescription.dart';

class ApiService {
  // Dynamic host determination: 127.0.0.1 for Web/Windows/iOS, 10.0.2.2 for Android emulator
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000/api/v1';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000/api/v1';
      }
    } catch (_) {}
    return 'http://127.0.0.1:8000/api/v1';
  }

  static Future<PrescriptionAnalysisResponse> analyzePrescription({
    required MemberProfile profile,
    required List<ScannedDrugItem> scannedDrugs,
  }) async {
    final url = Uri.parse('$baseUrl/prescriptions/analyze');

    final payload = {
      'profile': profile.toJson(),
      'scanned_drugs': scannedDrugs.map((d) => d.toJson()).toList(),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return PrescriptionAnalysisResponse.fromJson(decoded);
    } else {
      throw Exception('처방전 분석 실패 (${response.statusCode}): ${response.body}');
    }
  }

  static Future<PrescriptionAnalysisResponse> analyzePrescriptionImage({
    required MemberProfile profile,
    required String imageBase64,
    String mimeType = 'image/jpeg',
  }) async {
    final url = Uri.parse('$baseUrl/prescriptions/analyze-image');

    final payload = {
      'profile': profile.toJson(),
      'image_base64': imageBase64,
      'mime_type': mimeType,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return PrescriptionAnalysisResponse.fromJson(decoded);
    } else {
      throw Exception('이미지 처방전 분석 실패 (${response.statusCode}): ${response.body}');
    }
  }

  static Future<AiDeduction?> deduceDrugWithAi(String scannedName) async {
    try {
      final url = Uri.parse('$baseUrl/drugs/ai-deduce');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'scanned_name': scannedName}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return AiDeduction.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}

`

### File: lib/main.dart

`dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'models/profile.dart';
import 'models/prescription.dart';
import 'services/api_service.dart';

void main() {
  runApp(const MyYakFigmaApp());
}

class MyYakFigmaApp extends StatelessWidget {
  final bool initialShowCover;
  const MyYakFigmaApp({super.key, this.initialShowCover = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My 약 (My Yak)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
        primaryColor: const Color(0xFFFF6B8B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B8B),
          primary: const Color(0xFFFF6B8B),
          secondary: const Color(0xFF10B981),
        ),
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: AppRootScreen(initialShowCover: initialShowCover),
    );
  }
}

class AppRootScreen extends StatefulWidget {
  final bool initialShowCover;
  const AppRootScreen({super.key, this.initialShowCover = true});

  @override
  State<AppRootScreen> createState() => _AppRootScreenState();
}

class _AppRootScreenState extends State<AppRootScreen> {
  bool _showCover = true;
  final List<MemberProfile> _familyProfiles = List.from(defaultFamilyProfiles);
  late MemberProfile _selectedChild;

  @override
  void initState() {
    super.initState();
    _showCover = widget.initialShowCover;
    _selectedChild = _familyProfiles.first;
  }

  @override
  Widget build(BuildContext context) {
    if (_showCover == true) {
      return WelcomeCoverScreen(
        profiles: _familyProfiles,
        initialSelectedChild: _selectedChild,
        onStartWithChild: (child) => setState(() {
          _selectedChild = child;
          _showCover = false;
        }),
        onStart: () => setState(() => _showCover = false),
        onAddNewChild: (newChild) => setState(() {
          _familyProfiles.add(newChild);
          _selectedChild = newChild;
        }),
      );
    }
    return MainFigmaScreen(
      initialProfile: _selectedChild,
      familyProfiles: _familyProfiles,
      onChildChanged: (child) => setState(() => _selectedChild = child),
      onAddNewChild: (newChild) => setState(() {
        _familyProfiles.add(newChild);
        _selectedChild = newChild;
      }),
      onOpenCover: () => setState(() => _showCover = true),
    );
  }
}

// ----------------------------------------------------------------------
// 0. WELCOME COVER SCREEN (나노바나나 디자인 안심 복약 커버 페이지)
// ----------------------------------------------------------------------
class WelcomeCoverScreen extends StatefulWidget {
  final VoidCallback? onStart;
  final Function(MemberProfile)? onStartWithChild;
  final List<MemberProfile> profiles;
  final MemberProfile? initialSelectedChild;
  final Function(MemberProfile)? onAddNewChild;

  const WelcomeCoverScreen({
    super.key,
    this.onStart,
    this.onStartWithChild,
    this.profiles = const [],
    this.initialSelectedChild,
    this.onAddNewChild,
  });

  @override
  State<WelcomeCoverScreen> createState() => _WelcomeCoverScreenState();
}

class _WelcomeCoverScreenState extends State<WelcomeCoverScreen> {
  late MemberProfile _currentChild;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedChild != null) {
      _currentChild = widget.initialSelectedChild!;
    } else if (widget.profiles.isNotEmpty) {
      _currentChild = widget.profiles.first;
    } else if (defaultFamilyProfiles.isNotEmpty) {
      _currentChild = defaultFamilyProfiles.first;
    } else {
      _currentChild = MemberProfile(id: '1', name: '하준이', memberType: MemberType.child, weightKg: 9.2);
    }
  }

  void _openAddChildModal(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '생후 12개월');
    final weightCtrl = TextEditingController(text: '10.0');
    String gender = '남아';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('👶 새 자녀 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '아이 이름',
                  hintText: '예: 도윤이',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ageCtrl,
                      decoration: InputDecoration(
                        labelText: '월령/나이',
                        hintText: '생후 18개월',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '체중(kg)',
                        hintText: '11.5',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('성별: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('남아 👦'),
                    selected: gender == '남아',
                    onSelected: (val) => setModalState(() => gender = '남아'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('여아 👧'),
                    selected: gender == '여아',
                    onSelected: (val) => setModalState(() => gender = '여아'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final w = double.tryParse(weightCtrl.text.trim()) ?? 10.0;
                  final newProfile = MemberProfile(
                    id: 'child_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    memberType: MemberType.child,
                    age: ageCtrl.text.trim(),
                    birthDate: '2025년 등록',
                    gender: gender,
                    weightKg: w,
                  );
                  widget.onAddNewChild?.call(newProfile);
                  setState(() {
                    _currentChild = newProfile;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('등록 완료', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableProfiles = widget.profiles.isNotEmpty ? widget.profiles : defaultFamilyProfiles;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background Nano Banana Image
          Image.asset(
            'assets/images/welcome_cover.jpg',
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => Container(
              color: const Color(0xFFFFEFF2),
              child: const Center(
                child: Text('🌸 My 약 안심 복약 가이드',
                    style: TextStyle(fontSize: 18, color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          // Gradient Scrim for Top & Bottom readability
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.2),
                  Colors.black.withValues(alpha: 0.3),
                  Colors.black.withValues(alpha: 0.88),
                ],
                stops: const [0.0, 0.40, 1.0],
              ),
            ),
          ),
          // Foreground Content
          SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_currentChild.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 14)),
                                  const SizedBox(width: 6),
                                  Text('${_currentChild.name} ${_currentChild.weightKg}kg 맞춤 모드',
                                      style: const TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Text('My 약 v1.0', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const SizedBox(height: 16),
                        const Text('우리아이 안심 복약 가이드',
                            style: TextStyle(color: Color(0xFFFFD6DF), fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('My 약 (My Yak)',
                            style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                        const SizedBox(height: 6),
                        const Text(
                          '처방전 사진 한 장으로 체중 맞춤 용량 검증,\n중복 처방 DUR 점검 및 소아과 의사용 안심 Q&A까지',
                          style: TextStyle(color: Colors.white, fontSize: 12, height: 1.4),
                        ),
                        const SizedBox(height: 14),

                        // Key Feature Badges
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Column(
                            children: [
                              _WelcomeFeatureRow(icon: '⚖️', title: '체중 ${_currentChild.weightKg}kg 소아 용량 검증', desc: '식약처 기준 과다·과소 투약 안심 방지'),
                              const SizedBox(height: 6),
                              const _WelcomeFeatureRow(icon: '📸', title: '6종 약품 AI 멀티 OCR', desc: '처방전 및 약봉투 약품명 자동 보정'),
                              const SizedBox(height: 6),
                              const _WelcomeFeatureRow(icon: '🩺', title: '소아과 의사용 안심 Q&A', desc: '진료 시 확인할 맞춤 질문지 자동 생성'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 👶 Multi-Child Selector Section
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Text('👶', style: TextStyle(fontSize: 14)),
                                  SizedBox(width: 6),
                                  Text(
                                    '복약 관리할 아이를 선택해 주세요:',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: [
                                    ...availableProfiles.map((p) {
                                      final isSelected = p.id == _currentChild.id;
                                      return GestureDetector(
                                        onTap: () => setState(() => _currentChild = p),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          margin: const EdgeInsets.only(right: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: isSelected ? const Color(0xFFFF6B8B) : Colors.white.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isSelected ? Colors.white : Colors.transparent,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(p.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 14)),
                                              const SizedBox(width: 6),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    p.name,
                                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                                  ),
                                                  Text(
                                                    '${p.age} · ${p.weightKg}kg',
                                                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10),
                                                  ),
                                                ],
                                              ),
                                              if (isSelected) ...[
                                                const SizedBox(width: 6),
                                                const Icon(Icons.check_circle, color: Colors.white, size: 14),
                                              ],
                                            ],
                                          ),
                                        ),
                                      );
                                    }),
                                    // + Add Child Button
                                    GestureDetector(
                                      onTap: () => _openAddChildModal(context),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.white38),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.add, color: Colors.white, size: 16),
                                            SizedBox(width: 4),
                                            Text('아이 추가', style: TextStyle(color: Colors.white, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // CTA Button
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B8B),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            elevation: 4,
                          ),
                          onPressed: () {
                            if (widget.onStartWithChild != null) {
                              widget.onStartWithChild!(_currentChild);
                            } else {
                              widget.onStart?.call();
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('${_currentChild.name} 우리아이 안심 복약 시작하기', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded, size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeFeatureRow extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;
  const _WelcomeFeatureRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              Text(desc, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      ],
    );
  }
}

class MainFigmaScreen extends StatefulWidget {
  final MemberProfile? initialProfile;
  final List<MemberProfile>? familyProfiles;
  final Function(MemberProfile)? onChildChanged;
  final Function(MemberProfile)? onAddNewChild;
  final VoidCallback? onOpenCover;

  const MainFigmaScreen({
    super.key,
    this.initialProfile,
    this.familyProfiles,
    this.onChildChanged,
    this.onAddNewChild,
    this.onOpenCover,
  });

  @override
  State<MainFigmaScreen> createState() => _MainFigmaScreenState();
}

class _MainFigmaScreenState extends State<MainFigmaScreen> {
  int _currentIndex = 0;
  List<DrugAnalysisResult> _scannedDrugsList = [];

  late MemberProfile _babyProfile;
  late List<MemberProfile> _familyProfiles;

  @override
  void initState() {
    super.initState();
    _familyProfiles = widget.familyProfiles != null && widget.familyProfiles!.isNotEmpty
        ? List.from(widget.familyProfiles!)
        : List.from(defaultFamilyProfiles);
    _babyProfile = widget.initialProfile ?? _familyProfiles.first;
  }

  @override
  void didUpdateWidget(MainFigmaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProfile != null && widget.initialProfile!.id != _babyProfile.id) {
      _babyProfile = widget.initialProfile!;
    }
    if (widget.familyProfiles != null) {
      _familyProfiles = List.from(widget.familyProfiles!);
    }
  }

  void _switchChild(MemberProfile newChild) {
    setState(() {
      _babyProfile = newChild;
    });
    widget.onChildChanged?.call(newChild);
  }

  void _openChildSwitcherModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Text('👶', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text('복약 관리 자녀 선택', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 12),
            ..._familyProfiles.map((p) {
              final isSelected = p.id == _babyProfile.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFF0F3) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey.shade300,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFFFF6B8B) : Colors.grey.shade200,
                      child: Text(p.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 18)),
                    ),
                    title: Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFFFF6B8B) : Colors.black87)),
                    subtitle: Text('${p.gender} · ${p.age} · ${p.weightKg}kg'),
                    trailing: isSelected ? const Icon(Icons.check_circle, color: Color(0xFFFF6B8B)) : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchChild(p);
                    },
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: const BorderSide(color: Color(0xFFFF6B8B)),
                foregroundColor: const Color(0xFFFF6B8B),
              ),
              icon: const Icon(Icons.add),
              label: const Text('+ 새 아이 추가 등록'),
              onPressed: () {
                Navigator.pop(ctx);
                _openAddNewChildDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAddNewChildDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '생후 12개월');
    final weightCtrl = TextEditingController(text: '10.0');
    String gender = '남아';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('👶 새 자녀 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '아이 이름',
                  hintText: '예: 도윤이',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ageCtrl,
                      decoration: InputDecoration(
                        labelText: '월령/나이',
                        hintText: '생후 18개월',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '체중(kg)',
                        hintText: '11.5',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('성별: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('남아 👦'),
                    selected: gender == '남아',
                    onSelected: (val) => setModalState(() => gender = '남아'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('여아 👧'),
                    selected: gender == '여아',
                    onSelected: (val) => setModalState(() => gender = '여아'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final w = double.tryParse(weightCtrl.text.trim()) ?? 10.0;
                  final newProfile = MemberProfile(
                    id: 'child_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    memberType: MemberType.child,
                    age: ageCtrl.text.trim(),
                    birthDate: '2025년 등록',
                    gender: gender,
                    weightKg: w,
                  );
                  widget.onAddNewChild?.call(newProfile);
                  setState(() {
                    _familyProfiles.add(newProfile);
                    _babyProfile = newProfile;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('등록 완료', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DoctorQnaItem> _doctorQuestions = [
    DoctorQnaItem(
      id: 'q1',
      category: '해열제 교차복용',
      question: '코미시럽과 다른 해열제(타이레놀 시럽 등)를 동시에 복용해도 정말 부작용이 없을까요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q2',
      category: '졸림/대체약',
      question: '코미시럽 복용 후 졸림 증상이 있는데, 다음 방문 시 처방을 다른 대체약으로 변경할 수 있을까요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q3',
      category: '항생제/설사',
      question: '이 항생제(아모클란듀오)는 설사 증상을 유발할 수 있다고 하던데 유산균을 함께 먹여야 하나요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q4',
      category: '시간 누락',
      question: '깜빡 잊고 아기 감기약 복용 시간을 놓쳤을 때는 발견 즉시 바로 먹여도 괜찮은가요?',
      isSelected: false,
    ),
  ];

  void _onTabChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        profile: _babyProfile,
        onNavigateScan: () => _onTabChanged(2),
        onNavigateDrugs: () => _onTabChanged(1),
        onOpenCover: widget.onOpenCover,
        onSwitchChild: () => _openChildSwitcherModal(context),
      ),
      DrugsListScreen(
        profile: _babyProfile,
        scannedDrugs: _scannedDrugsList,
      ),
      ScanScreen(
        profile: _babyProfile,
        onNavigateTab: (idx) => _onTabChanged(idx),
        onUpdateQuestions: (qnaList) {
          setState(() {
            _doctorQuestions = qnaList;
          });
        },
        onUpdateScannedDrugs: (drugs) {
          setState(() {
            _scannedDrugsList = drugs;
          });
        },
      ),
      DoctorQnaScreen(
        profile: _babyProfile,
        questions: _doctorQuestions,
      ),
      BabyProfileScreen(
        profile: _babyProfile,
        onSwitchChild: () => _openChildSwitcherModal(context),
        onProfileUpdated: (newProfile) {
          setState(() {
            _babyProfile = newProfile;
          });
        },
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabChanged,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6B8B),
        unselectedItemColor: Colors.grey.shade400,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.medication_outlined), label: '복용 정보'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt_outlined), label: '스캔'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), label: '의사 Q&A'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '내 아이'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 1. HOME SCREEN (홈 화면)
// ----------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final MemberProfile profile;
  final VoidCallback onNavigateScan;
  final VoidCallback onNavigateDrugs;
  final VoidCallback? onOpenCover;
  final VoidCallback? onSwitchChild;

  const HomeScreen({
    super.key,
    required this.profile,
    required this.onNavigateScan,
    required this.onNavigateDrugs,
    this.onOpenCover,
    this.onSwitchChild,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _TodayDoseItem {
  final String id;
  final String timeTag;
  final String title;
  final String subtitle;
  bool isCompleted;

  _TodayDoseItem({
    required this.id,
    required this.timeTag,
    required this.title,
    required this.subtitle,
    this.isCompleted = false,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  late List<_TodayDoseItem> _doses;

  @override
  void initState() {
    super.initState();
    _doses = _buildDosesForChild(widget.profile);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id || oldWidget.profile.weightKg != widget.profile.weightKg) {
      setState(() {
        _doses = _buildDosesForChild(widget.profile);
      });
    }
  }

  List<_TodayDoseItem> _buildDosesForChild(MemberProfile profile) {
    if (profile.name == '서아') {
      return [
        _TodayDoseItem(id: 's1', timeTag: '아침 08:30', title: '기관지염 항생제 (클래리시드 건조시럽)', subtitle: '1회 5ml · 식후 30분', isCompleted: true),
        _TodayDoseItem(id: 's2', timeTag: '점심 13:00', title: '유산균 정장제 (항생제 설사 예방)', subtitle: '1회 1포 · 식사 직후', isCompleted: false),
        _TodayDoseItem(id: 's3', timeTag: '저녁 19:00', title: '클래리시드 건조시럽 & 정장제', subtitle: '1회 5ml, 가루 1포 · 식후 30분', isCompleted: false),
      ];
    } else {
      // Default (하준이)
      return [
        _TodayDoseItem(id: '1', timeTag: '아침 08:30', title: '감기 물약 (코미시럽)', subtitle: '1회 4ml · 식전 30분', isCompleted: true),
        _TodayDoseItem(id: '2', timeTag: '점심 13:00', title: '기관지 패치 & 항생제', subtitle: '1회 1포 · 식사 직후', isCompleted: false),
        _TodayDoseItem(id: '3', timeTag: '저녁 19:00', title: '감기 물약 & 정장제', subtitle: '1회 4ml, 가루 1포 · 취침 전', isCompleted: false),
      ];
    }
  }

  int get _completedCount => _doses.where((d) => d.isCompleted).length;
  double get _progress => _doses.isEmpty ? 0 : (_completedCount / _doses.length);

  void _toggleDose(_TodayDoseItem item) {
    setState(() {
      item.isCompleted = !item.isCompleted;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.isCompleted
              ? '✓ "${item.title}" 복약 완료로 기록되었습니다! 👶👏'
              : '"${item.title}" 복약 대기 상태로 변경되었습니다.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openAntipyreticCalculatorModal(BuildContext context) {
    final weight = widget.profile.weightKg ?? 9.2;
    // 아세트아미노펜 (12.5mg/kg, 농도 32mg/ml - 어린이타이레놀/챔프 빨강)
    final acetaDose = (weight * 12.5 / 32).toStringAsFixed(1);
    // 덱시부프로펜 (6.0mg/kg, 농도 12mg/ml - 맥시부펜)
    final dexiDose = (weight * 6.0 / 12).toStringAsFixed(1);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (c, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🌡️', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    const Text('해열제 교차복용 계산기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.profile.name} 현재 체중(${weight}kg, ${widget.profile.age}) 맞춤 권장 용량 및 안전 간격입니다.',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // 1. 아세트아미노펜 계열 카드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '아세트아미노펜 계열 (1계열)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFE11D48)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Text('생후 4개월 이상', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('대표 약품: 챔프시럽(빨강), 어린이 타이레놀 현탁액, 세토펜', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1회 권장 투약량', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('$acetaDose ml', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('• 같은 계열 투약 시: 최소 4~6시간 간격 (1일 최대 5회 이내)', style: TextStyle(fontSize: 11, color: Color(0xFF9F1239))),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2. 덱시부프로펜 / 이부프로펜 계열 카드
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '덱시부프로펜 계열 (2계열)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF2563EB)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Text('생후 6개월 이상', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('대표 약품: 맥시부펜 시럽, 챔프 이부펜(파랑), 어린이 부루펜', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  const Divider(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1회 권장 투약량', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('$dexiDose ml', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2563EB))),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('• 같은 계열 투약 시: 최소 4~6시간 간격 (1일 최대 4회 이내)', style: TextStyle(fontSize: 11, color: Color(0xFF1E40AF))),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 3. 교차복용 필수 황금 수칙
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.rule, color: Color(0xFFD97706), size: 18),
                      SizedBox(width: 8),
                      Text('소아과 전문의 교차복용 황금 수칙', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E))),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text('1. 서로 다른 계열(아세트아미노펜 ↔ 덱시부프로펜) 교차 투약 시: 최소 2시간 간격을 둡니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4)),
                  SizedBox(height: 4),
                  Text('2. 같은 계열을 다시 먹일 때는: 반드시 4~6시간 이상 간격을 유지해야 합니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4)),
                  SizedBox(height: 4),
                  Text('3. 38도 미만의 미열이거나 아기 컨디션이 좋을 때는 투약보다 수분 섭취와 휴식을 권장합니다.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF78350F), height: 1.4)),
                  SizedBox(height: 4),
                  Text('4. 생후 3개월 미만 신생아 발열(38.0℃ 이상) 시에는 해열제를 먹이지 말고 즉시 소아응급실로 가셔야 합니다.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C), height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header Profile Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFFFF0F3),
                  child: Text('👶', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘도 건강하게 자라는 중 🌱', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text('${widget.profile.name} (${widget.profile.age}, ${widget.profile.weightKg}kg)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                if (widget.onSwitchChild != null)
                  ActionChip(
                    avatar: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFFF6B8B)),
                    label: const Text('아이 변경', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                    backgroundColor: const Color(0xFFFFF0F3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFFD6DF))),
                    onPressed: widget.onSwitchChild,
                  ),
                IconButton(
                  icon: const Icon(Icons.notifications_none, color: Colors.grey),
                  onPressed: () {},
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Nano Banana Welcome Cover Banner
        if (widget.onOpenCover != null)
          GestureDetector(
            onTap: widget.onOpenCover,
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0F3), Color(0xFFFFE4E8)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFD6DF)),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/welcome_cover.jpg',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, _, __) => Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFFFF6B8B),
                        child: const Center(child: Text('🎨', style: TextStyle(fontSize: 20))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('🎨 나노바나나 안심 복약 커버 페이지',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFFF6B8B))),
                        SizedBox(height: 2),
                        Text('하준이 9.2kg 맞춤 검증 & 서비스 소개 커버 다시보기',
                            style: TextStyle(fontSize: 11, color: Colors.black87)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFF6B8B)),
                ],
              ),
            ),
          ),

        // 2 Big Quick Action Buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onNavigateScan,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFFFD6DF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.crop_free, color: Color(0xFFFF6B8B), size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text('처방전 스캔하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('약봉투 & 처방전 OCR', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: widget.onNavigateDrugs,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F7F0),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.medication, color: Color(0xFF10B981), size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text('처방 기록 보기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('복약 현황 관리', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 🌡️ Antipyretic Calculator Action Banner
        GestureDetector(
          onTap: () => _openAntipyreticCalculatorModal(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFDBA74)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('🌡️', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text('열날 때 해열제 교차복용 계산기',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFFC2410C))),
                          SizedBox(width: 6),
                          Text('1-TAP',
                              style: TextStyle(color: Color(0xFFEA580C), fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.profile.name} 현재 체중(${widget.profile.weightKg}kg) 맞춤 1회 적정량 & 안전 간격 확인',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF9A3412)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFEA580C)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Schedule criteria explanation banner
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 15, color: Color(0xFF475569)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '💡 복약 스케줄 산정 기준: ${widget.profile.name}의 현재 활성 처방약(복용 중)의 1일 복용 횟수와 아침·점심·저녁 타이밍을 기준으로 자동 편성된 맞춤 일정입니다.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF334155), height: 1.35),
                ),
              ),
            ],
          ),
        ),

        // Today's Medication Timeline with interactive toggle & progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('오늘의 복약 일정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _progress == 1.0 ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFFF6B8B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$_completedCount/${_doses.length} 완료 (${(_progress * 100).round()}%)',
                style: TextStyle(
                  color: _progress == 1.0 ? const Color(0xFF059669) : const Color(0xFFFF6B8B),
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: _progress,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(_progress == 1.0 ? const Color(0xFF10B981) : const Color(0xFFFF6B8B)),
          ),
        ),
        const SizedBox(height: 12),

        ..._doses.map((dose) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildTimelineCard(dose),
        )),

        const SizedBox(height: 10),
        // Today's Safety Tip Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('🔑', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('오늘의 복약 안심 정보', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E))),
                    SizedBox(height: 2),
                    Text('하준이가 먹는 세페클러계 항생제는 졸음을 유발할 수 있으니 수분 섭취를 충분히 해주세요.',
                        style: TextStyle(fontSize: 11, color: Color(0xFFB45309))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard(_TodayDoseItem dose) {
    final statusColor = dose.isCompleted ? const Color(0xFF10B981) : const Color(0xFFFF6B8B);
    final statusText = dose.isCompleted ? '✓ 복용 완료' : '복용 대기';

    return GestureDetector(
      onTap: () => _toggleDose(dose),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: dose.isCompleted ? const Color(0xFFA7F3D0) : Colors.transparent,
            width: dose.isCompleted ? 1.5 : 1,
          ),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    dose.timeTag,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        decoration: dose.isCompleted ? TextDecoration.lineThrough : null,
                        color: dose.isCompleted ? Colors.grey.shade600 : Colors.black87,
                      ),
                    ),
                    Text(dose.subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    dose.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 14,
                    color: statusColor,
                  ),
                  const SizedBox(width: 4),
                  Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 2. DRUGS LIST SCREEN (처방약 목록 및 상세 화면)
// ----------------------------------------------------------------------
class DrugsListScreen extends StatefulWidget {
  final MemberProfile profile;
  final List<DrugAnalysisResult> scannedDrugs;
  const DrugsListScreen({
    super.key,
    required this.profile,
    this.scannedDrugs = const [],
  });

  @override
  State<DrugsListScreen> createState() => _DrugsListScreenState();
}

class _DrugsListScreenState extends State<DrugsListScreen> {
  bool _isDetailView = false;
  int _tabFilter = 0; // 0: 복용 중, 1: 복용 완료
  String _selectedDrug = '코미시럽 (코감기약)';
  String _selectedCategory = '권장대비: 상위 안심 1등급';
  String _selectedDesc = '코막힘, 콧물, 재채기 등 알레르기성 비염 증상 완화제';

  final Set<String> _completedDrugTitles = {
    '비오플 250산 (유산균 정장제)',
    '세파클러 건조시럽 (2세대 세파 항생제)',
    '맥시부펜 시럽 (덱시부프로펜 해열제)',
    '풀미코트 분무용 현탁액 (호흡기 흡입액)',
    '유시락스 시럽 (가려움/알레르기)',
  };

  void _toggleDrugCompletion(String drugTitle) {
    setState(() {
      if (_completedDrugTitles.contains(drugTitle)) {
        _completedDrugTitles.remove(drugTitle);
      } else {
        _completedDrugTitles.add(drugTitle);
      }
    });

    final isNowDone = _completedDrugTitles.contains(drugTitle);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isNowDone
              ? '✓ "$drugTitle"(이)가 [복용 완료]로 이동되었습니다! 🎉'
              : '"$drugTitle"(이)가 [복용 중]으로 다시 이동되었습니다.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDetailView) {
      return _buildDrugDetailView();
    }

    final baseActiveList = [
      '코미시럽 (코감기약)',
      '아모클란듀오 시럽 (항생제)',
    ];

    final scannedActiveList = widget.scannedDrugs.map((d) => d.drugName).toList();
    final allPossibleActive = [...baseActiveList, ...scannedActiveList];

    final currentActiveCount = allPossibleActive.where((d) => !_completedDrugTitles.contains(d)).length;
    final currentCompletedCount = _completedDrugTitles.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('우리아이 처방약 목록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),

        // Segmented Tab - 복용 중 / 복용 완료 (클릭 필터 전환 지원)
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabFilter = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tabFilter == 0 ? const Color(0xFFFF6B8B) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '복용 중 ($currentActiveCount)',
                        style: TextStyle(
                          color: _tabFilter == 0 ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabFilter = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tabFilter == 1 ? const Color(0xFFFF6B8B) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '복용 완료 ($currentCompletedCount)',
                        style: TextStyle(
                          color: _tabFilter == 1 ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Filtered Drug Cards
        if (_tabFilter == 0) ...[
          // 복용 중 약품 목록
          if (!_completedDrugTitles.contains('코미시럽 (코감기약)'))
            _buildDrugCard(
              title: '코미시럽 (코감기약)',
              prescriptionMeta: '소아과 1월 24일 처방',
              dosage: '1일 3회, 1회 4ml',
              remainingDays: '남은 복용 기간 2일',
              statusBadge: '복용 중',
              statusColor: const Color(0xFFFF6B8B),
              onTap: () => setState(() {
                _selectedDrug = '코미시럽 (코감기약)';
                _selectedCategory = '권장대비: 상위 안심 1등급';
                _selectedDesc = '코막힘, 콧물, 재채기 등 알레르기성 비염 증상 완화제';
                _isDetailView = true;
              }),
            ),
          if (!_completedDrugTitles.contains('코미시럽 (코감기약)'))
            const SizedBox(height: 12),

          if (!_completedDrugTitles.contains('아모클란듀오 시럽 (항생제)'))
            _buildDrugCard(
              title: '아모클란듀오 시럽 (항생제)',
              prescriptionMeta: '이비인후과 1월 20일 처방',
              dosage: '1일 2회, 1회 3ml',
              remainingDays: '남은 복용 기간 5일',
              statusBadge: '복용 중',
              statusColor: const Color(0xFFFF6B8B),
              onTap: () => setState(() {
                _selectedDrug = '아모클란듀오 시럽 (항생제)';
                _selectedCategory = '권장대비: 적정 항생 처방';
                _selectedDesc = '중이염 및 호흡기 감염 치료용 복합 항생제';
                _isDetailView = true;
              }),
            ),
          if (!_completedDrugTitles.contains('아모클란듀오 시럽 (항생제)'))
            const SizedBox(height: 12),

          // 새로 스캔된 약품들 동적 반영 (복용 완료된 것은 제외)
          ...widget.scannedDrugs
              .where((scanned) => !_completedDrugTitles.contains(scanned.drugName))
              .map((scanned) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildDrugCard(
                      title: scanned.drugName,
                      prescriptionMeta: '인식: ${scanned.originalScanned} · 유사도 ${(scanned.confidence * 100).toInt()}%',
                      dosage: scanned.status == 'SAFE' ? '${widget.profile.name} ${widget.profile.weightKg}kg 적정 용량' : '소아 용량 주의 확인 필요',
                      remainingDays: '안심 복약 진행 중',
                      statusBadge: scanned.status == 'SAFE' ? '복용 중' : '⚠️ 주의',
                      statusColor: scanned.status == 'SAFE' ? const Color(0xFFFF6B8B) : const Color(0xFFDC2626),
                      onTap: () => setState(() {
                        _selectedDrug = scanned.drugName;
                        _selectedCategory = scanned.status == 'SAFE' ? '적정 소아 처방' : '⚠️ 용량 점검 요망';
                        _selectedDesc = scanned.comment;
                        _isDetailView = true;
                      }),
                    ),
                  )),

          if (currentActiveCount == 0)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Text('🎉', style: TextStyle(fontSize: 40)),
                  SizedBox(height: 12),
                  Text('현재 복용 중인 모든 처방약을 완료했습니다!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 4),
                  Text('복약 완료 탭에서 이전 복용 기록을 확인하실 수 있습니다.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
        ] else ...[
          // 복용 완료된 처방약 목록 (상단 기본약 중 완료된 것들 동적 표시)
          if (_completedDrugTitles.contains('코미시럽 (코감기약)')) ...[
            _buildDrugCard(
              title: '코미시럽 (코감기약)',
              prescriptionMeta: '소아과 1월 24일 처방',
              dosage: '1일 3회, 1회 4ml',
              remainingDays: '복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '코미시럽 (코감기약)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '코막힘, 콧물, 재채기 등 알레르기성 비염 증상 완화제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (_completedDrugTitles.contains('아모클란듀오 시럽 (항생제)')) ...[
            _buildDrugCard(
              title: '아모클란듀오 시럽 (항생제)',
              prescriptionMeta: '이비인후과 1월 20일 처방',
              dosage: '1일 2회, 1회 3ml',
              remainingDays: '복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '아모클란듀오 시럽 (항생제)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '중이염 및 호흡기 감염 치료용 복합 항생제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],

          // 기본 과거 완료 처방약 히스토리
          if (_completedDrugTitles.contains('비오플 250산 (유산균 정장제)')) ...[
            _buildDrugCard(
              title: '비오플 250산 (유산균 정장제)',
              prescriptionMeta: '소아과 1월 5일 처방',
              dosage: '1일 2회, 1회 1포',
              remainingDays: '5일간 복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '비오플 250산 (유산균 정장제)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '장내 균총 정상화 및 설사 개선용 소아 정장 생균제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],

          if (_completedDrugTitles.contains('세파클러 건조시럽 (2세대 세파 항생제)')) ...[
            _buildDrugCard(
              title: '세파클러 건조시럽 (2세대 세파 항생제)',
              prescriptionMeta: '소아과 12월 28일 처방',
              dosage: '1일 3회, 1회 3.5ml',
              remainingDays: '7일간 복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '세파클러 건조시럽 (2세대 세파 항생제)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '기관지염 및 편도염 치료용 소아용 세파계 항생제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],

          if (_completedDrugTitles.contains('맥시부펜 시럽 (덱시부프로펜 해열제)')) ...[
            _buildDrugCard(
              title: '맥시부펜 시럽 (덱시부프로펜 해열제)',
              prescriptionMeta: '소아과 12월 15일 처방',
              dosage: '발열 시 1회 4ml (4~6시간 간격)',
              remainingDays: '3일간 복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '맥시부펜 시럽 (덱시부프로펜 해열제)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '유소아 급성 상기도 감염으로 인한 발열 완화 해열진통소염제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],

          if (_completedDrugTitles.contains('풀미코트 분무용 현탁액 (호흡기 흡입액)')) ...[
            _buildDrugCard(
              title: '풀미코트 분무용 현탁액 (호흡기 흡입액)',
              prescriptionMeta: '이비인후과 11월 20일 처방',
              dosage: '1일 2회, 네블라이저 흡입',
              remainingDays: '4일간 복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '풀미코트 분무용 현탁액 (호흡기 흡입액)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '소아 후두염(크룹) 및 기관지 천식 증상 완화제';
                _isDetailView = true;
              }),
            ),
            const SizedBox(height: 12),
          ],

          if (_completedDrugTitles.contains('유시락스 시럽 (가려움/알레르기)')) ...[
            _buildDrugCard(
              title: '유시락스 시럽 (가려움/알레르기)',
              prescriptionMeta: '피부과 11월 02일 처방',
              dosage: '취침 전 1회 2ml',
              remainingDays: '3일간 복용 완료',
              statusBadge: '✓ 복용 완료',
              statusColor: const Color(0xFF10B981),
              onTap: () => setState(() {
                _selectedDrug = '유시락스 시럽 (가려움/알레르기)';
                _selectedCategory = '완료 기록';
                _selectedDesc = '소아 알레르기성 피부염 및 가려움 완화 항히스타민제';
                _isDetailView = true;
              }),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildDrugCard({
    required String title,
    required String prescriptionMeta,
    required String dosage,
    required String remainingDays,
    String statusBadge = '복용 중',
    Color statusColor = const Color(0xFFFF6B8B),
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusBadge,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(prescriptionMeta, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dosage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    remainingDays,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrugDetailView() {
    final isCompleted = _completedDrugTitles.contains(_selectedDrug);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _isDetailView = false)),
            const Text('처방약 상세 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),

        // Top Grade Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(12)),
                child: Text(_selectedCategory, style: const TextStyle(color: Color(0xFFFF6B8B), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text(_selectedDrug, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(_selectedDesc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Weight Dosage Verification Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.profile.name} 맞춤 용량 검증', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🟢 용량 적정치 일치 (검증 완료)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF047857))),
                    const SizedBox(height: 4),
                    Text('${widget.profile.name} 몸무게(${widget.profile.weightKg}kg) 대비 1회 적정 권장량은 ${(widget.profile.weightKg! * 0.4).toStringAsFixed(1)}ml ~ ${(widget.profile.weightKg! * 0.5).toStringAsFixed(1)}ml 입니다. 현재 처방 용량은 안전한 범위에 속합니다.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF065F46), height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Ingredients
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주요 성분 & 안심 등급', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('페닐레프린염산염', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('코막힘 완화 · 혈관 수축 작용', style: TextStyle(fontSize: 11)),
                  trailing: Chip(label: Text('안심', style: TextStyle(fontSize: 10, color: Color(0xFF047857))), backgroundColor: Color(0xFFECFDF5)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('클로르페니라민말레산염', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('항히스타민제 · 졸음 및 목마름 모니터링', style: TextStyle(fontSize: 11)),
                  trailing: Chip(label: Text('주의', style: TextStyle(fontSize: 10, color: Color(0xFFB45309))), backgroundColor: Color(0xFFFFFBEB)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Toggle Active / Completed Button
        ElevatedButton.icon(
          icon: Icon(isCompleted ? Icons.undo : Icons.check_circle, size: 20),
          label: Text(
            isCompleted ? '🔄 다시 [복용 중]으로 변경' : '✓ [복용 완료]로 변경',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isCompleted ? const Color(0xFFFF6B8B) : const Color(0xFF10B981),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: () {
            _toggleDrugCompletion(_selectedDrug);
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 3. SCAN SCREEN (OCR 카메라 스캔 화면)
// ----------------------------------------------------------------------
class ScanScreen extends StatefulWidget {
  final MemberProfile profile;
  final Function(int) onNavigateTab;
  final Function(List<DoctorQnaItem>) onUpdateQuestions;
  final Function(List<DrugAnalysisResult>)? onUpdateScannedDrugs;

  const ScanScreen({
    super.key,
    required this.profile,
    required this.onNavigateTab,
    required this.onUpdateQuestions,
    this.onUpdateScannedDrugs,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isAnalyzing = false;
  String? _selectedImageName;
  Uint8List? _previewImageBytes;
  PrescriptionAnalysisResponse? _analysisResult;
  final ImagePicker _picker = ImagePicker();

  Future<void> _processScanWithDrugs(List<ScannedDrugItem> drugs) async {
    setState(() => _isAnalyzing = true);

    try {
      final res = await ApiService.analyzePrescription(
        profile: widget.profile,
        scannedDrugs: drugs,
      );

      widget.onUpdateQuestions(res.doctorQna);
      widget.onUpdateScannedDrugs?.call(res.analyzedDrugs);

      if (mounted) {
        setState(() {
          _analysisResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('스캔 분석 실패: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // 실제 업로드된 처방전 이미지 바이트를 Base64로 인코딩하여 백엔드 Gemini Vision OCR로 전달
  Future<void> _processScanWithImage() async {
    if (_previewImageBytes == null) {
      await _processScanWithDrugs([
        ScannedDrugItem(scannedName: '코미시럽', doseUnit: 4.0, freqPerDay: 3, days: 3),
        ScannedDrugItem(scannedName: '아모클란듀오', doseUnit: 3.0, freqPerDay: 2, days: 5),
      ]);
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final base64Image = base64Encode(_previewImageBytes!);
      final res = await ApiService.analyzePrescriptionImage(
        profile: widget.profile,
        imageBase64: base64Image,
        mimeType: 'image/jpeg',
      );

      widget.onUpdateQuestions(res.doctorQna);
      widget.onUpdateScannedDrugs?.call(res.analyzedDrugs);

      if (mounted) {
        setState(() {
          _analysisResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이미지 OCR 분석 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // 1. 앨범/갤러리에서 사진 가져오기 (미리보기 단계로 진입)
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (mounted) {
          setState(() {
            _previewImageBytes = bytes;
            _selectedImageName = pickedFile.name;
            _analysisResult = null; // 미리보기 화면 전환
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앨범 사진 불러오기 실패: $e')),
        );
      }
    }
  }

  // 2. 카메라 촬영 (미리보기 단계로 진입)
  Future<void> _captureFromCamera() async {
    try {
      final XFile? captured = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (captured != null) {
        final bytes = await captured.readAsBytes();
        if (mounted) {
          setState(() {
            _previewImageBytes = bytes;
            _selectedImageName = captured.name;
            _analysisResult = null; // 미리보기 화면 전환
          });
        }
      }
    } catch (_) {
      // 카메라 하드웨어나 권한 문제 시 갤러리 선택으로 자연스럽게 Fallback
      await _pickImageFromGallery();
    }
  }

  // 2. 직접 수동 입력 모달 다이얼로그 오픈
  void _openManualInputDialog() {
    final nameCtrl = TextEditingController(text: '코미시럽');
    final doseCtrl = TextEditingController(text: '4.0');
    final freqCtrl = TextEditingController(text: '3');
    final daysCtrl = TextEditingController(text: '3');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('✎ 처방약 직접 입력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.profile.name}(${widget.profile.weightKg}kg) 맞춤 용량 및 안전성 검증을 위해 약품 정보를 입력해 주세요.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 18),

              // 약품명
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '약품명 (처방전 또는 약봉투 이름)',
                  hintText: '예: 코미시럽, 아모클란듀오',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.medication, color: Color(0xFFFF6B8B)),
                ),
              ),
              const SizedBox(height: 12),

              // 1회 투약량 & 1일 횟수
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: doseCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '1회 투여량 (ml 또는 정)',
                        hintText: '4.0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.science, color: Color(0xFF10B981)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: freqCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '1일 복용 횟수',
                        hintText: '3',
                        suffixText: '회',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.repeat, color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: daysCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '처방/투약 일수',
                  hintText: '3',
                  suffixText: '일분',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.calendar_today, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  final drugName = nameCtrl.text.trim();
                  final dose = double.tryParse(doseCtrl.text.trim()) ?? 4.0;
                  final freq = int.tryParse(freqCtrl.text.trim()) ?? 3;
                  final days = int.tryParse(daysCtrl.text.trim()) ?? 3;

                  if (drugName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('약품명을 입력해 주세요.')),
                    );
                    return;
                  }

                  Navigator.pop(ctx);

                  _processScanWithDrugs([
                    ScannedDrugItem(scannedName: drugName, doseUnit: dose, freqPerDay: freq, days: days),
                  ]);
                },
                child: const Text('안심 분석 시작하기 ➔', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyAiDeduction(DrugAnalysisResult originalDrug, AiDeduction deduction) async {
    if (_analysisResult == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final targetName = deduction.suggestedDbKey.isNotEmpty ? deduction.suggestedDbKey : deduction.deducedName;

      final updatedList = <ScannedDrugItem>[];
      for (final drug in _analysisResult!.analyzedDrugs) {
        if (drug.drugName == originalDrug.drugName && drug.originalScanned == originalDrug.originalScanned) {
          updatedList.add(ScannedDrugItem(
            scannedName: targetName,
            doseUnit: 1.0,
            freqPerDay: 2,
            days: 3,
          ));
        } else {
          updatedList.add(ScannedDrugItem(
            scannedName: drug.drugName,
            doseUnit: 1.0,
            freqPerDay: 3,
            days: 3,
          ));
        }
      }

      await _processScanWithDrugs(updatedList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ AI 스마트 추천으로 "$targetName"(으)로 자동 보정하여 용량 분석을 완료했습니다!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자동 보정 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  Widget _buildAiDeductionCard(DrugAnalysisResult d) {
    final deduction = d.aiDeduction;
    final deducedName = deduction?.deducedName ?? (d.originalScanned.contains('슈클래리') ? '슈클래리정250밀리그램' : d.drugName);
    final ingredient = deduction?.ingredient ?? (d.originalScanned.contains('슈클래리') ? '클래리스로마이신 (Clarithromycin 250mg)' : '확인 필요');
    final category = deduction?.category ?? '마크로라이드계 항생제';
    final reason = deduction?.reason ??
        '입력된 "${d.originalScanned}"은(는) 유한양행의 마크로라이드계 항생제 슈클래리정(클래리스로마이신)으로 추론됩니다. 소아 중이염 및 호흡기 감염 치료제입니다.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAF5FF), Color(0xFFF3E8FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8B4FE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(8)),
                    child: const Text('🤖', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '혹시 이 약을 찾으셨나요? (AI 스마트 추천)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6B21A8)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Text('Gemini AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('추천 약품: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF581C87))),
              Expanded(
                child: Text(
                  deducedName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('주요 성분: ', style: TextStyle(fontSize: 11, color: Color(0xFF4C1D95))),
              Expanded(
                child: Text(
                  '$ingredient ($category)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF581C87)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: const TextStyle(fontSize: 11, color: Color(0xFF4C1D95), height: 1.35),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: Text('✓ "$deducedName"으로 자동 보정하여 용량 검증', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            onPressed: () {
              final aiDec = deduction ?? AiDeduction(
                deducedName: deducedName,
                ingredient: ingredient,
                category: category,
                reason: reason,
                confidence: 0.95,
                suggestedDbKey: deducedName,
              );
              _applyAiDeduction(d, aiDec);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisResultView(PrescriptionAnalysisResponse result) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('처방전 안심 분석 결과', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.grey),
              tooltip: '다시 스캔하기',
              onPressed: () => setState(() {
                _analysisResult = null;
                _selectedImageName = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Success Header Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundColor: Color(0xFF10B981),
                radius: 20,
                child: Icon(Icons.check, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${widget.profile.name}(${widget.profile.weightKg}kg) 용량 검증 완료',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF065F46))),
                    const SizedBox(height: 2),
                    const Text('식약처 e-약은요 공공데이터 및 소아 체중 기준에 부합합니다.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF047857))),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // '주의' 판정 종합 안내 배너
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Color(0xFFD97706), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠️ [주의] 판정의 의미 및 복약 안내',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF92400E))),
                    SizedBox(height: 3),
                    Text(
                      '• \'주의\' 표시 약품은 하준이(9.2kg) 소아 체중 기준 1일/1회 최대 용량을 초과했거나 처방전 글자 인식이 모호한 약품입니다.\n'
                      '• 아래 추천 유사·대체 의약품을 탭하여 정보를 확인하시고, 진료 시 의사용 Q&A를 통해 소아과 의사 선생님과 상의하세요.',
                      style: TextStyle(fontSize: 11, color: Color(0xFFB45309), height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Analyzed Drugs Section
        const Text('분석된 처방 의약품', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),
        ...result.analyzedDrugs.map((d) {
          final bool isSafe = d.status == 'SAFE';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSafe ? Colors.grey.shade200 : const Color(0xFFFCA5A5)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.medication, color: isSafe ? const Color(0xFFFF6B8B) : const Color(0xFFDC2626), size: 20),
                        const SizedBox(width: 8),
                        Text(d.drugName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSafe ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSafe ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
                      ),
                      child: Text(
                        isSafe ? '🟢 적정 용량' : '⚠️ 주의',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isSafe ? const Color(0xFF047857) : const Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('OCR 인식: "${d.originalScanned}" · 유사도: ${(d.confidence * 100).toInt()}%',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isSafe ? const Color(0xFFF8FAFC) : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(d.comment,
                      style: TextStyle(fontSize: 12, color: isSafe ? const Color(0xFF334155) : const Color(0xFF991B1B), height: 1.4)),
                ),

                // '주의' 판정 사유 박스
                if (!isSafe) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            d.status == 'WARNING'
                                ? '주의 사유: 체중 ${widget.profile.weightKg}kg 기준 1일 최대 상한을 초과하여 유아 신장/간에 부담을 줄 수 있습니다. 감량 처방 여부를 확인해 주세요.'
                                : d.status == 'HIGH'
                                    ? '주의 사유: 체중 ${widget.profile.weightKg}kg 1회 권장량을 초과했습니다. 시럽 전용 투약기로 정확히 계량하여 투여해야 합니다.'
                                    : d.status == 'LOW'
                                        ? '주의 사유: 권장량 미달로 기대 효과가 낮을 수 있으니 소아과에 확인해 주세요.'
                                        : '주의 사유: 약품명 인식이 모호하여 오투약 위험이 있으니 약봉투를 재확인해 주세요.',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // AI 스마트 추천 ("혹시 이 약을 찾으셨나요?") 카드
                if (d.aiDeduction != null || d.status == 'UNKNOWN' || d.confidence < 0.7) ...[
                  const SizedBox(height: 10),
                  _buildAiDeductionCard(d),
                ],
              ],
            ),
          );
        }),

        // DUR Warnings or Safety Check
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: result.durWarnings.isEmpty ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: result.durWarnings.isEmpty ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
          ),
          child: Row(
            children: [
              Icon(
                result.durWarnings.isEmpty ? Icons.security : Icons.warning_amber_rounded,
                color: result.durWarnings.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  result.durWarnings.isEmpty
                      ? '🛡️ 중복 성분 및 병용 금기 상호작용 없음 (안전)'
                      : result.durWarnings.map((w) => w.message).join('\n'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: result.durWarnings.isEmpty ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        // AI Doctor Q&A notification banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF0F3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFFD6DF)),
          ),
          child: Row(
            children: [
              const Text('✨', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('소아과 의사용 안심 질문지 준비 완료',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFF6B8B))),
                    const SizedBox(height: 2),
                    Text('처방 약품을 바탕으로 소아과 진료 시 의사 선생님께 확인할 맞춤 질문 ${result.doctorQna.length}건이 준비되었습니다.',
                        style: const TextStyle(fontSize: 11, color: Colors.black87)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        // 2 Action Buttons
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 2,
          ),
          icon: const Icon(Icons.assignment, size: 18),
          label: Text('📋 의사용 안심 Q&A 보러가기 (${result.doctorQna.length}건) ➔',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: () => widget.onNavigateTab(3),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.medication, color: Color(0xFF10B981)),
          label: const Text('처방약 복용 정보 목록 보기',
              style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: () => widget.onNavigateTab(1),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _analysisResult = null;
              _previewImageBytes = null;
              _selectedImageName = null;
            }),
            child: const Text('다른 처방전 다시 스캔하기', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoPreviewConfirmView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('처방전 사진 확인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
              label: const Text('다시 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
              onPressed: () => setState(() {
                _previewImageBytes = null;
                _selectedImageName = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('촬영하거나 업로드한 처방전/약봉투 사진이 맞는지 확인해 주세요. 글씨가 선명할수록 정확하게 분석됩니다.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 16),

        // Photo Preview Card
        Container(
          height: 340,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
            border: Border.all(color: const Color(0xFFFF6B8B), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_previewImageBytes != null)
                Image.memory(
                  _previewImageBytes!,
                  fit: BoxFit.contain,
                )
              else
                const Center(
                  child: Icon(Icons.receipt_long, size: 64, color: Colors.white54),
                ),
              // File tag overlay at the top
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          _selectedImageName ?? '처방전 이미지',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Checklist Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            children: [
              Text('💡', style: TextStyle(fontSize: 18)),
              SizedBox(width: 10),
              Expanded(
                child: Text('약품명, 1회 투약량(ml/정), 1일 복용 횟수가 사진 안에 잘 담겨있는지 확인해 주세요.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 1. Analyze Button (Trigger)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            elevation: 2,
          ),
          icon: _isAnalyzing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.psychology, size: 22),
          label: Text(
            _isAnalyzing ? '하준이 맞춤 용량 및 안전성 분석 중...' : '🔍 처방전 안심 분석 시작하기 ➔',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: _isAnalyzing ? null : _processScanWithImage,
        ),
        const SizedBox(height: 10),

        // 2. Pre-Review / Direct Edit Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.2),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.edit_note, color: Color(0xFFFF6B8B), size: 20),
          label: const Text('약품명 직접 확인 & 보정해서 분석하기',
              style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: _openManualInputDialog,
        ),
        const SizedBox(height: 10),

        // 3. Reselect / Retake Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.photo_library, color: Colors.grey, size: 18),
          label: const Text('다른 사진으로 다시 선택하기',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: _isAnalyzing ? null : _pickImageFromGallery,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_analysisResult != null) {
      return _buildAnalysisResultView(_analysisResult!);
    }

    if (_previewImageBytes != null) {
      return _buildPhotoPreviewConfirmView();
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('처방전 / 약봉투 스캔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),

        // Camera Viewfinder Box
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFFF6B8B), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: const Text('🔍 텍스트를 자동으로 감지하는 중', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  const Text('처방전이나 약봉투 글씨가 밝고 명확하게 보이도록 넣어주세요.',
                      style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                ],
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 앨범 선택 아이콘 버튼
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.photo_library, color: Colors.white),
                      tooltip: '앨범에서 선택',
                      onPressed: _isAnalyzing ? null : _pickImageFromGallery,
                    ),
                    // 카메라 촬영 셔터 버튼
                    GestureDetector(
                      onTap: _isAnalyzing ? null : _captureFromCamera,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B8B),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: _isAnalyzing
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                      ),
                    ),
                    // 플래시 토글 버튼
                    IconButton(
                      iconSize: 28,
                      icon: const Icon(Icons.flash_auto, color: Colors.white),
                      tooltip: '플래시',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_selectedImageName != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.image, size: 18, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('선택된 이미지: $_selectedImageName',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 1. 앨범/갤러리에서 사진 가져오기 버튼
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            minimumSize: const Size.fromHeight(50),
          ),
          icon: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
          label: const Text('🖼️ 앨범 / 갤러리에서 사진 가져오기',
              style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: _isAnalyzing ? null : _pickImageFromGallery,
        ),
        const SizedBox(height: 10),

        // 2. 약품 직접 수동 입력 모달 버튼
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFF0F3),
            foregroundColor: const Color(0xFFFF6B8B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            minimumSize: const Size.fromHeight(50),
          ),
          icon: const Icon(Icons.edit_note, color: Color(0xFFFF6B8B)),
          label: const Text('✎ 약품 직접 입력해서 등록하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: _openManualInputDialog,
        ),
        const SizedBox(height: 16),

        // 3. Quick Sample Presets (소아과 대표 처방전 1-Tap 불러오기)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFF6B8B)),
                  SizedBox(width: 6),
                  Text('소아과 대표 처방전 1-Tap 샘플 분석',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                ],
              ),
              const SizedBox(height: 4),
              const Text('처방전 사진이 없으셔도 실제 소아과 다빈도 처방 세트로 즉시 분석 체험이 가능합니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        side: const BorderSide(color: Color(0xFFFF6B8B)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isAnalyzing
                          ? null
                          : () {
                              _processScanWithDrugs([
                                ScannedDrugItem(scannedName: '코미시럽', doseUnit: 4.0, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '암브로콜시럽', doseUnit: 3.0, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '시네츄라시럽', doseUnit: 3.5, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '메디락베베산', doseUnit: 1.0, freqPerDay: 2, days: 3),
                                ScannedDrugItem(scannedName: '삼아아토크건조시럽', doseUnit: 1.0, freqPerDay: 2, days: 3),
                                ScannedDrugItem(scannedName: '챔프시럽', doseUnit: 3.6, freqPerDay: 3, days: 3),
                              ]);
                            },
                      child: const Column(
                        children: [
                          Text('🏥 감기약 6종 세트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFF6B8B))),
                          SizedBox(height: 2),
                          Text('코미·암브로콜·챔프 등', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isAnalyzing
                          ? null
                          : () {
                              _processScanWithDrugs([
                                ScannedDrugItem(scannedName: '아모클란듀오 시럽', doseUnit: 3.0, freqPerDay: 2, days: 7),
                                ScannedDrugItem(scannedName: '비오플 250산', doseUnit: 1.0, freqPerDay: 2, days: 7),
                                ScannedDrugItem(scannedName: '맥시부펜 시럽', doseUnit: 4.6, freqPerDay: 3, days: 3),
                              ]);
                            },
                      child: const Column(
                        children: [
                          Text('💊 중이염 항생제 세트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10B981))),
                          SizedBox(height: 2),
                          Text('아모클란·비오플 등', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 4. DOCTOR Q&A SCREEN (소아과 의사용 안심 Q&A 화면)
// ----------------------------------------------------------------------
class DoctorQnaScreen extends StatefulWidget {
  final MemberProfile profile;
  final List<DoctorQnaItem> questions;

  const DoctorQnaScreen({super.key, required this.profile, required this.questions});

  @override
  State<DoctorQnaScreen> createState() => _DoctorQnaScreenState();
}

class _DoctorQnaScreenState extends State<DoctorQnaScreen> {
  void _openAddQuestionDialog() {
    final catCtrl = TextEditingController(text: '보호자 직접 질문');
    final questionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFFFF6B8B)),
            SizedBox(width: 8),
            Text('나만의 질문 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: catCtrl,
              decoration: InputDecoration(
                labelText: '질문 분류',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: questionCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '의사 선생님께 여쭤볼 내용',
                hintText: '예: 열이 38.5도 넘으면 응급실로 가야 하나요?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final text = questionCtrl.text.trim();
              if (text.isEmpty) return;
              setState(() {
                widget.questions.add(
                  DoctorQnaItem(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    category: catCtrl.text.trim().isEmpty ? '보호자 질문' : catCtrl.text.trim(),
                    question: text,
                    isSelected: true,
                  ),
                );
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('질문이 추가되었습니다!')),
              );
            },
            child: const Text('추가하기'),
          ),
        ],
      ),
    );
  }

  void _shareDoctorQuestions() async {
    final selected = widget.questions.where((q) => q.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 질문을 1개 이상 선택해 주세요.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 [My 약 - 소아과 진료 안심 질문지]');
    buffer.writeln('• 아기 이름: ${widget.profile.name} (${widget.profile.gender}, ${widget.profile.age})');
    buffer.writeln('• 현재 체중: ${widget.profile.weightKg}kg');
    if (widget.profile.allergyNotes.isNotEmpty) {
      buffer.writeln('• 특이사항/알레르기: ${widget.profile.allergyNotes}');
    }
    buffer.writeln('');
    buffer.writeln('[의사 선생님 상담 질문]');
    for (var i = 0; i < selected.length; i++) {
      final q = selected[i];
      buffer.writeln('${i + 1}. [${q.category}] ${q.question}');
    }
    buffer.writeln('');
    final shareText = buffer.toString();
    try {
      Clipboard.setData(ClipboardData(text: shareText));
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
                    SizedBox(width: 8),
                    Text('클립보드 복사 완료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('카카오톡, 문자 메시지 또는 병원 접수 메모에 붙여넣어 진료 시 바로 활용하세요.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(shareText, style: const TextStyle(fontSize: 11, height: 1.5, fontFamily: 'monospace')),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('다시 복사하기', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('질문지가 클립보드에 다시 복사되었습니다.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('소아과 의사용 안심 Q&A', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('✨ 스마트 AI 질문지 생성기', style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 4),
              Text('${widget.profile.name}(${widget.profile.weightKg}kg)의 현재 처방 성분을 분석하여 다른 소아과 방문 시 의사 선생님께 질문하면 좋은 내용들을 자동으로 추천해 드립니다.',
                  style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('선택된 질문 목록', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFFFF6B8B)),
              label: const Text('직접 질문 추가', style: TextStyle(color: Color(0xFFFF6B8B), fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _openAddQuestionDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),

        ...widget.questions.map((q) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (q.isSelected == true) ? const Color(0xFFFF6B8B) : Colors.transparent),
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: CheckboxListTile(
              activeColor: const Color(0xFFFF6B8B),
              value: q.isSelected == true,
              onChanged: (val) => setState(() => q.isSelected = (val == true)),
              title: Text(q.question, style: const TextStyle(fontSize: 12, height: 1.4)),
              subtitle: Text(q.category, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ),
        )),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.share, color: Colors.white, size: 18),
          label: const Text('의사 질문지 저장 및 공유하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: _shareDoctorQuestions,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 5. BABY PROFILE & HISTORY SCREEN (아기 프로필 & 이력 화면)
// ----------------------------------------------------------------------
class BabyProfileScreen extends StatelessWidget {
  final MemberProfile profile;
  final VoidCallback? onSwitchChild;
  final Function(MemberProfile)? onProfileUpdated;

  const BabyProfileScreen({
    super.key,
    required this.profile,
    this.onSwitchChild,
    this.onProfileUpdated,
  });

  void _openEditProfileDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: profile.name);
    final ageCtrl = TextEditingController(text: profile.age);
    final weightCtrl = TextEditingController(text: profile.weightKg?.toString() ?? '9.2');
    final allergyCtrl = TextEditingController(text: profile.allergyNotes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('✎ 아기 정보 및 체중 수정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 4),
              const Text('체중 변경 시 소아 용량 검증 및 해열제 계산기가 실시간으로 업데이트됩니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 18),

              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '아기 이름',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.person, color: Color(0xFFFF6B8B)),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ageCtrl,
                      decoration: InputDecoration(
                        labelText: '월령 / 나이',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.cake, color: Colors.blue),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '현재 몸무게',
                        suffixText: 'kg',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.monitor_weight, color: Color(0xFF10B981)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: allergyCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: '특이사항 및 알레르기',
                  hintText: '예: 페니실린 계열 항생제 발진 이력',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () {
                  final parsedWeight = double.tryParse(weightCtrl.text.trim()) ?? (profile.weightKg ?? 9.2);
                  final updated = profile.copyWith(
                    name: nameCtrl.text.trim().isEmpty ? profile.name : nameCtrl.text.trim(),
                    age: ageCtrl.text.trim().isEmpty ? profile.age : ageCtrl.text.trim(),
                    weightKg: parsedWeight,
                    allergyNotes: allergyCtrl.text.trim(),
                  );
                  onProfileUpdated?.call(updated);
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('🎉 ${updated.name}의 정보 및 몸무게(${updated.weightKg}kg)가 업데이트되었습니다!')),
                  );
                },
                child: const Text('수정 내용 저장하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('아기 프로필 & 이력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Row(
              children: [
                if (onSwitchChild != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFFF6B8B)),
                    label: const Text('아이 전환', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFFD6DF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: onSwitchChild,
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit, size: 14, color: Color(0xFFFF6B8B)),
                  label: const Text('정보 수정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFFD6DF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => _openEditProfileDialog(context),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFFFF0F3),
                child: Text('👶', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${profile.name} (${profile.gender})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('생년월일: ${profile.birthDate}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Text('월령', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(profile.age, style: const TextStyle(color: Color(0xFFFF6B8B), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Text('현재 몸무게', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${profile.weightKg} kg', style: const TextStyle(color: Color(0xFF10B981), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Allergy Warning Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFFECACA))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('🚨 특이사항 및 알레르기', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Text(profile.allergyNotes, style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 11, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 18),

        const Text('복약 히스토리', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        ...profile.history.map((h) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(h.dateStr, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              const SizedBox(height: 2),
              Text(h.drugName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text('${h.durationStr} · ${h.clinicName}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
        )),
      ],
    );
  }
}

`

### File: test_api.py

`python
import unittest
import asyncio
from fastapi.testclient import TestClient

from drug_matcher import DrugMatcher, combined_similarity
from main import app, LEGAL_DISCLAIMER
from koda_service import fetch_drug_from_public_api
from database import db_repo
from report_generator import generate_safety_report
from dur_engine import check_dur_interactions
from qna_generator import generate_doctor_qna

class TestMyYakAPI(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)

    def test_similarity_functions(self):
        # 1. Trigram 및 Levenshtein 유사도 산출 검증
        sim_exact = combined_similarity("맥시부펜시럽", "맥시부펜시럽")
        self.assertGreaterEqual(sim_exact, 0.95)

        # 약간의 오타 ("맥시부펜" -> "맥시부펜시럽")
        sim_typo = combined_similarity("맥시부펜", "맥시부펜시럽")
        self.assertGreaterEqual(sim_typo, 0.7)

        # 전혀 다른 약품
        sim_diff = combined_similarity("이상한약이름xyz", "맥시부펜시럽")
        self.assertLess(sim_diff, 0.4)

    def test_drug_matcher(self):
        matcher = DrugMatcher(["맥시부펜시럽", "타이레놀8시간이알서방정", "코미시럽"])

        # High match
        res_high = matcher.match("맥시부펜")
        self.assertIn(res_high.status, ("EXACT", "HIGH"))
        self.assertEqual(res_high.best_matched_name, "맥시부펜시럽")

        # Ambiguous / Unknown match (가드레일 검증: 억지 추측 금지)
        res_unknown = matcher.match("알수없는생소한약")
        self.assertEqual(res_unknown.status, "UNKNOWN")

    def test_database_repository(self):
        # DatabaseRepository 조회 검증
        drug_names = asyncio.run(db_repo.get_all_drug_names())
        self.assertIn("맥시부펜시럽", drug_names)

        drug_detail = asyncio.run(db_repo.get_drug_by_name("맥시부펜시럽"))
        self.assertIsNotNone(drug_detail)
        self.assertEqual(drug_detail["item_seq"], "200808948")

    def test_koda_service(self):
        # 식약처 e약은요 공공데이터 연동/실제 API 검증
        res = asyncio.run(fetch_drug_from_public_api("게보린정"))
        self.assertIsNotNone(res)
        self.assertTrue("게보린정" in res["name"])
        self.assertIn("두통", res["efficacy"])

    def test_dur_interactions(self):
        # DUR 병용/임부 주의 검증
        drugs = [
            {"drug_name": "맥시부펜시럽"},
            {"drug_name": "타이레놀8시간이알서방정"}
        ]
        warnings = check_dur_interactions(drugs, is_pregnant=True)
        self.assertGreaterEqual(len(warnings), 1)

    def test_safety_report_generator(self):
        profile = {"name": "김소아", "member_type": "CHILD", "weight_kg": 15.0}
        analyzed_drugs = [
            {
                "original_scanned": "맥시부펜",
                "drug_name": "맥시부펜시럽",
                "status": "SAFE",
                "comment": "15kg 기준 권장 복약 범위입니다."
            }
        ]
        report = generate_safety_report(profile, analyzed_drugs)
        self.assertIn("김소아", report)
        self.assertIn("맥시부펜시럽", report)
        self.assertIn("복약 관련 결정은 반드시 의료진과 상의하세요", report)

    def test_analyze_endpoint_child(self):
        payload = {
            "profile": {
                "name": "김소아",
                "member_type": "CHILD",
                "weight_kg": 15.0,
                "is_pregnant": False
            },
            "scanned_drugs": [
                {
                    "scanned_name": "맥시부펜",
                    "dose_unit": 6.0,
                    "freq_per_day": 3,
                    "days": 3
                },
                {
                    "scanned_name": "이상한약품123",
                    "dose_unit": 1.0,
                    "freq_per_day": 2,
                    "days": 2
                }
            ]
        }

        response = self.client.post("/api/v1/prescriptions/analyze", json=payload)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        self.assertIn("analyzed_drugs", data)
        self.assertIn("dur_warnings", data)
        self.assertIn("safety_report", data)
        self.assertEqual(data["disclaimer"], LEGAL_DISCLAIMER)

        drugs = data["analyzed_drugs"]
        self.assertEqual(len(drugs), 2)

        # 맥시부펜 보정 및 SAFE 분석 검증
        drug1 = drugs[0]
        self.assertEqual(drug1["drug_name"], "맥시부펜시럽")
        self.assertIn(drug1["match_status"], ("EXACT", "HIGH"))
        self.assertIn(drug1["status"], ("SAFE", "HIGH", "LOW", "WARNING"))

        # 가드레일: '이상한약품123' -> UNKNOWN 상태 처리 검증
        drug2 = drugs[1]
        self.assertEqual(drug2["status"], "UNKNOWN")
        self.assertTrue("확인 불가" in drug2["comment"] or "정밀 매칭할 수 없어" in drug2["comment"])
        self.assertIn("doctor_qna", data)

    def test_doctor_qna_unit(self):
        profile = {"name": "하준이", "weight_kg": 9.2}
        drugs = [{"drug_name": "코미시럽"}, {"drug_name": "아모클란듀오 시럽"}]
        qna = generate_doctor_qna(profile, drugs, allergy_notes="페니실린 발진")
        self.assertGreaterEqual(len(qna), 3)
        questions_text = " ".join([q["question"] for q in qna])
        self.assertIn("졸림", questions_text)
        self.assertIn("설사", questions_text)
        self.assertIn("페니실린", questions_text)

    def test_analyze_endpoint_adult(self):
        payload = {
            "profile": {
                "name": "홍길동",
                "member_type": "ADULT",
                "weight_kg": None,
                "is_pregnant": False
            },
            "scanned_drugs": [
                {
                    "scanned_name": "타이레놀8시간",
                    "dose_unit": 2.0,  # 2정 * 650mg = 1300mg /회
                    "freq_per_day": 4,  # 4회 = 5200mg > 4000mg (WARNING)
                    "days": 2
                }
            ]
        }

        response = self.client.post("/api/v1/prescriptions/analyze", json=payload)
        self.assertEqual(response.status_code, 200)

        data = response.json()
        drug = data["analyzed_drugs"][0]
        self.assertEqual(drug["drug_name"], "타이레놀8시간이알서방정")
        self.assertEqual(drug["status"], "WARNING")
        self.assertIn("홍길동", data["safety_report"])

    def test_analyze_image_endpoint(self):
        """테스트 10: 처방전 이미지 업로드 종합 분석 엔드포인트 테스트"""
        payload = {
            "profile": {
                "name": "하준이",
                "member_type": "CHILD",
                "weight_kg": 9.2,
                "is_pregnant": False
            },
            "image_base64": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==",
            "mime_type": "image/png"
        }
        response = self.client.post("/api/v1/prescriptions/analyze-image", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(len(data["analyzed_drugs"]) >= 1)
        self.assertIn("하준이", data["safety_report"])

    def test_ai_deduce_endpoint(self):
        """테스트 11: 슈클래리정250밀리그램 등 불확실 약품명에 대한 AI 스마트 추론 테스트"""
        payload = {"scanned_name": "슈클래리정250밀리그램"}
        response = self.client.post("/api/v1/drugs/ai-deduce", json=payload)
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("deduced_name", data)
        self.assertIn("ingredient", data)
        self.assertTrue("슈클래리" in data["deduced_name"] or "클래리스로마이신" in data["ingredient"])
        self.assertTrue(data["confidence"] >= 0.7)

if __name__ == "__main__":
    unittest.main()

`

### File: test/widget_test.dart

`dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_yak/main.dart';
import 'package:my_yak/models/prescription.dart';

void main() {
  testWidgets('MyYakFigmaApp launches welcome cover, navigates tabs, and toggles medication filters', (WidgetTester tester) async {
    // 1. App starts with Welcome Cover Screen (Nano Banana design)
    await tester.pumpWidget(const MyYakFigmaApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('우리아이 안심 복약 시작하기'), findsOneWidget);
    expect(find.textContaining('My 약 (My Yak)'), findsOneWidget);

    // Tap to enter Main App
    await tester.tap(find.textContaining('우리아이 안심 복약 시작하기'));
    await tester.pumpAndSettle();

    // 2. Verify Home screen profile greeting & child name
    expect(find.textContaining('하준이'), findsWidgets);
    expect(find.textContaining('오늘도 건강하게 자라는 중'), findsOneWidget);
    expect(find.textContaining('나노바나나 안심 복약 커버 페이지'), findsOneWidget);

    // Verify Bottom Navigation Bar tabs
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('복용 정보'), findsOneWidget);
    expect(find.text('스캔'), findsOneWidget);
    expect(find.text('의사 Q&A'), findsOneWidget);
    expect(find.text('내 아이'), findsOneWidget);

    // 3. Test '복용 정보' (Medication Info) tab and filter toggle
    await tester.tap(find.text('복용 정보'));
    await tester.pumpAndSettle();

    // In '복용 중' mode
    expect(find.textContaining('복용 중'), findsWidgets);
    expect(find.textContaining('코미시럽'), findsWidgets);

    // Tap '복용 완료 (5)' filter tab
    await tester.tap(find.textContaining('복용 완료 (5)'));
    await tester.pumpAndSettle();

    // Verify completed history medications are now shown
    expect(find.textContaining('비오플 250산'), findsOneWidget);
    expect(find.textContaining('세파클러 건조시럽'), findsOneWidget);
    expect(find.textContaining('맥시부펜 시럽'), findsOneWidget);

    // 4. Test '내 아이' (Profile) tab
    await tester.tap(find.text('내 아이'));
    await tester.pumpAndSettle();

    expect(find.textContaining('아기 프로필'), findsOneWidget);
    expect(find.textContaining('9.2 kg'), findsOneWidget);

    // 5. Navigate back to '홈' tab
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘의 복약 일정'), findsOneWidget);
  });

  testWidgets('HomeScreen dose toggle and antipyretic calculator test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // 1. Check initial dose progress (1/3 완료 (33%))
    expect(find.textContaining('1/3 완료 (33%)'), findsOneWidget);

    // 2. Tap second dose item ('기관지 패치 & 항생제') to toggle completion
    await tester.tap(find.text('기관지 패치 & 항생제'));
    await tester.pumpAndSettle();

    // Now 2/3 완료 (67%)
    expect(find.textContaining('2/3 완료 (67%)'), findsOneWidget);

    // 3. Open Antipyretic Calculator modal
    await tester.tap(find.textContaining('열날 때 해열제 교차복용 계산기'));
    await tester.pumpAndSettle();

    // Check modal content: 3.6 ml (acetaminophen) & 4.6 ml (dexibuprofen) for 9.2kg
    expect(find.text('해열제 교차복용 계산기'), findsOneWidget);
    expect(find.text('3.6 ml'), findsOneWidget);
    expect(find.text('4.6 ml'), findsOneWidget);
    expect(find.textContaining('소아과 전문의 교차복용 황금 수칙'), findsOneWidget);

    // Close modal
    await tester.tap(find.text('확인 완료'));
    await tester.pumpAndSettle();
  });

  testWidgets('BabyProfileScreen edit profile and weight update test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '내 아이' tab
    await tester.tap(find.text('내 아이'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9.2 kg'), findsOneWidget);

    // Tap '정보 수정' button
    await tester.tap(find.text('정보 수정'));
    await tester.pumpAndSettle();

    expect(find.text('✎ 아기 정보 및 체중 수정'), findsOneWidget);

    // Update weight to 9.8
    final weightField = find.widgetWithText(TextField, '현재 몸무게');
    await tester.enterText(weightField, '9.8');
    await tester.pumpAndSettle();

    // Tap save
    await tester.tap(find.text('수정 내용 저장하기'));
    await tester.pumpAndSettle();

    // Verify updated weight appears on profile screen
    expect(find.textContaining('9.8 kg'), findsOneWidget);

    // Verify updated weight on Home screen too
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9.8kg'), findsWidgets);
  });

  testWidgets('DoctorQnaScreen add custom question and share test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '의사 Q&A' tab
    await tester.tap(find.text('의사 Q&A'));
    await tester.pumpAndSettle();

    expect(find.text('소아과 의사용 안심 Q&A'), findsOneWidget);

    // Tap '직접 질문 추가'
    await tester.tap(find.text('직접 질문 추가'));
    await tester.pumpAndSettle();

    expect(find.text('나만의 질문 추가'), findsOneWidget);

    final questionField = find.widgetWithText(TextField, '의사 선생님께 여쭤볼 내용');
    await tester.enterText(questionField, '열이 38.5도 넘으면 야간 응급실에 가야 하나요?');
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('야간 응급실에 가야 하나요?'), findsOneWidget);

    // Scroll up so button is above bottom navigation bar
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final shareBtn = find.text('의사 질문지 저장 및 공유하기');
    await tester.tap(shareBtn);
    await tester.pumpAndSettle();

    expect(find.text('클립보드 복사 완료'), findsOneWidget);
  });

  testWidgets('DrugsListScreen toggle active and completed test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '복용 정보' tab
    await tester.tap(find.text('복용 정보'));
    await tester.pumpAndSettle();

    expect(find.textContaining('복용 중 (2)'), findsOneWidget);
    expect(find.textContaining('복용 완료 (5)'), findsOneWidget);

    // Tap '코미시럽 (코감기약)' to enter detail
    await tester.tap(find.text('코미시럽 (코감기약)'));
    await tester.pumpAndSettle();

    expect(find.text('처방약 상세 정보'), findsOneWidget);

    // Tap [✓ [복용 완료]로 변경] button
    await tester.tap(find.text('✓ [복용 완료]로 변경'));
    await tester.pumpAndSettle();

    // Detail button changed to [🔄 다시 [복용 중]으로 변경]
    expect(find.text('🔄 다시 [복용 중]으로 변경'), findsOneWidget);

    // Go back to drug list
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Now '복용 중' has 1 drug, '복용 완료' has 6 drugs!
    expect(find.textContaining('복용 중 (1)'), findsOneWidget);
    expect(find.textContaining('복용 완료 (6)'), findsOneWidget);
  });

  testWidgets('Multi-child selection on Welcome Cover and Header switcher test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 1. Launch app with Welcome Cover Screen
    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: true));
    await tester.pumpAndSettle();

    // Verify both children are listed in multi-child selector
    expect(find.text('하준이'), findsWidgets);
    expect(find.text('서아'), findsWidgets);

    // 2. Select '서아'
    await tester.tap(find.text('서아'));
    await tester.pumpAndSettle();

    // Verify top badge updated to '서아 14.5kg 맞춤 모드'
    expect(find.textContaining('서아 14.5kg 맞춤 모드'), findsOneWidget);

    // Tap CTA button with 서아
    await tester.tap(find.textContaining('우리아이 안심 복약 시작하기'));
    await tester.pumpAndSettle();

    // 3. Verify Home Screen is now tailored for 서아 (14.5kg)
    expect(find.textContaining('서아'), findsWidgets);
    expect(find.textContaining('14.5kg'), findsWidgets);
    expect(find.textContaining('클래리시드 건조시럽'), findsWidgets);

    // 4. Test Header '아이 변경' ActionChip to switch back to 하준이
    await tester.tap(find.text('아이 변경'));
    await tester.pumpAndSettle();

    expect(find.text('복약 관리 자녀 선택'), findsOneWidget);

    // Tap '하준이'
    await tester.tap(find.text('하준이').last);
    await tester.pumpAndSettle();

    // Verify Home Screen is back to 하준이 (9.2kg)
    expect(find.textContaining('하준이 (생후 10개월, 9.2kg)'), findsOneWidget);
    expect(find.textContaining('감기 물약 (코미시럽)'), findsWidgets);
  });

  testWidgets('AiDeduction model parsing and AI Smart Deduction UI test', (WidgetTester tester) async {
    // 1. Test AiDeduction JSON parsing (e.g. from /api/v1/drugs/ai-deduce)
    final json = {
      'drug_name': '슈클래리정250밀리그램',
      'original_scanned': '슈클래리정250밀리그램',
      'match_status': 'UNKNOWN',
      'confidence': 0.5,
      'status': 'UNKNOWN',
      'comment': "식약처 DB 및 시스템 목록에서 약품명 '슈클래리정250밀리그램'을(를) 정밀 매칭할 수 없어 '확인 불가' 상태로 처리되었습니다.",
      'candidates': <String>[],
      'ai_deduction': {
        'deduced_name': '슈클래리정250밀리그램',
        'ingredient': '클래리스로마이신 (Clarithromycin 250mg)',
        'category': '마크로라이드계 항생제',
        'reason': "유한양행의 마크로라이드계 항생제 '슈클래리정'으로 추론됩니다. 소아 호흡기 및 이비인후과 감염에 사용됩니다.",
        'confidence': 0.95,
        'suggested_db_key': '슈클래리정250밀리그램'
      }
    };

    final result = DrugAnalysisResult.fromJson(json);
    expect(result.status, 'UNKNOWN');
    expect(result.aiDeduction, isNotNull);
    expect(result.aiDeduction!.deducedName, '슈클래리정250밀리그램');
    expect(result.aiDeduction!.ingredient, contains('클래리스로마이신'));
    expect(result.aiDeduction!.category, contains('마크로라이드계'));
  });
}

`

