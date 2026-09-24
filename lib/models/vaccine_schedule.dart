class VaccineItem {
  final String id;
  final String name;
  final String category; // "필수접종", "영유아검진", "선택접종"
  final String targetDisease;
  final int targetMonths;
  final String monthRangeLabel;
  final String precautions;
  final bool isCheckup;

  const VaccineItem({
    required this.id,
    required this.name,
    required this.category,
    required this.targetDisease,
    required this.targetMonths,
    required this.monthRangeLabel,
    required this.precautions,
    this.isCheckup = false,
  });

  DateTime getRecommendedDate(DateTime birthDate) {
    return DateTime(birthDate.year, birthDate.month + targetMonths, birthDate.day);
  }

  int getDDay(DateTime birthDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = getRecommendedDate(birthDate);
    final targetDay = DateTime(target.year, target.month, target.day);
    return targetDay.difference(today).inDays;
  }
}

// 질병관리청(KCDA) & 국민건강보험공단 표준 영유아 접종 및 검진 데이터베이스
final List<VaccineItem> standardSchedules = [
  // 1. 출생 직후
  const VaccineItem(
    id: 'vac_bcg',
    name: 'BCG (결핵)',
    category: '필수접종',
    targetDisease: '중증 결핵성 수막염·속립결핵 예방',
    targetMonths: 0,
    monthRangeLabel: '생후 4주 이내 (출생 직후)',
    precautions: '피내용(무료/보건소) 또는 경피용(유료/소아과) 선택. 열이 없을 때 접종.',
  ),
  const VaccineItem(
    id: 'vac_hep_b_1',
    name: 'B형간염 1차',
    category: '필수접종',
    targetDisease: 'B형 간염 바이러스 감염 예방',
    targetMonths: 0,
    monthRangeLabel: '출생 시 (분만 병원)',
    precautions: '출생 직후 분만 병원에서 대부분 당일 접종합니다.',
  ),

  // 2. 1개월
  const VaccineItem(
    id: 'chk_1',
    name: '영유아 건강검진 1차',
    category: '영유아검진',
    targetDisease: '신체계측(키·몸무게·머리둘레), 수유 지도, 영아돌연사 예방',
    targetMonths: 1,
    monthRangeLabel: '생후 14일 ~ 35일',
    precautions: '문진표를 모바일(The건강보험 앱)에서 미리 작성해가시면 빠릅니다.',
    isCheckup: true,
  ),
  const VaccineItem(
    id: 'vac_hep_b_2',
    name: 'B형간염 2차',
    category: '필수접종',
    targetDisease: 'B형 간염 바이러스 만성화 예방',
    targetMonths: 1,
    monthRangeLabel: '생후 1개월',
    precautions: '1차 접종일로부터 1개월 뒤 접종합니다.',
  ),

  // 3. 2개월 (접종 마라톤 시작)
  const VaccineItem(
    id: 'vac_dtap_1',
    name: 'DTaP-IPV-Hib-B형 6가 (1차)',
    category: '필수접종',
    targetDisease: '디프테리아·파상풍·백일해·소아마비·뇌수막염',
    targetMonths: 2,
    monthRangeLabel: '생후 2개월',
    precautions: '6가 콤보백신(헥사심 등)으로 1대로 단축 가능. 미열 발생 대비 체온계 필수 준비.',
  ),
  const VaccineItem(
    id: 'vac_pcv_1',
    name: '폐렴구균 1차 (PCV)',
    category: '필수접종',
    targetDisease: '폐렴, 급성 중이염, 균혈증 예방',
    targetMonths: 2,
    monthRangeLabel: '생후 2개월',
    precautions: '접종열(38℃ 안팎) 빈도가 높은 주사입니다. 타이레놀(아세트아미노펜) 구비 권장.',
  ),
  const VaccineItem(
    id: 'vac_rota_1',
    name: '로타바이러스 1차 (경구)',
    category: '필수접종',
    targetDisease: '영유아 급성 설사·구토성 장염 예방',
    targetMonths: 2,
    monthRangeLabel: '생후 2개월',
    precautions: '먹는 백신(로타릭스 2회 또는 로타텍 3회). 수유 1시간 전후로 접종 권장.',
  ),

  // 4. 4개월
  const VaccineItem(
    id: 'chk_2',
    name: '영유아 건강검진 2차',
    category: '영유아검진',
    targetDisease: '뒤집기·목가누기 발달 평가, 수면 교육, 이유식 시작 지도',
    targetMonths: 4,
    monthRangeLabel: '생후 4개월 ~ 6개월',
    precautions: '뒤집기 지연 여부와 고관절 이형성증을 집중 확인합니다.',
    isCheckup: true,
  ),
  const VaccineItem(
    id: 'vac_dtap_2',
    name: 'DTaP-IPV 2차 콤보',
    category: '필수접종',
    targetDisease: '디프테리아·파상풍·백일해·소아마비 2차',
    targetMonths: 4,
    monthRangeLabel: '생후 4개월',
    precautions: '1차와 동일 백신 권장. 이상반응 여부 관찰.',
  ),
  const VaccineItem(
    id: 'vac_pcv_2',
    name: '폐렴구균 2차',
    category: '필수접종',
    targetDisease: '폐렴구균 중이염·수막염 2차 방어',
    targetMonths: 4,
    monthRangeLabel: '생후 4개월',
    precautions: '1차 접종 후 접종열 경험이 있었다면 오전에 일찍 접종하세요.',
  ),
  const VaccineItem(
    id: 'vac_rota_2',
    name: '로타바이러스 2차 (경구)',
    category: '필수접종',
    targetDisease: '로타바이러스 장염 2차',
    targetMonths: 4,
    monthRangeLabel: '생후 4개월',
    precautions: '먹는 백신. 게워냄 주의.',
  ),

  // 5. 6개월
  const VaccineItem(
    id: 'vac_dtap_3',
    name: 'DTaP-IPV 3차 콤보',
    category: '필수접종',
    targetDisease: '디프테리아·파상풍·백일해 기초면역 완성',
    targetMonths: 6,
    monthRangeLabel: '생후 6개월',
    precautions: '기초접종 3회차 완성을 통해 강력한 항체가 형성됩니다.',
  ),
  const VaccineItem(
    id: 'vac_pcv_3',
    name: '폐렴구균 3차',
    category: '필수접종',
    targetDisease: '폐렴구균 3차 기초접종',
    targetMonths: 6,
    monthRangeLabel: '생후 6개월',
    precautions: '접종 후 문지르지 말고 가볍게 1분간 압박 지혈하세요.',
  ),
  const VaccineItem(
    id: 'vac_hep_b_3',
    name: 'B형간염 3차',
    category: '필수접종',
    targetDisease: 'B형간염 평생 항체 형성 완료',
    targetMonths: 6,
    monthRangeLabel: '생후 6개월',
    precautions: '생후 6개월 이전에는 접종하지 않도록 주의합니다.',
  ),
  const VaccineItem(
    id: 'vac_flu',
    name: '인플루엔자(독감) 1·2차',
    category: '필수접종',
    targetDisease: '계절성 독감(A/B형) 바이러스 감염 예방',
    targetMonths: 6,
    monthRangeLabel: '생후 6개월 이상 (가을/겨울철)',
    precautions: '생애 첫 접종 시 4주 간격으로 2회 접종(무료 국가예방접종).',
  ),

  // 6. 9~12개월
  const VaccineItem(
    id: 'chk_3',
    name: '영유아 건강검진 3차',
    category: '영유아검진',
    targetDisease: '앉기·잡고 일어서기, 손가락 쥐기, 빈혈 및 낙상 사고 예방',
    targetMonths: 9,
    monthRangeLabel: '생후 9개월 ~ 12개월',
    precautions: '철분 부족 빈혈 검사와 분리불안 대처 교육이 포함됩니다.',
    isCheckup: true,
  ),

  // 7. 12~15개월 (돌 기념 주사)
  const VaccineItem(
    id: 'vac_mmr_1',
    name: 'MMR 1차 (홍역·유행성이하선염·풍진)',
    category: '필수접종',
    targetDisease: '홍역, 볼거리, 풍진 바이러스 예방',
    targetMonths: 12,
    monthRangeLabel: '생후 12개월 ~ 15개월 (돌 이후)',
    precautions: '생백신으로 접종 7~10일 뒤 미열이나 가벼운 발진이 올 수 있습니다.',
  ),
  const VaccineItem(
    id: 'vac_var',
    name: '수두 1차',
    category: '필수접종',
    targetDisease: '수두 바이러스 수포 감염 예방',
    targetMonths: 12,
    monthRangeLabel: '생후 12개월 ~ 15개월',
    precautions: 'MMR과 같은 날 동시 접종하거나, 4주 이상 간격을 두고 접종합니다.',
  ),
  const VaccineItem(
    id: 'vac_pcv_4',
    name: '폐렴구균 4차 (추가접종)',
    category: '필수접종',
    targetDisease: '폐렴구균 추가 방어 완성',
    targetMonths: 12,
    monthRangeLabel: '생후 12개월 ~ 15개월',
    precautions: '3차 접종 후 최소 2개월 이상 경과한 뒤 접종합니다.',
  ),
  const VaccineItem(
    id: 'vac_je_1',
    name: '일본뇌염 1차',
    category: '필수접종',
    targetDisease: '일본뇌염 모기 매개 뇌염 바이러스 예방',
    targetMonths: 12,
    monthRangeLabel: '생후 12개월 ~ 24개월',
    precautions: '사백신(총 5회 무료) 또는 생백신(총 2회 무료) 중 하나를 선택하여 진행.',
  ),

  // 8. 18~24개월
  const VaccineItem(
    id: 'chk_4',
    name: '영유아 건강검진 4차 & 1차 구강검진',
    category: '영유아검진',
    targetDisease: '걷기·달리기, 첫 낱말 발화, 유치 충치 점검 및 불소 지도',
    targetMonths: 18,
    monthRangeLabel: '생후 18개월 ~ 24개월',
    precautions: '치과 방문을 통한 구강검진이 처음으로 함께 시작됩니다.',
    isCheckup: true,
  ),
  const VaccineItem(
    id: 'vac_dtap_4',
    name: 'DTaP 4차 (추가접종)',
    category: '필수접종',
    targetDisease: '디프테리아·백일해 면역 보강',
    targetMonths: 18,
    monthRangeLabel: '생후 15개월 ~ 18개월',
    precautions: '3차 접종 후 6개월 이상 경과한 뒤 접종합니다.',
  ),
];

DateTime parseBabyBirthDate(String birthDateStr, {String ageStr = ''}) {
  try {
    // 1. 정규식으로 YYYY, MM, DD 추출
    final reg = RegExp(r'(\d{4})[^\d]+(\d{1,2})[^\d]+(\d{1,2})');
    final match = reg.firstMatch(birthDateStr);
    if (match != null) {
      final y = int.parse(match.group(1)!);
      final m = int.parse(match.group(2)!);
      final d = int.parse(match.group(3)!);
      return DateTime(y, m, d);
    }

    // 2. YYYY-MM-DD
    final parsed = DateTime.tryParse(birthDateStr.replaceAll('.', '-').trim());
    if (parsed != null) return parsed;
  } catch (_) {}

  // 3. 만약 파싱 실패 시 나이/월령 텍스트에서 역산
  final monthMatch = RegExp(r'(\d+)\s*개월').firstMatch(ageStr);
  if (monthMatch != null) {
    final months = int.tryParse(monthMatch.group(1)!) ?? 0;
    final now = DateTime.now();
    return DateTime(now.year, now.month - months, 15);
  }

  // 기본 fallback: 1년 전
  final now = DateTime.now();
  return DateTime(now.year - 1, now.month, now.day);
}
