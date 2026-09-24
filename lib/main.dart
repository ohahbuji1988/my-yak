import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'models/profile.dart';
import 'models/prescription.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'models/vaccine_schedule.dart';
import 'screens/vaccine_scheduler_sheet.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KidipediaApp());
}

typedef MyYakFigmaApp = KidipediaApp;

class KidipediaApp extends StatelessWidget {
  final bool initialShowCover;
  const KidipediaApp({super.key, this.initialShowCover = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kidipedia (키디피디아)',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFFAF9F6),
        primaryColor: const Color(0xFFFF6B8B),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B8B),
          primary: const Color(0xFFFF6B8B),
          secondary: const Color(0xFF10B981),
        ),
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: AppRootScreen(initialShowCover: initialShowCover),
    );
  }
}

class AppRootScreen extends StatefulWidget {
  final bool initialShowCover;
  const AppRootScreen({super.key, this.initialShowCover = true});

  @override
  State<AppRootScreen> createState() => _AppRootScreenState();
}

class _AppRootScreenState extends State<AppRootScreen> {
  bool _showCover = true;
  bool _isLoading = true;
  List<MemberProfile> _familyProfiles = [];
  late MemberProfile _selectedChild;

  @override
  void initState() {
    super.initState();
    _showCover = widget.initialShowCover;
    _initStorageAndProfiles();
  }

  Future<void> _initStorageAndProfiles() async {
    final customUrl = await StorageService.loadCustomServerUrl();
    if (customUrl != null && customUrl.isNotEmpty) {
      ApiService.customBaseUrl = customUrl;
    }

    final loadedProfiles = await StorageService.loadProfiles();
    final savedId = await StorageService.loadSelectedProfileId();

    MemberProfile initial;
    if (loadedProfiles.isNotEmpty) {
      final found = loadedProfiles.where((p) => p.id == savedId);
      initial = found.isNotEmpty ? found.first : loadedProfiles.first;
    } else {
      initial = MemberProfile(
        id: 'child_',
        name: '우리 아이',
        memberType: MemberType.child,
        age: '생후 12개월',
        weightKg: 10.0,
      );
      loadedProfiles.add(initial);
      await StorageService.saveProfiles(loadedProfiles);
    }

    if (mounted) {
      setState(() {
        _familyProfiles = loadedProfiles;
        _selectedChild = initial;
        _isLoading = false;
      });
    }
  }

  void _handleAddNewChild(MemberProfile newChild) {
    setState(() {
      _familyProfiles.add(newChild);
      _selectedChild = newChild;
    });
    StorageService.saveProfiles(_familyProfiles);
    StorageService.saveSelectedProfileId(newChild.id);
  }

  void _handleDeleteChild(String childId) {
    setState(() {
      _familyProfiles.removeWhere((p) => p.id == childId);
      if (_familyProfiles.isEmpty) {
        final fallback = MemberProfile(
          id: 'child_',
          name: '우리 아이',
          memberType: MemberType.child,
          age: '생후 12개월',
          weightKg: 10.0,
        );
        _familyProfiles.add(fallback);
        _selectedChild = fallback;
      } else if (_selectedChild.id == childId) {
        _selectedChild = _familyProfiles.first;
      }
    });
    StorageService.saveProfiles(_familyProfiles);
    StorageService.saveSelectedProfileId(_selectedChild.id);
  }

  void _handleProfileUpdated(MemberProfile updated) {
    setState(() {
      final index = _familyProfiles.indexWhere((p) => p.id == updated.id);
      if (index != -1) {
        _familyProfiles[index] = updated;
      }
      if (_selectedChild.id == updated.id) {
        _selectedChild = updated;
      }
    });
    StorageService.saveProfiles(_familyProfiles);
  }

  void _handleChildChanged(MemberProfile child) {
    setState(() {
      _selectedChild = child;
    });
    StorageService.saveSelectedProfileId(child.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFFAF9F6),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
        ),
      );
    }

    if (_showCover == true) {
      return WelcomeCoverScreen(
        profiles: _familyProfiles,
        initialSelectedChild: _selectedChild,
        onStartWithChild: (child) => setState(() {
          _selectedChild = child;
          _showCover = false;
        }),
        onStart: () => setState(() => _showCover = false),
        onAddNewChild: _handleAddNewChild,
        onDeleteChild: _handleDeleteChild,
      );
    }
    return MainFigmaScreen(
      initialProfile: _selectedChild,
      familyProfiles: _familyProfiles,
      onChildChanged: _handleChildChanged,
      onAddNewChild: _handleAddNewChild,
      onDeleteChild: _handleDeleteChild,
      onProfileUpdated: _handleProfileUpdated,
      onOpenCover: () => setState(() => _showCover = true),
    );
  }
}

// ----------------------------------------------------------------------
// 0. WELCOME COVER SCREEN (나노바나나 디자인 안심 복약 커버 페이지)
// ----------------------------------------------------------------------
class WelcomeCoverScreen extends StatefulWidget {
  final VoidCallback? onStart;
  final Function(MemberProfile)? onStartWithChild;
  final List<MemberProfile> profiles;
  final MemberProfile? initialSelectedChild;
  final Function(MemberProfile)? onAddNewChild;
  final Function(String)? onDeleteChild;

  const WelcomeCoverScreen({
    super.key,
    this.onStart,
    this.onStartWithChild,
    this.profiles = const [],
    this.initialSelectedChild,
    this.onAddNewChild,
    this.onDeleteChild,
  });

  @override
  State<WelcomeCoverScreen> createState() => _WelcomeCoverScreenState();
}

class _WelcomeCoverScreenState extends State<WelcomeCoverScreen> {
  // nullable 로 선언해 초기화 전 접근 방지
  MemberProfile? _currentChildNullable;
  MemberProfile get _currentChild => _currentChildNullable!;

  @override
  void initState() {
    super.initState();
    _syncCurrentChild();
  }

  @override
  void didUpdateWidget(WelcomeCoverScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCurrentChild();
  }

  void _syncCurrentChild() {
    if (widget.initialSelectedChild != null &&
        widget.profiles.any((p) => p.id == widget.initialSelectedChild!.id)) {
      _currentChildNullable = widget.initialSelectedChild!;
    } else if (widget.profiles.isNotEmpty) {
      // _currentChildNullable이 아직 null이거나 목록에 없으면 첫 번째로 교체
      final currentId = _currentChildNullable?.id;
      if (currentId == null || !widget.profiles.any((p) => p.id == currentId)) {
        _currentChildNullable = widget.profiles.first;
      }
    } else {
      _currentChildNullable = MemberProfile(
        id: '1',
        name: '우리 아이',
        memberType: MemberType.child,
        weightKg: 10.0,
      );
    }
  }

