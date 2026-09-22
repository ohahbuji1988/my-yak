import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../models/prescription.dart';

class ApiService {
  // Dynamic host determination: uses current origin in production/all-in-one web, 8000 in debug
  static String get baseUrl {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      // 로컬 Flutter 디버그(5000번 포트)일 때는 8000번 FastAPI를 바라보고,
      // 올인원 서빙 및 배포 환경(Render, 동일 포트 등)에서는 현재 웹 도메인을 그대로 활용
      if (origin.isNotEmpty && !origin.startsWith('file:') && !origin.contains(':5000')) {
        return '$origin/api/v1';
      }
      return 'http://127.0.0.1:8000/api/v1';
    }
    try {
      if (Platform.isAndroid) {
        return 'http://10.0.2.2:8000/api/v1';
      }
    } catch (_) {}
    return 'http://127.0.0.1:8000/api/v1';
  }

  static Future<PrescriptionAnalysisResponse> analyzePrescription({
    required MemberProfile profile,
    required List<ScannedDrugItem> scannedDrugs,
  }) async {
    final url = Uri.parse('$baseUrl/prescriptions/analyze');

    final payload = {
      'profile': profile.toJson(),
      'scanned_drugs': scannedDrugs.map((d) => d.toJson()).toList(),
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return PrescriptionAnalysisResponse.fromJson(decoded);
    } else {
      throw Exception('처방전 분석 실패 (${response.statusCode}): ${response.body}');
    }
  }

  static Future<PrescriptionAnalysisResponse> analyzePrescriptionImage({
    required MemberProfile profile,
    required String imageBase64,
    String mimeType = 'image/jpeg',
  }) async {
    final url = Uri.parse('$baseUrl/prescriptions/analyze-image');

    final payload = {
      'profile': profile.toJson(),
      'image_base64': imageBase64,
      'mime_type': mimeType,
    };

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return PrescriptionAnalysisResponse.fromJson(decoded);
    } else {
      throw Exception('이미지 처방전 분석 실패 (${response.statusCode}): ${response.body}');
    }
  }

  static Future<AiDeduction?> deduceDrugWithAi(String scannedName) async {
    try {
      final url = Uri.parse('$baseUrl/drugs/ai-deduce');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'scanned_name': scannedName}),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return AiDeduction.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }
}
