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
    storage_method: str = "실온 보관(1~30°C)"
    discard_days: Optional[int] = None
    is_antibiotic: bool = False
    compliance_note: str = ""
    purpose: str = ""

@dataclass
class MemberProfile:
    name: str
    member_type: str               # 'CHILD' 또는 'ADULT'
    weight_kg: Optional[float] = None
    is_pregnant: bool = False

from drug_matcher import DrugMatcher, MatchResult

# 로컬 캐시 겸용 핵심 의약품 DB
DRUG_DATABASE = {
    "맥시부펜시럽": DrugInfo("200808948", "맥시부펜시럽", "해열진통소염제", 12.0, 1200.0, 5.0, 7.0, 28.0, storage_method="실온 보관 (1~30°C)", discard_days=30, purpose="발열 완화 및 목 통증·염증 가라앉힘 (해열소염진통제)"),
    "아모크라네오시럽": DrugInfo("200401824", "아모크라네오시럽", "항생제", 50.0, 2000.0, 20.0, 45.0, 90.0, warning_note="조제 후 냉장 보관 필수", storage_method="🧊 냉장 보관(2~8°C) 필수", discard_days=7, is_antibiotic=True, compliance_note="내성균 방지를 위해 증상이 호전되어도 처방 일수 끝까지 완복용(Complete Course)하세요.", purpose="중이염·부비동염·세균 감염 치료 (페니실린계 항생제)"),
    "코미시럽": DrugInfo("199901533", "코미시럽", "항히스타민/비염", 2.5, 50.0, 1.0, 3.0, 10.0, storage_method="실온 보관 (차광)", discard_days=30, purpose="코막힘·콧물·재채기 알레르기 증상 완화 (코감기약)"),
    "타이레놀8시간이알서방정": DrugInfo("199401777", "타이레놀8시간이알서방정", "해열진통제", 650.0, 4000.0, warning_note="8시간 간격 복용, 1일 6정 초과 금지", storage_method="실온 보관", purpose="열 내림 및 두통·신체 통증 완화 (해열진통제)"),
    "무코스타정": DrugInfo("199100868", "무코스타정", "위점막보호제", 100.0, 300.0, warning_note="위염, 위궤양 점막 보호", storage_method="실온 보관", purpose="위점막 보호 및 속쓰림·위염 증상 개선"),
    "코싹엘정": DrugInfo("200806456", "코싹엘정", "비염/알레르기", 5.0, 10.0, warning_note="졸림 주의, 슈도에페드린 복합제", storage_method="실온 보관", purpose="코막힘 뚫림 및 알레르기 비염 증상 완화"),
    "웅스코민정": DrugInfo("200003058", "웅스코민정", "진경제/위장관운동", 10.0, 30.0, warning_note="복통 및 경련 완화", storage_method="실온 보관", purpose="복통 및 배앓이·위장관 경련 완화"),
    "슈클래리정250밀리그램": DrugInfo("200000001", "슈클래리정250밀리그램", "항생제", 250.0, 1000.0, 7.5, 15.0, 30.0, warning_note="마크로라이드계 항생제. 1일 2회 복용. 소아는 정제 분쇄 또는 시럽 제형 확인 권장", storage_method="실온 보관", is_antibiotic=True, compliance_note="처방 일수 끝까지 완복용하세요.", purpose="기도·기관지염 및 세균성 호흡기 감염 치료 (항생제)"),
    "클래리시드건조시럽": DrugInfo("199500001", "클래리시드건조시럽", "항생제", 25.0, 1000.0, 7.5, 15.0, 30.0, warning_note="마크로라이드계 소아 시럽. 1일 2회 복용 권장", storage_method="🌡️ 실온 보관(15~30°C) (냉장 보관 시 쓴맛 증가 및 침전 주의)", discard_days=14, is_antibiotic=True, compliance_note="처방 일수 끝까지 완복용하세요.", purpose="급성 기관지염·폐렴 등 소아 호흡기 감염 치료 (항생제)")
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
                "ai_deduction": None,
                "storage_method": drug.storage_method,
                "discard_days": drug.discard_days,
                "is_antibiotic": drug.is_antibiotic,
                "compliance_note": drug.compliance_note if drug.compliance_note else None,
                "purpose": drug.purpose
            }
        # 소아 분석 분기 (체중 기준)
        else:
            if profile.weight_kg <= 0:
                return {
                    "drug_name": drug.name,
                    "original_scanned": drug_name,
                    "match_status": match_result.status,
                    "confidence": match_result.confidence,
                    "status": "WARNING",
                    "comment": "체중은 0kg 초과여야 정확한 소아 안전 용량을 계산할 수 있습니다.",
                    "candidates": candidates_list,
                    "ai_deduction": None
                }

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
                "ai_deduction": None,
                "storage_method": drug.storage_method,
                "discard_days": drug.discard_days,
                "is_antibiotic": drug.is_antibiotic,
                "compliance_note": drug.compliance_note,
                "purpose": drug.purpose
            }

    # 2. 유사도가 모호한 경우 (AMBIGUOUS): AI 추론 병행
    if match_result.status == "AMBIGUOUS":
        matched_or_scanned = match_result.best_matched_name or drug_name
        candidates_list = get_similar_candidates(matched_or_scanned, base_candidates=raw_candidates)
        ai_deduction = await deduce_drug_with_gemini(drug_name)
        # 가능하면 로컬 DB 매칭 약품의 보관법 정보도 포함
        local_drug = DRUG_DATABASE.get(match_result.best_matched_name or "") if match_result.best_matched_name else None
        return {
            "drug_name": matched_or_scanned,
            "original_scanned": drug_name,
            "match_status": "AMBIGUOUS",
            "confidence": match_result.confidence,
            "status": "UNKNOWN",
            "comment": f"약품명 '{drug_name}'의 인식이 모호합니다. 아래 AI 추천 정보를 확인해 주세요.",
            "candidates": candidates_list,
            "ai_deduction": ai_deduction,
            "storage_method": local_drug.storage_method if local_drug else None,
            "discard_days": local_drug.discard_days if local_drug else None,
            "is_antibiotic": local_drug.is_antibiotic if local_drug else False,
            "compliance_note": local_drug.compliance_note if local_drug and local_drug.compliance_note else None,
            "purpose": ai_deduction.get("category", "용도 확인 필요") if ai_deduction else "용도 확인 필요"
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

            # 식약처 허가 의약품이지만, 소아 체중당 용량(mg/kg) 공식 기준 미등록 시 용량은 '확인 필요' 상태로 처리
            return {
                "drug_name": cached_info["name"],
                "original_scanned": drug_name,
                "match_status": "PUBLIC_MATCH",
                "confidence": 0.85,
                "status": "UNKNOWN",
                "comment": f"식약처 허가 의약품이나, 체중별 소아 권장 용량 기준 정보가 미등록되어 용량 검증은 '확인 필요' 상태입니다. [효능: {efficacy_brief}]",
                "safety_guide": f"주의사항: {warning_brief} (정확한 1회 투여량은 의사·약사에게 직접 확인하세요)",
                "candidates": candidates_list,
                "ai_deduction": None,
                "purpose": efficacy_brief
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
        "ai_deduction": ai_deduction,
        "purpose": ai_deduction.get("category", "의사·약사 상담 필요") if ai_deduction else "의사·약사 상담 필요"
    }