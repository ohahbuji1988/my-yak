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
    } catch (e) {
      // 오류 발생 시 fallback
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
}
