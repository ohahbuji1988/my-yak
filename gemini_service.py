import os
import ssl
import json
import urllib.request
import asyncio
from typing import Optional, Dict, Any

import env_loader

GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent"

async def call_gemini_generate(prompt: str, system_instruction: Optional[str] = None) -> Dict[str, Any]:
    """
    Gemini REST API 호출 함수 (비동기)
    - GEMINI_API_KEY 환경 변수를 활용하여 프롬프트 질의 수행
    """
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return {
            "success": False,
            "error": "GEMINI_API_KEY_NOT_FOUND",
            "message": "환경변수에서 GEMINI_API_KEY를 찾을 수 없습니다."
        }

    url = f"{GEMINI_API_URL}?key={api_key}"
    
    payload: Dict[str, Any] = {
        "contents": [
            {
                "parts": [
                    {"text": prompt}
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": 2048
        }
    }

    if system_instruction:
        payload["systemInstruction"] = {
            "parts": [{"text": system_instruction}]
        }

    loop = asyncio.get_event_loop()

    def _post():
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        max_retries = 2
        for attempt in range(max_retries + 1):
            try:
                try:
                    ctx = ssl.create_default_context()
                except Exception:
                    ctx = ssl._create_unverified_context()

                try:
                    with urllib.request.urlopen(req, timeout=12, context=ctx) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                except urllib.error.URLError as ue:
                    if "CERTIFICATE_VERIFY_FAILED" in str(ue):
                        unverified_ctx = ssl._create_unverified_context()
                        with urllib.request.urlopen(req, timeout=12, context=unverified_ctx) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                    else:
                        raise ue

                candidates = data.get("candidates", [])
                if candidates:
                    parts = candidates[0].get("content", {}).get("parts", [])
                    if parts:
                        return {
                            "success": True,
                            "text": parts[0].get("text", "").strip(),
                            "model": "gemini-2.5-flash"
                        }
                return {"success": False, "error": "EMPTY_RESPONSE", "message": "응답 내용이 비어 있습니다."}
            except urllib.error.HTTPError as e:
                err_body = e.read().decode("utf-8", errors="ignore")
                if e.code in (429, 503) and attempt < max_retries:
                    import time
                    time.sleep(1.0 * (attempt + 1))
                    continue
                return {"success": False, "error": f"HTTP_{e.code}", "message": err_body}
            except Exception as e:
                if attempt < max_retries:
                    import time
                    time.sleep(1.0 * (attempt + 1))
                    continue
                return {"success": False, "error": "EXCEPTION", "message": str(e)}

    return await loop.run_in_executor(None, _post)

async def call_gemini_vision_ocr(image_base64: str, mime_type: str = "image/jpeg") -> List[Dict[str, Any]]:
    """
    Gemini Vision API를 활용하여 처방전/약봉투 이미지에서 모든 의약품 목록과 용법을 자동 추출합니다.
    """
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        return []

    url = f"{GEMINI_API_URL}?key={api_key}"

    prompt = (
        "당신은 대한민국 병원 및 약국의 처방전과 약봉투 전문 AI 분석기입니다.\n"
        "제공된 이미지에 인쇄되거나 수기로 작성된 모든 처방 의약품의 이름과 복약 지시사항(1회 투여량, 1일 복용 횟수, 총 투약 일수)을 빠짐없이 정확하게 읽어주세요.\n\n"
        "반드시 아래 JSON 배열 형식으로만 출력하세요. 마크다운 코드 블록(```json 등)이나 기타 설명 문구 없이 순수 JSON 배열 문자열만 반환해야 합니다:\n"
        "[\n"
        "  {\n"
        '    "scanned_name": "의약품명 (예: 코미시럽, 아모클란듀오, 맥시부펜 등)",\n'
        '    "dose_unit": 1회 복용량 (숫자, 예: 4.0, 1.0, 0.5. 단위 제외 숫자만),\n'
        '    "freq_per_day": 1일 복용 횟수 (정수, 예: 3, 2, 1),\n'
        '    "days": 투약 일수 (정수, 예: 3, 5, 7)\n'
        "  }\n"
        "]\n\n"
        "주의:\n"
        "1. 처방전/약봉투에 적힌 모든 약품을 1개도 빠뜨리지 말고 모두 배열에 담으세요.\n"
        "2. 약품명이 긴 경우에도 인쇄된 품목명을 가능한 충실하게 기재하세요."
    )

    if not mime_type or mime_type == "application/octet-stream":
        mime_type = "image/jpeg"

    payload = {
        "contents": [
            {
                "parts": [
                    {
                        "inlineData": {
                            "mimeType": mime_type,
                            "data": image_base64
                        }
                    },
                    {
                        "text": prompt
                    }
                ]
            }
        ],
        "generationConfig": {
            "temperature": 0.1,
            "maxOutputTokens": 2048
        }
    }

    loop = asyncio.get_event_loop()

    def _post_vision():
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST"
        )
        max_retries = 2
        for attempt in range(max_retries + 1):
            try:
                try:
                    ctx = ssl.create_default_context()
                except Exception:
                    ctx = ssl._create_unverified_context()

                try:
                    with urllib.request.urlopen(req, timeout=20, context=ctx) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                except urllib.error.URLError as ue:
                    if "CERTIFICATE_VERIFY_FAILED" in str(ue):
                        unverified_ctx = ssl._create_unverified_context()
                        with urllib.request.urlopen(req, timeout=20, context=unverified_ctx) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                    else:
                        raise ue

                candidates = data.get("candidates", [])
                if not candidates:
                    return []

                parts = candidates[0].get("content", {}).get("parts", [])
                if not parts:
                    return []

                text = parts[0].get("text", "").strip()
                # Clean possible markdown block
                if text.startswith("```"):
                    lines = text.splitlines()
                    if lines[0].startswith("```"):
                        lines = lines[1:]
                    if lines and lines[-1].startswith("```"):
                        lines = lines[:-1]
                    text = "\n".join(lines).strip()

                parsed = json.loads(text)
                if isinstance(parsed, list):
                    result = []
                    for item in parsed:
                        if isinstance(item, dict) and "scanned_name" in item:
                            result.append({
                                "scanned_name": str(item.get("scanned_name", "")).strip(),
                                "dose_unit": float(item.get("dose_unit", 1.0) or 1.0),
                                "freq_per_day": int(item.get("freq_per_day", 3) or 3),
                                "days": int(item.get("days", 3) or 3)
                            })
                    return result
                return []
            except urllib.error.HTTPError as e:
                if e.code in (429, 503) and attempt < max_retries:
                    import time
                    time.sleep(1.0 * (attempt + 1))
                    continue
                print(f"[Gemini Vision OCR HTTP Error]: {e}")
                return []
            except Exception as e:
                if attempt < max_retries:
                    import time
                    time.sleep(1.0 * (attempt + 1))
                    continue
                print(f"[Gemini Vision OCR Error]: {e}")
                return []

    return await loop.run_in_executor(None, _post_vision)
