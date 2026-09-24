import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/profile.dart';

class StorageService {
  static const String _keyProfiles = 'my_yak_family_profiles';
  static const String _keyInitialized = 'my_yak_profiles_initialized';
  static const String _keySelectedProfileId = 'my_yak_selected_profile_id';
  static const String _keyCustomServerUrl = 'my_yak_custom_server_url';

  /// 저장된 프로필 목록 로드 (최초 실행 시 기본 예시 프로필 제공, 이후 사용자 수정/삭제 영구 반영)
  static Future<List<MemberProfile>> loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasInitialized = prefs.getBool(_keyInitialized) ?? false;

      if (!hasInitialized) {
        // 최초 실행: 기본 예시 프로필 저장 후 반환
        final initialList = List<MemberProfile>.from(defaultFamilyProfiles);
        await saveProfiles(initialList);
        await prefs.setBool(_keyInitialized, true);
        return initialList;
      }

      final jsonString = prefs.getString(_keyProfiles);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> decoded = jsonDecode(jsonString);
      return decoded.map((item) => MemberProfile.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e, stack) {
      // JSON 파싱 오류 등 예외 발생 — 데이터 유실 방지를 위해 기본 프로필로 복구
      // 실기기 환경에서 콘솔/로깅에서 확인 가능
      // ignore: avoid_print
      print('[StorageService] loadProfiles 오류 (데이터 복구): $e\n$stack');
      return List<MemberProfile>.from(defaultFamilyProfiles);
    }
  }

  /// 프로필 목록 저장
  static Future<void> saveProfiles(List<MemberProfile> profiles) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final listMap = profiles.map((p) => p.toMap()).toList();
      final jsonString = jsonEncode(listMap);
      await prefs.setString(_keyProfiles, jsonString);
      await prefs.setBool(_keyInitialized, true);
    } catch (_) {}
  }

  /// 마지막 선택된 프로필 ID 로드
  static Future<String?> loadSelectedProfileId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keySelectedProfileId);
    } catch (_) {
      return null;
    }
  }

  /// 마지막 선택된 프로필 ID 저장
  static Future<void> saveSelectedProfileId(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keySelectedProfileId, id);
    } catch (_) {}
  }

  /// 커스텀 서버 URL 로드
  static Future<String?> loadCustomServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_keyCustomServerUrl);
    } catch (_) {
      return null;
    }
  }

  /// 커스텀 서버 URL 저장
  static Future<void> saveCustomServerUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyCustomServerUrl, url.trim());
    } catch (_) {}
  }

  /// 접종/검진 완료 목록 로드
  static Future<List<String>> loadCompletedVaccines(String profileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList('vaccine_completed_$profileId') ?? [];
    } catch (_) {
      return [];
    }
  }

  /// 접종/검진 완료 목록 저장
  static Future<void> saveCompletedVaccines(String profileId, List<String> completedIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('vaccine_completed_$profileId', completedIds);
    } catch (_) {}
  }

  /// 접종/검진 다가오는 알림 활성화 여부 로드 (기본 true)
  static Future<bool> loadVaccineAlarmEnabled(String profileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('vaccine_alarm_$profileId') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 접종/검진 다가오는 알림 활성화 여부 저장
  static Future<void> saveVaccineAlarmEnabled(String profileId, bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('vaccine_alarm_$profileId', enabled);
    } catch (_) {}
  }
}
