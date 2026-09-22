from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional

# 해열제 계열 정의
# 계열 1: 아세트아미노펜 (타이레놀, 챔프 빨강 등)
# 계열 2: 이부프로펜 / 덱시부프로펜 (맥시부펜, 챔프 파랑 등)
ANTIPYRETIC_CLASSES = {
    "ACETAMINOPHEN": {
        "name": "아세트아미노펜 계열",
        "keywords": ["타이레놀", "아세트아미노펜", "세토펜", "챔프빨강", "콜대원보라"],
        "min_interval_hours": 4.0,
        "single_dose_mg_kg": 12.5, # 10~15 mg/kg
        "daily_limit_mg_kg": 75.0,
        "concentration_mg_ml": 32.0 # 어린이타이레놀현탁액 (32mg/ml)
    },
    "DEXIBUPROFEN": {
        "name": "덱시부프로펜/이부프로펜 계열",
        "keywords": ["맥시부펜", "덱시부프로펜", "이부프로펜", "부루펜", "챔프파랑", "콜대원주황"],
        "min_interval_hours": 4.0,
        "single_dose_mg_kg": 6.0, # 5~7 mg/kg
        "daily_limit_mg_kg": 28.0,
        "concentration_mg_ml": 12.0 # 맥시부펜시럽 (12mg/ml)
    }
}

CROSS_DOSE_MIN_INTERVAL_HOURS = 2.0  # 교차복용(다른 계열) 최소 권장 간격: 2시간

def identify_antipyretic_class(drug_name: str) -> Optional[str]:
    """약품명에서 해열제 계열 식별"""
    cleaned = drug_name.replace(" ", "")
    for cls_key, info in ANTIPYRETIC_CLASSES.items():
        if any(k in cleaned for k in info["keywords"]):
            return cls_key
    return None

def calculate_antipyretic_dosage(
    weight_kg: float,
    antipyretic_class: str,
    age_months: Optional[int] = None,
    temperature_c: Optional[float] = None
) -> Dict[str, Any]:
    """체중(kg) 기준 1회 적정 권장 복용량(ml 및 mg) 계산 (0 이하 체중 거부, 생후 6개월 미만 NSAID 금기 검증)"""
    if weight_kg <= 0:
        raise ValueError("체중은 0kg보다 큰 양수여야 합니다.")

    cls_info = ANTIPYRETIC_CLASSES.get(antipyretic_class)
    if not cls_info:
        return {}

    # 생후 6개월 미만 영아 NSAID 금기 검증 (임상 가드레일)
    is_contraindicated = False
    contraindication_reason = ""
    safety_note = ""
    if age_months is not None and age_months < 6 and antipyretic_class == "DEXIBUPROFEN":
        is_contraindicated = True
        contraindication_reason = "생후 6개월 미만 영아는 신장 기능 미성숙으로 이부프로펜/덱시부프로펜 투약이 금기입니다. 아세트아미노펜 단일제를 투약하세요."
        safety_note = "생후 6개월 미만 영아 덱시부프로펜 투약 금기"

    # 생후 3개월 미만 발열 응급 경고
    age_alert = None
    if age_months is not None and age_months < 3:
        age_alert = {
            "is_emergency": True,
            "message": "🚨 [긴급] 생후 3개월 미만 영아의 38°C 이상 발열은 패혈증 위험이 있으므로 즉시 소아응급실로 직행하세요."
        }

    single_mg = weight_kg * cls_info["single_dose_mg_kg"]
    single_ml = round(single_mg / cls_info["concentration_mg_ml"], 1)
    daily_limit_mg = weight_kg * cls_info["daily_limit_mg_kg"]
    daily_limit_ml = round(daily_limit_mg / cls_info["concentration_mg_ml"], 1)

    return {
        "class_name": cls_info["name"],
        "weight_kg": weight_kg,
        "age_months": age_months,
        "temperature_c": temperature_c,
        "single_dose_mg": round(single_mg, 1),
        "single_dose_ml": single_ml,
        "daily_limit_mg": round(daily_limit_mg, 1),
        "daily_limit_ml": daily_limit_ml,
        "min_same_interval_hours": cls_info["min_interval_hours"],
        "is_contraindicated": is_contraindicated,
        "contraindication_reason": contraindication_reason,
        "safety_note": safety_note,
        "age_alert": age_alert
    }

