from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
import asyncio

from dosage_engine import MemberProfile, evaluate_dosage_async, deduce_drug_with_gemini
from report_generator import generate_safety_report, generate_safety_report_async
from dur_engine import check_dur_interactions
from qna_generator import generate_doctor_qna, generate_doctor_qna_async
from gemini_service import call_gemini_vision_ocr
from antipyretic_calculator import get_vomit_guidance, calculate_next_dose_timing
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
    scanned_drugs: List[ScannedDrugItem] = Field(..., min_length=1, description="OCR 처방 약품 목록")

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

from fastapi.responses import FileResponse
import os

WEB_BUILD_DIR = os.path.join(os.path.dirname(__file__), "build", "web")

@app.get("/")
def read_root():
    index_file = os.path.join(WEB_BUILD_DIR, "index.html")
    if os.path.exists(index_file):
        return FileResponse(index_file)
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

    raw_results = await asyncio.gather(*tasks, return_exceptions=True)

    results = []
    for item, res in zip(request.scanned_drugs, raw_results):
        if isinstance(res, Exception):
            res_dict = {
                "drug_name": item.scanned_name,
                "original_scanned": item.scanned_name,
                "match_status": "ERROR",
                "confidence": 0.0,
                "status": "UNKNOWN",
                "comment": f"약품 분석 중 일시적 오류가 발생하여 안전 확인이 필요합니다: {str(res)}",
                "candidates": [],
                "ai_deduction": None
            }
        else:
            res_dict = res
        res_dict["scanned_dose_unit"] = item.dose_unit
        res_dict["scanned_freq_per_day"] = item.freq_per_day
        res_dict["scanned_days"] = item.days
        results.append(res_dict)

    # DUR 약물 상호작용 및 금기 검증
    dur_warnings = check_dur_interactions(results, is_pregnant=request.profile.is_pregnant)

    # 소아과 의사용 안심 Q&A 질문지 및 Stage 2 LLM 안심 복약 리포트 비동기 병렬 생성
    doctor_qna_task = generate_doctor_qna_async(
        profile=request.profile.model_dump(),
        analyzed_drugs=results,
        allergy_notes=request.profile.allergy_notes or ""
    )
    safety_report_task = generate_safety_report_async(request.profile.model_dump(), results)

    doctor_qna, report_text = await asyncio.gather(doctor_qna_task, safety_report_task)

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
        "questions": await generate_doctor_qna_async(
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

@app.get(
    "/api/v1/clinical/vomit-guide",
    summary="소아 복약 후 구토 시 임상 재투약 가이드라인",
    description="복약 후 경과 시간(분)에 따라 즉시 재투약 여부 및 안전 수칙을 반환합니다."
)
def vomit_guide_endpoint(elapsed_minutes: int = 15):
    return get_vomit_guidance(elapsed_minutes)

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
        # MED-01: OCR 인식 실패 시 임의의 데모 약품을 생성하지 않고 명확한 에러 코드로 재촬영/수동 입력 안내
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={
                "code": "OCR_EXTRACTION_FAILED",
                "message": (
                    "처방전 또는 약봉투에서 약품 정보를 정확히 읽지 못했습니다. "
                    "약봉투의 글씨가 선명하도록 밝은 곳에서 다시 촬영하거나, 직접 약품명을 입력해 주세요."
                )
            }
        )

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

# ==============================================================================
# Flutter Web 올인원 단일 서빙 (PWA 배포 모드)
# build/web 디렉터리가 존재하면 FastAPI가 웹 화면과 PWA를 메인 주소에서 직접 서빙
# ==============================================================================
from fastapi.staticfiles import StaticFiles

if os.path.exists(WEB_BUILD_DIR):
    app.mount("/", StaticFiles(directory=WEB_BUILD_DIR, html=True), name="flutter_web")
