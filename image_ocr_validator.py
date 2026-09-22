import base64
from typing import Dict, Any, List, Optional

def validate_and_extract_ocr(
    image_bytes: Optional[bytes] = None,
    image_base64: Optional[str] = None
) -> Dict[str, Any]:
    """
    약봉투/처방전 이미지 품질 검증 및 텍스트 OCR 추출
    - 흐림/잘림/해상도 부족 시 '재촬영(Retake)' 가드레일 작동
    """
    raw_bytes = b""
    if image_bytes:
        raw_bytes = image_bytes
    elif image_base64:
        try:
            # data:image/jpeg;base64,... 헤더 분리
            if "," in image_base64:
                image_base64 = image_base64.split(",")[1]
            raw_bytes = base64.b64decode(image_base64)
        except Exception:
            return {
                "success": False,
                "require_retake": True,
                "reason": "INVALID_FORMAT",
                "message": "이미지 포맷을 해석할 수 없습니다. 다시 촬영해 주세요.",
                "scanned_drugs": []
            }

    # 1. 파일 크기 검증 (20KB 미만은 흐리거나 손상된 이미지로 판정)
    if len(raw_bytes) < 20 * 1024:
        return {
            "success": False,
            "require_retake": True,
            "reason": "BLURRY_OR_LOW_RES",
            "message": "사진 해상도가 너무 낮거나 흐립니다. 약봉투의 글씨가 선명하도록 다시 촬영해 주세요.",
            "scanned_drugs": []
        }

    # 2. 유효한 이미지 시뮬레이션 추출 (실제 프로덕션에선 Vision LLM 모델 호출)
    return {
        "success": True,
        "require_retake": False,
        "quality_score": 0.94,
        "message": "처방전 텍스트가 선명하게 감지되었습니다.",
        "scanned_drugs": [
          {"scanned_name": "코미시럽", "dose_unit": 4.0, "freq_per_day": 3, "days": 3},
          {"scanned_name": "아모클란듀오", "dose_unit": 3.0, "freq_per_day": 2, "days": 5}
        ]
    }
