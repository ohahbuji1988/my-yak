import json
from typing import List, Dict, Any, Optional

def _get_portal_mom_cafe_fallback_qna(
    profile: Dict[str, Any],
    analyzed_drugs: List[Dict[str, Any]],
    allergy_notes: str = ""
) -> List[Dict[str, Any]]:
    """
    네이버 지식iN(소아청소년과 전문의 상담), 맘카페 단골 게시글, 구글 육아 포털에서
    부모들이 가장 불안해하고 실제로 의사에게 집요하게 확인하는 날카로운 실전 질문 풀
    """
    child_name = profile.get("name", "우리아이")
    weight_kg = profile.get("weight_kg")
    age = profile.get("age", "")

    questions: List[Dict[str, Any]] = []
    drug_names = [d.get("drug_name", "") for d in analyzed_drugs]
    combined_names = " ".join(drug_names)

    # 1. 맘카페 검색 1위: 약 먹이기 전쟁 (쓴맛 거부, 구토, 음식 혼합)
    if any(k in combined_names for k in ["클래리", "슈클래리", "항생제", "가루약", "시럽", "코미"]):
        questions.append({
            "id": "q_bitter_taste_mix",
            "category": "맘카페 1위: 쓴맛 거부 & 음식 혼합",
            "question": f"약(특히 항생제나 가루약) 특유의 쓴맛이나 냄새 때문에 {child_name}가 완강히 거부하고 게워내는데, 주스·초코시럽·아이스크림·우유에 섞여 먹여도 성분 침전이나 흡수 저하, 약효 파괴가 없나요?",
            "is_default_selected": True
        })

    # 2. 소아과 단골 질문: 항생제 설사/기저귀 발진 vs 임의 중단 딜레마
    if any(k in combined_names for k in ["아모클란", "아모크라", "항생제", "클라불란산", "세파", "클래리", "슈클래리"]):
        questions.append({
            "id": "q_antibiotic_diarrhea_dilemma",
            "category": "소아과 단골: 항생제 설사 vs 임의 중단",
            "question": f"항생제 복용 후 물설사나 엉덩이 짓무름(기저귀 발진)이 심해질 때, 임의로 중단하면 내성균 위험이 크다는데 비오플(유산균)을 2시간 간격으로 먹이며 버텨야 하나요, 아니면 즉시 내원하여 다른 계열 항생제로 변경해야 하나요?",
            "is_default_selected": True
        })
        questions.append({
            "id": "q_antibiotic_finish_exact",
            "category": "지식iN 전문의 상담: 완약 복용 일수",
            "question": f"열이 완전히 내리고 콧물·기침 증상이 겉보기에 멀쩡해져도, 내성균 방지를 위해 처방된 항생제 일수(총 일수)를 빠짐없이 끝까지 다 먹여야 하는 약이 정확히 어떤 것인가요?",
            "is_default_selected": True
        })

    # 3. 코감기약 / 항히스타민제 관련 질문 (포털 최빈도: 심한 졸림 및 처짐)
    if any(k in combined_names for k in ["코미시럽", "코싹", "항히스타민", "페닐레프린", "비염", "감기"]):
        questions.append({
            "id": "q_antihistamine_drowsy",
            "category": "지식iN 다빈도: 심한 졸림·처짐",
            "question": f"코감기약 복용 후 아이가 평소보다 너무 졸려하거나 멍하게 처지는데, 낮 복용량을 조절하거나 다음 진료 시 졸림이 덜한 대체약으로 변경이 가능한가요?",
            "is_default_selected": True
        })

    # 4. 약물 과다 복용(오버도즈) 불안: 종합 감기시럽과 해열제 성분 중복
    if any(k in combined_names for k in ["코미시럽", "코싹", "페닐레프린", "시네츄라", "암브로콜", "콜대원", "판콜"]):
        questions.append({
            "id": "q_overdose_duplicate_check",
            "category": "포털 최다 검색: 감기약+해열제 중복",
            "question": f"처방된 감기 시럽약 안에 해열·진통 성분이나 항히스타민이 복합되어 있어, 열이 오를 때 맥시부펜이나 챔프/타이레놀을 추가로 먹이면 {child_name}({weight_kg or ''}kg)의 1일 안전 허용치를 초과하지 않나요?",
            "is_default_selected": True
        })

    # 4. 야간 발열 응급 대처: 2시간 교차복용 후 저체온증 대처
    if any(k in combined_names for k in ["맥시부펜", "타이레놀", "아세트아미노펜", "이부프로펜", "덱시부프로펜", "챔프", "해열"]):
        questions.append({
            "id": "q_hypothermia_alert",
            "category": "야간 응급: 교차복용 후 저체온증",
            "question": "열이 안 떨어져 2시간 간격으로 해열제를 교차복용시켰는데, 땀을 뻘뻘 흘리며 갑자기 35.5도 이하 저체온으로 떨어졌을 때 옷을 껴입히는 것 외에 즉각적인 대처 가이드가 어떻게 되나요?",
            "is_default_selected": True
        })

    # 5. 어린이집/유치원 보관 & 투약 의뢰
    questions.append({
        "id": "q_daycare_storage",
        "category": "워킹맘 필수: 어린이집 실온 보관",
        "question": "점심 복용분을 어린이집에 투약 의뢰할 때 실온에 반나절 두어도 약효가 변질되지 않는 약인지, 반드시 보냉백에 얼음팩과 함께 냉장 보관을 요청해야 하는 약인가요?",
        "is_default_selected": False
    })

    # 6. 복약 도중 피부 발진: 바이러스성 열꽃 vs 약물 알레르기 감별
    questions.append({
        "id": "q_rash_differentiation",
        "category": "맘카페 다빈도: 약 발진 vs 열꽃 감별",
        "question": f"약을 먹는 도중 아이 얼굴이나 몸에 오돌토돌한 붉은 발진이 올라왔을 때, 단순 바이러스성 열꽃인지 이번 처방약에 의한 약물 알레르기인지 병원 방문 전 집에서 어떻게 구별할 수 있나요?",
        "is_default_selected": False
    })

    # 7. 기관지 확장제/패치 관련 부작용 (손떨림, 가슴두근거림, 수면장애)
    if any(k in combined_names for k in ["아토크", "기관지", "패치", "기관지확장", "호쿠테롤"]):
        questions.append({
            "id": "q_broncho_side_effect",
            "category": "지식iN 다빈도: 기관지 패치 수면장애",
            "question": "기관지 패치나 확장제 투약 후 아이가 가슴 두근거림이나 손 떨림, 밤에 잠을 안 자고 심하게 보채는 각성 반응이 있을 때 즉시 떼어내거나 투약을 중단해야 하나요?",
            "is_default_selected": True
        })

    # 8. 기존 알레르기 특이사항 교차 반응 확인
    if allergy_notes and ("페니실린" in allergy_notes or allergy_notes.strip()):
        questions.append({
            "id": "q_allergy_cross_check",
            "category": "🚨 알레르기 교차 반응 경고",
            "question": f"{child_name}에게 기존 알레르기/발진 이력('{allergy_notes}')이 등록되어 있는데, 이번 처방약 중 분자 구조상 교차 알레르기를 유발할 수 있는 계열이 100% 배제되어 처방된 것인지 확인 부탁드립니다.",
            "is_default_selected": True
        })

    return questions

