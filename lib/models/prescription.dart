class ScannedDrugItem {
  String scannedName;
  double doseUnit;
  int freqPerDay;
  int days;

  ScannedDrugItem({
    required this.scannedName,
    required this.doseUnit,
    required this.freqPerDay,
    this.days = 1,
  });

  Map<String, dynamic> toJson() {
    return {
      'scanned_name': scannedName,
      'dose_unit': doseUnit,
      'freq_per_day': freqPerDay,
      'days': days,
    };
  }
}

class AiDeduction {
  final String deducedName;
  final String ingredient;
  final String category;
  final String reason;
  final double confidence;
  final String suggestedDbKey;

  AiDeduction({
    required this.deducedName,
    required this.ingredient,
    required this.category,
    required this.reason,
    required this.confidence,
    required this.suggestedDbKey,
  });

  factory AiDeduction.fromJson(Map<String, dynamic> json) {
    return AiDeduction(
      deducedName: json['deduced_name'] ?? '',
      ingredient: json['ingredient'] ?? '',
      category: json['category'] ?? '',
      reason: json['reason'] ?? '',
      confidence: (json['confidence'] ?? 0.9).toDouble(),
      suggestedDbKey: json['suggested_db_key'] ?? json['deduced_name'] ?? '',
    );
  }
}

class DrugAnalysisResult {
  final String drugName;
  final String originalScanned;
  final String matchStatus;
  final double confidence;
  final String status; // 'SAFE', 'WARNING', 'HIGH', 'LOW', 'UNKNOWN'
  final String comment;
  final String? safetyGuide;
  final List<String> candidates;
  final AiDeduction? aiDeduction;
  final double? scannedDoseUnit;
  final int? scannedFreqPerDay;
  final int? scannedDays;
  final String? storageMethod;
  final int? discardDays;
  final bool? isAntibiotic;
  final String? complianceNote;
  final String? purpose;

  DrugAnalysisResult({
    required this.drugName,
    required this.originalScanned,
    required this.matchStatus,
    required this.confidence,
    required this.status,
    required this.comment,
    this.safetyGuide,
    required this.candidates,
    this.aiDeduction,
    this.scannedDoseUnit,
    this.scannedFreqPerDay,
    this.scannedDays,
    this.storageMethod,
    this.discardDays,
    this.isAntibiotic,
    this.complianceNote,
    this.purpose,
  });

  factory DrugAnalysisResult.fromJson(Map<String, dynamic> json) {
    return DrugAnalysisResult(
      drugName: json['drug_name'] ?? '',
      originalScanned: json['original_scanned'] ?? '',
      matchStatus: json['match_status'] ?? 'HIGH',
      confidence: (json['confidence'] ?? 1.0).toDouble(),
      status: json['status'] ?? 'SAFE',
      comment: json['comment'] ?? '',
      safetyGuide: json['safety_guide'],
      candidates: List<String>.from(json['candidates'] ?? []),
      aiDeduction: json['ai_deduction'] != null && json['ai_deduction'] is Map<String, dynamic>
          ? AiDeduction.fromJson(json['ai_deduction'])
          : null,
      scannedDoseUnit: json['scanned_dose_unit'] != null ? (json['scanned_dose_unit'] as num).toDouble() : null,
      scannedFreqPerDay: json['scanned_freq_per_day'] != null ? (json['scanned_freq_per_day'] as num).toInt() : null,
      scannedDays: json['scanned_days'] != null ? (json['scanned_days'] as num).toInt() : null,
      storageMethod: json['storage_method'],
      discardDays: json['discard_days'] != null ? (json['discard_days'] as num).toInt() : null,
      isAntibiotic: json['is_antibiotic'] == true,
      complianceNote: json['compliance_note'],
      purpose: json['purpose'] ?? (json['ai_deduction'] != null ? json['ai_deduction']['category'] : null),
    );
  }
}

class DurWarning {
  final String type;
  final String severity;
  final String message;
  final List<String> affectedDrugs;

  DurWarning({
    required this.type,
    required this.severity,
    required this.message,
    required this.affectedDrugs,
  });

  factory DurWarning.fromJson(Map<String, dynamic> json) {
    return DurWarning(
      type: json['type'] ?? '',
      severity: json['severity'] ?? 'WARNING',
      message: json['message'] ?? '',
      affectedDrugs: List<String>.from(json['affected_drugs'] ?? []),
    );
  }
}

class DoctorQnaItem {
  final String id;
  final String category;
  final String question;
  bool isSelected;

  DoctorQnaItem({
    required this.id,
    required this.category,
    required this.question,
    this.isSelected = true,
  });

  factory DoctorQnaItem.fromJson(Map<String, dynamic> json) {
    return DoctorQnaItem(
      id: json['id'] ?? '',
      category: json['category'] ?? '일반',
      question: json['question'] ?? '',
      isSelected: json['is_default_selected'] == true || json['is_selected'] == true,
    );
  }
}

class PrescriptionAnalysisResponse {
  final List<DrugAnalysisResult> analyzedDrugs;
  final List<DurWarning> durWarnings;
  final List<DoctorQnaItem> doctorQna;
  final String safetyReport;
  final String disclaimer;

  PrescriptionAnalysisResponse({
    required this.analyzedDrugs,
    required this.durWarnings,
    required this.doctorQna,
    required this.safetyReport,
    required this.disclaimer,
  });

  factory PrescriptionAnalysisResponse.fromJson(Map<String, dynamic> json) {
    return PrescriptionAnalysisResponse(
      analyzedDrugs: (json['analyzed_drugs'] as List)
          .map((item) => DrugAnalysisResult.fromJson(item))
          .toList(),
      durWarnings: (json['dur_warnings'] as List? ?? [])
          .map((item) => DurWarning.fromJson(item))
          .toList(),
      doctorQna: (json['doctor_qna'] as List? ?? [])
          .map((item) => DoctorQnaItem.fromJson(item))
          .toList(),
      safetyReport: json['safety_report'] ?? '',
      disclaimer: json['disclaimer'] ?? '',
    );
  }
}