def calculate_next_dose_timing(
    weight_kg: float,
    last_drug_name: str,
    last_dose_time: datetime,
    target_next_drug_name: Optional[str] = None,
    daily_history: Optional[List[Dict[str, Any]]] = None,
    age_months: Optional[int] = None,
    temperature_c: Optional[float] = None
) -> Dict[str, Any]:
    """
    마지막 복용 약품과 복용 시간, 당일 누적 복용 이력, 개월수 및 체온을 기준으로
    1일 최대 허용량 초과 여부와 안전 복용 가능 시각, 체온별 대처 가이드 계산
    """
    if weight_kg <= 0:
        raise ValueError("체중은 0kg보다 큰 양수여야 합니다.")

    last_class = identify_antipyretic_class(last_drug_name)

    # 1. 동일 계열 다음 복용 가능 시각 (최소 4시간 후)
    same_class_time = last_dose_time + timedelta(hours=4)
    # 2. 교차 복용(다른 계열) 다음 복용 가능 시각 (최소 2시간 후)
    cross_class_time = last_dose_time + timedelta(hours=CROSS_DOSE_MIN_INTERVAL_HOURS)

    alt_class = "DEXIBUPROFEN" if last_class == "ACETAMINOPHEN" else "ACETAMINOPHEN"
    last_dosage_info = calculate_antipyretic_dosage(weight_kg, last_class, age_months=age_months) if last_class else {}
    alt_dosage_info = calculate_antipyretic_dosage(weight_kg, alt_class, age_months=age_months) if alt_class in ANTIPYRETIC_CLASSES else {}

    # 당일 누적 복용량 검증 (MED-04)
    cumulative_mg = {"ACETAMINOPHEN": 0.0, "DEXIBUPROFEN": 0.0}
    if daily_history:
        for entry in daily_history:
            entry_name = entry.get("drug_name", "")
            entry_ml = float(entry.get("dose_ml", 0.0))
            entry_class = identify_antipyretic_class(entry_name)
            if entry_class and entry_class in ANTIPYRETIC_CLASSES:
                conc = ANTIPYRETIC_CLASSES[entry_class]["concentration_mg_ml"]
                cumulative_mg[entry_class] += entry_ml * conc

    # 마지막 약품 및 대체 약품 1일 한도 초과 여부
    last_daily_limit = last_dosage_info.get("daily_limit_mg", float("inf"))
    alt_daily_limit = alt_dosage_info.get("daily_limit_mg", float("inf"))

    last_exceeded = last_class and cumulative_mg.get(last_class, 0.0) >= last_daily_limit
    alt_exceeded = alt_class and cumulative_mg.get(alt_class, 0.0) >= alt_daily_limit

    # 체온별 대처 가이드 (Fever Triage)
    triage_info = {}
    if temperature_c is not None:
        if temperature_c < 38.0:
            triage_info = {
                "level": "미열 (38.0°C 미만)",
                "action": "해열제 투약 유예",
                "guide": "아이의 체온이 38°C 미만입니다. 미온수 마사지와 수분 섭취를 유도하고 옷을 가볍게 입혀주세요. 무리한 해열제 투약은 권장하지 않습니다."
            }
        elif 38.0 <= temperature_c < 39.0:
            triage_info = {
                "level": "중등도 발열 (38.0~38.9°C)",
                "action": "필요 시 교차 복용 허용",
                "guide": "이전 투약 후 2시간 이상 경과하였고, 아이가 보채거나 처짐이 있는 경우 교차 복용을 고려할 수 있습니다."
            }
        else:
            triage_info = {
                "level": "고열 (39.0°C 이상)",
                "action": "즉시 투약 및 집중 관찰",
                "guide": "고열 상태입니다. 정량 해열제를 즉시 투약하시고, 열성 경련이나 탈수(소변량 감소, 입술 마름) 증상을 면밀히 살피세요. 30분 후에도 호전이 없으면 야간 진료/응급실 방문을 권장합니다."
            }

    # 생후 3개월 미만 긴급 경고
    age_alert = ""
    if age_months is not None and age_months < 3:
        age_alert = "🚨 [긴급] 생후 3개월 미만 영아의 38°C 이상 발열은 패혈증, 요로감염 등 중증 질환 위험이 있으므로 해열제 임의 투약 전 즉시 응급실/소아청소년과 진료를 받으셔야 합니다."

    if alt_dosage_info.get("is_contraindicated"):
        safety_note = f"⚠️ 금기 경고: {alt_dosage_info.get('contraindication_reason')}"
        cross_allowed = False
    elif alt_exceeded:
        safety_note = (
            f"⚠️ 주의: {ANTIPYRETIC_CLASSES[alt_class]['name']}의 1일 최대 허용 누적량({alt_daily_limit:.1f}mg)에 도달했습니다. "
            "추가 투여를 즉시 중단하고 소아청소년과 전문의 또는 응급의료기관(119)에 상담하세요."
        )
        cross_allowed = False
    elif last_class is None:
        safety_note = f"'{last_drug_name}'의 해열제 계열을 식별할 수 없습니다. 의사 또는 약사에게 교차 복용 가능 여부를 반드시 확인하세요."
        cross_allowed = False
    else:
        safety_note = (
            f"최소 2시간 경과 후에도 38도 이상 고열 지속 시에만 "
            f"{ANTIPYRETIC_CLASSES[alt_class]['name']} ({alt_dosage_info.get('single_dose_ml', 0.0)}ml)을 교차 투여할 수 있습니다. "
            f"(체온이 안정되면 추가 투여하지 마세요)"
        )
        cross_allowed = True

    return {
        "weight_kg": weight_kg,
        "age_months": age_months,
        "temperature_c": temperature_c,
        "age_alert": age_alert,
        "triage_info": triage_info,
        "last_drug": {
            "name": last_drug_name,
            "class": last_class or "UNKNOWN",
            "dose_time": last_dose_time.strftime("%H:%M"),
            "dosage_guide": last_dosage_info,
            "cumulative_mg_today": round(cumulative_mg.get(last_class, 0.0), 1) if last_class else 0.0,
            "daily_limit_exceeded": bool(last_exceeded)
        },
        "timings": {
            "cross_dose_earliest_time": cross_class_time.strftime("%H:%M"),
            "cross_dose_min_interval_hours": CROSS_DOSE_MIN_INTERVAL_HOURS,
            "same_dose_earliest_time": same_class_time.strftime("%H:%M"),
            "same_dose_min_interval_hours": 4.0
        },
        "cross_dose_recommendation": {
            "allowed": cross_allowed,
            "recommended_alt_class": ANTIPYRETIC_CLASSES[alt_class]["name"] if alt_class in ANTIPYRETIC_CLASSES else "UNKNOWN",
            "alt_single_dose_ml": alt_dosage_info.get("single_dose_ml", 0.0),
            "alt_cumulative_mg_today": round(cumulative_mg.get(alt_class, 0.0), 1) if alt_class else 0.0,
            "alt_daily_limit_exceeded": bool(alt_exceeded),
            "safety_note": safety_note
        }
    }

