import os
import urllib.parse
import urllib.request
import json
import asyncio
from typing import Optional, Dict, Any

# 식약처 e약은요 개방 API 엔드포인트
PUBLIC_API_URL = "http://apis.data.go.kr/1471000/DrbEasyDrugInfoService/getDrbEasyDrugList"

# 로컬 오프라인 데이터베이스 (API 키 미설정 또는 네트워크 단선 시 가드레일용 Mock 데이터)
MOCK_PUBLIC_DRUGS: Dict[str, Dict[str, Any]] = {
    "게보린정": {
        "item_seq": "197900277",
        "name": "게보린정",
        "entp_name": "삼진제약(주)",
        "efficacy": "두통, 치통, 생리통, 신경통 완화",
        "use_method": "성인 1회 1정, 1일 3회까지 복용",
        "warning": "15세 미만 소아 복용 금지, 빈속 복용 피할 것"
    },
    "판콜에스내복액": {
        "item_seq": "196800045",
        "name": "판콜에스내복액",
        "entp_name": "동화약품(주)",
        "efficacy": "감기의 제증상(콧물, 코막힘, 재채기, 인후통, 기침, 가래, 발열) 완화",
        "use_method": "성인 1회 1병(30mL), 1일 3회 식후 30분에 복용",
        "warning": "아세트아미노펜 포함 (다른 아세트아미노펜 제품과 중복 복용 주의)"
    },
    "펜잘큐정": {
        "item_seq": "200809117",
        "name": "펜잘큐정",
        "entp_name": "종근당",
        "efficacy": "두통, 치통, 발치후 통증, 생리통, 신경통 완화",
        "use_method": "성인 1회 1정, 1일 3회 복용",
        "warning": "간장애 환자 주의, 매일 세잔 이상 음주 시 의사 상의"
    }
}

import env_loader

async def fetch_drug_from_public_api(drug_name: str) -> Optional[Dict[str, Any]]:
    """
    식약처 'e약은요' 공공데이터 API 조회 함수 (비동기)
    - API 서비스 키(PUBLIC_DATA_API_KEY, MFDS_API_KEY, DATA_GO_KR_API_KEY) 설정 시 실시간 HTTP OpenAPI 조회
    - API 키 미설정 또는 실패 시 로컬 오프라인 Mock DB에서 조회
    """
    api_key = os.getenv("PUBLIC_DATA_API_KEY") or os.getenv("MFDS_API_KEY") or os.getenv("DATA_GO_KR_API_KEY")
    
    if api_key:
        try:
            params = {
                "serviceKey": api_key,
                "itemName": drug_name,
                "type": "json",
                "pageNo": "1",
                "numOfRows": "1"
            }
            url = f"{PUBLIC_API_URL}?{urllib.parse.urlencode(params)}"
            
            loop = asyncio.get_event_loop()
            
            def _http_get():
                req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
                with urllib.request.urlopen(req, timeout=5) as resp:
                    return json.loads(resp.read().decode('utf-8'))
            
            data = await loop.run_in_executor(None, _http_get)
            
            body = data.get("body", {})
            items = body.get("items", [])
            
            if items:
                item = items[0]
                return {
                    "item_seq": item.get("itemSeq", ""),
                    "name": item.get("itemName", drug_name),
                    "entp_name": item.get("entpName", ""),
                    "efficacy": item.get("efcyQesitm", "효능 정보가 등록되어 있지 않습니다."),
                    "use_method": item.get("useMethodQesitm", "용법 용량이 등록되어 있지 않습니다."),
                    "warning": item.get("atpnQesitm", item.get("atpnWarnQesitm", ""))
                }
        except Exception as e:
            print(f"[koda_service] 공공 API 조회 실패/오류: {e}")
    
    # API 키 미설정 또는 API 조회 실패 시 로컬 Mock 데이터 캐시 반환
    for key, info in MOCK_PUBLIC_DRUGS.items():
        if drug_name in key or key in drug_name:
            return info
            
    return None
