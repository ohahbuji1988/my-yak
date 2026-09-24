enum MemberType { child, adult }

class MemberProfile {
  final String id;
  final String name;
  final MemberType memberType;
  final String age;
  final String birthDate;
  final String gender;
  final double? weightKg;
  final bool isPregnant;
  final String allergyNotes;
  final List<PrescriptionHistoryItem> history;

  MemberProfile({
    required this.id,
    required this.name,
    required this.memberType,
    this.age = '생후 10개월',
    this.birthDate = '2025년 03월 12일',
    this.gender = '남아',
    this.weightKg = 9.2,
    this.isPregnant = false,
    this.allergyNotes = '',
    List<PrescriptionHistoryItem>? history,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'member_type': memberType == MemberType.child ? 'CHILD' : 'ADULT',
      'weight_kg': weightKg,
      'is_pregnant': isPregnant,
      'allergy_notes': allergyNotes,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'member_type': memberType == MemberType.child ? 'child' : 'adult',
      'age': age,
      'birth_date': birthDate,
      'gender': gender,
      'weight_kg': weightKg,
      'is_pregnant': isPregnant,
      'allergy_notes': allergyNotes,
      'history': history.map((item) => item.toMap()).toList(),
    };
  }

  factory MemberProfile.fromMap(Map<String, dynamic> map) {
    return MemberProfile(
      id: map['id'] ?? 'child_${DateTime.now().millisecondsSinceEpoch}',
      name: map['name'] ?? '우리 아이',
      memberType: map['member_type'] == 'adult' ? MemberType.adult : MemberType.child,
      age: map['age'] ?? '생후 12개월',
      birthDate: map['birth_date'] ?? '2025년 등록',
      gender: map['gender'] ?? '남아',
      weightKg: (map['weight_kg'] as num?)?.toDouble() ?? 10.0,
      isPregnant: map['is_pregnant'] ?? false,
      allergyNotes: map['allergy_notes'] ?? '',
      history: (map['history'] as List<dynamic>?)
              ?.map((item) => PrescriptionHistoryItem.fromMap(item as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  int? get ageMonths {
    final match = RegExp(r'(\d+)\s*개월').firstMatch(age);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    final yearMatch = RegExp(r'만\s*(\d+)세').firstMatch(age);
    if (yearMatch != null) {
      return (int.tryParse(yearMatch.group(1)!) ?? 0) * 12;
    }
    return null;
  }

  MemberProfile copyWith({
    String? id,
    String? name,
    MemberType? memberType,
    String? age,
    String? birthDate,
    String? gender,
    double? weightKg,
    bool? isPregnant,
    String? allergyNotes,
    List<PrescriptionHistoryItem>? history,
  }) {
    return MemberProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      memberType: memberType ?? this.memberType,
      age: age ?? this.age,
      birthDate: birthDate ?? this.birthDate,
      gender: gender ?? this.gender,
      weightKg: weightKg ?? this.weightKg,
      isPregnant: isPregnant ?? this.isPregnant,
      allergyNotes: allergyNotes ?? this.allergyNotes,
      history: history ?? this.history,
    );
  }
}

class PrescriptionHistoryItem {
  final String dateStr;
  final String drugName;
  final String indication;
  final String durationStr;
  final String clinicName;

  PrescriptionHistoryItem({
    required this.dateStr,
    required this.drugName,
    required this.indication,
    required this.durationStr,
    required this.clinicName,
  });

  Map<String, dynamic> toMap() {
    return {
      'date_str': dateStr,
      'drug_name': drugName,
      'indication': indication,
      'duration_str': durationStr,
      'clinic_name': clinicName,
    };
  }

  factory PrescriptionHistoryItem.fromMap(Map<String, dynamic> map) {
    return PrescriptionHistoryItem(
      dateStr: map['date_str'] ?? '',
      drugName: map['drug_name'] ?? '',
      indication: map['indication'] ?? '',
      durationStr: map['duration_str'] ?? '',
      clinicName: map['clinic_name'] ?? '',
    );
  }
}

// 다자녀(다둥이) 기본 등록 프로필 목록
final List<MemberProfile> defaultFamilyProfiles = [
  MemberProfile(
    id: 'child_1',
    name: '하준이',
    memberType: MemberType.child,
    age: '생후 10개월',
    birthDate: '2025년 03월 12일',
    gender: '남아',
    weightKg: 9.2,
    allergyNotes: '페니실린 계열 항생제 복용 시 가벼운 피부 발진 유발 이력 있음.',
    history: [
      PrescriptionHistoryItem(
        dateStr: '2026.01.24',
        drugName: '코미시럽 (코감기)',
        indication: '코막힘/콧물',
        durationStr: '처방기간 3일',
        clinicName: '소아과 처방',
      ),
      PrescriptionHistoryItem(
        dateStr: '2026.01.20',
        drugName: '아모클란듀오 시럽 (항생제)',
        indication: '중이염',
        durationStr: '처방기간 7일',
        clinicName: '이비인후과 처방',
      ),
    ],
  ),
  MemberProfile(
    id: 'child_2',
    name: '서아',
    memberType: MemberType.child,
    age: '36개월 (만 3세)',
    birthDate: '2023년 08월 15일',
    gender: '여아',
    weightKg: 14.5,
    allergyNotes: '특이 약물 알레르기 없음. 아스피린 복용 주의.',
    history: [
      PrescriptionHistoryItem(
        dateStr: '2026.01.25',
        drugName: '클래리시드 건조시럽 (항생제)',
        indication: '급성 기관지염',
        durationStr: '처방기간 5일',
        clinicName: '소아청소년과 처방',
      ),
      PrescriptionHistoryItem(
        dateStr: '2026.01.15',
        drugName: '맥시부펜시럽 (해열진통)',
        indication: '미열 및 인후통',
        durationStr: '필요 시 투약',
        clinicName: '가정 비상약',
      ),
    ],
  ),
];