async def generate_doctor_qna_async(
    profile: Dict[str, Any],
    analyzed_drugs: List[Dict[str, Any]],
    allergy_notes: str = ""
) -> List[Dict[str, Any]]:
    """
    Gemini AI를 활용하여 네이버 지식iN 소아청소년과 전문의 상담, 맘카페 최빈도 게시글,
    구글 육아 포털 실제 검색어 기반의 고도로 날카롭고 현실적인 소아과 의사용 질문지를 실시간 생성합니다.
    (실패 시 고도화된 실전 포털/맘카페 FAQ 풀로 자동 Fallback)
    """
    child_name = profile.get("name", "우리아이")
    weight_kg = profile.get("weight_kg", "")
    age = profile.get("age", "")
    gender = profile.get("gender", "")

    drugs_desc = []
    for d in analyzed_drugs:
        name = d.get("drug_name", "")
        purpose = d.get("purpose", "")
        status = d.get("status", "")
        dose = d.get("scanned_dose_unit", "")
        freq = d.get("scanned_freq_per_day", "")
        storage = d.get("storage_method", "")
        drugs_desc.append(f"- {name} (1회 {dose}ml/정, 1일 {freq}회, 용도: {purpose}, 판정: {status}, 보관: {storage})")

    drugs_text = "\n".join(drugs_desc) if drugs_desc else "처방약 목록 확인 필요"

    try:
        from gemini_service import call_gemini_generate

        prompt = (
            f"당신은 소아청소년과 전문의이자 대한민국 맘카페, 네이버 지식iN, 구글 육아 포털의 실전 질의응답 빅데이터를 꿰뚫고 있는 소아 복약 전문가입니다.\n\n"
            f"[환아 정보]\n"
            f"- 이름: {child_name} ({gender}, {age})\n"
            f"- 체중: {weight_kg}kg\n"
            f"- 특이사항/알레르기: {allergy_notes or '없음'}\n\n"
            f"[처방된 의약품 목록]\n"
            f"{drugs_text}\n\n"
            "위 처방전과 아이의 상태를 분석하여, 보호자가 소아과 의사·약사 진료실에서 실제로 반드시 확인해야 할 **가장 날카롭고 현실적인 질문 4~5개**를 생성하세요.\n"
            "일반적이고 뻔한 질문은 배제하고, 실제 맘카페와 네이버 지식iN에서 부모들이 가장 불안해하는 주제(쓴맛 거부 시 혼합 가능 식품, 항생제 설사 시 유산균 간격 vs 중단 기준, 감기약+해열제 중복 오버도즈, 2시간 교차복용 후 저체온증 대처, 어린이집 실온 보관 등)를 환아의 실제 처방약 이름과 연계하여 1~2문장으로 날카롭게 작성하세요.\n\n"
            "반드시 아래 JSON 배열 형식으로만 응답하세요 (마크다운 block 없이 순수 JSON 배열 문자열):\n"
            "[\n"
            "  {\n"
            '    "id": "q1",\n'
            '    "category": "맘카페 1위: 쓴맛 거부 & 혼합 복용",\n'
            '    "question": "실제 의사에게 건넬 구체적이고 정곡을 찌르는 1~2문장의 질문",\n'
            '    "is_default_selected": true\n'
            "  }\n"
            "]"
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
            if isinstance(data, list) and len(data) >= 3:
                return data
    except Exception as e:
        print(f"[generate_doctor_qna_async Gemini Fallback]: {e}")

    # Fallback to high-precision portal/mom-cafe FAQ pool
    return _get_portal_mom_cafe_fallback_qna(profile, analyzed_drugs, allergy_notes)

def generate_doctor_qna(
    profile: Dict[str, Any],
    analyzed_drugs: List[Dict[str, Any]],
    allergy_notes: str = ""
) -> List[Dict[str, Any]]:
    """동기식 호출을 위한 포털·맘카페 다빈도 실전 질문 선별기"""
    return _get_portal_mom_cafe_fallback_qna(profile, analyzed_drugs, allergy_notes)

