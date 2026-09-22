# Flutter 앱 연동 API 가이드 (`POST /api/v1/prescriptions/analyze`)

이 문서는 **My 약 (My Yak)** Flutter 앱에서 처방전 분석 백엔드 API를 연동하기 위한 데이터 모델 및 HTTP 클라이언트 예제 코드입니다.

---

## 1. Request / Response JSON 명세

### Endpoint
`POST http://<SERVER_HOST>:8000/api/v1/prescriptions/analyze`

### Request Body (JSON)
```json
{
  "profile": {
    "name": "김소아",
    "member_type": "CHILD",
    "weight_kg": 15.0,
    "is_pregnant": false
  },
  "scanned_drugs": [
    {
      "scanned_name": "맥시부펜",
      "dose_unit": 6.0,
      "freq_per_day": 3,
      "days": 3
    }
  ]
}
```

### Response Body (JSON)
```json
{
  "profile": {
    "name": "김소아",
    "member_type": "CHILD",
    "weight_kg": 15.0,
    "is_pregnant": false
  },
  "analyzed_drugs": [
    {
      "drug_name": "맥시부펜시럽",
      "original_scanned": "맥시부펜",
      "match_status": "HIGH",
      "confidence": 0.85,
      "status": "SAFE",
      "comment": "15.0kg 기준 권장 복약 범위입니다.",
      "candidates": ["맥시부펜시럽", "타이레놀8시간이알서방정"],
      "scanned_dose_unit": 6.0,
      "scanned_freq_per_day": 3,
      "scanned_days": 3
    }
  ],
  "safety_report": "📋 [My 약] 온 가족 복약 안심 분석 리포트...",
  "disclaimer": "※ 본 서비스는 공공 의약품 데이터 기반의 참고 자료일 뿐..."
}
```

---

## 2. Flutter (Dart) 연동 코드 예시

```dart
import 'dart:convert';
import 'http/http.dart' as http;

Future<Map<String, dynamic>> analyzePrescription({
  required String name,
  required String memberType, // 'CHILD' or 'ADULT'
  double? weightKg,
  required List<Map<String, dynamic>> scannedDrugs,
}) async {
  final url = Uri.parse('http://10.0.2.2:8000/api/v1/prescriptions/analyze'); // Android 에뮬레이터용 IP

  final payload = {
    'profile': {
      'name': name,
      'member_type': memberType,
      'weight_kg': weightKg,
      'is_pregnant': false,
    },
    'scanned_drugs': scannedDrugs,
  };

  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload),
  );

  if (response.statusCode == 200) {
    return jsonDecode(utf8.decode(response.bodyBytes));
  } else {
    throw Exception('처방전 분석 실패: ${response.statusCode}');
  }
}
```
