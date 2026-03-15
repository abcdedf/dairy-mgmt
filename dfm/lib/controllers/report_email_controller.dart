// lib/controllers/report_email_controller.dart

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../core/api_client.dart';

class ReportEmailSchedule {
  final int id;
  final String reportKey;
  final String reportLabel;
  final String emails;
  final String frequency;
  final int? dayOfWeek;
  final int? dayOfMonth;
  final int timeHour;
  final int? locationId;
  final String locationName;
  final int dateRangeDays;
  final bool isActive;
  final String? lastSentAt;

  const ReportEmailSchedule({
    required this.id,
    required this.reportKey,
    required this.reportLabel,
    required this.emails,
    required this.frequency,
    this.dayOfWeek,
    this.dayOfMonth,
    required this.timeHour,
    this.locationId,
    required this.locationName,
    required this.dateRangeDays,
    required this.isActive,
    this.lastSentAt,
  });

  factory ReportEmailSchedule.fromJson(Map<String, dynamic> j) {
    int? tryInt(String k) {
      final v = j[k];
      if (v == null) return null;
      return int.tryParse(v.toString());
    }
    return ReportEmailSchedule(
      id: int.parse(j['id'].toString()),
      reportKey: j['report_key']?.toString() ?? '',
      reportLabel: j['report_label']?.toString() ?? '',
      emails: j['emails']?.toString() ?? '',
      frequency: j['frequency']?.toString() ?? 'daily',
      dayOfWeek: tryInt('day_of_week'),
      dayOfMonth: tryInt('day_of_month'),
      timeHour: int.tryParse(j['time_hour']?.toString() ?? '8') ?? 8,
      locationId: tryInt('location_id'),
      locationName: j['location_name']?.toString() ?? '',
      dateRangeDays: int.tryParse(j['date_range_days']?.toString() ?? '7') ?? 7,
      isActive: j['is_active']?.toString() != '0',
      lastSentAt: j['last_sent_at']?.toString(),
    );
  }

  String get frequencyLabel {
    switch (frequency) {
      case 'daily': return 'Daily at ${timeHour.toString().padLeft(2, '0')}:00';
      case 'weekly':
        const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        final day = (dayOfWeek != null && dayOfWeek! >= 0 && dayOfWeek! <= 6)
            ? days[dayOfWeek!] : '?';
        return 'Weekly on $day at ${timeHour.toString().padLeft(2, '0')}:00';
      case 'monthly':
        return 'Monthly on day $dayOfMonth at ${timeHour.toString().padLeft(2, '0')}:00';
      default: return frequency;
    }
  }
}

class ReportOption {
  final String key;
  final String label;
  const ReportOption({required this.key, required this.label});
}

class LocationOption {
  final int id;
  final String name;
  const LocationOption({required this.id, required this.name});
}

class ReportEmailController extends GetxController {
  final isLoading    = false.obs;
  final isSaving     = false.obs;
  final isSending    = false.obs;
  final errorMessage = ''.obs;
  final successMsg   = ''.obs;
  final schedules    = <ReportEmailSchedule>[].obs;
  final reports      = <ReportOption>[].obs;
  final locations    = <LocationOption>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final res = await ApiClient.get('/report-email-schedules');
      isLoading.value = false;
      if (!res.ok) {
        errorMessage.value = res.message ?? 'Failed to load schedules.';
        return;
      }
      schedules.value = (res.data['schedules'] as List)
          .map((e) => ReportEmailSchedule.fromJson(e as Map<String, dynamic>))
          .toList();
      reports.value = (res.data['reports'] as List)
          .map((e) => ReportOption(
              key: e['key'].toString(), label: e['label'].toString()))
          .toList();
      locations.value = (res.data['locations'] as List)
          .map((e) => LocationOption(
              id: int.parse(e['id'].toString()), name: e['name'].toString()))
          .toList();
    } catch (e, st) {
      isLoading.value = false;
      errorMessage.value = 'Unexpected error.';
      debugPrint('[ReportEmailController] load error: $e\n$st');
    }
  }

  Future<bool> save({
    int? id,
    required String reportKey,
    required String emails,
    required String frequency,
    int? dayOfWeek,
    int? dayOfMonth,
    required int timeHour,
    int? locationId,
    required int dateRangeDays,
    required bool isActive,
  }) async {
    isSaving.value = true;
    errorMessage.value = '';
    successMsg.value = '';
    final body = <String, dynamic>{
      'report_key': reportKey,
      'emails': emails,
      'frequency': frequency,
      'time_hour': timeHour,
      'date_range_days': dateRangeDays,
      'is_active': isActive ? 1 : 0,
    };
    if (id != null && id > 0) body['id'] = id;
    if (frequency == 'weekly') body['day_of_week'] = dayOfWeek;
    if (frequency == 'monthly') body['day_of_month'] = dayOfMonth;
    if (locationId != null) body['location_id'] = locationId;

    final res = await ApiClient.post('/report-email-schedule', body);
    isSaving.value = false;
    if (res.ok) {
      successMsg.value = id != null ? 'Schedule updated.' : 'Schedule created.';
      await load();
      return true;
    }
    errorMessage.value = res.message ?? 'Save failed.';
    return false;
  }

  Future<bool> delete(int id) async {
    errorMessage.value = '';
    successMsg.value = '';
    final res = await ApiClient.delete('/report-email-schedule/$id');
    if (res.ok) {
      successMsg.value = 'Schedule deleted.';
      await load();
      return true;
    }
    errorMessage.value = res.message ?? 'Delete failed.';
    return false;
  }

  Future<bool> testSend(int id) async {
    isSending.value = true;
    errorMessage.value = '';
    successMsg.value = '';
    final res = await ApiClient.post('/report-email-schedule/$id/send', {});
    isSending.value = false;
    if (res.ok) {
      successMsg.value = 'Test email sent successfully.';
      return true;
    }
    errorMessage.value = res.message ?? 'Failed to send test email.';
    return false;
  }
}