def calculate_fever_triage(temperature_c: float) -> Dict[str, Any]:
    """체온(°C) 기준 소아과 임상 Fever Triage 분류"""
    if temperature_c < 38.0:
        return {
            "triage_level": "MILD_FEVER",
            "level_name": "미열 (38.0°C 미만)",
            "action": "해열제 투약 유예",
            "guide": "아이의 체온이 38°C 미만입니다. 미온수 마사지와 수분 섭취를 유도하고 옷을 가볍게 입혀주세요. 무리한 해열제 투약은 권장하지 않습니다."
        }
    elif 38.0 <= temperature_c < 39.0:
        return {
            "triage_level": "MODERATE_FEVER",
            "level_name": "중등도 발열 (38.0~38.9°C)",
            "action": "필요 시 교차 복용 허용",
            "guide": "이전 투약 후 2시간 이상 경과하였고, 아이가 보채거나 처짐이 있는 경우 교차 복용을 고려할 수 있습니다."
        }
    else:
        return {
            "triage_level": "HIGH_FEVER",
            "level_name": "고열 (39.0°C 이상)",
            "action": "즉시 투약 및 집중 관찰",
            "guide": "고열 상태입니다. 정량 해열제를 즉시 투약하시고, 열성 경련이나 탈수 증상을 면밀히 살피세요. 30분 후에도 호전이 없으면 야간 진료/응급실 방문을 권장합니다."
        }

def get_vomit_guidance(elapsed_minutes: int) -> Dict[str, Any]:
    """
    소아 복약 후 구토 시 임상 재투약 가이드라인
    - 10분 이내: 즉시 정량 재투약 (can_redose=True, action_code="REDOSE_NOW")
    - 10~30분: 상태 관찰 및 유예 (can_redose=False, action_code="OBSERVE_AND_WAIT")
    - 30분 이후: 흡수 완료, 재투약 금지 (can_redose=False, action_code="DO_NOT_REDOSE")
    """
    if elapsed_minutes <= 10:
        return {
            "time_window": "복약 후 10분 이내 구토",
            "action": "동일 1회 정량 즉시 재투약 권장",
            "action_code": "REDOSE_NOW",
            "can_redose": True,
            "status_color": "GREEN",
            "reason": "약물이 위에 머무르다 거의 흡수되지 않고 그대로 게워졌으므로, 아이의 입을 헹구고 진정시킨 뒤 1회 용량을 다시 먹이세요."
        }
    elif elapsed_minutes <= 30:
        return {
            "time_window": "복약 후 10~30분 사이 구토",
            "action": "상태 관찰 (즉시 재투약 유예)",
            "action_code": "OBSERVE_AND_WAIT",
            "can_redose": False,
            "status_color": "ORANGE",
            "reason": "약물의 일부(약 30~50%)가 혈중으로 흡수되었을 수 있습니다. 해열제는 2시간 뒤 체온을 확인하고, 항생제/감기약은 임의 재투약 없이 다음 복약 시간에 투여하세요."
        }
    else:
        return {
            "time_window": "복약 후 30분 이후 구토",
            "action": "재투약 절대 금지 (정상 흡수 완료)",
            "action_code": "DO_NOT_REDOSE",
            "can_redose": False,
            "status_color": "RED",
            "reason": "약물의 대부분이 위장관을 통해 이미 전신 흡수되었습니다. 다시 먹이면 과다 복용 위험이 있으므로 재투약하지 마시고 다음 정규 시간에 복용시키세요."
        }
