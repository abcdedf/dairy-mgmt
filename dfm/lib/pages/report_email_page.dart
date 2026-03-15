// lib/pages/report_email_page.dart

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/report_email_controller.dart';
import 'shared_widgets.dart';

class ReportEmailPage extends StatefulWidget {
  const ReportEmailPage({super.key});

  @override
  State<ReportEmailPage> createState() => _ReportEmailPageState();
}

class _ReportEmailPageState extends State<ReportEmailPage> {
  late ReportEmailController ctrl;

  @override
  void initState() {
    super.initState();
    Get.delete<ReportEmailController>(force: true);
    ctrl = Get.put(ReportEmailController());
  }

  @override
  void dispose() {
    Get.delete<ReportEmailController>(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(titleWithLocation('Email Schedules'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kNavy,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: kNavy,
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => _showDialog(context, null),
      ),
      body: Obx(() {
        if (ctrl.isLoading.value) return const LoadingCenter();

        if (ctrl.successMsg.value.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final msg = ctrl.successMsg.value;
            ctrl.successMsg.value = '';
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: kGreen));
          });
        }
        if (ctrl.errorMessage.value.isNotEmpty && !ctrl.isSaving.value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final msg = ctrl.errorMessage.value;
            ctrl.errorMessage.value = '';
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(msg), backgroundColor: kRed));
          });
        }

        if (ctrl.schedules.isEmpty) {
          return const Center(child: EmptyState(
            icon: Icons.email_outlined,
            message: 'No email schedules configured.',
          ));
        }
        return RefreshIndicator(
          onRefresh: ctrl.load,
          child: ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: ctrl.schedules.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _ScheduleCard(
              schedule: ctrl.schedules[i],
              onEdit: () => _showDialog(context, ctrl.schedules[i]),
              onDelete: () => _confirmDelete(context, ctrl.schedules[i]),
              onTestSend: () => _testSend(ctrl.schedules[i]),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _testSend(ReportEmailSchedule s) async {
    await ctrl.testSend(s.id);
  }

  void _confirmDelete(BuildContext context, ReportEmailSchedule s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text('Delete "${s.reportLabel}" email schedule?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () { Navigator.pop(ctx); ctrl.delete(s.id); },
            child: const Text('Delete', style: TextStyle(color: kRed)),
          ),
        ],
      ),
    );
  }

  void _showDialog(BuildContext context, ReportEmailSchedule? existing) {
    final isEdit = existing != null;
    String reportKey = existing?.reportKey ?? '';
    String emails = existing?.emails ?? '';
    String frequency = existing?.frequency ?? 'daily';
    int? dayOfWeek = existing?.dayOfWeek ?? 1;
    int? dayOfMonth = existing?.dayOfMonth ?? 1;
    int timeHour = existing?.timeHour ?? 8;
    int? locationId = existing?.locationId;
    int dateRangeDays = existing?.dateRangeDays ?? 7;
    bool isActive = existing?.isActive ?? true;

    final emailCtrl = TextEditingController(text: emails);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Schedule' : 'New Schedule'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Report dropdown
                  DropdownButtonFormField<String>(
                    initialValue: ctrl.reports.any((r) => r.key == reportKey) ? reportKey : null,
                    decoration: const InputDecoration(labelText: 'Report', border: OutlineInputBorder()),
                    items: ctrl.reports.map((r) => DropdownMenuItem(
                      value: r.key, child: Text(r.label, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => reportKey = v ?? ''),
                  ),
                  const SizedBox(height: 12),

                  // Emails
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Recipient Emails',
                      hintText: 'a@x.com, b@x.com',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                    onChanged: (v) => emails = v,
                  ),
                  const SizedBox(height: 12),

                  // Frequency
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(labelText: 'Frequency', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'daily', child: Text('Daily')),
                      DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                    ],
                    onChanged: (v) => setDialogState(() => frequency = v ?? 'daily'),
                  ),
                  const SizedBox(height: 12),

                  // Day of week (weekly only)
                  if (frequency == 'weekly') ...[
                    DropdownButtonFormField<int>(
                      initialValue: dayOfWeek,
                      decoration: const InputDecoration(labelText: 'Day of Week', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Sunday')),
                        DropdownMenuItem(value: 1, child: Text('Monday')),
                        DropdownMenuItem(value: 2, child: Text('Tuesday')),
                        DropdownMenuItem(value: 3, child: Text('Wednesday')),
                        DropdownMenuItem(value: 4, child: Text('Thursday')),
                        DropdownMenuItem(value: 5, child: Text('Friday')),
                        DropdownMenuItem(value: 6, child: Text('Saturday')),
                      ],
                      onChanged: (v) => setDialogState(() => dayOfWeek = v),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Day of month (monthly only)
                  if (frequency == 'monthly') ...[
                    DropdownButtonFormField<int>(
                      initialValue: dayOfMonth,
                      decoration: const InputDecoration(labelText: 'Day of Month', border: OutlineInputBorder()),
                      items: List.generate(28, (i) => DropdownMenuItem(
                        value: i + 1, child: Text('${i + 1}'),
                      )),
                      onChanged: (v) => setDialogState(() => dayOfMonth = v),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Time hour
                  DropdownButtonFormField<int>(
                    initialValue: timeHour,
                    decoration: const InputDecoration(labelText: 'Send Hour (IST)', border: OutlineInputBorder()),
                    items: List.generate(24, (i) => DropdownMenuItem(
                      value: i,
                      child: Text('${i.toString().padLeft(2, '0')}:00'),
                    )),
                    onChanged: (v) => setDialogState(() => timeHour = v ?? 8),
                  ),
                  const SizedBox(height: 12),

                  // Location
                  DropdownButtonFormField<int?>(
                    initialValue: locationId,
                    decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All Locations')),
                      ...ctrl.locations.map((l) => DropdownMenuItem<int?>(
                        value: l.id, child: Text(l.name),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => locationId = v),
                  ),
                  const SizedBox(height: 12),

                  // Date range
                  DropdownButtonFormField<int>(
                    initialValue: dateRangeDays,
                    decoration: const InputDecoration(labelText: 'Date Range', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 7, child: Text('Last 7 days')),
                      DropdownMenuItem(value: 14, child: Text('Last 14 days')),
                      DropdownMenuItem(value: 30, child: Text('Last 30 days')),
                      DropdownMenuItem(value: 60, child: Text('Last 60 days')),
                      DropdownMenuItem(value: 90, child: Text('Last 90 days')),
                    ],
                    onChanged: (v) => setDialogState(() => dateRangeDays = v ?? 7),
                  ),
                  const SizedBox(height: 12),

                  // Active toggle
                  SwitchListTile(
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (v) => setDialogState(() => isActive = v),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              )),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              Obx(() => ElevatedButton(
                onPressed: ctrl.isSaving.value ? null : () async {
                  emails = emailCtrl.text.trim();
                  if (reportKey.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a report.'), backgroundColor: kRed));
                    return;
                  }
                  if (emails.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter at least one email.'), backgroundColor: kRed));
                    return;
                  }
                  final ok = await ctrl.save(
                    id: existing?.id,
                    reportKey: reportKey,
                    emails: emails,
                    frequency: frequency,
                    dayOfWeek: dayOfWeek,
                    dayOfMonth: dayOfMonth,
                    timeHour: timeHour,
                    locationId: locationId,
                    dateRangeDays: dateRangeDays,
                    isActive: isActive,
                  );
                  if (ok && ctx.mounted) Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(backgroundColor: kNavy),
                child: ctrl.isSaving.value
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(isEdit ? 'Update' : 'Create',
                        style: const TextStyle(color: Colors.white)),
              )),
            ],
          );
        });
      },
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final ReportEmailSchedule schedule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTestSend;

  const _ScheduleCard({
    required this.schedule,
    required this.onEdit,
    required this.onDelete,
    required this.onTestSend,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(
                schedule.reportLabel.isNotEmpty ? schedule.reportLabel : schedule.reportKey,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: schedule.isActive ? kGreen.withValues(alpha: 0.12) : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  schedule.isActive ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: schedule.isActive ? kGreen : Colors.grey.shade600,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            _info(Icons.schedule, schedule.frequencyLabel),
            const SizedBox(height: 4),
            _info(Icons.email_outlined, schedule.emails),
            const SizedBox(height: 4),
            _info(Icons.location_on_outlined,
                schedule.locationName.isNotEmpty ? schedule.locationName : 'All Locations'),
            const SizedBox(height: 4),
            _info(Icons.date_range, 'Last ${schedule.dateRangeDays} days'),
            if (schedule.lastSentAt != null) ...[
              const SizedBox(height: 4),
              _info(Icons.check_circle_outline, 'Last sent: ${schedule.lastSentAt}'),
            ],
            const Divider(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: onTestSend,
                icon: const Icon(Icons.send, size: 16),
                label: const Text('Test Send'),
                style: TextButton.styleFrom(foregroundColor: kNavy),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: kNavy),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: kRed),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.grey.shade500),
      const SizedBox(width: 6),
      Expanded(child: Text(text,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          overflow: TextOverflow.ellipsis, maxLines: 2)),
    ]);
  }
}
