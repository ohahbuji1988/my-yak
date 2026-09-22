import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:my_yak/main.dart';
import 'package:my_yak/models/prescription.dart';

void main() {
  testWidgets('MyYakFigmaApp launches welcome cover, navigates tabs, and toggles medication filters', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 1. App starts with Welcome Cover Screen (Nano Banana design)
    await tester.pumpWidget(const MyYakFigmaApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('우리아이 안심 복약 시작하기'), findsOneWidget);
    expect(find.textContaining('My 약 (My Yak)'), findsOneWidget);

    // Tap to enter Main App
    await tester.tap(find.textContaining('우리아이 안심 복약 시작하기'));
    await tester.pumpAndSettle();

    // 2. Verify Home screen profile greeting & child name
    expect(find.textContaining('하준이'), findsWidgets);
    expect(find.textContaining('오늘도 건강하게 자라는 중'), findsOneWidget);
    expect(find.textContaining('나노바나나 안심 복약 커버 페이지'), findsOneWidget);

    // Verify Bottom Navigation Bar tabs
    expect(find.text('홈'), findsOneWidget);
    expect(find.text('복용 정보'), findsOneWidget);
    expect(find.text('스캔'), findsOneWidget);
    expect(find.text('의사 Q&A'), findsOneWidget);
    expect(find.text('내 아이'), findsOneWidget);

    // 3. Test '복용 정보' (Medication Info) tab and filter toggle
    await tester.tap(find.text('복용 정보'));
    await tester.pumpAndSettle();

    // In '복용 중' mode
    expect(find.textContaining('복용 중'), findsWidgets);
    expect(find.textContaining('코미시럽'), findsWidgets);

    // Tap '복용 완료 (5)' filter tab
    await tester.tap(find.textContaining('복용 완료 (5)'));
    await tester.pumpAndSettle();

    // Verify completed history medications are now shown
    expect(find.textContaining('비오플 250산'), findsOneWidget);
    expect(find.textContaining('세파클러 건조시럽'), findsOneWidget);
    expect(find.textContaining('맥시부펜 시럽'), findsOneWidget);

    // 4. Test '내 아이' (Profile) tab
    await tester.tap(find.text('내 아이'));
    await tester.pumpAndSettle();

    expect(find.textContaining('아기 프로필'), findsOneWidget);
    expect(find.textContaining('9.2 kg'), findsOneWidget);

    // 5. Navigate back to '홈' tab
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.textContaining('오늘의 복약 일정'), findsOneWidget);
  });

  testWidgets('HomeScreen dose toggle and antipyretic calculator test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // 1. Check initial dose progress (1/3 완료 (33%))
    expect(find.textContaining('1/3 완료 (33%)'), findsOneWidget);

    // 2. Tap second dose item ('기관지 패치 & 항생제') to toggle completion
    await tester.tap(find.text('기관지 패치 & 항생제'));
    await tester.pumpAndSettle();

    // Now 2/3 완료 (67%)
    expect(find.textContaining('2/3 완료 (67%)'), findsOneWidget);

    // 3. Open Antipyretic Calculator modal (from bottom compact TIP cards)
    await tester.scrollUntilVisible(find.text('해열제 교차계산'), 200);
    await tester.tap(find.text('해열제 교차계산'));
    await tester.pumpAndSettle();

    // Check modal content: 3.6 ml (acetaminophen) & 4.6 ml (dexibuprofen) for 9.2kg
    expect(find.text('해열제 교차복용 계산기'), findsOneWidget);
    expect(find.text('3.6 ml'), findsOneWidget);
    expect(find.text('4.6 ml'), findsOneWidget);
    expect(find.textContaining('소아과 전문의 교차복용 황금 수칙'), findsOneWidget);

    // Close modal
    await tester.tap(find.text('확인 완료'));
    await tester.pumpAndSettle();
  });

  testWidgets('BabyProfileScreen edit profile and weight update test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '내 아이' tab
    await tester.tap(find.text('내 아이'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9.2 kg'), findsOneWidget);

    // Tap '정보 수정' button
    await tester.tap(find.text('정보 수정'));
    await tester.pumpAndSettle();

    expect(find.text('✎ 아기 정보 및 체중 수정'), findsOneWidget);

    // Update weight to 9.8
    final weightField = find.widgetWithText(TextField, '현재 몸무게');
    await tester.enterText(weightField, '9.8');
    await tester.pumpAndSettle();

    // Tap save
    await tester.tap(find.text('수정 내용 저장하기'));
    await tester.pumpAndSettle();

    // Verify updated weight appears on profile screen
    expect(find.textContaining('9.8 kg'), findsOneWidget);

    // Verify updated weight on Home screen too
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();

    expect(find.textContaining('9.8kg'), findsWidgets);
  });

  testWidgets('DoctorQnaScreen add custom question and share test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '의사 Q&A' tab
    await tester.tap(find.text('의사 Q&A'));
    await tester.pumpAndSettle();

    expect(find.text('소아과 의사용 안심 Q&A'), findsOneWidget);

    // Tap '직접 질문 추가'
    await tester.tap(find.text('직접 질문 추가'));
    await tester.pumpAndSettle();

    expect(find.text('나만의 질문 추가'), findsOneWidget);

    final questionField = find.widgetWithText(TextField, '의사 선생님께 여쭤볼 내용');
    await tester.enterText(questionField, '열이 38.5도 넘으면 야간 응급실에 가야 하나요?');
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가하기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('야간 응급실에 가야 하나요?'), findsOneWidget);

    // Scroll up so button is above bottom navigation bar
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    final shareBtn = find.text('의사 질문지 저장 및 공유하기');
    await tester.tap(shareBtn);
    await tester.pumpAndSettle();

    expect(find.text('클립보드 복사 완료'), findsOneWidget);
  });

  testWidgets('DrugsListScreen toggle active and completed test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // Navigate to '복용 정보' tab
    await tester.tap(find.text('복용 정보'));
    await tester.pumpAndSettle();

    expect(find.textContaining('복용 중 (2)'), findsOneWidget);
    expect(find.textContaining('복용 완료 (5)'), findsOneWidget);

    // Tap '코미시럽 (코감기약)' to enter detail
    await tester.tap(find.text('코미시럽 (코감기약)'));
    await tester.pumpAndSettle();

    expect(find.text('처방약 상세 정보'), findsOneWidget);

    // Tap [✓ [복용 완료]로 변경] button
    await tester.tap(find.text('✓ [복용 완료]로 변경'));
    await tester.pumpAndSettle();

    // Detail button changed to [🔄 다시 [복용 중]으로 변경]
    expect(find.text('🔄 다시 [복용 중]으로 변경'), findsOneWidget);

    // Go back to drug list
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Now '복용 중' has 1 drug, '복용 완료' has 6 drugs!
    expect(find.textContaining('복용 중 (1)'), findsOneWidget);
    expect(find.textContaining('복용 완료 (6)'), findsOneWidget);
  });

  testWidgets('Multi-child selection on Welcome Cover and Header switcher test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    // 1. Launch app with Welcome Cover Screen
    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: true));
    await tester.pumpAndSettle();

    // Verify both children are listed in multi-child selector
    expect(find.text('하준이'), findsWidgets);
    expect(find.text('서아'), findsWidgets);

    // 2. Select '서아'
    await tester.tap(find.text('서아'));
    await tester.pumpAndSettle();

    // Verify top badge updated to '서아 14.5kg 맞춤 모드'
    expect(find.textContaining('서아 14.5kg 맞춤 모드'), findsOneWidget);

    // Tap CTA button with 서아
    await tester.tap(find.textContaining('우리아이 안심 복약 시작하기'));
    await tester.pumpAndSettle();

    // 3. Verify Home Screen is now tailored for 서아 (14.5kg)
    expect(find.textContaining('서아'), findsWidgets);
    expect(find.textContaining('14.5kg'), findsWidgets);
    expect(find.textContaining('클래리시드 건조시럽'), findsWidgets);

    // 4. Test Header '아이 변경' ActionChip to switch back to 하준이
    await tester.tap(find.text('아이 변경'));
    await tester.pumpAndSettle();

    expect(find.text('복약 관리 자녀 선택'), findsOneWidget);

    // Tap '하준이'
    await tester.tap(find.text('하준이').last);
    await tester.pumpAndSettle();

    // Verify Home Screen is back to 하준이 (9.2kg)
    expect(find.textContaining('하준이 (생후 10개월, 9.2kg)'), findsOneWidget);
    expect(find.textContaining('감기 물약 (코미시럽)'), findsWidgets);
  });

  testWidgets('AiDeduction model parsing and AI Smart Deduction UI test', (WidgetTester tester) async {
    // 1. Test AiDeduction JSON parsing (e.g. from /api/v1/drugs/ai-deduce)
    final json = {
      'drug_name': '슈클래리정250밀리그램',
      'original_scanned': '슈클래리정250밀리그램',
      'match_status': 'UNKNOWN',
      'confidence': 0.5,
      'status': 'UNKNOWN',
      'comment': "식약처 DB 및 시스템 목록에서 약품명 '슈클래리정250밀리그램'을(를) 정밀 매칭할 수 없어 '확인 불가' 상태로 처리되었습니다.",
      'candidates': <String>[],
      'ai_deduction': {
        'deduced_name': '슈클래리정250밀리그램',
        'ingredient': '클래리스로마이신 (Clarithromycin 250mg)',
        'category': '마크로라이드계 항생제',
        'reason': "유한양행의 마크로라이드계 항생제 '슈클래리정'으로 추론됩니다. 소아 호흡기 및 이비인후과 감염에 사용됩니다.",
        'confidence': 0.95,
        'suggested_db_key': '슈클래리정250밀리그램'
      }
    };

    final result = DrugAnalysisResult.fromJson(json);
    expect(result.status, 'UNKNOWN');
    expect(result.aiDeduction, isNotNull);
    expect(result.aiDeduction!.deducedName, '슈클래리정250밀리그램');
    expect(result.aiDeduction!.ingredient, contains('클래리스로마이신'));
    expect(result.aiDeduction!.category, contains('마크로라이드계'));
  });

  testWidgets('ARCH-01: Dose completion state persists across child switches without data leakage', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // 1. Toggle 하준이 second dose (기관지 패치) -> 2/3 완료
    await tester.tap(find.text('기관지 패치 & 항생제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2/3 완료 (67%)'), findsOneWidget);

    // 2. Switch child to 서아
    await tester.tap(find.text('아이 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('서아'));
    await tester.pumpAndSettle();

    // Verify 서아 initial doses are shown (1/3 완료)
    expect(find.textContaining('서아 (36개월'), findsOneWidget);
    expect(find.textContaining('기관지염 항생제 (클래리시드 건조시럽)'), findsWidgets);

    // 3. Switch back to 하준이
    await tester.tap(find.text('아이 변경'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('하준이').last);
    await tester.pumpAndSettle();

    // Verify 하준이's completion state (2/3 완료) was PRESERVED!
    expect(find.textContaining('하준이 (생후 10개월, 9.2kg)'), findsOneWidget);
    expect(find.textContaining('2/3 완료 (67%)'), findsOneWidget);
  });

  testWidgets('MED-02: Scanned dose unit, freq and days are preserved in DrugAnalysisResult', (WidgetTester tester) async {
    final json = {
      'drug_name': '슈클래리정250밀리그램',
      'original_scanned': '슈클래리정',
      'match_status': 'HIGH',
      'confidence': 0.95,
      'status': 'SAFE',
      'comment': '권장 복약 범위입니다.',
      'candidates': <String>[],
      'scanned_dose_unit': 5.0,
      'scanned_freq_per_day': 2,
      'scanned_days': 7,
      'storage_method': '실온 보관(1~30℃)',
      'discard_days': 14,
      'is_antibiotic': true,
      'compliance_note': '증상이 호전되어도 처방 일수를 끝까지 복용하세요.',
    };

    final result = DrugAnalysisResult.fromJson(json);
    expect(result.scannedDoseUnit, 5.0);
    expect(result.scannedFreqPerDay, 2);
    expect(result.scannedDays, 7);
    expect(result.storageMethod, '실온 보관(1~30℃)');
    expect(result.discardDays, 14);
    expect(result.isAntibiotic, isTrue);
  });

  testWidgets('Vomit guidance modal and Fever Triage interactive test', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MyYakFigmaApp(initialShowCover: false));
    await tester.pumpAndSettle();

    // 1. Tap Vomit Guidance Card (from bottom compact TIP cards)
    await tester.scrollUntilVisible(find.text('토했을 때 가이드'), 200);
    await tester.tap(find.text('토했을 때 가이드'));
    await tester.pumpAndSettle();

    expect(find.text('약 먹고 토했을 때 가이드'), findsOneWidget);
    expect(find.textContaining('10분 이내 토함'), findsOneWidget);
    expect(find.textContaining('동일 정량 즉시 재투약'), findsOneWidget);
    expect(find.textContaining('재투약 절대 금지'), findsOneWidget);

    // Close modal
    await tester.tap(find.text('확인 완료'));
    await tester.pumpAndSettle();

    // 2. Tap Antipyretic Calculator Card (from bottom compact TIP cards)
    await tester.scrollUntilVisible(find.text('해열제 교차계산'), 200);
    await tester.tap(find.text('해열제 교차계산'));
    await tester.pumpAndSettle();

    expect(find.text('해열제 교차복용 계산기'), findsOneWidget);
    expect(find.textContaining('체온별 Fever Triage'), findsOneWidget);

    // Tap 39.2℃ 고열 chip
    await tester.tap(find.text('39.2℃ 고열'));
    await tester.pumpAndSettle();

    expect(find.textContaining('고열 긴급 관찰'), findsOneWidget);

    // Close modal
    await tester.tap(find.text('확인 완료'));
    await tester.pumpAndSettle();
  });
}