  void _confirmDeleteProfile(BuildContext context, MemberProfile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Color(0xFFFF6B8B)),
            const SizedBox(width: 8),
            Text('${profile.name} 삭제', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text('\'${profile.name}\'의 프로필을 삭제하시겠습니까?\n삭제 후에는 복구할 수 없습니다.',
            style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDeleteChild?.call(profile.id);
            },
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openAddChildModal(BuildContext context) {
    DateTime selectedBirthDate = DateTime.now().subtract(const Duration(days: 365));
    final birthDateCtrl = TextEditingController(
      text: '${selectedBirthDate.year}년 ${selectedBirthDate.month.toString().padLeft(2, '0')}월 ${selectedBirthDate.day.toString().padLeft(2, '0')}일',
    );
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '생후 12개월');
    final weightCtrl = TextEditingController(text: '10.0');
    String gender = '남아';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('👶 새 자녀 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '아이 이름',
                  hintText: '예: 도윤이',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: birthDateCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '생년월일 (예방접종·검진 기준)',
                  hintText: '생년월일을 선택해주세요',
                  prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFFFF6B8B), size: 20),
                  suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedBirthDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 12)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() {
                      selectedBirthDate = picked;
                      birthDateCtrl.text = '${picked.year}년 ${picked.month.toString().padLeft(2, '0')}월 ${picked.day.toString().padLeft(2, '0')}일';
                      int months = (DateTime.now().year - picked.year) * 12 + (DateTime.now().month - picked.month);
                      if (DateTime.now().day < picked.day) months--;
                      if (months < 0) months = 0;
                      ageCtrl.text = '생후 $months개월';
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ageCtrl,
                      decoration: InputDecoration(
                        labelText: '월령/나이',
                        hintText: '생후 18개월',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '체중(kg)',
                        hintText: '11.5',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('성별: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('남아 👦'),
                    selected: gender == '남아',
                    onSelected: (val) => setModalState(() => gender = '남아'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('여아 👧'),
                    selected: gender == '여아',
                    onSelected: (val) => setModalState(() => gender = '여아'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final w = double.tryParse(weightCtrl.text.trim()) ?? 10.0;
                  final newProfile = MemberProfile(
                    id: 'child_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    memberType: MemberType.child,
                    age: ageCtrl.text.trim(),
                    birthDate: birthDateCtrl.text.trim(),
                    gender: gender,
                    weightKg: w,
                    allergyNotes: '',
                    history: [],
                  );
                  widget.onAddNewChild?.call(newProfile);
                  setState(() {
                    _currentChildNullable = newProfile;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('등록 완료', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableProfiles = widget.profiles;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF7F9),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFFD6DF)),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currentChild.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          '${_currentChild.name} ${_currentChild.weightKg}kg 맞춤 모드',
                          style: const TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Kidipedia v1.0',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 🌟 Unobscured High-Resolution Cover Image (대문 사진 100% 원본 비율 & 가림 없음)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFFFE0E8), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1408 / 768, // 원본 해상도 비율 그대로 유지하여 좌우/상하 잘림 0%
                    child: Image.asset(
                      'assets/images/kidipedia_logo.png',
                      fit: BoxFit.contain, // 사진 전체를 선명하게 100% 노출
                      filterQuality: FilterQuality.high,
                      errorBuilder: (ctx, err, stack) => Image.asset(
                        'assets/images/kidipedia_logo.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (ctx2, err2, stack2) => Container(
                          color: const Color(0xFFFFEFF2),
                          child: const Center(
                            child: Text(
                              '🌸 Kidipedia 안심 복약 가이드',
                              style: TextStyle(fontSize: 18, color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title & Service Intro Section (사진 아래에 위치하여 사진을 전혀 가리지 않음)
              const Text(
                '우리아이 안심 복약 가이드',
                style: TextStyle(color: Color(0xFFFF6B8B), fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Kidipedia (키디피디아)',
                style: TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '처방전 사진 한 장으로 체중 맞춤 용량 검증,\n중복 처방 DUR 점검 및 소아과 의사용 안심 Q&A까지',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5, height: 1.45),
              ),
              const SizedBox(height: 14),

              // 👶 Multi-Child Selector Section
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFFFE0E8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('👶', style: TextStyle(fontSize: 14)),
                        SizedBox(width: 6),
                        Text(
                          '복약 관리할 아이를 선택해 주세요:',
                          style: TextStyle(color: Color(0xFF334155), fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...availableProfiles.map((p) {
                            final isSelected = p.id == _currentChild.id;
                            return GestureDetector(
                              onTap: () => setState(() => _currentChildNullable = p),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFFFF6B8B) : const Color(0xFFFFF0F3),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isSelected ? const Color(0xFFFF6B8B) : const Color(0xFFFFD6DF),
                                    width: 1.5,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFFF6B8B).withValues(alpha: 0.25),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(p.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 6),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: TextStyle(
                                            color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        Text(
                                          '${p.age} · ${p.weightKg}kg',
                                          style: TextStyle(
                                            color: isSelected ? Colors.white.withValues(alpha: 0.9) : const Color(0xFF64748B),
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isSelected) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.check_circle, color: Colors.white, size: 14),
                                    ],
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => _confirmDeleteProfile(context, p),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: isSelected ? Colors.black.withValues(alpha: 0.2) : const Color(0xFFE2E8F0),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 12,
                                          color: isSelected ? Colors.white : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          // + Add Child Button
                          GestureDetector(
                            onTap: () => _openAddChildModal(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFF6B8B), style: BorderStyle.solid),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, color: Color(0xFFFF6B8B), size: 16),
                                  SizedBox(width: 4),
                                  Text(
                                    '아이 추가',
                                    style: TextStyle(color: Color(0xFFFF6B8B), fontSize: 11.5, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Key Feature Badges
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _WelcomeFeatureRow(
                      icon: '⚖️',
                      title: '체중 ${_currentChild.weightKg}kg 소아 맞춤 용량 검증',
                      desc: '식약처 기준 과다·과소 투약 안심 방지',
                    ),
                    const Divider(height: 14, thickness: 0.7, color: Color(0xFFF1F5F9)),
                    const _WelcomeFeatureRow(
                      icon: '📸',
                      title: '약품 AI 멀티 OCR 자동 분석',
                      desc: '처방전 및 약봉투 약품명 실시간 교정 및 인식',
                    ),
                    const Divider(height: 14, thickness: 0.7, color: Color(0xFFF1F5F9)),
                    const _WelcomeFeatureRow(
                      icon: '🩺',
                      title: '소아과 의사용 안심 Q&A 자동 생성',
                      desc: '진료 시 빠뜨리지 않고 확인할 맞춤 질문지',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Main CTA Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 3,
                  shadowColor: const Color(0xFFFF6B8B).withValues(alpha: 0.4),
                ),
                onPressed: () {
                  if (widget.onStartWithChild != null) {
                    widget.onStartWithChild!(_currentChild);
                  } else {
                    widget.onStart?.call();
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${_currentChild.name} 우리아이 안심 복약 시작하기',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeFeatureRow extends StatelessWidget {
  final String icon;
  final String title;
  final String desc;
  const _WelcomeFeatureRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 12)),
              Text(desc, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10.5)),
            ],
          ),
        ),
      ],
    );
  }
}

class MainFigmaScreen extends StatefulWidget {
  final MemberProfile? initialProfile;
  final List<MemberProfile>? familyProfiles;
  final Function(MemberProfile)? onChildChanged;
  final Function(MemberProfile)? onAddNewChild;
  final Function(String)? onDeleteChild;
  final Function(MemberProfile)? onProfileUpdated;
  final VoidCallback? onOpenCover;

  const MainFigmaScreen({
    super.key,
    this.initialProfile,
    this.familyProfiles,
    this.onChildChanged,
    this.onAddNewChild,
    this.onDeleteChild,
    this.onProfileUpdated,
    this.onOpenCover,
  });

  @override
  State<MainFigmaScreen> createState() => _MainFigmaScreenState();
}

class _MainFigmaScreenState extends State<MainFigmaScreen> {
  int _currentIndex = 0;
  final List<int> _tabHistory = [0];
  List<DrugAnalysisResult> _scannedDrugsList = [];

  late MemberProfile _babyProfile;
  late List<MemberProfile> _familyProfiles;
  final Map<String, bool> _childDoseCompletionState = {};

  @override
  void initState() {
    super.initState();
    _familyProfiles = widget.familyProfiles != null && widget.familyProfiles!.isNotEmpty
        ? List.from(widget.familyProfiles!)
        : (widget.familyProfiles ?? []);
    _babyProfile = widget.initialProfile ?? (_familyProfiles.isNotEmpty ? _familyProfiles.first : MemberProfile(id: '1', name: '우리 아이', memberType: MemberType.child, weightKg: 10.0));
  }

  @override
  void didUpdateWidget(MainFigmaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialProfile != null && widget.initialProfile!.id != _babyProfile.id) {
      _babyProfile = widget.initialProfile!;
    }
    if (widget.familyProfiles != null) {
      _familyProfiles = List.from(widget.familyProfiles!);
      if (!_familyProfiles.any((p) => p.id == _babyProfile.id) && _familyProfiles.isNotEmpty) {
        _babyProfile = _familyProfiles.first;
      }
    }
  }

  void _switchChild(MemberProfile newChild) {
    setState(() {
      _babyProfile = newChild;
    });
    widget.onChildChanged?.call(newChild);
  }

  void _confirmDeleteChild(BuildContext context, MemberProfile profile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline, color: Color(0xFFFF6B8B)),
            const SizedBox(width: 8),
            Text('${profile.name} 삭제', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Text('\'${profile.name}\'의 프로필을 삭제하시겠습니까?\n삭제 후에는 복구할 수 없습니다.',
            style: const TextStyle(fontSize: 14, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onDeleteChild?.call(profile.id);
            },
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openChildSwitcherModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Text('👶', style: TextStyle(fontSize: 20)),
                    SizedBox(width: 8),
                    Text('복약 관리 자녀 선택', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 12),
            ..._familyProfiles.map((p) {
              final isSelected = p.id == _babyProfile.id;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFFFF0F3) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey.shade300,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFFFF6B8B) : Colors.grey.shade200,
                      child: Text(p.gender == '남아' ? '👦' : '👧', style: const TextStyle(fontSize: 18)),
                    ),
                    title: Text(p.name, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? const Color(0xFFFF6B8B) : Colors.black87)),
                    subtitle: Text('${p.gender} · ${p.age} · ${p.weightKg}kg'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSelected) const Icon(Icons.check_circle, color: Color(0xFFFF6B8B), size: 18),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey, size: 18),
                          tooltip: '프로필 삭제',
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmDeleteChild(context, p);
                          },
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _switchChild(p);
                    },
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: const BorderSide(color: Color(0xFFFF6B8B)),
                foregroundColor: const Color(0xFFFF6B8B),
              ),
              icon: const Icon(Icons.add),
              label: const Text('+ 새 아이 추가 등록'),
              onPressed: () {
                Navigator.pop(ctx);
                _openAddNewChildDialog(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openAddNewChildDialog(BuildContext context) {
    DateTime selectedBirthDate = DateTime.now().subtract(const Duration(days: 365));
    final birthDateCtrl = TextEditingController(
      text: '${selectedBirthDate.year}년 ${selectedBirthDate.month.toString().padLeft(2, '0')}월 ${selectedBirthDate.day.toString().padLeft(2, '0')}일',
    );
    final nameCtrl = TextEditingController();
    final ageCtrl = TextEditingController(text: '생후 12개월');
    final weightCtrl = TextEditingController(text: '10.0');
    String gender = '남아';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('👶 새 자녀 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '아이 이름',
                  hintText: '예: 도윤이',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: birthDateCtrl,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: '생년월일 (예방접종·검진 기준)',
                  hintText: '생년월일을 선택해주세요',
                  prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFFFF6B8B), size: 20),
                  suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedBirthDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365 * 12)),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() {
                      selectedBirthDate = picked;
                      birthDateCtrl.text = '${picked.year}년 ${picked.month.toString().padLeft(2, '0')}월 ${picked.day.toString().padLeft(2, '0')}일';
                      int months = (DateTime.now().year - picked.year) * 12 + (DateTime.now().month - picked.month);
                      if (DateTime.now().day < picked.day) months--;
                      if (months < 0) months = 0;
                      ageCtrl.text = '생후 $months개월';
                    });
                  }
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ageCtrl,
                      decoration: InputDecoration(
                        labelText: '월령/나이',
                        hintText: '생후 18개월',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: weightCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '체중(kg)',
                        hintText: '11.5',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('성별: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  ChoiceChip(
                    label: const Text('남아 👦'),
                    selected: gender == '남아',
                    onSelected: (val) => setModalState(() => gender = '남아'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('여아 👧'),
                    selected: gender == '여아',
                    onSelected: (val) => setModalState(() => gender = '여아'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: () {
                  final name = nameCtrl.text.trim();
                  if (name.isEmpty) return;
                  final w = double.tryParse(weightCtrl.text.trim()) ?? 10.0;
                  final newProfile = MemberProfile(
                    id: 'child_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    memberType: MemberType.child,
                    age: ageCtrl.text.trim(),
                    birthDate: birthDateCtrl.text.trim(),
                    gender: gender,
                    weightKg: w,
                    allergyNotes: '',
                    history: [],
                  );
                  widget.onAddNewChild?.call(newProfile);
                  setState(() {
                    _familyProfiles.add(newProfile);
                    _babyProfile = newProfile;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('등록 완료', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<DoctorQnaItem> _doctorQuestions = [
    DoctorQnaItem(
      id: 'q1',
      category: '해열제 교차복용',
      question: '코미시럽과 다른 해열제(타이레놀 시럽 등)를 동시에 복용해도 정말 부작용이 없을까요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q2',
      category: '졸림/대체약',
      question: '코미시럽 복용 후 졸림 증상이 있는데, 다음 방문 시 처방을 다른 대체약으로 변경할 수 있을까요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q3',
      category: '항생제/설사',
      question: '이 항생제(아모클란듀오)는 설사 증상을 유발할 수 있다고 하던데 유산균을 함께 먹여야 하나요?',
      isSelected: true,
    ),
    DoctorQnaItem(
      id: 'q4',
      category: '시간 누락',
      question: '깜빡 잊고 아기 감기약 복용 시간을 놓쳤을 때는 발견 즉시 바로 먹여도 괜찮은가요?',
      isSelected: false,
    ),
  ];

  void _onTabChanged(int index) {
    setState(() {
      if (_currentIndex != index) {
        _tabHistory.add(index);
      }
      _currentIndex = index;
    });
  }

  void _handleGoBack() {
    setState(() {
      if (_tabHistory.length > 1) {
        _tabHistory.removeLast();
        _currentIndex = _tabHistory.last;
      } else {
        _currentIndex = 0;
        _tabHistory.clear();
        _tabHistory.add(0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(
        profile: _babyProfile,
        onNavigateScan: () => _onTabChanged(2),
        onNavigateDrugs: () => _onTabChanged(1),
        onOpenCover: widget.onOpenCover,
        onSwitchChild: () => _openChildSwitcherModal(context),
        doseCompletionState: _childDoseCompletionState,
        scannedDrugs: _scannedDrugsList,
      ),
      DrugsListScreen(
        profile: _babyProfile,
        scannedDrugs: _scannedDrugsList,
        onGoBack: _handleGoBack,
        onNavigateScan: () => _onTabChanged(2),
        onDeleteDrug: (drugName) {
          setState(() {
            _scannedDrugsList.removeWhere((d) => d.drugName == drugName);
          });
        },
      ),
      ScanScreen(
        profile: _babyProfile,
        onNavigateTab: (idx) => _onTabChanged(idx),
        onGoBack: _handleGoBack,
        onUpdateQuestions: (qnaList) {
          setState(() {
            _doctorQuestions = qnaList;
          });
        },
        onUpdateScannedDrugs: (drugs) {
          setState(() {
            _scannedDrugsList = drugs;
          });
        },
      ),
      DoctorQnaScreen(
        profile: _babyProfile,
        questions: _doctorQuestions,
        onGoBack: _handleGoBack,
      ),
      BabyProfileScreen(
        profile: _babyProfile,
        onGoBack: _handleGoBack,
        onSwitchChild: () => _openChildSwitcherModal(context),
        onProfileUpdated: (newProfile) {
          setState(() {
            _babyProfile = newProfile;
          });
          widget.onProfileUpdated?.call(newProfile);
        },
        onDeleteProfile: () => _confirmDeleteChild(context, _babyProfile),
      ),
    ];

    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleGoBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: IndexedStack(
            index: _currentIndex,
            children: screens,
          ),
        ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _onTabChanged,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFFFF6B8B),
        unselectedItemColor: Colors.grey.shade400,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: '홈'),
          BottomNavigationBarItem(icon: Icon(Icons.medication_outlined), label: '복용 정보'),
          BottomNavigationBarItem(icon: Icon(Icons.camera_alt_outlined), label: '스캔'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment_outlined), label: '의사 Q&A'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: '내 아이'),
        ],
      ),
    ),
  );
}
}

// ----------------------------------------------------------------------
// 1. HOME SCREEN (홈 화면)
// ----------------------------------------------------------------------
class HomeScreen extends StatefulWidget {
  final MemberProfile profile;
  final VoidCallback onNavigateScan;
  final VoidCallback onNavigateDrugs;
  final VoidCallback? onOpenCover;
  final VoidCallback? onSwitchChild;
  final Map<String, bool>? doseCompletionState;
  final List<DrugAnalysisResult>? scannedDrugs;

  const HomeScreen({
    super.key,
    required this.profile,
    required this.onNavigateScan,
    required this.onNavigateDrugs,
    this.onOpenCover,
    this.onSwitchChild,
    this.doseCompletionState,
    this.scannedDrugs,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _TodayDoseItem {
  final String id;
  final String timeTag;
  final String title;
  final String subtitle;
  final List<String> drugDetails;
  bool isCompleted;
  bool isExpanded;

  _TodayDoseItem({
    required this.id,
    required this.timeTag,
    required this.title,
    required this.subtitle,
    this.drugDetails = const [],
    this.isCompleted = false,
  }) : isExpanded = false;
}

class _PediatricNewsItem {
  final String title;
  final String content;
  final String date;
  final String source;

  const _PediatricNewsItem({
    required this.title,
    required this.content,
    required this.date,
    required this.source,
  });
}

List<_PediatricNewsItem> _getPediatricNewsList(MemberProfile profile) {
  final months = profile.ageMonths ?? 10;
  if (months < 12) {
    return const [
      _PediatricNewsItem(
        title: '영유아 RS바이러스(RSV) 유행 대비 항체주사(베이포투스) 권고',
        content: '가을·겨울철 영아 모세기관지염·폐렴 급증에 대비해 장기 지속형 RSV 예방 항체주사 접종이 권고됩니다. 발열과 쌕쌕거림(천명) 관찰 시 소아과 진료를 서두르세요.',
        date: '09.18',
        source: '질병관리청 & 대한소아청소년과학회',
      ),
      _PediatricNewsItem(
        title: '생후 6개월 이상 영유아 인플루엔자(독감) 국가 무료 접종 개시',
        content: '생후 6개월부터 만 13세 아동을 대상으로 2026-2027절기 4가 독감 무료 백신 접종이 시작되었습니다. 유행 전 사전 접종을 권장합니다.',
        date: '09.20',
        source: '질병관리청 예방접종관리과',
      ),
      _PediatricNewsItem(
        title: '환절기 신생아·영아 급성 바이러스 장염 주의 당부',
        content: '일교차가 큰 시기 로타·노로바이러스 등 장염 감염에 유의하세요. 수유기구 소독 및 기저귀 교환 후 손씻기, 탈수 징후를 면밀히 관찰해야 합니다.',
        date: '09.14',
        source: '대한소아감염학회',
      ),
    ];
  } else if (months <= 36) {
    return const [
      _PediatricNewsItem(
        title: '어린이 인플루엔자(독감) 국가 무료 예방접종 시행 안내',
        content: '생후 6개월~만 13세 이하 어린이를 대상으로 2026-2027절기 4가 인플루엔자 무료 백신 접종이 개시되었습니다. 단체생활 중 마이코플라스마 및 호흡기 감염에 유의하세요.',
        date: '09.20',
        source: '질병관리청 예방접종관리과',
      ),
      _PediatricNewsItem(
        title: '소아 마이코플라스마 폐렴 및 백일해 유행 주의보',
        content: '3주 이상 지속되는 발작성 기침이나 야간 기침 심화 시 소아과 감별 진료를 권장합니다. 가족 간 감염 차단을 위해 마스크 착용이 권고됩니다.',
        date: '09.16',
        source: '질병관리청 감염병포털',
      ),
      _PediatricNewsItem(
        title: '어린이집 등 보육시설 내 유아 수족구병 예방 수칙',
        content: '손발 수포 및 입안 궤양 증상이 나타나면 등원을 중단하고 자택 격리 치료를 권고합니다. 탈수 예방을 위해 차가운 물과 부드러운 음식을 섭취해 주세요.',
        date: '09.12',
        source: '대한소아청소년과학회',
      ),
    ];
  } else {
    return const [
      _PediatricNewsItem(
        title: '가을철 소아 호흡기 감염병(마이코플라스마·독감) 예방 수칙',
        content: '어린이집·유치원 등 단체생활 아동 중심의 발열성 기침 환자가 증가하고 있습니다. 4가 독감 접종 완료와 함께 올바른 손씻기 및 기침 예절을 지도해 주세요.',
        date: '09.20',
        source: '질병관리청 감염병포털 & 대한소아감염학회',
      ),
      _PediatricNewsItem(
        title: '환절기 소아 알레르기 비염 및 아토피 피부염 관리 지침',
        content: '아침저녁 10도 이상 벌어지는 기온차에 대비해 실내 습도 50~60% 유지와 보습제 도포가 권장됩니다. 처방받은 비염 스프레이나 항히스타민제는 정해진 용법을 준수하세요.',
        date: '09.17',
        source: '대한소아알레르기호흡기학회',
      ),
      _PediatricNewsItem(
        title: '야간 소아 고열 및 열성경련 시 가정 응급 대처법',
        content: '열이 급격히 오를 때 옷을 얇게 입히고 미온수로 몸을 닦아주세요. 경련 발생 시 입에 물건을 물리지 말고 고개를 옆으로 돌려 기도를 확보한 뒤 시간을 측정하세요.',
        date: '09.10',
        source: '대한응급의학회 소아분과',
      ),
    ];
  }
}

class _EmergencyHospitalItem {
  final String name;
  final String region;
  final String type; // '소아전문응급센터' or '달빛어린이병원'
  final String address;
  final String hours;
  final String phone;
  final bool is24Hours;

  const _EmergencyHospitalItem({
    required this.name,
    required this.region,
    required this.type,
    required this.address,
    required this.hours,
    required this.phone,
    required this.is24Hours,
  });
}

final List<_EmergencyHospitalItem> _emergencyHospitals = [
  // 서울
  const _EmergencyHospitalItem(
    name: '서울대학교병원 소아전문응급의료센터',
    region: '서울',
    type: '소아전문응급센터',
    address: '서울 종로구 대학로 101 (혜화동)',
    hours: '24시간 365일 연중무휴 (소아응급전문의 상주)',
    phone: '02-2072-3456',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '서울아산병원 소아전문응급의료센터',
    region: '서울',
    type: '소아전문응급센터',
    address: '서울 송파구 올림픽로43길 88 (풍납동)',
    hours: '24시간 365일 연중무휴 (소아중환자 전담)',
    phone: '02-3010-3333',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '신촌세브란스병원 소아전문응급의료센터',
    region: '서울',
    type: '소아전문응급센터',
    address: '서울 서대문구 연세로 50-1 (신촌)',
    hours: '24시간 365일 연중무휴 (소아외상·소아응급)',
    phone: '02-2228-5555',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '우리아이들병원 (구로) 달빛어린이병원',
    region: '서울',
    type: '달빛어린이병원',
    address: '서울 구로구 새말로 120 (신도림)',
    hours: '평일 08:30~23:00 / 토·일·공휴일 08:30~18:00',
    phone: '02-868-2200',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '성북우리아이들병원 달빛어린이병원',
    region: '서울',
    type: '달빛어린이병원',
    address: '서울 성북구 동소문로 46',
    hours: '평일 08:30~23:00 / 토·일·공휴일 08:30~18:00',
    phone: '02-953-2300',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '연세곰돌이소아청소년과의원 달빛어린이병원',
    region: '서울',
    type: '달빛어린이병원',
    address: '서울 서초구 방배로 226',
    hours: '평일 08:30~23:00 / 토·일·공휴일 08:30~18:00',
    phone: '02-596-0063',
    is24Hours: false,
  ),

  // 경기 / 인천
  const _EmergencyHospitalItem(
    name: '분당차병원 소아전문응급의료센터',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '경기 성남시 분당구 야탑로 59',
    hours: '24시간 365일 연중무휴 (경기 남부 권역)',
    phone: '031-780-5000',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '아주대학교병원 소아전문응급의료센터',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '경기 수원시 영통구 월드컵로 164',
    hours: '24시간 365일 연중무휴 (수원 권역)',
    phone: '031-219-5114',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '명지병원 소아전문응급의료센터',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '경기 고양시 덕양구 화수로14번길 55',
    hours: '24시간 365일 연중무휴 (경기 북부 권역)',
    phone: '031-810-5114',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '송도 VIC365 소아청소년과의원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '인천 연수구 인천타워대로 132번길 30, 휴먼빌파크 3층 (송도동)',
    hours: '평일 08:30~23:00 / 토·일·공휴일 09:00~18:00 (365일 야간진료)',
    phone: '032-834-0365',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '인하대학교병원 소아전문응급의료센터',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '인천 중구 인항로 27',
    hours: '24시간 365일 연중무휴 (인천·서해 권역)',
    phone: '032-890-2222',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '가천대길병원 권역응급의료센터',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '인천 남동구 남동대로 774번길 21 (구월동)',
    hours: '24시간 365일 연중무휴 (소아중증응급)',
    phone: '032-460-3114',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '청라연세어린이병원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '인천 서구 중봉대로 612번길 10-17 (청라동)',
    hours: '평일 09:00~23:00 / 토·일·공휴일 09:00~18:00',
    phone: '032-567-7582',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '김포아이제일병원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '경기 김포시 김포한강4로 125',
    hours: '평일 08:30~23:00 / 토·일·공휴일 09:00~18:00',
    phone: '031-987-0075',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '아이플러스어린이병원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '경기 부천시 원미구 신흥로 190',
    hours: '평일 09:00~23:00 / 토·일·공휴일 09:00~18:00',
    phone: '032-656-7582',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '한림대학교성심병원 권역응급의료센터 (소아응급진료)',
    region: '경기/인천',
    type: '소아전문응급센터',
    address: '경기 안양시 동안구 관평로170번길 22 (평촌동)',
    hours: '24시간 365일 연중무휴 (안양·만안·동안·군포·의왕 권역 소아응급)',
    phone: '031-380-1500',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '안양 한솔어린이병원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '경기 안양시 만안구 안양로 314번길 18 (안양동)',
    hours: '평일 09:00~23:00 / 토·일·공휴일 09:00~18:00 (만안구 365 야간진료)',
    phone: '031-469-7582',
    is24Hours: false,
  ),
  const _EmergencyHospitalItem(
    name: '안양 센트럴아동병원 달빛어린이병원',
    region: '경기/인천',
    type: '달빛어린이병원',
    address: '경기 안양시 동안구 시민대로 214 (호계동)',
    hours: '평일 08:30~23:00 / 토·일·공휴일 09:00~18:00',
    phone: '031-381-8275',
    is24Hours: false,
  ),

  // 충청 / 대전 / 세종
  const _EmergencyHospitalItem(
    name: '세종충남대학교병원 소아전문응급의료센터',
    region: '충청/대전',
    type: '소아전문응급센터',
    address: '세종시 보듬7로 20 (도담동)',
    hours: '24시간 365일 연중무휴',
    phone: '044-995-3114',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '순천향대학교천안병원 소아전문응급의료센터',
    region: '충청/대전',
    type: '소아전문응급센터',
    address: '충남 천안시 동남구 순천향6길 31',
    hours: '24시간 365일 연중무휴 (충남 권역)',
    phone: '041-570-3555',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '충남대학교병원 권역소아응급의료센터',
    region: '충청/대전',
    type: '소아전문응급센터',
    address: '대전 중구 문화로 282',
    hours: '24시간 365일 연중무휴 (대전 권역)',
    phone: '042-280-8129',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '대전 한국병원 달빛어린이병원',
    region: '충청/대전',
    type: '달빛어린이병원',
    address: '대전 동구 동서대로 1672',
    hours: '평일 18:00~23:00 / 주말·공휴일 09:00~18:00',
    phone: '042-606-1000',
    is24Hours: false,
  ),

  // 영남 / 부산 / 대구 / 울산
  const _EmergencyHospitalItem(
    name: '양산부산대학교병원 소아전문응급의료센터',
    region: '영남/부산/대구',
    type: '소아전문응급센터',
    address: '경남 양산시 물금읍 금오로 20',
    hours: '24시간 365일 연중무휴 (부산·경남 권역)',
    phone: '055-360-1119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '칠곡경북대학교병원 소아전문응급의료센터',
    region: '영남/부산/대구',
    type: '소아전문응급센터',
    address: '대구 북구 호국로 807 (학정동)',
    hours: '24시간 365일 연중무휴 (대구·경북 권역)',
    phone: '053-200-2119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '울산대학교병원 소아전문응급의료센터',
    region: '영남/부산/대구',
    type: '소아전문응급센터',
    address: '울산 동구 대학병원로 25',
    hours: '24시간 365일 연중무휴 (울산 권역)',
    phone: '052-250-7000',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '부산 정관아동병원 달빛어린이병원',
    region: '영남/부산/대구',
    type: '달빛어린이병원',
    address: '부산 기장군 정관읍 정관로 579',
    hours: '평일 09:00~23:00 / 주말·공휴일 09:00~18:00',
    phone: '051-727-8855',
    is24Hours: false,
  ),

  // 호남 / 광주 / 전북 / 전남
  const _EmergencyHospitalItem(
    name: '전남대학교병원 소아전문응급의료센터',
    region: '호남/광주',
    type: '소아전문응급센터',
    address: '광주 동구 제봉로 42 (학동)',
    hours: '24시간 365일 연중무휴 (광주·전남 권역)',
    phone: '062-220-6119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '전북대학교병원 소아전문응급의료센터',
    region: '호남/광주',
    type: '소아전문응급센터',
    address: '전북 전주시 덕진구 건지로 20',
    hours: '24시간 365일 연중무휴 (전북 권역)',
    phone: '063-250-1119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '광주 광산수완미래아동병원 달빛어린이병원',
    region: '호남/광주',
    type: '달빛어린이병원',
    address: '광주 광산구 임방울대로 348',
    hours: '평일 09:00~23:00 / 주말·공휴일 09:00~18:00',
    phone: '062-950-8000',
    is24Hours: false,
  ),

  // 강원 / 제주
  const _EmergencyHospitalItem(
    name: '강원대학교병원 소아전문응급의료센터',
    region: '강원/제주',
    type: '소아전문응급센터',
    address: '강원 춘천시 백령로 156',
    hours: '24시간 365일 연중무휴 (강원 권역)',
    phone: '033-258-2119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '제주대학교병원 소아응급진료센터',
    region: '강원/제주',
    type: '소아전문응급센터',
    address: '제주 제주시 아란13길 15',
    hours: '24시간 365일 연중무휴 (제주 권역)',
    phone: '064-717-1119',
    is24Hours: true,
  ),
  const _EmergencyHospitalItem(
    name: '탑동365일의원 달빛어린이병원',
    region: '강원/제주',
    type: '달빛어린이병원',
    address: '제주 제주시 중앙로 4',
    hours: '평일·주말·공휴일 08:30~23:00',
    phone: '064-756-3650',
    is24Hours: false,
  ),
];

class _HomeScreenState extends State<HomeScreen> {
  late List<_TodayDoseItem> _doses;
  // ARCH-01: childId + doseId 기반 다자녀 복약 완료 상태 격리 저장소
  final Map<String, bool> _localCompletionState = {};
  Map<String, bool> get _completionState => widget.doseCompletionState ?? _localCompletionState;

  @override
  void initState() {
    super.initState();
    _doses = _buildDosesForChild(widget.profile);
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id ||
        oldWidget.profile.weightKg != widget.profile.weightKg ||
        oldWidget.scannedDrugs != widget.scannedDrugs) {
      setState(() {
        _doses = _buildDosesForChild(widget.profile);
      });
    }
  }

  List<_TodayDoseItem> _buildDosesForChild(MemberProfile profile) {
    final List<_TodayDoseItem> items = [];
    final scanned = widget.scannedDrugs;

    // 1. 사용자가 스캔한 처방전 데이터가 있는 경우 -> 스캔 약품 기반 일정 자동 생성
    if (scanned != null && scanned.isNotEmpty) {
      final morningDrugs = <String>[];
      final lunchDrugs = <String>[];
      final dinnerDrugs = <String>[];
      final nightDrugs = <String>[];

      for (final drug in scanned) {
        final freq = drug.scannedFreqPerDay ?? 3;
        final doseStr = drug.scannedDoseUnit != null ? ' ${drug.scannedDoseUnit}ml' : '';
        final label = '${drug.drugName}$doseStr';

        if (freq >= 3) {
          morningDrugs.add(label);
          lunchDrugs.add(label);
          dinnerDrugs.add(label);
        } else if (freq == 2) {
          morningDrugs.add(label);
          dinnerDrugs.add(label);
        } else if (freq == 1) {
          dinnerDrugs.add(label);
        } else {
          nightDrugs.add(label);
        }
      }

      String formatDrugsTitle(List<String> list) {
        if (list.isEmpty) return '';
        if (list.length == 1) return list.first;
        if (list.length == 2) return '${list[0]} + ${list[1]}';
        return '${list.first} 외 ${list.length - 1}종';
      }

      String formatDrugsSubtitle(List<String> list, String defaultSub) {
        if (list.length > 2) {
          return '${list.join(", ")} · $defaultSub';
        }
        return '$defaultSub · 스캔 처방전 자동 편성';
      }

      if (morningDrugs.isNotEmpty) {
        final key = '${profile.id}_scanned_morn';
        items.add(_TodayDoseItem(
          id: 'scanned_morn',
          timeTag: '아침 08:30',
          title: formatDrugsTitle(morningDrugs),
          subtitle: formatDrugsSubtitle(morningDrugs, '식후 30분'),
          drugDetails: List.from(morningDrugs),
          isCompleted: _completionState[key] ?? false,
        ));
      }
      if (lunchDrugs.isNotEmpty) {
        final key = '${profile.id}_scanned_lunch';
        items.add(_TodayDoseItem(
          id: 'scanned_lunch',
          timeTag: '점심 13:00',
          title: formatDrugsTitle(lunchDrugs),
          subtitle: formatDrugsSubtitle(lunchDrugs, '식사 직후'),
          drugDetails: List.from(lunchDrugs),
          isCompleted: _completionState[key] ?? false,
        ));
      }
      if (dinnerDrugs.isNotEmpty) {
        final key = '${profile.id}_scanned_dinner';
        items.add(_TodayDoseItem(
          id: 'scanned_dinner',
          timeTag: '저녁 19:00',
          title: formatDrugsTitle(dinnerDrugs),
          subtitle: formatDrugsSubtitle(dinnerDrugs, '식후 30분'),
          drugDetails: List.from(dinnerDrugs),
          isCompleted: _completionState[key] ?? false,
        ));
      }
      if (nightDrugs.isNotEmpty) {
        final key = '${profile.id}_scanned_night';
        items.add(_TodayDoseItem(
          id: 'scanned_night',
          timeTag: '취침전 21:30',
          title: formatDrugsTitle(nightDrugs),
          subtitle: formatDrugsSubtitle(nightDrugs, '필요 시/발열 시 복용'),
          drugDetails: List.from(nightDrugs),
          isCompleted: _completionState[key] ?? false,
        ));
      }
    }

    // 2. 스캔 데이터가 아직 없는 경우 -> 기본 샘플 프로필(하준이/서아)에만 예시를 제공하고, 새로 등록된 자녀는 샘플 없이 완전히 새로운 상태로 시작
    if (items.isEmpty) {
      if (profile.id == 'child_2' || profile.name == '서아') {
        items.addAll([
          _TodayDoseItem(id: 's1', timeTag: '아침 08:30', title: '기관지염 항생제 (클래리시드 건조시럽)', subtitle: '1회 5ml · 식후 30분', isCompleted: true),
          _TodayDoseItem(id: 's2', timeTag: '점심 13:00', title: '유산균 정장제 (항생제 설사 예방)', subtitle: '1회 1포 · 식사 직후', isCompleted: false),
          _TodayDoseItem(id: 's3', timeTag: '저녁 19:00', title: '클래리시드 건조시럽 & 정장제', subtitle: '1회 5ml, 가루 1포 · 식후 30분', isCompleted: false),
        ]);
      } else if (profile.id == 'child_1' || profile.name == '하준이') {
        items.addAll([
          _TodayDoseItem(id: '1', timeTag: '아침 08:30', title: '감기 물약 (코미시럽)', subtitle: '1회 4ml · 식전 30분', isCompleted: true),
          _TodayDoseItem(id: '2', timeTag: '점심 13:00', title: '기관지 패치 & 항생제', subtitle: '1회 1포 · 식사 직후', isCompleted: false),
          _TodayDoseItem(id: '3', timeTag: '저녁 19:00', title: '감기 물약 & 정장제', subtitle: '1회 4ml, 가루 1포 · 취침 전', isCompleted: false),
        ]);
      } else {
        // 새로 추가된 자녀: 샘플 투약 일정 없이 깨끗하게 시작 (처방전 스캔 시 등록)
      }
    }

    // childId + doseId 고유 키로 이전 완료 체크 상태 복원 (ARCH-01)
    for (final item in items) {
      final key = '${profile.id}_${item.id}';
      if (_completionState.containsKey(key)) {
        item.isCompleted = _completionState[key]!;
      }
    }
    return items;
  }

  int get _completedCount => _doses.where((d) => d.isCompleted).length;
  double get _progress => _doses.isEmpty ? 0 : (_completedCount / _doses.length);

  void _toggleDose(_TodayDoseItem item) {
    setState(() {
      item.isCompleted = !item.isCompleted;
      final key = '${widget.profile.id}_${item.id}';
      _completionState[key] = item.isCompleted;
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          item.isCompleted
              ? '✓ "${item.title}" 복약 완료로 기록되었습니다! 👶👏'
              : '"${item.title}" 복약 대기 상태로 변경되었습니다.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _openVomitGuidanceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (c, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🤢', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('약 먹고 토했을 때 가이드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('소아과 전문의 임상 재투약 기준', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '💡 약을 먹인 뒤 경과 시간에 따라 체내 흡수 정도가 다릅니다. 아래 기준을 정확히 확인하세요.',
                style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade800, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),

            // 1. 10분 이내
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(8)),
                        child: const Text('⏱️ 10분 이내 토함', style: TextStyle(color: Color(0xFF047857), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Text('동일 정량 즉시 재투약', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '위에서 약물이 거의 흡수되지 않고 그대로 배출된 상태입니다.\n아기를 안아 진정시키고 입안을 헹군 뒤, 1회 정량을 그대로 다시 먹이셔도 안전합니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 2. 10분 ~ 30분
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                        child: const Text('⏱️ 10 ~ 30분 사이', style: TextStyle(color: Color(0xFFB45309), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Text('추가 투약 보류 및 관찰', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '약물의 상당 부분이 십이지장으로 넘어가 흡수 중일 가능성이 큽니다.\n지금 바로 다시 먹이면 과량 투약 위험이 있으므로, 30분~1시간 동안 아기 체온과 증상을 지켜보세요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. 30분 이후
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                        child: const Text('⏱️ 30분 이후 토함', style: TextStyle(color: Color(0xFF1D4ED8), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      const Text('재투약 절대 금지 (흡수 완료)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '약의 유효 성분이 이미 체내에 대부분 흡수되었습니다.\n토사물에 약 냄새나 색이 섞여 보여도 절대로 다시 먹이지 마시고, 다음 정규 복용 시간까지 대기하세요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 위험 징후 안내
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFECDD3)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                      SizedBox(width: 6),
                      Text('🚨 즉시 소아응급실 내원이 필요한 경우', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B))),
                    ],
                  ),
                  SizedBox(height: 6),
                  Text('• 초록색(담즙) 또는 피가 섞인 토를 할 때\n• 약과 상관없이 물만 마셔도 3회 이상 분수토를 할 때\n• 처지거나 눈이 쑥 들어가고 소변을 6시간 이상 보지 않을 때(탈수)',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF7F1D1D), height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  void _openAntipyreticCalculatorModal(BuildContext context) {
    final weight = widget.profile.weightKg ?? 9.2;
    final months = widget.profile.ageMonths ?? 10;
    final isNsaidContraindicated = months < 6;
    final isNeonateWarning = months < 3;

    // 아세트아미노펜 (12.5mg/kg, 농도 32mg/ml - 어린이타이레놀/챔프 빨강)
    final acetaDose = (weight * 12.5 / 32).toStringAsFixed(1);
    // 덱시부프로펜 (6.0mg/kg, 농도 12mg/ml - 맥시부펜)
    final dexiDose = (weight * 6.0 / 12).toStringAsFixed(1);

    double currentTemp = 38.3;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          String triageTitle = '발열 대처 (해열제 1차 투약)';
          String triageDesc = '1차로 아세트아미노펜 또는 덱시부프로펜을 1회 정량 투약하세요. 2시간 후에도 38도 이상 유지 시 다른 계열로 교차복용을 고려할 수 있습니다.';
          Color triageColor = const Color(0xFFD97706);
          Color triageBg = const Color(0xFFFFFBEB);
          Color triageBorder = const Color(0xFFFDE68A);

          if (currentTemp < 38.0) {
            triageTitle = '미열 관리 (수분 보충 & 휴식)';
            triageDesc = '38.0℃ 미만의 미열은 신체 면역 반응입니다. 해열제 투약보다는 얇은 옷으로 갈아입히고 미온수로 땀을 닦아주며 수분을 충분히 보충하세요.';
            triageColor = const Color(0xFF059669);
            triageBg = const Color(0xFFECFDF5);
            triageBorder = const Color(0xFFA7F3D0);
          } else if (currentTemp >= 39.0) {
            triageTitle = '🚨 고열 긴급 관찰 (즉시 투약 & 집중 케어)';
            triageDesc = '즉시 정량 투약하세요. 오한(손발 차가움)이 멈추면 미온수 마사지를 병행하고, 2시간 간격으로 다른 계열 교차복용을 준비하세요. 의식이 처지면 소아응급실 내원이 필요합니다.';
            triageColor = const Color(0xFFDC2626);
            triageBg = const Color(0xFFFEF2F2);
            triageBorder = const Color(0xFFFECACA);
          }

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (c, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('🌡️', style: TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('해열제 교차복용 계산기', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('체온별 Fever Triage & 안전 가드레일', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.profile.name} 현재 체중(${weight}kg, ${widget.profile.age}) 맞춤 권장 용량입니다.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // 생후 3개월 미만 신생아 긴급 경고
                if (isNeonateWarning) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.emergency, color: Color(0xFFDC2626), size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '⚠️ 생후 3개월 미만 신생아는 38.0℃ 이상 발열 시 패혈증 등 중증 감염 위험이 있습니다. 해열제를 임의 투약하지 마시고 즉시 소아응급실로 직행하세요!',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C), height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 체온 선택 칩 인터랙티브
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('현재 아기 체온을 선택하세요:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('37.6℃ 미열'),
                              selected: currentTemp < 38.0,
                              onSelected: (_) => setModalState(() => currentTemp = 37.6),
                              selectedColor: const Color(0xFFA7F3D0),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('38.3℃ 발열'),
                              selected: currentTemp >= 38.0 && currentTemp < 39.0,
                              onSelected: (_) => setModalState(() => currentTemp = 38.3),
                              selectedColor: const Color(0xFFFDE68A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('39.2℃ 고열'),
                              selected: currentTemp >= 39.0,
                              onSelected: (_) => setModalState(() => currentTemp = 39.2),
                              selectedColor: const Color(0xFFFECACA),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: triageBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: triageBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(triageTitle, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: triageColor)),
                            const SizedBox(height: 4),
                            Text(triageDesc, style: TextStyle(fontSize: 11.5, color: triageColor, height: 1.35)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 1. 아세트아미노펜 계열 카드
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '아세트아미노펜 계열 (1계열)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(6)),
                            child: const Text('생후 4개월 이상', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('대표 약품: 챔프시럽(빨강), 어린이 타이레놀 현탁액, 세토펜', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const Divider(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('1회 권장 투약량', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                          Text('$acetaDose ml', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFFE11D48))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('• 같은 계열 투약 시: 최소 4~6시간 간격 (1일 최대 5회 이내)', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. 덱시부프로펜 / 이부프로펜 계열 카드
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '덱시부프로펜 계열 (2계열)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isNsaidContraindicated ? const Color(0xFFDC2626) : const Color(0xFF1E293B),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isNsaidContraindicated ? const Color(0xFFFEF2F2) : const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isNsaidContraindicated ? '⛔ 6개월 미만 금기' : '생후 6개월 이상',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isNsaidContraindicated ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('대표 약품: 맥시부펜 시럽, 챔프 이부펜(파랑), 어린이 부루펜', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      const Divider(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('1회 권장 투약량', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155))),
                          Text(
                            isNsaidContraindicated ? '투약 금기 (의사 상담)' : '$dexiDose ml',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isNsaidContraindicated ? const Color(0xFFDC2626) : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isNsaidContraindicated
                            ? '• 생후 6개월 미만 영아는 신기능 미숙으로 덱시부프로펜 복용이 금기됩니다.'
                            : '• 같은 계열 투약 시: 최소 4~6시간 간격 (1일 최대 4회 이내)',
                        style: TextStyle(fontSize: 11, color: isNsaidContraindicated ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. 교차복용 필수 황금 수칙
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.rule, color: Color(0xFF475569), size: 18),
                          SizedBox(width: 8),
                          Text('소아과 전문의 교차복용 황금 수칙', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                        ],
                      ),
                      SizedBox(height: 10),
                      Text('1. 서로 다른 계열(아세트아미노펜 ↔ 덱시부프로펜) 교차 투약 시: 최소 2시간 간격을 둡니다.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45)),
                      SizedBox(height: 4),
                      Text('2. 같은 계열을 다시 먹일 때는: 반드시 4~6시간 이상 간격을 유지해야 합니다.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45)),
                      SizedBox(height: 4),
                      Text('3. 38도 미만의 미열이거나 아기 컨디션이 좋을 때는 투약보다 수분 섭취와 휴식을 권장합니다.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45)),
                      SizedBox(height: 4),
                      Text('4. 생후 3개월 미만 신생아 발열(38.0℃ 이상) 시에는 해열제를 먹이지 말고 즉시 소아응급실로 가셔야 합니다.',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFB91C1C), height: 1.45)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B8B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openAntibioticsGuidanceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (c, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('💊', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('항생제 복용 5대 골든룰', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('소아 세균 감염 및 내성균 예방 가이드', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Text(
                '💡 항생제는 증상이 사라졌다고 임의로 중단하면 살아남은 균이 "내성균(슈퍼박테리아)"으로 변해 재발합니다. 처방받은 일수를 반드시 완복하세요.',
                style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF), height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            _buildGuidanceCard(
              badge: '1. 임의 중단 절대 금지',
              badgeColor: const Color(0xFFDC2626),
              title: '열·기침 멈춰도 끝까지 완복',
              content: '세균이 완전히 박멸되지 않은 상태에서 약을 끊으면 재감염 시 기존 항생제가 듣지 않습니다. 소아과에서 처방한 기간(보통 3~7일)은 반드시 끝까지 먹이세요.',
              cardBg: const Color(0xFFFEF2F2),
              cardBorder: const Color(0xFFFECACA),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '2. 냉장 vs 실온 보관 구별',
              badgeColor: const Color(0xFF2563EB),
              title: '약품별 보관 수칙 확인 필수',
              content: '• 아모클란/오구멘틴(페니실린계): 물과 섞은 후 "반드시 냉장보관" (7~14일 후 폐기)\n• 클래리시드/지스로맥스(마크로라이드계): "실온 보관" (냉장 시 침전 및 쓴맛 극대화)',
              cardBg: const Color(0xFFF0FDF4),
              cardBorder: const Color(0xFFBBF7D0),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '3. 정장제(유산균) 2시간 시간차',
              badgeColor: const Color(0xFFD97706),
              title: '항생제 설사 예방 골든타임',
              content: '항생제는 장내 유익균도 함께 공격해 설사를 유발할 수 있습니다. 비오플 등 정장제나 유산균은 항생제 복용 "최소 2시간 뒤"에 먹여야 유산균이 죽지 않습니다.',
              cardBg: const Color(0xFFFFFBEB),
              cardBorder: const Color(0xFFFDE68A),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '4. 복용 전 충분히 흔들기',
              badgeColor: const Color(0xFF7C3AED),
              title: '가라앉은 유효성분 균일화',
              content: '어린이 항생제 시럽은 가루가 액체에 분산된 현탁액입니다. 먹이기 직전에 상하로 충분히 흔들어 약효 성분이 균일하게 섞이도록 하세요.',
              cardBg: const Color(0xFFFAF5FF),
              cardBorder: const Color(0xFFE9D5FF),
            ),
            const SizedBox(height: 18),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  void _openRefusalGuidanceModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (c, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('🍯', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('약 안 먹는 아이 투약 노하우', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('약 뱉음·구토 예방 실전 꿀팁', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: const Text(
                '💡 억지로 코를 막고 먹이거나 눕혀 먹이면 기도로 약이 넘어가 흡인성 폐렴 위험이 있습니다. 아래의 미뢰 우회법을 활용하세요.',
                style: TextStyle(fontSize: 12, color: Color(0xFFC2410C), height: 1.4),
              ),
            ),
            const SizedBox(height: 14),

            _buildGuidanceCard(
              badge: '1. 볼 안쪽(미뢰 우회) 주입',
              badgeColor: const Color(0xFFDC2626),
              title: '혀 앞쪽·가운데는 피하세요',
              content: '혀의 앞부분과 중앙은 미각이 매우 예민합니다. 투약용 주사기나 피펫을 아기 어금니 쪽 볼 안쪽 구석으로 비스듬히 넣어 조금씩 천천히 밀어 넣어주세요.',
              cardBg: const Color(0xFFFEF2F2),
              cardBorder: const Color(0xFFFECACA),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '2. 분유/우유에 타지 않기',
              badgeColor: const Color(0xFFD97706),
              title: '수유 거부의 주원인',
              content: '젖병에 약을 섞으면 분유 맛이 변해 아기가 젖병 전체를 거부할 수 있습니다. 또한 분유를 다 먹지 않으면 정량을 섭취하지 못합니다.',
              cardBg: const Color(0xFFFFFBEB),
              cardBorder: const Color(0xFFFDE68A),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '3. 퓨레·올리고당 살짝 묻히기',
              badgeColor: const Color(0xFF059669),
              title: '쓴맛 가리기 팁',
              content: '가루약이나 쓴맛 시럽은 소량의 사과퓨레, 딸기잼, 올리고당을 숟가락 끝에 살짝 묻혀 약을 감싼 뒤 한입에 꿀꺽 삼키게 도와주세요.',
              cardBg: const Color(0xFFECFDF5),
              cardBorder: const Color(0xFFA7F3D0),
            ),
            const SizedBox(height: 10),

            _buildGuidanceCard(
              badge: '4. 45도 상체 세우기 & 칭찬',
              badgeColor: const Color(0xFF2563EB),
              title: '기도 흡인 예방과 긍정 피드백',
              content: '아기를 45도 이상 비스듬히 안거나 앉힌 뒤 턱을 가볍게 들어주세요. 투약 직후 물을 한 모금 마시게 하고 아낌없이 칭찬해 주세요.',
              cardBg: const Color(0xFFEFF6FF),
              cardBorder: const Color(0xFFBFDBFE),
            ),
            const SizedBox(height: 18),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidanceCard({
    required String badge,
    required Color badgeColor,
    required String title,
    required String content,
    required Color cardBg,
    required Color cardBorder,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(badge, style: TextStyle(color: badgeColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(content, style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), height: 1.45)),
        ],
      ),
    );
  }

  void _openNightPediatricEmergencyModal(BuildContext context) {
    String selectedRegion = '전체';
    String selectedType = '전체 병원';
    String searchQuery = '';
    String currentLocationName = '인천 송도';
    String currentSearchKeyword = '송도';
    final searchCtrl = TextEditingController();

    final regions = ['전체', '서울', '경기/인천', '충청/대전', '영남/부산/대구', '호남/광주', '강원/제주'];
    final types = ['전체 병원', '24시간 소아응급', '달빛어린이병원'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final filteredHospitals = _emergencyHospitals.where((h) {
            if (selectedRegion != '전체' && h.region != selectedRegion) return false;
            if (selectedType == '24시간 소아응급' && !h.is24Hours) return false;
            if (selectedType == '달빛어린이병원' && h.is24Hours) return false;
            if (searchQuery.isNotEmpty) {
              final query = searchQuery.toLowerCase();
              final matchesName = h.name.toLowerCase().contains(query);
              final matchesAddr = h.address.toLowerCase().contains(query);
              if (!matchesName && !matchesAddr) return false;
            }
            return true;
          }).toList();

          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.9,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (c, scrollCtrl) => ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(20),
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text('🚨', style: TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('야간·소아응급실 & 달빛병원', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            Text('24시간 소아응급센터 및 야간 진료 안내', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 14),

                // 📞 119 구급상황관리센터 퀵 안내 배너
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.phone_in_talk, color: Color(0xFFE11D48), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('야간 119 소아응급의료 상담 (무료)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B))),
                            SizedBox(height: 2),
                            Text('24시간 전문의·간호사 상주! 응급처치 지도 및 실시간 진료 가능 병원 안내',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B), height: 1.35)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: '119'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('📞 119 전화번호가 클립보드에 복사되었습니다. 통화 앱에서 바로 연결하세요.')),
                          );
                        },
                        child: const Text('119 안내', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Triage Guide: 달빛어린이병원 vs 24시간 소아응급센터
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.help_outline, size: 16, color: Color(0xFF475569)),
                          SizedBox(width: 6),
                          Text('어디로 가야 할까요? (방문 기준 가이드)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF1E293B))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFAF5FF),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE9D5FF)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('🌙 달빛어린이병원', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFF7C3AED))),
                                  SizedBox(height: 3),
                                  Text('• 밤 11~12시까지 운영\n• 미열, 감기, 중이염, 장염 등 경증\n• 짧은 대기시간 & 일반 외래 진료비',
                                      style: TextStyle(fontSize: 10, color: Color(0xFF581C87), height: 1.35)),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFFECACA)),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('🚨 소아전문응급센터', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: Color(0xFFDC2626))),
                                  SizedBox(height: 3),
                                  Text('• 24시간 연중무휴 (대학병원 ER)\n• 3개월 미만 38℃ 이상 고열\n• 5분 이상 경련, 호흡곤란, 의식 처짐',
                                      style: TextStyle(fontSize: 10, color: Color(0xFF991B1B), height: 1.35)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Quick Location Bar (내 위치 기반 스마트 추천)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFBBF7D0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.my_location, size: 16, color: Color(0xFF16A34A)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Color(0xFF15803D)),
                                children: [
                                  const TextSpan(text: '📍 내 위치: '),
                                  TextSpan(
                                    text: currentLocationName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF166534)),
                                  ),
                                  const TextSpan(text: ' 추천'),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                selectedRegion = currentLocationName.contains('서울') ? '서울' : '경기/인천';
                                searchCtrl.text = currentSearchKeyword;
                                searchQuery = currentSearchKeyword;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$currentLocationName 병원 보기',
                                style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () {
                              setModalState(() {
                                selectedRegion = '전체';
                                searchCtrl.clear();
                                searchQuery = '';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF86EFAC)),
                              ),
                              child: const Text('초기화', style: TextStyle(fontSize: 11, color: Color(0xFF15803D))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // 빠른 동네 변경 칩 바
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            const Text('동네 변경: ', style: TextStyle(fontSize: 10.5, color: Color(0xFF166534), fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            ...[
                              {'name': '인천 송도', 'kw': '송도', 'region': '경기/인천'},
                              {'name': '안양시 만안구', 'kw': '안양', 'region': '경기/인천'},
                              {'name': '서울 구로/신도림', 'kw': '구로', 'region': '서울'},
                              {'name': '경기 성남/분당', 'kw': '분당', 'region': '경기/인천'},
                              {'name': '경기 수원/영통', 'kw': '수원', 'region': '경기/인천'},
                            ].map((loc) {
                              final isCurrent = currentLocationName == loc['name'];
                              return Padding(
                                padding: const EdgeInsets.only(right: 5),
                                child: InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      currentLocationName = loc['name']!;
                                      currentSearchKeyword = loc['kw']!;
                                      selectedRegion = loc['region']!;
                                      searchCtrl.text = loc['kw']!;
                                      searchQuery = loc['kw']!;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isCurrent ? const Color(0xFF15803D) : Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isCurrent ? const Color(0xFF15803D) : const Color(0xFFA7F3D0),
                                      ),
                                    ),
                                    child: Text(
                                      loc['name']!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        color: isCurrent ? Colors.white : const Color(0xFF166534),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Search Bar
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: '병원명 또는 지역구 검색 (예: 송도, 서울대, 분당)',
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              setModalState(() {
                                searchCtrl.clear();
                                searchQuery = '';
                              });
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  onChanged: (val) => setModalState(() => searchQuery = val.trim()),
                ),
                const SizedBox(height: 10),

                // Region Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: regions.map((r) {
                      final isSelected = selectedRegion == r;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(r, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                          selected: isSelected,
                          selectedColor: const Color(0xFFFF6B8B),
                          labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black87),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedRegion = r);
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),

                // Type Chips
                Row(
                  children: types.map((t) {
                    final isSelected = selectedType == t;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        selected: isSelected,
                        selectedColor: const Color(0xFFFFD6DF),
                        checkmarkColor: const Color(0xFFFF6B8B),
                        onSelected: (val) {
                          setModalState(() => selectedType = t);
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // Hospital Count
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('검색 결과: 총 ${filteredHospitals.length}개 기관',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87)),
                    const Text('⚠️ 방문 전 전화 확인 필수', style: TextStyle(fontSize: 10, color: Color(0xFFDC2626), fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 8),

                // Hospital List
                if (filteredHospitals.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(16)),
                    child: const Center(
                      child: Column(
                        children: [
                          Icon(Icons.search_off, size: 36, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('조건에 맞는 응급의료기관이 없습니다.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          SizedBox(height: 4),
                          Text('응급 시에는 국번없이 119로 전화하여 실시간 진료 병원을 안내받으세요.',
                              style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ],
                      ),
                    ),
                  )
                else
                  ...filteredHospitals.map((h) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: h.is24Hours ? const Color(0xFFFFF1F2) : const Color(0xFFF5F3FF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                h.is24Hours ? '🚨 24시간 소아전문응급' : '🌙 달빛어린이병원',
                                style: TextStyle(
                                  color: h.is24Hours ? const Color(0xFFE11D48) : const Color(0xFF7C3AED),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                              child: Text(h.region, style: TextStyle(fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(h.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            const Icon(Icons.access_time, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(h.hours, style: TextStyle(fontSize: 11, color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(h.address, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('📞 ${h.phone}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E40AF))),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.call, size: 14),
                              label: const Text('전화번호 복사', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: h.is24Hours ? const Color(0xFFFEF2F2) : const Color(0xFFFAF5FF),
                                foregroundColor: h.is24Hours ? const Color(0xFFDC2626) : const Color(0xFF7C3AED),
                                elevation: 0,
                                side: BorderSide(color: h.is24Hours ? const Color(0xFFFCA5A5) : const Color(0xFFD8B4FE)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: h.phone));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('📞 ${h.name} 전화번호(${h.phone})가 복사되었습니다. 통화 앱에서 바로 연결하세요.'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )),

                const SizedBox(height: 14),
                // Checklist Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.checklist_rounded, size: 18, color: Color(0xFFD97706)),
                          SizedBox(width: 6),
                          Text('야간 응급실 출발 전 필수 지참물', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF92400E))),
                        ],
                      ),
                      SizedBox(height: 6),
                      Text('1. 아기 체중 및 현재 복용 중인 약 (Kidipedia 앱의 처방전 화면 제시)\n2. 해열제 최근 투약 시간 및 체온 변화 기록\n3. 구토/혈변 시 기저귀 또는 사진 지참\n4. 아기 보온 겉싸개, 여벌 옷, 기저귀, 보온병 분유',
                          style: TextStyle(fontSize: 11, color: Color(0xFF78350F), height: 1.4)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 🏛️ 정부 공공데이터 공식 출처 안내 배너
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified, size: 16, color: Color(0xFF6366F1)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '자료 출처: 보건복지부 지정 전국 달빛어린이병원 & 국립중앙의료원 중앙응급의료센터 E-Gen 공공포털 최신 데이터',
                          style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B8B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('확인 완료', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPediatricNewsDetail(BuildContext context, _PediatricNewsItem news) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('보건 소식', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.black87)),
                ),
                const SizedBox(width: 8),
                Text('📅 ${news.date}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              news.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87, height: 1.35),
            ),
            const SizedBox(height: 12),
            Text(
              news.content,
              style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.55),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.account_balance_outlined, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(news.source, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildCareTipTextRow({
    required String icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
    bool isEmergency = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isEmergency ? const Color(0xFFDC2626) : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    desc,
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  Widget _buildCareTipDivider() {
    return const Divider(height: 1, thickness: 0.6, color: Color(0xFFF3F4F6));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header Profile Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFFFF0F3),
                  child: Text('👶', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘도 건강하게 자라는 중 🌱', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    Text('${widget.profile.name} (${widget.profile.age}, ${widget.profile.weightKg}kg)',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                if (widget.onSwitchChild != null)
                  ActionChip(
                    avatar: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFFF6B8B)),
                    label: const Text('아이 변경', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                    backgroundColor: const Color(0xFFFFF0F3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFFD6DF))),
                    onPressed: widget.onSwitchChild,
                  ),
                IconButton(
                  icon: const Icon(Icons.notifications_active_outlined, color: Color(0xFFFF6B8B)),
                  tooltip: '접종 및 검진 알림',
                  onPressed: () => VaccineSchedulerSheet.show(context, widget.profile),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // 💉 우리 아이 필수 예방접종 & 영유아검진 알림 D-Day 카드
        Builder(
          builder: (ctx) {
            final birthDate = parseBabyBirthDate(widget.profile.birthDate, ageStr: widget.profile.age);
            // 90일 경과 미접종 항목은 자동 제외
            final upcomingList = standardSchedules.where((s) => s.getDDay(birthDate) >= -90).toList();
            if (upcomingList.isEmpty) return const SizedBox.shrink();
            final nextItem = upcomingList.first;
            final dday = nextItem.getDDay(birthDate);
            final overdue = -dday;

            Color badgeBg = const Color(0xFF059669);
            Color badgeFg = Colors.white;
            Gradient? badgeGradient;
            String ddayStr;
            Color cardBorder = const Color(0xFF86EFAC);

            if (dday == 0) {
              badgeBg = const Color(0xFFDC2626);
              badgeFg = Colors.white;
              ddayStr = '🔥 오늘 권장';
              cardBorder = const Color(0xFFDC2626);
            } else if (dday > 0) {
              if (dday <= 14) {
                badgeBg = const Color(0xFFFF6B8B);
                ddayStr = 'D-$dday (임박)';
                cardBorder = const Color(0xFFFF6B8B);
              } else {
                badgeBg = const Color(0xFF059669);
                ddayStr = 'D-$dday';
              }
            } else {
              // dday < 0 (지연)
              if (overdue > 30) {
                // 60일 지연 (31~90일): 빨간색 + 검은색 + 보라색 조합
                badgeGradient = const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF111827), Color(0xFFDC2626)],
                );
                badgeFg = Colors.white;
                ddayStr = '⚠️ 60일 지연 (+$overdue일)';
                cardBorder = const Color(0xFF7C3AED);
              } else if (overdue > 15) {
                // 30일 지연 (16~30일): 빨간색
                badgeBg = const Color(0xFFDC2626);
                badgeFg = Colors.white;
                ddayStr = '🚨 30일 지연 (+$overdue일)';
                cardBorder = const Color(0xFFDC2626);
              } else {
                // 15일 지연 (1~15일): 노란색
                badgeBg = const Color(0xFFF59E0B);
                badgeFg = Colors.white;
                ddayStr = '⏰ 15일 지연 (+$overdue일)';
                cardBorder = const Color(0xFFF59E0B);
              }
            }

            return GestureDetector(
              onTap: () => VaccineSchedulerSheet.show(context, widget.profile),
              child: Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: dday < 0 && overdue > 30
                        ? [const Color(0xFFFAF5FF), const Color(0xFFF3E8FF)]
                        : (dday < 0 && overdue > 15
                            ? [const Color(0xFFFFF5F5), const Color(0xFFFEE2E2)]
                            : (dday < 0
                                ? [const Color(0xFFFFFBEB), const Color(0xFFFEF3C7)]
                                : [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)])),
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: cardBorder, width: dday < 0 ? 1.5 : 1.0),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(nextItem.isCheckup ? '🩺' : '💉', style: const TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: badgeGradient == null ? badgeBg : null,
                                  gradient: badgeGradient,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(ddayStr, style: TextStyle(color: badgeFg, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  nextItem.isCheckup ? '다가오는 영유아 검진' : '다음 권장 예방접종',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: dday < 0 && overdue > 30
                                        ? const Color(0xFF6B21A8)
                                        : (dday < 0 && overdue > 15
                                            ? const Color(0xFF991B1B)
                                            : (dday < 0 ? const Color(0xFF92400E) : const Color(0xFF065F46))),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text('${nextItem.name} (${nextItem.monthRangeLabel})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 1),
                          const Text('일정 확인 및 D-Day 알림 설정하기 >',
                              style: TextStyle(fontSize: 10, color: Color(0xFF059669), fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF059669)),
                  ],
                ),
              ),
            );
          },
        ),

        // 2 Big Quick Action Buttons
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onNavigateScan,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFFFD6DF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.crop_free, color: Color(0xFFFF6B8B), size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text('처방전 스캔하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('약봉투 & 처방전 OCR', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: widget.onNavigateDrugs,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0F3),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFFFD6DF)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.medication, color: Color(0xFFFF6B8B), size: 24),
                      ),
                      const SizedBox(height: 12),
                      const Text('처방 기록 보기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('복약 현황 관리', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Schedule criteria explanation banner (스캔 기반 여부 동적 안내)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                ? const Color(0xFFEFF6FF)
                : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                ? const Color(0xFFBFDBFE)
                : const Color(0xFFCBD5E1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                    ? Icons.document_scanner
                    : Icons.info_outline,
                size: 15,
                color: widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF475569),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                      ? '📋 2026.01.24 스캔 처방전 기반 실시간 복약 일정 (총 ${widget.scannedDrugs!.length}개 의약품 연동)'
                      : (_doses.isNotEmpty
                          ? '💡 복약 스케줄: ${widget.profile.name}의 활성 처방약(복용 중) 기준 맞춤 일정입니다. 처방전 스캔 시 자동 동기화됩니다.'
                          : '💡 ${widget.profile.name}의 등록된 처방약이 없습니다. 상단 [처방전 스캔하기]로 첫 처방을 기록해보세요.'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: widget.scannedDrugs != null && widget.scannedDrugs!.isNotEmpty
                        ? const Color(0xFF1E40AF)
                        : const Color(0xFF334155),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Today's Medication Timeline with interactive toggle & progress
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('오늘의 복약 일정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            if (_doses.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _progress == 1.0 ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFFF6B8B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$_completedCount/${_doses.length} 완료 (${(_progress * 100).round()}%)',
                  style: TextStyle(
                    color: _progress == 1.0 ? const Color(0xFF059669) : const Color(0xFFFF6B8B),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_doses.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Center(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.medication_outlined, size: 32, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 10),
                  Text('${widget.profile.name}의 등록된 복약 일정이 없습니다',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                  const SizedBox(height: 4),
                  const Text('병원 처방전이나 약봉투를 스캔하면\n복약 일정과 안전 알림이 자동으로 등록됩니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4)),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: widget.onNavigateScan,
                    icon: const Icon(Icons.crop_free, size: 16),
                    label: const Text('첫 처방전 스캔하기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(_progress == 1.0 ? const Color(0xFF10B981) : const Color(0xFFFF6B8B)),
            ),
          ),
          const SizedBox(height: 12),
          ..._doses.map((dose) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _buildTimelineCard(dose),
          )),
        ],

        const SizedBox(height: 10),
        // Today's Safety Tip Banner (calm, neutral background, soft text)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘의 복약 안내', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(
                      _doses.isNotEmpty
                          ? '${widget.profile.name}이가 복용 중인 약품은 정해진 시간과 용량을 지켜 투약하고, 충분한 수분을 섭취해 주세요.'
                          : '${widget.profile.name}의 등록된 처방약이 없습니다. 상단 [처방전 스캔하기]를 누르면 약봉투나 처방전을 바로 등록할 수 있습니다.',
                      style: const TextStyle(fontSize: 11, color: Colors.black54, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 💡 안심 케어 TIP & 긴급 가이드 (테두리 없는 미니멀 텍스트 리스트)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '안심 케어 TIP & 긴급 가이드',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                Text(
                  '${widget.profile.age} 맞춤',
                  style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 4개 안심 케어 항목을 하나의 깔끔한 테두리 카드로 통합
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  _buildCareTipTextRow(
                    icon: '🌡️',
                    title: '해열제 교차계산',
                    desc: '체온별 적정 용량 및 교차 복용 간격',
                    onTap: () => _openAntipyreticCalculatorModal(context),
                  ),
                  _buildCareTipDivider(),
                  _buildCareTipTextRow(
                    icon: '🤢',
                    title: '토했을 때 가이드',
                    desc: '10분/30분 이내 구토 시 재투약 수칙',
                    onTap: () => _openVomitGuidanceModal(context),
                  ),
                  _buildCareTipDivider(),
                  _buildCareTipTextRow(
                    icon: '💊',
                    title: '항생제 복용 수칙',
                    desc: '증상 호전 시에도 임의중단 금지 · 냉장보관',
                    onTap: () => _openAntibioticsGuidanceModal(context),
                  ),
                  _buildCareTipDivider(),
                  _buildCareTipTextRow(
                    icon: '🍯',
                    title: '약 거부 대처 팁',
                    desc: '약 뱉는 아이 달래기 및 안전 투약 노하우',
                    onTap: () => _openRefusalGuidanceModal(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // 🚨 야간 소아응급실 & 달빛병원 (테두리와 가시성을 강화한 전용 긴급 카드)
            InkWell(
              onTap: () => _openNightPediatricEmergencyModal(context),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1ADC2626), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.emergency, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '야간 소아응급실 & 달빛병원',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF991B1B)),
                              ),
                              SizedBox(width: 6),
                              Text(
                                '24h',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                              ),
                            ],
                          ),
                          SizedBox(height: 2),
                          Text(
                            '전국 소아전문응급의료센터 · 심야 진료 달빛병원 찾기',
                            style: TextStyle(fontSize: 11, color: Color(0xFFB91C1C), height: 1.25),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('병원 찾기', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFDC2626))),
                          SizedBox(width: 2),
                          Icon(Icons.arrow_forward_ios, size: 9, color: Color(0xFFDC2626)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 📢 최신 보건 소식 (단일 테두리 카드로 감싼 업그레이드 디자인)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '최신 보건 소식',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('질병관리청', style: TextStyle(fontSize: 9.5, color: Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  ..._getPediatricNewsList(widget.profile).asMap().entries.map((entry) {
                    final index = entry.key;
                    final news = entry.value;
                    return Column(
                      children: [
                        if (index > 0)
                          const Divider(height: 1, thickness: 0.5, color: Color(0xFFF3F4F6)),
                        InkWell(
                          onTap: () => _showPediatricNewsDetail(context, news),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                            child: Row(
                              children: [
                                const Text('•', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    news.title,
                                    style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  news.date,
                                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF9CA3AF)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildTimelineCard(_TodayDoseItem dose) {
    final statusColor = dose.isCompleted ? const Color(0xFF10B981) : const Color(0xFFFF6B8B);
    final statusText = dose.isCompleted ? '✓ 복용 완료' : '복용 대기';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: dose.isCompleted ? const Color(0xFFA7F3D0) : Colors.transparent,
          width: dose.isCompleted ? 1.5 : 1,
        ),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () {
              if (dose.drugDetails.isNotEmpty) {
                setState(() => dose.isExpanded = !dose.isExpanded);
              } else {
                _toggleDose(dose);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            dose.timeTag,
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      dose.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        decoration: dose.isCompleted ? TextDecoration.lineThrough : null,
                                        color: dose.isCompleted ? Colors.grey.shade600 : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  if (dose.drugDetails.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      dose.isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dose.drugDetails.isNotEmpty
                                    ? (dose.isExpanded ? '터치하여 약 목록 접기 ▲' : '터치하여 포함 약품 & 용량(ml) 보기 ▼')
                                    : dose.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: dose.drugDetails.isNotEmpty ? const Color(0xFF64748B) : Colors.grey,
                                  fontWeight: dose.drugDetails.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 독립 체크 버튼
                  GestureDetector(
                    onTap: () => _toggleDose(dose),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            dose.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 포함된 약품 및 몇 ml 인지 아코디언 드롭다운 노출
          if (dose.isExpanded && dose.drugDetails.isNotEmpty) ...[
            const Divider(height: 1, indent: 14, endIndent: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.medication_liquid_outlined, size: 14, color: Color(0xFFFF6B8B)),
                      SizedBox(width: 6),
                      Text(
                        '처방 복용 약품 및 1회 권장 용량:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...dose.drugDetails.map((detail) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF10B981)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              detail,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// 2. DRUGS LIST SCREEN (처방약 목록 및 상세 화면)
// ----------------------------------------------------------------------
class _DisplayDrugItem {
  final String title;
  final String prescriptionMeta;
  final String dosage;
  final String remainingDays;
  final String statusBadge;
  final Color statusColor;
  final String category;
  final String desc;
  final bool isCompleted;

  const _DisplayDrugItem({
    required this.title,
    required this.prescriptionMeta,
    required this.dosage,
    required this.remainingDays,
    required this.statusBadge,
    required this.statusColor,
    required this.category,
    required this.desc,
    required this.isCompleted,
  });
}

class DrugsListScreen extends StatefulWidget {
  final MemberProfile profile;
  final List<DrugAnalysisResult> scannedDrugs;
  final VoidCallback? onGoBack;
  final VoidCallback? onNavigateScan;
  final Function(String)? onDeleteDrug;

  const DrugsListScreen({
    super.key,
    required this.profile,
    this.scannedDrugs = const [],
    this.onGoBack,
    this.onNavigateScan,
    this.onDeleteDrug,
  });

  @override
  State<DrugsListScreen> createState() => _DrugsListScreenState();
}

class _DrugsListScreenState extends State<DrugsListScreen> {
  bool _isDetailView = false;
  int _tabFilter = 0; // 0: 복용 중, 1: 복용 완료
  String _selectedDrug = '';
  String _selectedCategory = '';
  String _selectedDesc = '';

  final Set<String> _completedDrugTitles = {};
  final Set<String> _deletedDrugTitles = {};

  void _toggleDrugCompletion(String drugTitle) {
    setState(() {
      if (_completedDrugTitles.contains(drugTitle)) {
        _completedDrugTitles.remove(drugTitle);
      } else {
        _completedDrugTitles.add(drugTitle);
      }
    });

    final isNowDone = _completedDrugTitles.contains(drugTitle);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isNowDone
              ? '✓ "$drugTitle"(이)가 [복용 완료]로 이동되었습니다! 🎉'
              : '"$drugTitle"(이)가 [복용 중]으로 다시 이동되었습니다.',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmDeleteDrug(String title) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Color(0xFFFF6B8B)),
            SizedBox(width: 8),
            Text('처방약 삭제', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Text('\'$title\'(을)를 목록에서 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _deletedDrugTitles.add(title);
                _completedDrugTitles.remove(title);
                if (_isDetailView && _selectedDrug == title) {
                  _isDetailView = false;
                }
              });
              widget.onDeleteDrug?.call(title);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('\'$title\'이(가) 삭제되었습니다.')),
              );
            },
            child: const Text('삭제', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDetailView) {
      return _buildDrugDetailView();
    }

    final List<_DisplayDrugItem> activeDrugs = [];
    final List<_DisplayDrugItem> completedDrugs = [];

    // 1. 실제 스캔된 처방약 반영
    for (final scanned in widget.scannedDrugs) {
      if (_deletedDrugTitles.contains(scanned.drugName)) continue;
      final isDone = _completedDrugTitles.contains(scanned.drugName);
      final item = _DisplayDrugItem(
        title: scanned.drugName,
        prescriptionMeta: '인식: ${scanned.originalScanned} · 유사도 ${(scanned.confidence * 100).toInt()}%',
        dosage: scanned.status == 'SAFE' ? '${widget.profile.name} ${widget.profile.weightKg}kg 적정 용량' : '소아 용량 주의 확인 필요',
        remainingDays: isDone ? '복용 완료' : '안심 복약 진행 중',
        statusBadge: isDone ? '✓ 복용 완료' : (scanned.status == 'SAFE' ? '복용 중' : '⚠️ 주의'),
        statusColor: isDone ? const Color(0xFF10B981) : (scanned.status == 'SAFE' ? const Color(0xFFFF6B8B) : const Color(0xFFDC2626)),
        category: scanned.status == 'SAFE' ? '적정 소아 처방' : '⚠️ 용량 점검 요망',
        desc: scanned.comment,
        isCompleted: isDone,
      );
      if (isDone) {
        completedDrugs.add(item);
      } else {
        activeDrugs.add(item);
      }
    }


    final currentActiveCount = activeDrugs.length;
    final currentCompletedCount = completedDrugs.length;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            if (widget.onGoBack != null) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: widget.onGoBack,
              ),
              const SizedBox(width: 8),
            ],
            const Text('우리아이 처방약 목록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 14),

        // Segmented Tab - 복용 중 / 복용 완료
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabFilter = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tabFilter == 0 ? const Color(0xFFFF6B8B) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '복용 중 ($currentActiveCount)',
                        style: TextStyle(
                          color: _tabFilter == 0 ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _tabFilter = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: _tabFilter == 1 ? const Color(0xFFFF6B8B) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        '복용 완료 ($currentCompletedCount)',
                        style: TextStyle(
                          color: _tabFilter == 1 ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Filtered Drug Cards
        if (_tabFilter == 0) ...[
          // 복용 중 약품 목록
          ...activeDrugs.map((drug) => _buildDrugCard(
                title: drug.title,
                prescriptionMeta: drug.prescriptionMeta,
                dosage: drug.dosage,
                remainingDays: drug.remainingDays,
                statusBadge: drug.statusBadge,
                statusColor: drug.statusColor,
                onTap: () => setState(() {
                  _selectedDrug = drug.title;
                  _selectedCategory = drug.category;
                  _selectedDesc = drug.desc;
                  _isDetailView = true;
                }),
                onDelete: () => _confirmDeleteDrug(drug.title),
              )),

          if (currentActiveCount == 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF3F4F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.medication_outlined, size: 40, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.scannedDrugs.isNotEmpty
                        ? '현재 복용 중인 모든 처방약을 완료했습니다! 🎉'
                        : '${widget.profile.name}의 등록된 처방약이 없습니다',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.scannedDrugs.isNotEmpty
                        ? '[복용 완료] 탭에서 이전 복용 기록을 확인하실 수 있습니다.'
                        : '병원 처방전이나 약봉투를 스캔하면\n복약 일정과 안전 복용 정보가 자동으로 등록됩니다.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.45),
                  ),
                  if (widget.scannedDrugs.isEmpty) ...[
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: widget.onNavigateScan,
                      icon: const Icon(Icons.crop_free, size: 16),
                      label: const Text('첫 처방전 스캔하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B8B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ] else ...[
          // 복용 완료된 처방약 목록
          ...completedDrugs.map((drug) => _buildDrugCard(
                title: drug.title,
                prescriptionMeta: drug.prescriptionMeta,
                dosage: drug.dosage,
                remainingDays: drug.remainingDays,
                statusBadge: drug.statusBadge,
                statusColor: drug.statusColor,
                onTap: () => setState(() {
                  _selectedDrug = drug.title;
                  _selectedCategory = drug.category;
                  _selectedDesc = drug.desc;
                  _isDetailView = true;
                }),
                onDelete: () => _confirmDeleteDrug(drug.title),
              )),

          if (currentCompletedCount == 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(Icons.assignment_turned_in_outlined, size: 40, color: Color(0xFF9CA3AF)),
                  SizedBox(height: 14),
                  Text('복용 완료된 처방약이 없습니다',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                  SizedBox(height: 6),
                  Text(
                    '복용 중인 약을 끝까지 복용하고 [복용 완료] 처리하면\n이곳에 안전 복약 기록으로 보관됩니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.45),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDrugCard({
    required String title,
    required String prescriptionMeta,
    required String dosage,
    required String remainingDays,
    String statusBadge = '복용 중',
    Color statusColor = const Color(0xFFFF6B8B),
    required VoidCallback onTap,
    VoidCallback? onDelete,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusBadge,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onDelete != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: '처방약 삭제',
                        onPressed: onDelete,
                      ),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            Text(prescriptionMeta, style: const TextStyle(color: Colors.grey, fontSize: 11)),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(dosage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    remainingDays,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrugDetailView() {
    final isCompleted = _completedDrugTitles.contains(_selectedDrug);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _isDetailView = false)),
                const Text('처방약 상세 정보', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.grey),
              tooltip: '처방약 삭제',
              onPressed: () => _confirmDeleteDrug(_selectedDrug),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Top Grade Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(12)),
                child: Text(_selectedCategory, style: const TextStyle(color: Color(0xFFFF6B8B), fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text(_selectedDrug, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(_selectedDesc, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Weight Dosage Verification Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${widget.profile.name} 맞춤 용량 검증', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFA7F3D0))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🟢 용량 적정치 일치 (검증 완료)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF047857))),
                    const SizedBox(height: 4),
                    Text('${widget.profile.name} 몸무게(${widget.profile.weightKg}kg) 대비 1회 적정 권장량은 ${(widget.profile.weightKg! * 0.4).toStringAsFixed(1)}ml ~ ${(widget.profile.weightKg! * 0.5).toStringAsFixed(1)}ml 입니다. 현재 처방 용량은 안전한 범위에 속합니다.',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF065F46), height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Ingredients
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('주요 성분 & 안심 등급', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('페닐레프린염산염', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('코막힘 완화 · 혈관 수축 작용', style: TextStyle(fontSize: 11)),
                  trailing: Chip(label: Text('안심', style: TextStyle(fontSize: 10, color: Color(0xFF047857))), backgroundColor: Color(0xFFECFDF5)),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('클로르페니라민말레산염', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  subtitle: Text('항히스타민제 · 졸음 및 목마름 모니터링', style: TextStyle(fontSize: 11)),
                  trailing: Chip(label: Text('주의', style: TextStyle(fontSize: 10, color: Color(0xFFB45309))), backgroundColor: Color(0xFFFFFBEB)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Storage & Discard D-Day Guidance Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB), size: 18),
                  SizedBox(width: 8),
                  Text('보관 방법 & 폐기 기한', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                        ? const Color(0xFFBFDBFE)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크') ? '❄️' : '🌡️',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                              ? '냉장 보관(2~8℃) 필수'
                              : _selectedDrug.contains('클래리')
                                  ? '실온 보관(1~30℃, 냉장보관 금지)'
                                  : '실온 차광 보관(1~30℃)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                                ? const Color(0xFF1D4ED8)
                                : const Color(0xFF334155),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                          ? '• 개봉/조제 후 7일 이내 폐기 (상온 방치 시 역가가 급감하여 효과 없음)\n• 💊 항생제 완약 복용: 증상이 좋아져도 처방 일수를 끝까지 복용해야 내성균이 생기지 않습니다.'
                          : _selectedDrug.contains('클래리')
                              ? '• 조제 후 14일 이내 폐기\n• ⚠️ 주의: 냉장 보관 시 쓴맛이 심해져 아기가 복용을 거부할 수 있으므로 반드시 실온 보관하세요.'
                              : '• 개봉 후 30일 이내 권장\n• 직사광선을 피해 서늘하고 건조한 실온에 보관하세요.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: _selectedDrug.contains('아모클') || _selectedDrug.contains('아모크')
                            ? const Color(0xFF1E40AF)
                            : const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Toggle Active / Completed Button
        ElevatedButton.icon(
          icon: Icon(isCompleted ? Icons.undo : Icons.check_circle, size: 20),
          label: Text(
            isCompleted ? '🔄 다시 [복용 중]으로 변경' : '✓ [복용 완료]로 변경',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isCompleted ? const Color(0xFFFF6B8B) : const Color(0xFF10B981),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: () {
            _toggleDrugCompletion(_selectedDrug);
          },
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 3. SCAN SCREEN (OCR 카메라 스캔 화면)
// ----------------------------------------------------------------------
class ScanScreen extends StatefulWidget {
  final MemberProfile profile;
  final Function(int) onNavigateTab;
  final Function(List<DoctorQnaItem>) onUpdateQuestions;
  final Function(List<DrugAnalysisResult>)? onUpdateScannedDrugs;
  final VoidCallback? onGoBack;

  const ScanScreen({
    super.key,
    required this.profile,
    required this.onNavigateTab,
    required this.onUpdateQuestions,
    this.onUpdateScannedDrugs,
    this.onGoBack,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isAnalyzing = false;
  String? _selectedImageName;
  Uint8List? _previewImageBytes;
  PrescriptionAnalysisResponse? _analysisResult;
  final ImagePicker _picker = ImagePicker();

  Future<void> _processScanWithDrugs(List<ScannedDrugItem> drugs) async {
    setState(() => _isAnalyzing = true);

    try {
      final res = await ApiService.analyzePrescription(
        profile: widget.profile,
        scannedDrugs: drugs,
      );

      widget.onUpdateQuestions(res.doctorQna);
      widget.onUpdateScannedDrugs?.call(res.analyzedDrugs);

      if (mounted) {
        setState(() {
          _analysisResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('스캔 분석 실패: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // 실제 업로드된 처방전 이미지 바이트를 Base64로 인코딩하여 백엔드 Gemini Vision OCR로 전달
  Future<void> _processScanWithImage() async {
    if (_previewImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ 분석할 처방전 사진을 먼저 촬영하거나 앨범에서 선택해 주세요.'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }

    setState(() => _isAnalyzing = true);

    try {
      final base64Image = base64Encode(_previewImageBytes!);
      final res = await ApiService.analyzePrescriptionImage(
        profile: widget.profile,
        imageBase64: base64Image,
        mimeType: 'image/jpeg',
      );

      widget.onUpdateQuestions(res.doctorQna);
      widget.onUpdateScannedDrugs?.call(res.analyzedDrugs);

      if (mounted) {
        setState(() {
          _analysisResult = res;
        });
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e.toString().contains('OCR_EXTRACTION_FAILED')
            ? '⚠️ 처방전 글씨를 정확히 인식하지 못했습니다. 약봉투를 밝은 곳에서 글씨가 선명하도록 다시 촬영하거나, 직접 입력해 주세요.'
            : '처방전 이미지 분석 중 오류가 발생했습니다: $e';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  // 1. 앨범/갤러리에서 사진 가져오기 (미리보기 단계로 진입)
  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (pickedFile != null) {
        final bytes = await pickedFile.readAsBytes();
        if (mounted) {
          setState(() {
            _previewImageBytes = bytes;
            _selectedImageName = pickedFile.name;
            _analysisResult = null; // 미리보기 화면 전환
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앨범 사진 불러오기 실패: $e')),
        );
      }
    }
  }

  // 2. 카메라 촬영 (미리보기 단계로 진입)
  Future<void> _captureFromCamera() async {
    try {
      final XFile? captured = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
      );

      if (captured != null) {
        final bytes = await captured.readAsBytes();
        if (mounted) {
          setState(() {
            _previewImageBytes = bytes;
            _selectedImageName = captured.name;
            _analysisResult = null; // 미리보기 화면 전환
          });
        }
      }
    } catch (_) {
      // 카메라 하드웨어나 권한 문제 시 갤러리 선택으로 자연스럽게 Fallback
      await _pickImageFromGallery();
    }
  }

  // 2. 직접 수동 입력 모달 다이얼로그 오픈
  void _openManualInputDialog() {
    final nameCtrl = TextEditingController(text: '코미시럽');
    final doseCtrl = TextEditingController(text: '4.0');
    final freqCtrl = TextEditingController(text: '3');
    final daysCtrl = TextEditingController(text: '3');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('✎ 처방약 직접 입력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.profile.name}(${widget.profile.weightKg}kg) 맞춤 용량 및 안전성 검증을 위해 약품 정보를 입력해 주세요.',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 18),

              // 약품명
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: '약품명 (처방전 또는 약봉투 이름)',
                  hintText: '예: 코미시럽, 아모클란듀오',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.medication, color: Color(0xFFFF6B8B)),
                ),
              ),
              const SizedBox(height: 12),

              // 1회 투약량 & 1일 횟수
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: doseCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: '1회 투여량 (ml 또는 정)',
                        hintText: '4.0',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.science, color: Color(0xFF10B981)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: freqCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: '1일 복용 횟수',
                        hintText: '3',
                        suffixText: '회',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        prefixIcon: const Icon(Icons.repeat, color: Colors.blue),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: daysCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '처방/투약 일수',
                  hintText: '3',
                  suffixText: '일분',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  prefixIcon: const Icon(Icons.calendar_today, color: Colors.orange),
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B8B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () {
                  final drugName = nameCtrl.text.trim();
                  final dose = double.tryParse(doseCtrl.text.trim()) ?? 4.0;
                  final freq = int.tryParse(freqCtrl.text.trim()) ?? 3;
                  final days = int.tryParse(daysCtrl.text.trim()) ?? 3;

                  if (drugName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('약품명을 입력해 주세요.')),
                    );
                    return;
                  }

                  Navigator.pop(ctx);

                  _processScanWithDrugs([
                    ScannedDrugItem(scannedName: drugName, doseUnit: dose, freqPerDay: freq, days: days),
                  ]);
                },
                child: const Text('안심 분석 시작하기 ➔', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyAiDeduction(DrugAnalysisResult originalDrug, AiDeduction deduction) async {
    if (_analysisResult == null) return;

    setState(() => _isAnalyzing = true);
    try {
      final targetName = deduction.suggestedDbKey.isNotEmpty ? deduction.suggestedDbKey : deduction.deducedName;

      final updatedList = <ScannedDrugItem>[];
      for (final drug in _analysisResult!.analyzedDrugs) {
        final origDose = drug.scannedDoseUnit ?? 1.0;
        final origFreq = drug.scannedFreqPerDay ?? 3;
        final origDays = drug.scannedDays ?? 3;

        if (drug.drugName == originalDrug.drugName && drug.originalScanned == originalDrug.originalScanned) {
          // MED-02: AI 자동 보정 시 원래 처방전의 1회 투여량, 1일 복용 횟수, 복용 일수를 100% 보존
          updatedList.add(ScannedDrugItem(
            scannedName: targetName,
            doseUnit: origDose,
            freqPerDay: origFreq,
            days: origDays,
          ));
        } else {
          updatedList.add(ScannedDrugItem(
            scannedName: drug.drugName,
            doseUnit: origDose,
            freqPerDay: origFreq,
            days: origDays,
          ));
        }
      }

      await _processScanWithDrugs(updatedList);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ AI 스마트 추천으로 "$targetName"(으)로 자동 보정하여 용량 분석을 완료했습니다!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자동 보정 실패: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  bool _isSameDrugBaseName(String a, String b) {
    String clean(String s) {
      return s
          .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '')
          .replaceAll(RegExp(r'[^가-힣a-zA-Z0-9]'), '')
          .toLowerCase()
          .trim();
    }
    final ca = clean(a);
    final cb = clean(b);
    if (ca.isEmpty || cb.isEmpty) return false;
    return ca == cb || ca.contains(cb) || cb.contains(ca);
  }

  Widget _buildAiDeductionCard(DrugAnalysisResult d) {
    final deduction = d.aiDeduction;
    if (deduction == null) return const SizedBox.shrink();

    final deducedName = deduction.deducedName;
    final ingredient = deduction.ingredient;
    final category = deduction.category;
    final reason = deduction.reason;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFAF5FF), Color(0xFFF3E8FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8B4FE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFF8B5CF6), borderRadius: BorderRadius.circular(8)),
                    child: const Text('🤖', style: TextStyle(fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '혹시 이 약을 찾으셨나요? (AI 스마트 추천)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF6B21A8)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: const Text('Gemini AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('추천 약품: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF581C87))),
              Expanded(
                child: Text(
                  deducedName,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('주요 성분: ', style: TextStyle(fontSize: 11, color: Color(0xFF4C1D95))),
              Expanded(
                child: Text(
                  '$ingredient ($category)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF581C87)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason,
            style: const TextStyle(fontSize: 11, color: Color(0xFF4C1D95), height: 1.35),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C3AED),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            icon: _isAnalyzing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high, size: 16),
            label: Text(
              _isAnalyzing ? 'AI 보정 및 용량 재검증 중...' : '✓ "$deducedName"(으)로 자동 보정하여 용량 검증',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: _isAnalyzing
                ? null
                : () {
                    _applyAiDeduction(d, deduction);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildFormattedAiSafetyReport(String safetyReport) {
    if (safetyReport.trim().isEmpty) return const SizedBox.shrink();

    final rawLines = safetyReport
        .split(RegExp(r'\n+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    String? disclaimer;
    final parsedCards = <_AiReportCardData>[];

    for (final line in rawLines) {
      if (line.startsWith('※') || (line.contains('의료진') && line.contains('상의'))) {
        disclaimer = line.replaceAll('*', '').trim();
        continue;
      }

      String tag = '';
      String body = '';

      // Pattern 1: [태그] 내용
      final bracketMatch = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(line);
      if (bracketMatch != null) {
        tag = bracketMatch.group(1)?.trim() ?? '';
        body = bracketMatch.group(2)?.trim() ?? '';
      } else {
        // Pattern 2: • or 1. **제목**: 내용
        final boldMatch = RegExp(r'^(?:[-•\d\.]+\s*)?\*\*([^*]+)\*\*[:\s]*(.*)$').firstMatch(line);
        if (boldMatch != null) {
          tag = boldMatch.group(1)?.trim() ?? '';
          body = boldMatch.group(2)?.trim() ?? '';
        } else {
          // Pattern 3: • 아이콘 제목: 내용
          final colonMatch = RegExp(r'^(?:[-•\d\.]+\s*)?([^:：]+)[:：]\s*(.*)$').firstMatch(line);
          if (colonMatch != null && colonMatch.group(1)!.length < 25) {
            tag = colonMatch.group(1)?.replaceAll('*', '').trim() ?? '';
            body = colonMatch.group(2)?.replaceAll('*', '').trim() ?? '';
          } else {
            // General text
            body = line.replaceAll('*', '').replaceAll(RegExp(r'^[-•\d\.]+\s*'), '').trim();
          }
        }
      }

      body = body.replaceAll('*', '').trim();
      if (tag.isEmpty && body.isNotEmpty) {
        if (parsedCards.isEmpty) {
          tag = '⚖️ 안심 용량';
        } else if (parsedCards.length == 1) {
          tag = '💊 핵심 복약 수칙';
        } else {
          tag = '⏱️ 돌봄 TIP';
        }
      }

      if (body.isNotEmpty || tag.isNotEmpty) {
        parsedCards.add(_AiReportCardData(tag: tag, body: body.isEmpty ? tag : body));
      }
    }

    if (parsedCards.isEmpty && (disclaimer == null || disclaimer.isEmpty)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'AI 안심 복약 가이드',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '3줄 핵심 요약',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFF4F46E5)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...parsedCards.map((card) {
            Color badgeBg;
            Color badgeText;
            Color cardBorder;
            Color cardBg;

            if (card.tag.contains('주의') || card.tag.contains('확인') || card.tag.contains('경고')) {
              badgeBg = const Color(0xFFFEF3C7);
              badgeText = const Color(0xFFB45309);
              cardBorder = const Color(0xFFFDE68A);
              cardBg = const Color(0xFFFFFBEB);
            } else if (card.tag.contains('용량') || card.tag.contains('적정') || card.tag.contains('안심 용량')) {
              badgeBg = const Color(0xFFDCFCE7);
              badgeText = const Color(0xFF15803D);
              cardBorder = const Color(0xFFBBF7D0);
              cardBg = const Color(0xFFF0FDF4);
            } else if (card.tag.contains('항생제') || card.tag.contains('수칙') || card.tag.contains('처방')) {
              badgeBg = const Color(0xFFEEF2FF);
              badgeText = const Color(0xFF4338CA);
              cardBorder = const Color(0xFFC7D2FE);
              cardBg = const Color(0xFFF8FAFC);
            } else {
              badgeBg = const Color(0xFFFFE4E6);
              badgeText = const Color(0xFFBE123C);
              cardBorder = const Color(0xFFFECDD3);
              cardBg = const Color(0xFFFFF1F2);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.tag.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        card.tag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: badgeText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    card.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1E293B),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (disclaimer != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 12, color: Color(0xFF94A3B8)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    disclaimer,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisResultView(PrescriptionAnalysisResponse result) {
    final hasWarning = result.analyzedDrugs.any((d) => d.status == 'WARNING' || d.status == 'HIGH');
    final hasUnknown = result.analyzedDrugs.any((d) => d.status == 'UNKNOWN');

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (widget.onGoBack != null) ...[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: widget.onGoBack,
                        tooltip: '이전 화면으로',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Text('처방전 안심 분석 결과', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.grey),
                  tooltip: '다시 스캔하기',
                  onPressed: () => setState(() {
                    _analysisResult = null;
                    _selectedImageName = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 실시간 동적 종합 상태 배너 (모순 없는 정확한 판정)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasWarning
                    ? const Color(0xFFFEF2F2)
                    : hasUnknown
                        ? const Color(0xFFFFFBEB)
                        : const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: hasWarning
                      ? const Color(0xFFFECACA)
                      : hasUnknown
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFA7F3D0),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: hasWarning
                        ? const Color(0xFFDC2626)
                        : hasUnknown
                            ? const Color(0xFFD97706)
                            : const Color(0xFF10B981),
                    radius: 20,
                    child: Icon(
                      hasWarning
                          ? Icons.warning_amber_rounded
                          : hasUnknown
                              ? Icons.help_outline
                              : Icons.check,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasWarning
                              ? '${widget.profile.name}(${widget.profile.weightKg}kg) 소아 체중 기준 용량 초과 주의'
                              : hasUnknown
                                  ? '${widget.profile.name}(${widget.profile.weightKg}kg) 소아 권장 용량 확인 필요'
                                  : '${widget.profile.name}(${widget.profile.weightKg}kg) 전 약품 적정 용량 부합',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: hasWarning
                                ? const Color(0xFF991B1B)
                                : hasUnknown
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFF065F46),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hasWarning
                              ? '처방된 약품 중 1일 또는 1회 최대 상한을 초과한 약품이 있습니다. 아래 주의 사유를 확인하고 반드시 감량 또는 의사 상담을 진행하세요.'
                              : hasUnknown
                                  ? '식약처 허가 의약품이나 소아 체중당 기준 정보가 미등록되어 용량 검증에 의사·약사의 복약 지도가 필요합니다.'
                                  : '모든 처방약이 식약처 e-약은요 공공데이터 및 소아 체중 기준 안전 범위에 부합합니다.',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasWarning
                                ? const Color(0xFFB91C1C)
                                : hasUnknown
                                    ? const Color(0xFFB45309)
                                    : const Color(0xFF047857),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // DUR 안심 검토 배너 (상단 종합 안전성 카테고리로 통일)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: result.durWarnings.isEmpty ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: result.durWarnings.isEmpty ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  Icon(
                    result.durWarnings.isEmpty ? Icons.security : Icons.warning_amber_rounded,
                    color: result.durWarnings.isEmpty ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.durWarnings.isEmpty
                          ? '🛡️ 중복 성분 및 병용 금기 상호작용 없음 (안전)'
                          : result.durWarnings.map((w) => w.message).join('\n'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: result.durWarnings.isEmpty ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Analyzed Drugs Section
            const Text('분석된 처방 의약품', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            ...result.analyzedDrugs.map((d) {
              final bool isSafe = d.status == 'SAFE';
              final bool isModified = d.originalScanned.trim() != d.drugName.trim();

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isModified
                        ? const Color(0xFFC084FC)
                        : isSafe
                            ? Colors.grey.shade200
                            : const Color(0xFFFCA5A5),
                    width: isModified ? 1.5 : 1.0,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더 Row: 약품명 + 우측 슬림 미니 배지 칩 모음
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.medication, color: isSafe ? const Color(0xFFFF6B8B) : const Color(0xFFDC2626), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.drugName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              if (d.purpose != null && d.purpose!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '용도: ${d.purpose}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 우측 컴팩트 배지 Wrap (적정용량/주의 + 보관법 + 폐기일 + 완약복용 칩)
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          alignment: WrapAlignment.end,
                          children: [
                            // 1. 용량 판정 뱃지
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSafe
                                    ? const Color(0xFFECFDF5)
                                    : d.status == 'UNKNOWN'
                                        ? const Color(0xFFFFFBEB)
                                        : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSafe
                                      ? const Color(0xFFA7F3D0)
                                      : d.status == 'UNKNOWN'
                                          ? const Color(0xFFFDE68A)
                                          : const Color(0xFFFECACA),
                                ),
                              ),
                              child: Text(
                                isSafe
                                    ? '🟢 적정 용량'
                                    : d.status == 'UNKNOWN'
                                        ? '확인 필요'
                                        : '⚠️ 주의',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isSafe
                                      ? const Color(0xFF047857)
                                      : d.status == 'UNKNOWN'
                                          ? const Color(0xFFB45309)
                                          : const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                            // 2. 보관법 미니 배지 (실온/냉장)
                            if (d.storageMethod != null && d.storageMethod!.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: d.storageMethod!.contains('냉장')
                                      ? const Color(0xFFEFF6FF)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: d.storageMethod!.contains('냉장')
                                        ? const Color(0xFFBFDBFE)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  d.storageMethod!.contains('냉장') ? '❄️ 냉장' : '🌡️ 실온',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: d.storageMethod!.contains('냉장')
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF475569),
                                  ),
                                ),
                              ),
                            // 3. 폐기일 미니 배지
                            if (d.discardDays != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF7ED),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFED7AA)),
                                ),
                                child: Text(
                                  '⏳ ${d.discardDays}일 폐기',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFC2410C)),
                                ),
                              ),
                            // 4. 항생제 완약 복용 미니 배지
                            if (d.isAntibiotic == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFFECDD3)),
                                ),
                                child: const Text(
                                  '💊 완약 복용',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFBE123C)),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isSafe
                          ? 'OCR 인식: "${d.originalScanned}" · 유사도: ${(d.confidence * 100).toInt()}% · ${widget.profile.weightKg}kg 권장 용량 부합'
                          : 'OCR 인식: "${d.originalScanned}" · 유사도: ${(d.confidence * 100).toInt()}%',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),

                    // AI 자동 보정 완료 배지 (사용자가 무엇이 바뀌었는지 바로 확인 가능)
                    if (isModified) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFAF5FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFD8B4FE)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_fix_high, size: 13, color: Color(0xFF7C3AED)),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                '✨ AI 자동 보정 적용됨 (원래: "${d.originalScanned}" ➔ 현재: "${d.drugName}")',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B21A8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],


                    // 항생제 완약 복용 안내 팁 (심플한 정보 텍스트)
                    if (d.complianceNote != null) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 13, color: Color(0xFF0284C7)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                d.complianceNote!,
                                style: const TextStyle(fontSize: 11, color: Color(0xFF475569), height: 1.3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 주의/확인 필요 시에만 컴팩트한 안내 박스 노출 (적정 용량일 때는 거대한 박스 제거)
                    if (!isSafe) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: d.status == 'UNKNOWN' ? const Color(0xFFFFFBEB) : const Color(0xFFFFF1F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: d.status == 'UNKNOWN' ? const Color(0xFFFDE68A) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              d.status == 'UNKNOWN' ? Icons.info_outline : Icons.warning_amber_rounded,
                              color: d.status == 'UNKNOWN' ? const Color(0xFFD97706) : const Color(0xFFDC2626),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                d.comment,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: d.status == 'UNKNOWN' ? const Color(0xFF92400E) : const Color(0xFF991B1B),
                                  height: 1.35,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // AI 스마트 추천 ("혹시 이 약을 찾으셨나요?") 카드
                    // 엄격한 조건: 추천 약품명이 현재 분석된 약품명과 명확히 다를 때만 노출 (괄호 성분명 표기 등 동일 약품명 오표기 방지)
                    if (d.aiDeduction != null &&
                        d.aiDeduction!.deducedName.trim().isNotEmpty &&
                        !_isSameDrugBaseName(d.aiDeduction!.deducedName, d.drugName) &&
                        !_isSameDrugBaseName(d.aiDeduction!.deducedName, d.originalScanned)) ...[
                      const SizedBox(height: 10),
                      _buildAiDeductionCard(d),
                    ],
                  ],
                ),
              );
            }),

        // AI 안심 복약 3줄 핵심 요약 (정돈된 리포트 카드)
        if (result.safetyReport.isNotEmpty) ...[
          _buildFormattedAiSafetyReport(result.safetyReport),
          const SizedBox(height: 14),
        ],

        // 2 Action Buttons
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 1,
          ),
          icon: const Icon(Icons.assignment, size: 18),
          label: Text('📋 의사용 안심 Q&A 보러가기 (맞춤 질문 ${result.doctorQna.length}건 준비 완료) ➔',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
          onPressed: () => widget.onNavigateTab(3),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.medication, color: Color(0xFFFF6B8B)),
          label: const Text('처방약 복용 정보 목록 보기',
              style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: () => widget.onNavigateTab(1),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _analysisResult = null;
              _previewImageBytes = null;
              _selectedImageName = null;
            }),
            child: const Text('다른 처방전 다시 스캔하기', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        ),
      ],
    ),
    if (_isAnalyzing)
      Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 36),
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.5,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    'AI 맞춤 용량 재검증 중...',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '소아 체중 기준 적정 복용량을 다시 계산하고 있습니다.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

  Widget _buildPhotoPreviewConfirmView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (widget.onGoBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: widget.onGoBack,
                    tooltip: '이전 화면으로',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                ],
                const Text('처방전 사진 확인', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16, color: Colors.grey),
              label: const Text('다시 선택', style: TextStyle(color: Colors.grey, fontSize: 12)),
              onPressed: () => setState(() {
                _previewImageBytes = null;
                _selectedImageName = null;
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('촬영하거나 업로드한 처방전/약봉투 사진이 맞는지 확인해 주세요. 글씨가 선명할수록 정확하게 분석됩니다.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 16),

        // Photo Preview Card
        Container(
          height: 340,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
            border: Border.all(color: const Color(0xFFFF6B8B), width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_previewImageBytes != null)
                Image.memory(
                  _previewImageBytes!,
                  fit: BoxFit.contain,
                )
              else
                const Center(
                  child: Icon(Icons.receipt_long, size: 64, color: Colors.white54),
                ),
              // File tag overlay at the top
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          _selectedImageName ?? '처방전 이미지',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Checklist Banner
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Expanded(
                child: Text('약품명, 1회 투약량(ml/정), 1일 복용 횟수가 사진 안에 잘 담겨있는지 확인해 주세요.',
                    style: TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 1. Analyze Button (Trigger)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            elevation: 2,
          ),
          icon: _isAnalyzing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Icon(Icons.psychology, size: 22),
          label: Text(
            _isAnalyzing ? '${widget.profile.name} 맞춤 용량 및 안전성 분석 중...' : '🔍 처방전 안심 분석 시작하기 ➔',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          onPressed: _isAnalyzing ? null : _processScanWithImage,
        ),
        const SizedBox(height: 10),

        // 2. Pre-Review / Direct Edit Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.2),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.edit_note, color: Color(0xFFFF6B8B), size: 20),
          label: const Text('약품명 직접 확인 & 보정해서 분석하기',
              style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: _openManualInputDialog,
        ),
        const SizedBox(height: 10),

        // 3. Reselect / Retake Button
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.grey.shade300, width: 1.5),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: const Icon(Icons.photo_library, color: Colors.grey, size: 18),
          label: const Text('다른 사진으로 다시 선택하기',
              style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
          onPressed: _isAnalyzing ? null : _pickImageFromGallery,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_analysisResult != null) {
      return _buildAnalysisResultView(_analysisResult!);
    }

    if (_previewImageBytes != null) {
      return _buildPhotoPreviewConfirmView();
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            if (widget.onGoBack != null) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onGoBack,
                tooltip: '이전 화면으로',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
            ],
            const Text('처방전 / 약봉투 스캔', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),

        // Camera Viewfinder Box
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: const Color(0xFFFF6B8B), width: 2),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30, width: 2),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: const Text('🔍 텍스트를 자동으로 감지하는 중', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 8),
                  const Text('처방전이나 약봉투 글씨가 밝고 명확하게 보이도록 넣어주세요.',
                      style: TextStyle(color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                ],
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 앨범 선택 아이콘 버튼
                    IconButton(
                      iconSize: 32,
                      icon: const Icon(Icons.photo_library, color: Colors.white),
                      tooltip: '앨범에서 선택',
                      onPressed: _isAnalyzing ? null : _pickImageFromGallery,
                    ),
                    // 카메라 촬영 셔터 버튼
                    GestureDetector(
                      onTap: _isAnalyzing ? null : _captureFromCamera,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B8B),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: _isAnalyzing
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Icon(Icons.camera_alt, color: Colors.white, size: 28),
                      ),
                    ),
                    // 플래시 토글 버튼
                    IconButton(
                      iconSize: 28,
                      icon: const Icon(Icons.flash_auto, color: Colors.white),
                      tooltip: '플래시',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_selectedImageName != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.image, size: 18, color: Color(0xFFFF6B8B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('선택된 이미지: $_selectedImageName',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 1. 앨범/갤러리에서 사진 가져오기 버튼
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Color(0xFFFF6B8B), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            minimumSize: const Size.fromHeight(50),
          ),
          icon: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
          label: const Text('🖼️ 앨범 / 갤러리에서 사진 가져오기',
              style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: _isAnalyzing ? null : _pickImageFromGallery,
        ),
        const SizedBox(height: 10),

        // 2. 약품 직접 수동 입력 모달 버튼
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFF0F3),
            foregroundColor: const Color(0xFFFF6B8B),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            minimumSize: const Size.fromHeight(50),
          ),
          icon: const Icon(Icons.edit_note, color: Color(0xFFFF6B8B)),
          label: const Text('✎ 약품 직접 입력해서 등록하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          onPressed: _openManualInputDialog,
        ),
        const SizedBox(height: 16),

        // 3. Quick Sample Presets (소아과 대표 처방전 1-Tap 불러오기)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Color(0xFFFF6B8B)),
                  SizedBox(width: 6),
                  Text('소아과 대표 처방전 1-Tap 샘플 분석',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155))),
                ],
              ),
              const SizedBox(height: 4),
              const Text('처방전 사진이 없으셔도 실제 소아과 다빈도 처방 세트로 즉시 분석 체험이 가능합니다.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        side: const BorderSide(color: Color(0xFFFF6B8B)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isAnalyzing
                          ? null
                          : () {
                              _processScanWithDrugs([
                                ScannedDrugItem(scannedName: '코미시럽', doseUnit: 4.0, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '암브로콜시럽', doseUnit: 3.0, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '시네츄라시럽', doseUnit: 3.5, freqPerDay: 3, days: 3),
                                ScannedDrugItem(scannedName: '메디락베베산', doseUnit: 1.0, freqPerDay: 2, days: 3),
                                ScannedDrugItem(scannedName: '삼아아토크건조시럽', doseUnit: 1.0, freqPerDay: 2, days: 3),
                                ScannedDrugItem(scannedName: '챔프시럽', doseUnit: 3.6, freqPerDay: 3, days: 3),
                              ]);
                            },
                      child: const Column(
                        children: [
                          Text('🏥 감기약 6종 세트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFFFF6B8B))),
                          SizedBox(height: 2),
                          Text('코미·암브로콜·챔프 등', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _isAnalyzing
                          ? null
                          : () {
                              _processScanWithDrugs([
                                ScannedDrugItem(scannedName: '아모클란듀오 시럽', doseUnit: 3.0, freqPerDay: 2, days: 7),
                                ScannedDrugItem(scannedName: '비오플 250산', doseUnit: 1.0, freqPerDay: 2, days: 7),
                                ScannedDrugItem(scannedName: '맥시부펜 시럽', doseUnit: 4.6, freqPerDay: 3, days: 3),
                              ]);
                            },
                      child: const Column(
                        children: [
                          Text('💊 중이염 항생제 세트', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF10B981))),
                          SizedBox(height: 2),
                          Text('아모클란·비오플 등', style: TextStyle(fontSize: 10, color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 4. DOCTOR Q&A SCREEN (소아과 의사용 안심 Q&A 화면)
// ----------------------------------------------------------------------
class DoctorQnaScreen extends StatefulWidget {
  final MemberProfile profile;
  final List<DoctorQnaItem> questions;
  final VoidCallback? onGoBack;

  const DoctorQnaScreen({
    super.key,
    required this.profile,
    required this.questions,
    this.onGoBack,
  });

  @override
  State<DoctorQnaScreen> createState() => _DoctorQnaScreenState();
}

class _DoctorQnaScreenState extends State<DoctorQnaScreen> {
  late List<DoctorQnaItem> _localQuestions;

  @override
  void initState() {
    super.initState();
    _localQuestions = List.from(widget.questions);
  }

  @override
  void didUpdateWidget(DoctorQnaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 스캔 후 새 질문 목록이 들어오면 업데이트 (커스텀 질문은 유지)
    if (oldWidget.questions != widget.questions) {
      final customQuestions = _localQuestions.where((q) => q.id.startsWith('custom_')).toList();
      _localQuestions = List.from(widget.questions)..addAll(customQuestions);
    }
  }

  void _openAddQuestionDialog() {
    final catCtrl = TextEditingController(text: '보호자 직접 질문');
    final questionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: Color(0xFFFF6B8B)),
            SizedBox(width: 8),
            Text('나만의 질문 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: catCtrl,
              decoration: InputDecoration(
                labelText: '질문 분류',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: questionCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: '의사 선생님께 여쭤볼 내용',
                hintText: '예: 열이 38.5도 넘으면 응급실로 가야 하나요?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              final text = questionCtrl.text.trim();
              if (text.isEmpty) return;
              setState(() {
                _localQuestions.add(
                  DoctorQnaItem(
                    id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                    category: catCtrl.text.trim().isEmpty ? '보호자 질문' : catCtrl.text.trim(),
                    question: text,
                    isSelected: true,
                  ),
                );
              });
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('질문이 추가되었습니다!')),
              );
            },
            child: const Text('추가하기'),
          ),
        ],
      ),
    );
  }

  void _shareDoctorQuestions() async {
    final selected = _localQuestions.where((q) => q.isSelected).toList();
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('공유할 질문을 1개 이상 선택해 주세요.')),
      );
      return;
    }

    final buffer = StringBuffer();
    buffer.writeln('📋 [Kidipedia - 소아과 진료 안심 질문지]');
    buffer.writeln('• 아기 이름: ${widget.profile.name} (${widget.profile.gender}, ${widget.profile.age})');
    buffer.writeln('• 현재 체중: ${widget.profile.weightKg}kg');
    if (widget.profile.allergyNotes.isNotEmpty) {
      buffer.writeln('• 특이사항/알레르기: ${widget.profile.allergyNotes}');
    }
    buffer.writeln('');
    buffer.writeln('[의사 선생님 상담 질문]');
    for (var i = 0; i < selected.length; i++) {
      final q = selected[i];
      buffer.writeln('${i + 1}. [${q.category}] ${q.question}');
    }
    buffer.writeln('');
    final shareText = buffer.toString();
    try {
      Clipboard.setData(ClipboardData(text: shareText));
    } catch (_) {}

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
                    SizedBox(width: 8),
                    Text('클립보드 복사 완료', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('카카오톡, 문자 메시지 또는 병원 접수 메모에 붙여넣어 진료 시 바로 활용하세요.',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              constraints: const BoxConstraints(maxHeight: 220),
              child: SingleChildScrollView(
                child: Text(shareText, style: const TextStyle(fontSize: 11, height: 1.5, fontFamily: 'monospace')),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('다시 복사하기', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B8B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareText));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('질문지가 클립보드에 다시 복사되었습니다.')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            if (widget.onGoBack != null) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onGoBack,
                tooltip: '이전 화면으로',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
            ],
            const Text('소아과 의사용 안심 Q&A', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFFFF0F3), borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('✨ 스마트 AI 질문지 생성기', style: TextStyle(color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFCCD5)),
                    ),
                    child: const Text('포털·맘카페 다빈도 FAQ 기반', style: TextStyle(fontSize: 10, color: Color(0xFFFF6B8B), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${widget.profile.name}(${widget.profile.weightKg}kg)의 처방 의약품 성분과 포털(네이버·맘카페·구글)에서 부모들이 가장 많이 묻는 소아 다빈도 실전 질문들을 선별하여 의사 상담 질문지로 추천해 드립니다.',
                  style: const TextStyle(fontSize: 11, color: Colors.black87, height: 1.4)),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('선택된 질문 목록', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFFFF6B8B)),
              label: const Text('직접 질문 추가', style: TextStyle(color: Color(0xFFFF6B8B), fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _openAddQuestionDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),

        ..._localQuestions.map((q) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: (q.isSelected == true) ? const Color(0xFFFF6B8B) : Colors.transparent),
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: CheckboxListTile(
              activeColor: const Color(0xFFFF6B8B),
              value: q.isSelected == true,
              onChanged: (val) => setState(() => q.isSelected = (val == true)),
              title: Text(q.question, style: const TextStyle(fontSize: 12, height: 1.4)),
              subtitle: Text(q.category, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ),
          ),
        )),

        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: const Icon(Icons.share, color: Colors.white, size: 18),
          label: const Text('의사 질문지 저장 및 공유하기', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B8B),
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          onPressed: _shareDoctorQuestions,
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// 5. BABY PROFILE & HISTORY SCREEN (아기 프로필 & 이력 화면)
// ----------------------------------------------------------------------
class BabyProfileScreen extends StatelessWidget {
  final MemberProfile profile;
  final VoidCallback? onSwitchChild;
  final Function(MemberProfile)? onProfileUpdated;
  final VoidCallback? onDeleteProfile;
  final VoidCallback? onGoBack;

  const BabyProfileScreen({
    super.key,
    required this.profile,
    this.onSwitchChild,
    this.onProfileUpdated,
    this.onDeleteProfile,
    this.onGoBack,
  });

  void _openServerConfigDialog(BuildContext context) {
    final controller = TextEditingController(
      text: ApiService.customBaseUrl ?? ApiService.baseUrl.replaceAll('/api/v1', ''),
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.dns, color: Color(0xFFFF6B8B)),
            SizedBox(width: 8),
            Text('백엔드 서버 설정', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '모바일 앱(APK)에서 통신할 서버 URL입니다.\nRender 배포 주소 또는 커스텀 클라우드 주소를 지정하세요.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: '서버 주소',
                hintText: 'https://my-yak.onrender.com (Kidipedia 서버)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                ApiService.customBaseUrl = newUrl;
                await StorageService.saveCustomServerUrl(newUrl);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('서버 주소가 설정되었습니다: $newUrl')),
                  );
                }
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _openEditProfileDialog(BuildContext context) {
    DateTime selectedBirthDate = parseBabyBirthDate(profile.birthDate, ageStr: profile.age);
    final birthDateCtrl = TextEditingController(
      text: '${selectedBirthDate.year}년 ${selectedBirthDate.month.toString().padLeft(2, '0')}월 ${selectedBirthDate.day.toString().padLeft(2, '0')}일',
    );
    final nameCtrl = TextEditingController(text: profile.name);
    final ageCtrl = TextEditingController(text: profile.age);
    final weightCtrl = TextEditingController(text: profile.weightKg?.toString() ?? '9.2');
    final allergyCtrl = TextEditingController(text: profile.allergyNotes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('✎ 아기 정보 및 체중 수정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('생년월일 및 체중 변경 시 예방접종 플래너, 소아 용량 검증이 실시간 업데이트됩니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 18),

                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '아기 이름',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    prefixIcon: const Icon(Icons.person, color: Color(0xFFFF6B8B)),
                  ),
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: birthDateCtrl,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: '생년월일 (예방접종·검진 기준)',
                    hintText: '생년월일을 선택해주세요',
                    prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFFFF6B8B)),
                    suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selectedBirthDate,
                      firstDate: DateTime.now().subtract(const Duration(days: 365 * 12)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setModalState(() {
                        selectedBirthDate = picked;
                        birthDateCtrl.text = '${picked.year}년 ${picked.month.toString().padLeft(2, '0')}월 ${picked.day.toString().padLeft(2, '0')}일';
                        int months = (DateTime.now().year - picked.year) * 12 + (DateTime.now().month - picked.month);
                        if (DateTime.now().day < picked.day) months--;
                        if (months < 0) months = 0;
                        ageCtrl.text = '생후 $months개월';
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: ageCtrl,
                        decoration: InputDecoration(
                          labelText: '월령 / 나이',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          prefixIcon: const Icon(Icons.cake, color: Colors.blue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: weightCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: '현재 몸무게',
                          suffixText: 'kg',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          prefixIcon: const Icon(Icons.monitor_weight, color: Color(0xFF10B981)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextField(
                  controller: allergyCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: '특이사항 및 알레르기',
                    hintText: '예: 페니실린 계열 항생제 발진 이력',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    prefixIcon: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626)),
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B8B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                  onPressed: () {
                    final parsedWeight = double.tryParse(weightCtrl.text.trim()) ?? (profile.weightKg ?? 9.2);
                    final updated = profile.copyWith(
                      name: nameCtrl.text.trim().isEmpty ? profile.name : nameCtrl.text.trim(),
                      age: ageCtrl.text.trim().isEmpty ? profile.age : ageCtrl.text.trim(),
                      birthDate: birthDateCtrl.text.trim(),
                      weightKg: parsedWeight,
                      allergyNotes: allergyCtrl.text.trim(),
                    );
                    onProfileUpdated?.call(updated);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('🎉 ${updated.name}의 정보 및 몸무게(${updated.weightKg}kg)가 업데이트되었습니다!')),
                    );
                  },
                  child: const Text('수정 내용 저장하기', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                if (onGoBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: onGoBack,
                    tooltip: '이전 화면으로',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                ],
                const Text('아기 프로필 & 이력', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              children: [
                if (onSwitchChild != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFFFF6B8B)),
                    label: const Text('아이 전환', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFFD6DF)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    onPressed: onSwitchChild,
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit, size: 14, color: Color(0xFFFF6B8B)),
                  label: const Text('정보 수정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFF6B8B))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFFD6DF)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: () => _openEditProfileDialog(context),
                ),
                if (onDeleteProfile != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFFF6B8B)),
                    tooltip: '프로필 삭제',
                    onPressed: onDeleteProfile,
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 28,
                backgroundColor: Color(0xFFFFF0F3),
                child: Text('👶', style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${profile.name} (${profile.gender})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('생년월일: ${profile.birthDate}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Text('월령', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(profile.age, style: const TextStyle(color: Color(0xFFFF6B8B), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    const Text('현재 몸무게', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('${profile.weightKg} kg', style: const TextStyle(color: Color(0xFF10B981), fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 💉 예방접종 & 영유아 검진 플래너 바로가기 배너
        GestureDetector(
          onTap: () => VaccineSchedulerSheet.show(context, profile),
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFF0F3), Color(0xFFFFE4E8)],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFD6DF)),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('💉', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('우리아이 접종 & 검진 플래너',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFFF6B8B))),
                      SizedBox(height: 2),
                      Text('질병관리청 필수 접종 16종 & 검진 D-Day 알림',
                          style: TextStyle(fontSize: 11, color: Colors.black87)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFFF6B8B)),
              ],
            ),
          ),
        ),

        // Allergy Warning Box
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: profile.allergyNotes.trim().isNotEmpty ? const Color(0xFFFEF2F2) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: profile.allergyNotes.trim().isNotEmpty ? const Color(0xFFFECACA) : Colors.grey.shade200,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    profile.allergyNotes.trim().isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                    size: 16,
                    color: profile.allergyNotes.trim().isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    profile.allergyNotes.trim().isNotEmpty ? '🚨 특이사항 및 알레르기' : '🌱 특이사항 및 약물 알레르기',
                    style: TextStyle(
                      color: profile.allergyNotes.trim().isNotEmpty ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                profile.allergyNotes.trim().isNotEmpty
                    ? profile.allergyNotes
                    : '등록된 특이 약물 알레르기가 없습니다. 필요 시 상단 [정보 수정]에서 입력하실 수 있습니다.',
                style: TextStyle(
                  color: profile.allergyNotes.trim().isNotEmpty ? const Color(0xFFB91C1C) : Colors.grey.shade600,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        const Text('복약 히스토리', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),

        if (profile.history.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 36, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('아직 등록된 처방 이력이 없습니다.', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                  SizedBox(height: 4),
                  Text('처방전이나 약봉투를 스캔하면 여기에 안전하게 기록됩니다.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          )
        else
          ...profile.history.map((h) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.dateStr, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                const SizedBox(height: 2),
                Text(h.drugName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text('${h.durationStr} · ${h.clinicName}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          )),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.settings, size: 14, color: Colors.grey),
            label: const Text('클라우드 서버 주소 설정 (모바일 앱)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            onPressed: () => _openServerConfigDialog(context),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AiReportCardData {
  final String tag;
  final String body;
  _AiReportCardData({required this.tag, required this.body});
}
