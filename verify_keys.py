import sys
import asyncio
import os

# Windows cp949 인코딩 문제 방지
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

import env_loader
from koda_service import fetch_drug_from_public_api
from gemini_service import call_gemini_generate

async def main():
    print("=== API 키 연결 및 실제 호출 검증 ===")
    
    # 1. 환경변수 적재 여부 확인 (값은 마스킹하여 보안 유지)
    has_public_key = bool(os.getenv("PUBLIC_DATA_API_KEY") or os.getenv("MFDS_API_KEY"))
    has_gemini_key = bool(os.getenv("GEMINI_API_KEY"))
    
    print(f"1. .env 키 적재 확인:")
    print(f"   - PUBLIC_DATA_API_KEY: {'[연결됨]' if has_public_key else '[미설정]'}")
    print(f"   - GEMINI_API_KEY:      {'[연결됨]' if has_gemini_key else '[미설정]'}")
    
    # 2. 공공데이터포털 e약은요 실제 호출 테스트
    print("\n2. 공공데이터포털 식약처 API 실제 호출 테스트:")
    res_koda = await fetch_drug_from_public_api("게보린정")
    if res_koda:
        print("   [OK] 식약처 API 연동 성공!")
        print(f"   - 조회 약품: {res_koda.get('name')}")
        print(f"   - 품목코드: {res_koda.get('item_seq')}")
        print(f"   - 효능요약: {res_koda.get('efficacy')[:40]}...")
    else:
        print("   [FAIL] 식약처 API 응답 없음")
        
    # 3. Gemini API 실제 호출 테스트
    print("\n3. Gemini API (gemini-2.5-flash) 실제 호출 테스트:")
    if has_gemini_key:
        res_gemini = await call_gemini_generate("안녕하세요. 1+1은 무엇인가요? 한 단어로만 대답해 주세요.")
        if res_gemini.get("success"):
            print("   [OK] Gemini API 연동 성공!")
            print(f"   - 모델: {res_gemini.get('model')}")
            print(f"   - 응답: {res_gemini.get('text')}")
        else:
            print(f"   [FAIL] Gemini API 호출 실패: {res_gemini.get('error')} - {res_gemini.get('message')[:100]}")
    else:
        print("   - GEMINI_API_KEY가 설정되지 않아 호출을 건너뜁니다.")

    print("\n=== 검증 완료 ===")

if __name__ == "__main__":
    asyncio.run(main())
