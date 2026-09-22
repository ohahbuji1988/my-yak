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

    def test_analyze_image_endpoint_ocr_failure(self):
        """테스트 10: MED-01 - 처방전 이미지 판독 불가 시 임의 데모 생성 금지 및 422 반환 검증"""
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
        self.assertEqual(response.status_code, 422)
        data = response.json()
        self.assertIn("detail", data)
        self.assertEqual(data["detail"]["code"], "OCR_EXTRACTION_FAILED")

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

    def test_public_match_unverified_dosage(self):
        """테스트 12: MED-03 - 식약처 공공데이터 매칭 약품의 용량 미검증 시 SAFE 부여 차단 검증"""
        from dosage_engine import MemberProfile, evaluate_dosage_async
        profile = MemberProfile(name="김소아", member_type="CHILD", weight_kg=10.0)
        # 게보린정은 KODA Mock 공공데이터에 등록되어 있으나 소아 체중당 mg 기준 없음
        res = asyncio.run(evaluate_dosage_async(profile, "게보린정", dose_unit=1.0, freq_per_day=3))
        self.assertEqual(res["match_status"], "PUBLIC_MATCH")
        self.assertEqual(res["status"], "UNKNOWN")
        self.assertIn("확인 필요", res["comment"])

    def test_antipyretic_calculator_safety_rules(self):
        """테스트 13: MED-04 - 해열제 0 이하 체중 거부 및 1일 누적 한도 초과 검증"""
        from antipyretic_calculator import calculate_antipyretic_dosage, calculate_next_dose_timing
        from datetime import datetime

        # 1. 0kg 이하 체중 거부
        with self.assertRaises(ValueError):
            calculate_antipyretic_dosage(0.0, "ACETAMINOPHEN")

        with self.assertRaises(ValueError):
            calculate_next_dose_timing(-5.0, "챔프빨강", datetime.now())

        # 2. 1일 누적 한도 초과 검증 (10kg 아이에게 25ml = 800mg 투여 기록, 1일한도 750mg 초과)
        history = [
            {"drug_name": "타이레놀현탁액", "dose_ml": 25.0, "administered_at": datetime.now()}
        ]
        next_dose = calculate_next_dose_timing(
            weight_kg=10.0,
            last_drug_name="타이레놀현탁액",
            last_dose_time=datetime.now(),
            daily_history=history
        )
        self.assertTrue(next_dose["last_drug"]["daily_limit_exceeded"])

    def test_dur_ingredient_duplicate(self):
        """테스트 14: DUR-01 - 동일 성분 해열제(아세트아미노펜 중복) DANGER 검증"""
        analyzed_drugs = [
            {"drug_name": "어린이타이레놀현탁액"},
            {"drug_name": "세토펜현탁액"}
        ]
        warnings = check_dur_interactions(analyzed_drugs)
        self.assertTrue(any(w["severity"] == "DANGER" and "아세트아미노펜" in w["type"] for w in warnings))

    def test_clinical_vomit_guidance_endpoint(self):
        """테스트 15: 소아과 구토 시간대별 재투약 임상 가이드 엔드포인트 검증"""
        # 1. 5분 후 구토 -> 즉시 재투약
        res_5 = self.client.get("/api/v1/clinical/vomit-guide?elapsed_minutes=5")
        self.assertEqual(res_5.status_code, 200)
        data_5 = res_5.json()
        self.assertEqual(data_5["action_code"], "REDOSE_NOW")
        self.assertTrue(data_5["can_redose"])

        # 2. 15분 후 구토 -> 추가 투약 보류 및 관찰
        res_15 = self.client.get("/api/v1/clinical/vomit-guide?elapsed_minutes=15")
        data_15 = res_15.json()
        self.assertEqual(data_15["action_code"], "OBSERVE_AND_WAIT")
        self.assertFalse(data_15["can_redose"])

        # 3. 45분 후 구토 -> 재투약 금지 (흡수 완료)
        res_45 = self.client.get("/api/v1/clinical/vomit-guide?elapsed_minutes=45")
        data_45 = res_45.json()
        self.assertEqual(data_45["action_code"], "DO_NOT_REDOSE")
        self.assertFalse(data_45["can_redose"])

    def test_antipyretic_clinical_safeguards(self):
        """테스트 16: 생후 6개월 미만 NSAIDs 금기 및 생후 3개월 미만 신생아 응급 경고 검증"""
        from antipyretic_calculator import calculate_antipyretic_dosage, calculate_fever_triage

        # 1. 생후 5개월 -> 덱시부프로펜(DEXIBUPROFEN) 투약 금기
        res_dexi_5m = calculate_antipyretic_dosage(7.0, "DEXIBUPROFEN", age_months=5)
        self.assertTrue(res_dexi_5m["is_contraindicated"])
        self.assertIn("6개월 미만", res_dexi_5m["safety_note"])

        # 2. 생후 2개월 38.5도 발열 -> 긴급 신생아 응급 경고
        res_aceta_2m = calculate_antipyretic_dosage(5.0, "ACETAMINOPHEN", age_months=2, temperature_c=38.5)
        self.assertIsNotNone(res_aceta_2m["age_alert"])
        self.assertTrue(res_aceta_2m["age_alert"]["is_emergency"])

        # 3. 체온별 Fever Triage
        triage_mild = calculate_fever_triage(37.6)
        self.assertEqual(triage_mild["triage_level"], "MILD_FEVER")

        triage_high = calculate_fever_triage(39.5)
        self.assertEqual(triage_high["triage_level"], "HIGH_FEVER")

if __name__ == "__main__":
    unittest.main()

