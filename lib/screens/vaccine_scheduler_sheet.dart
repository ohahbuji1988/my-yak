import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../models/vaccine_schedule.dart';
import '../services/storage_service.dart';

class VaccineSchedulerSheet extends StatefulWidget {
  final MemberProfile profile;

  const VaccineSchedulerSheet({super.key, required this.profile});

  static void show(BuildContext context, MemberProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VaccineSchedulerSheet(profile: profile),
    );
  }

  @override
  State<VaccineSchedulerSheet> createState() => _VaccineSchedulerSheetState();
}

class _VaccineSchedulerSheetState extends State<VaccineSchedulerSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late DateTime _birthDate;
  List<String> _completedIds = [];
  bool _alarmEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _birthDate = parseBabyBirthDate(widget.profile.birthDate, ageStr: widget.profile.age);
    _loadData();
  }

  Future<void> _loadData() async {
    final completed = await StorageService.loadCompletedVaccines(widget.profile.id);
    final alarm = await StorageService.loadVaccineAlarmEnabled(widget.profile.id);
    if (mounted) {
      setState(() {
        _completedIds = completed;
        _alarmEnabled = alarm;
        _isLoading = false;
      });
    }
  }

  void _toggleComplete(String id) {
    setState(() {
      if (_completedIds.contains(id)) {
        _completedIds.remove(id);
      } else {
        _completedIds.add(id);
      }
    });
    StorageService.saveCompletedVaccines(widget.profile.id, _completedIds);
  }

  void _toggleAlarm(bool val) {
    setState(() {
      _alarmEnabled = val;
    });
    StorageService.saveVaccineAlarmEnabled(widget.profile.id, val);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(val ? '🔔 접종 7일 전 및 당일 알림이 설정되었습니다.' : '🔕 접종 알림이 해제되었습니다.'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaccines = standardSchedules.where((s) => !s.isCheckup).toList();
    final checkups = standardSchedules.where((s) => s.isCheckup).toList();

    final completedCount = standardSchedules.where((s) => _completedIds.contains(s.id)).length;
    final upcomingCount = standardSchedules.where((s) {
      if (_completedIds.contains(s.id)) return false;
      final dday = s.getDDay(_birthDate);
      return dday >= -90 && dday <= 30;
    }).length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFFFAF9F6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
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
                      child: const Text('💉', style: TextStyle(fontSize: 22)),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('우리아이 접종 & 검진 플래너',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('${widget.profile.name} (${widget.profile.age} · ${_birthDate.year}.${_birthDate.month.toString().padLeft(2, '0')}.${_birthDate.day.toString().padLeft(2, '0')} 출생)',
                            style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 🔔 Alarm & Summary Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF0F3), Color(0xFFFFEBF0)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFFFD6DF)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active, color: Color(0xFFFF6B8B), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('다가오는 검진·접종 알림', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            Text('예정일 7일 전과 당일에 알림을 보내드려요', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _alarmEnabled,
                        activeThumbColor: const Color(0xFFFF6B8B),
                        activeTrackColor: const Color(0xFFFFD6DF),
                        onChanged: _toggleAlarm,
                      ),
                    ],
                  ),
                  const Divider(height: 16, color: Color(0xFFFFD6DF)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryStat('지금/임박 일정', '$upcomingCount건', const Color(0xFFFF6B8B)),
                      Container(width: 1, height: 24, color: Colors.grey.shade300),
                      _buildSummaryStat('접종 완료', '$completedCount / ${standardSchedules.length}', const Color(0xFF10B981)),
                      Container(width: 1, height: 24, color: Colors.grey.shade300),
                      _buildSummaryStat('진행률', '${(completedCount / standardSchedules.length * 100).toInt()}%', const Color(0xFF3B82F6)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Tab Bar
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFFF6B8B),
            labelColor: const Color(0xFFFF6B8B),
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            tabs: [
              Tab(text: '💉 필수 예방접종 (${vaccines.length})'),
              Tab(text: '🩺 영유아 건강검진 (${checkups.length})'),
            ],
          ),

          // Tab View
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildScheduleList(vaccines),
                      _buildScheduleList(checkups),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
      ],
    );
  }

  Widget _buildScheduleList(List<VaccineItem> allItems) {
    // 90일 경과(지연) 미접종 항목은 자동 숨김 필터링
    final items = allItems.where((item) {
      final isDone = _completedIds.contains(item.id);
      if (isDone) return true;
      final dday = item.getDDay(_birthDate);
      if (dday < -90) return false; // 90일 초과 지연 숨김
      return true;
    }).toList();

    final hiddenCount = allItems.length - items.length;

    return Column(
      children: [
        if (hiddenCount > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '권장 시기가 90일 이상 지난 미접종 $hiddenCount건은 자동 숨김 처리되었습니다.',
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];
              final isDone = _completedIds.contains(item.id);
              final dueDate = item.getRecommendedDate(_birthDate);
              final dday = item.getDDay(_birthDate);
              final overdue = -dday;

              // 사용자 지정 기준에 따른 색상 및 뱃지 스타일링
              Color badgeBg = Colors.grey.shade100;
              Color badgeFg = Colors.grey.shade700;
              Gradient? badgeGradient;
              String badgeText = 'D-$dday';
              Color cardBg = Colors.white;
              Color cardBorder = Colors.grey.shade200;
              double cardBorderWidth = 1.0;

              if (isDone) {
                badgeBg = const Color(0xFFECFDF5);
                badgeFg = const Color(0xFF059669);
                badgeText = '✅ 접종 완료';
              } else if (dday == 0) {
                badgeBg = const Color(0xFFFEF2F2);
                badgeFg = const Color(0xFFDC2626);
                badgeText = '🔥 오늘 접종 권장';
                cardBorder = const Color(0xFFDC2626);
                cardBorderWidth = 1.5;
              } else if (dday > 0) {
                badgeBg = dday <= 14 ? const Color(0xFFFFF0F3) : Colors.grey.shade100;
                badgeFg = dday <= 14 ? const Color(0xFFFF6B8B) : Colors.grey.shade700;
                badgeText = dday <= 14 ? 'D-$dday (임박)' : 'D-$dday';
                if (dday <= 14) {
                  cardBorder = const Color(0xFFFF6B8B).withValues(alpha: 0.5);
                  cardBorderWidth = 1.2;
                }
              } else {
                // dday < 0 (미접종 지연)
                if (overdue > 30) {
                  // 60일 경과 (31~90일): 빨간색 + 검은색 + 보라색 조합
                  badgeGradient = const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFF111827), Color(0xFFDC2626)],
                  );
                  badgeFg = Colors.white;
                  badgeText = '⚠️ 60일 지연 (+$overdue일)';
                  cardBg = const Color(0xFFFAF5FF);
                  cardBorder = const Color(0xFF7C3AED);
                  cardBorderWidth = 1.8;
                } else if (overdue > 15) {
                  // 30일 경과 (16~30일): 빨간색
                  badgeBg = const Color(0xFFFEE2E2);
                  badgeFg = const Color(0xFFDC2626);
                  badgeText = '🚨 30일 지연 (+$overdue일)';
                  cardBg = const Color(0xFFFFF5F5);
                  cardBorder = const Color(0xFFDC2626);
                  cardBorderWidth = 1.5;
                } else {
                  // 15일 경과 (1~15일): 노란색
                  badgeBg = const Color(0xFFFEF3C7);
                  badgeFg = const Color(0xFFD97706);
                  badgeText = '⏰ 15일 경과 (+$overdue일)';
                  cardBg = const Color(0xFFFFFDF5);
                  cardBorder = const Color(0xFFF59E0B);
                  cardBorderWidth = 1.3;
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDone ? Colors.grey.shade200 : cardBorder,
                    width: isDone ? 1.0 : cardBorderWidth,
                  ),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(
                              color: badgeGradient == null ? badgeBg : null,
                              gradient: badgeGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: badgeFg),
                            ),
                          ),
                          Text(
                            '권장: ${dueDate.year}.${dueDate.month.toString().padLeft(2, '0')}.${dueDate.day.toString().padLeft(2, '0')}',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    decoration: isDone ? TextDecoration.lineThrough : null,
                                    color: isDone ? Colors.grey : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  item.monthRangeLabel,
                                  style: const TextStyle(fontSize: 11, color: Color(0xFFFF6B8B), fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isDone ? const Color(0xFF10B981) : Colors.grey.shade400,
                              size: 26,
                            ),
                            onPressed: () => _toggleComplete(item.id),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('🎯 ', style: TextStyle(fontSize: 11)),
                                Expanded(
                                  child: Text(item.targetDisease, style: const TextStyle(fontSize: 11, color: Colors.black87)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('💡 ', style: TextStyle(fontSize: 11)),
                                Expanded(
                                  child: Text(item.precautions, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
