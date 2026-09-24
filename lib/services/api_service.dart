import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import '../models/prescription.dart';

class ApiService {
  // 모바일 앱 및 원격 클라우드 연결용 커스텀 서버 주소 (미설정 시 기본 도메인 또는 로컬)
  static String? customBaseUrl;
  static const String defaultCloudServer = 'https://my-yak.onrender.com';

  static String get baseUrl {
    if (customBaseUrl != null && customBaseUrl!.isNotEmpty) {
      String clean = customBaseUrl!.trim();
      if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
      return clean.endsWith('/api/v1') ? clean : '$clean/api/v1';
    }

    if (kIsWeb) {
      final origin = Uri.base.origin;
      // 로컬 Flutter 디버그(5000번 포트)일 때는 8000번 FastAPI를 바라보고,
      // 올인원 서빙 및 배포 환경(Render, 동일 포트 등)에서는 현재 웹 도메인을 그대로 활용
      if (origin.isNotEmpty && !origin.startsWith('file:') && !origin.contains(':5000')) {
        return '$origin/api/v1';
      }
      return 'http://127.0.0.1:8000/api/v1';
    }

    // 모바일(갤럭시/Android) 앱 환경: 기본 배포 클라우드 주소 사용 (로컬 에뮬레이터가 아닌 실기기 배포)
    return '$defaultCloudServer/api/v1';
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
