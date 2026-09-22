from typing import List, Dict, Any

# DUR (Drug Utilization Review) 병용금기/성인·소아·임부 주의 룰 데이터
DUR_INTERACTION_RULES = [
    {
        "drugs": ["맥시부펜시럽", "타이레놀8시간이알서방정"],
        "type": "성분중복/해열제중복",
        "severity": "WARNING",
        "message": "해열진통제(덱시부프로펜 + 아세트아미노펜) 동시 복용 시 교차복용 시간 간격(최소 2시간)을 준수해야 합니다."
    },
    {
        "drugs": ["코싹엘정", "코미시럽"],
        "type": "항히스타민 중복",
        "severity": "CAUTION",
        "message": "항히스타민 성분이 중복 포함되어 있어 심한 졸음이나 입마름이 유발될 수 있습니다."
    }
]

def check_dur_interactions(analyzed_drugs: List[Dict[str, Any]], is_pregnant: bool = False) -> List[Dict[str, Any]]:
    """
    DUR (Drug Utilization Review) 병용금기 및 중복 복약 검증
    """
    warnings = []
    matched_names = [d.get("drug_name", "") for d in analyzed_drugs if d.get("drug_name")]

    # 1. 약품 간 병용금기/중복 검증 (룰베이스)
    for rule in DUR_INTERACTION_RULES:
        rule_drugs = rule["drugs"]
        if all(any(rd in name for name in matched_names) for rd in rule_drugs):
            warnings.append({
                "type": rule["type"],
                "severity": rule["severity"],
                "message": rule["message"],
                "affected_drugs": rule_drugs
            })

    # 2. 성분/약효군 레벨 중복 검증 (MED-04 / DUR-01)
    # 2-1. 아세트아미노펜 중복 검증
    acetaminophen_keywords = ["타이레놀", "아세트아미노펜", "세토펜", "챔프빨강", "콜대원보라", "판콜"]
    matched_apap = [name for name in matched_names if any(k in name for k in acetaminophen_keywords)]
    if len(matched_apap) >= 2:
        warnings.append({
            "type": "동일성분 중복 (아세트아미노펜 간독성 위험)",
            "severity": "DANGER",
            "message": f"동일한 아세트아미노펜 성분의 약품({', '.join(matched_apap)})이 중복 처방되어 심각한 간 손상 위험이 있습니다. 즉시 처방의 또는 약사와 확인하세요.",
            "affected_drugs": matched_apap
        })

    # 2-2. NSAIDs(이부프로펜/덱시부프로펜) 중복 검증
    nsaid_keywords = ["맥시부펜", "덱시부프로펜", "이부프로펜", "부루펜", "챔프파랑", "콜대원주황"]
    matched_nsaids = [name for name in matched_names if any(k in name for k in nsaid_keywords)]
    if len(matched_nsaids) >= 2:
        warnings.append({
            "type": "동일계열 중복 (위장장애 위험)",
            "severity": "DANGER",
            "message": f"동일한 소염진통제(NSAIDs) 계열({', '.join(matched_nsaids)})이 중복 처방되어 위장관 출혈 및 신장 부담 위험이 있습니다.",
            "affected_drugs": matched_nsaids
        })

    # 2-3. 아세트아미노펜 + NSAID 동시 처방 시 교차복용 안내
    if matched_apap and matched_nsaids and not any(w["type"] == "성분중복/해열제중복" for w in warnings):
        warnings.append({
            "type": "해열진통제 동시 처방 (교차 복용 준수)",
            "severity": "WARNING",
            "message": f"서로 다른 계열의 해열제({matched_apap[0]} + {matched_nsaids[0]})가 함께 처방되었습니다. 동시에 먹이지 마시고, 열이 떨어지지 않을 때 최소 2시간 간격을 두고 교차 복용하세요.",
            "affected_drugs": [matched_apap[0], matched_nsaids[0]]
        })

    # 3. 임부 주의/금기 검증
    if is_pregnant:
        for drug in analyzed_drugs:
            name = drug.get("drug_name", "")
            if any(k in name for k in ["맥시부펜", "덱시부프로펜", "아세트아미노펜", "이부프로펜"]):
                warnings.append({
                    "type": "임부주의",
                    "severity": "WARNING",
                    "message": f"'{name}'은 임신 중 복용 시 태아 영향 가능성이 있으므로 의사·약사와 상담이 필요합니다.",
                    "affected_drugs": [name]
                })

    return warnings
