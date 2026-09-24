from typing import List, Dict, Any

LEGAL_DISCLAIMER_TEXT = "※ 복약 관련 결정은 반드시 의료진과 상의하세요."

def generate_safety_report(profile: Dict[str, Any], analyzed_drugs: List[Dict[str, Any]]) -> str:
    """
    바쁜 보호자를 위한 초간결 3줄 핵심 복약 브리핑
    - 장황한 약품 재나열을 배제하고 핵심(용량/주의/보관)만 3개 불릿으로 요약
    """
    user_name = profile.get("name", "환자")
    weight_kg = profile.get("weight_kg")
    
    all_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("drug_name")]
    all_drugs_str = ", ".join(all_drugs) if all_drugs else "처방약"
    
    warning_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("status") in ("WARNING", "HIGH")]
    unknown_drugs = [d.get("drug_name", "") for d in analyzed_drugs if d.get("status") == "UNKNOWN"]
    antibiotics = [d.get("drug_name", "") for d in analyzed_drugs if d.get("is_antibiotic") or "아모" in d.get("drug_name", "") or "클래리" in d.get("drug_name", "")]
    cold_drugs = [d.get("drug_name", "") for d in analyzed_drugs if any(k in d.get("drug_name", "") for k in ["코미", "코싹", "시럽"])]

    lines = []

    # 1줄: 체중 기준 용량 판정 요약
    if warning_drugs:
        lines.append(f"• ⚖️ 용량 주의: {user_name} 님의 처방 중 {', '.join(warning_drugs)}이(가) 권장 상한을 초과하여 의사·약사 확인이 필요합니다.")
    elif unknown_drugs:
        lines.append(f"• ⚖️ 용량 확인: {user_name} 님의 처방 중 {', '.join(unknown_drugs)}은(는) 체중당 기준 미등록으로 복약 지도를 권장합니다.")
    else:
        weight_str = f"({weight_kg}kg)" if weight_kg else ""
        lines.append(f"• ⚖️ 용량 적정: {user_name} 님{weight_str} 처방 의약품({all_drugs_str})이 권장 복약 범위에 적정합니다.")

    # 2줄: 항생제 완약 및 핵심 보관 안내
    if antibiotics:
        lines.append(f"• 💊 항생제 수칙: {', '.join(antibiotics)}은(는) 증상이 호전되어도 내성균 방지를 위해 처방 일수 끝까지 완복용하세요.")
    elif cold_drugs:
        lines.append(f"• 💧 복약 주의: 코감기 시럽 복용 시 졸림이나 입마름이 생길 수 있으니 충분한 수분을 섭취해 주세요.")
    else:
        lines.append(f"• 🛡️ 상호작용: {all_drugs_str} 간 중복 처방 및 병용 금기 성분 없이 안전합니다.")

    # 3줄: 복약 팁
    lines.append("• ⏱️ 투약 팁: 약 먹인 후 10분 내 구토 시 즉시 재투약, 30분 이후엔 재투약 없이 다음 시간까지 대기하세요.")
    lines.append(LEGAL_DISCLAIMER_TEXT)

    return "\n".join(lines)

async def generate_safety_report_async(profile: Dict[str, Any], analyzed_drugs: List[Dict[str, Any]]) -> str:
    """Gemini AI 실시간 초간결 3줄 요약 (실패 시 룰베이스 3줄 브리핑 Fallback)"""
    import os
    user_name = profile.get("name", "환자")
    if os.getenv("GEMINI_API_KEY"):
        try:
            from gemini_service import call_gemini_generate
            prompt = (
                f"환자 프로필: {profile}\n"
                f"처방 약품: {analyzed_drugs}\n"
                f"바쁜 부모님을 위해 {user_name} 님의 이름을 첫 문장에 언급하고, 불필요한 인사말 없이 "
                "반드시 딱 3개의 명확한 불릿 포인트(•)로만 구성된 핵심 복약 가이드 3줄 요약을 작성하세요.\n"
                "1줄: 환자 이름 언급 및 체중/성인 기준 용량 적정성 평가\n"
                "2줄: 항생제 완약 또는 보관법 등 핵심 주의사항\n"
                "3줄: 복약 팁 (예: 해열제 간격, 구토 대처)\n"
                "마지막 줄에는 반드시 '※ 복약 관련 결정은 반드시 의료진과 상의하세요.' 문구를 넣으세요."
            )
            res = await call_gemini_generate(
                prompt=prompt,
                system_instruction="당신은 바쁜 환자 보호자에게 군더더기 없이 딱 3줄로 핵심만 명료하게 요약해 주는 소아과/약학 복약 어드바이저입니다."
            )
            if res.get("success") and res.get("text"):
                clean_text = res["text"].strip()
                lines = [l.strip() for l in clean_text.splitlines() if l.strip()]
                return "\n".join(lines[:5])
        except Exception:
            pass

    return generate_safety_report(profile, analyzed_drugs)


