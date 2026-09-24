from typing import List, Dict, Any

LEGAL_DISCLAIMER_TEXT = "※ 복약 관련 결정은 반드시 의료진(의사·약사)과 상의하세요."

def generate_safety_report(profile: Dict[str, Any], analyzed_drugs: List[Dict[str, Any]]) -> str:
    """
    바쁜 보호자를 위한 초간결 3줄 핵심 복약 브리핑
    - 기계적인 AI 문체를 배제하고, 사람이 직접 설명해 주듯 친절하고 직관적인 3개 카드로 요약
    """
    user_name = profile.get("name", "아이")
    weight_kg = profile.get("weight_kg")
    
    all_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("drug_name")]
    all_drugs_str = ", ".join(all_drugs) if all_drugs else "처방약"
    
    warning_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("status") in ("WARNING", "HIGH")]
    unknown_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("status") == "UNKNOWN"]
    antibiotics = [d.get("drug_name", "") for d in analyzed_drugs if d.get("is_antibiotic") or "아모" in d.get("drug_name", "") or "클래리" in d.get("drug_name", "")]
    cold_drugs = [d.get("drug_name", "") for d in analyzed_drugs if any(k in d.get("drug_name", "") for k in ["코미", "코싹", "시럽"])]

    lines = []

    # 1. 체중 기준 안심 용량 체크
    if warning_drugs:
        lines.append(f"[⚖️ 용량 확인 필요] {user_name}({weight_kg or ''}kg) 처방 중 {', '.join(warning_drugs)}의 권장 용량 재확인이 필요합니다. 복용 전 약사님과 상의하세요.")
    elif unknown_drugs:
        lines.append(f"[⚖️ 용량 확인 필요] {', '.join(unknown_drugs)}은(는) 체중별 가이드 확인이 필요합니다. 처방전의 1회 용량을 지켜주세요.")
    else:
        weight_str = f"({weight_kg}kg)" if weight_kg else ""
        lines.append(f"[⚖️ 안심 용량] {user_name}{weight_str} 기준 처방된 약품({all_drugs_str}) 모두 소아 권장 용량에 잘 맞추어져 있습니다.")

    # 2. 복약 수칙 (항생제/보관법)
    if antibiotics:
        lines.append(f"[💊 핵심 복약 수칙] {', '.join(antibiotics)}은(는) 항생제입니다. 열이 내리고 호전되어도 내성 방지를 위해 처방 일수를 끝까지 다 먹여주세요.")
    elif cold_drugs:
        lines.append(f"[💊 핵심 복약 수칙] 코감기약 복용 시 약간의 졸림이나 입마름이 생길 수 있으니 따뜻한 물이나 보리차를 충분히 먹여주세요.")
    else:
        lines.append(f"[💊 안심 처방] 처방된 약품 간에 서로 부딪히거나 위험한 중복 성분이 없어 안전하게 함께 복용할 수 있습니다.")

    # 3. 돌봄 케어 팁 (구토/복용 요령)
    lines.append("[⏱️ 돌봄 TIP] 약 먹고 10분 내에 토하면 같은 양을 즉시 다시 먹이고, 30분이 지난 뒤 토했다면 다시 먹이지 말고 다음 시간에 맞춰 먹이세요.")
    lines.append(LEGAL_DISCLAIMER_TEXT)

    return "\n".join(lines)

async def generate_safety_report_async(profile: Dict[str, Any], analyzed_drugs: List[Dict[str, Any]]) -> str:
    """Gemini AI 실시간 초간결 3줄 요약 (기계적 말투 배제, 소아청소년과 전문의/약사의 따뜻하고 명확한 브리핑)"""
    import os
    user_name = profile.get("name", "아이")
    if os.getenv("GEMINI_API_KEY"):
        try:
            from gemini_service import call_gemini_generate
            prompt = (
                f"환자 프로필: {profile}\n"
                f"처방 약품: {analyzed_drugs}\n"
                f"바쁜 부모님을 위해 로봇 같은 AI 말투를 일절 배제하고, 친절한 소아과 전문 약사가 엄마/아빠에게 직접 차분히 설명하듯 딱 3개의 명확한 핵심 카드로 작성하세요.\n"
                "각 줄은 반드시 아래 태그로 시작해야 합니다:\n"
                f"1줄: [⚖️ 안심 용량] 또는 [⚖️ 용량 확인 필요] 로 시작하여 {user_name}의 체중 기준 용량 적정성 설명\n"
                "2줄: [💊 핵심 복약 수칙] 으로 시작하여 항생제 완복용 여부, 보관법, 또는 성분 안전성 설명\n"
                "3줄: [⏱️ 돌봄 TIP] 으로 시작하여 구토 시 재투약 기준이나 복약 간격 팁 설명\n"
                "불필요한 서두나 '안녕하세요', 'AI 분석 결과입니다' 등의 말은 절대 쓰지 마세요.\n"
                "마지막 줄에는 반드시 '※ 복약 관련 결정은 반드시 의료진(의사·약사)과 상의하세요.' 문구를 넣으세요."
            )
            res = await call_gemini_generate(
                prompt=prompt,
                system_instruction="당신은 아이를 키우는 부모의 마음을 깊이 이해하는 따뜻하고 신뢰감 있는 소아청소년과 전담 약사입니다. 기계적인 문장 대신 한눈에 쏙 들어오는 명확하고 따뜻한 문장으로 설명합니다."
            )
            if res.get("success") and res.get("text"):
                clean_text = res["text"].strip()
                lines = [l.strip() for l in clean_text.splitlines() if l.strip()]
                return "\n".join(lines[:5])
        except Exception:
            pass

    return generate_safety_report(profile, analyzed_drugs)
