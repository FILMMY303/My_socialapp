import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/time_ago.dart';
import '../../data/models/models.dart';
import '../../data/repository_scope.dart';
import '../navigation.dart';
import '../widgets/common_widgets.dart';
import '../widgets/media_view.dart';

/// Reports on posts in a group, for its owner and staff to review.
class GroupReportsScreen extends StatefulWidget {
  const GroupReportsScreen({super.key, required this.group});

  final Group group;

  @override
  State<GroupReportsScreen> createState() => _GroupReportsScreenState();
}

class _GroupReportsScreenState extends State<GroupReportsScreen> {
  Future<List<GroupReport>>? _future;
  final _busy = <String>{};

  AppServices get _services => RepositoryScope.servicesOf(context);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _services.groups.reports(widget.group.id);
  }

  Future<void> _reload() async {
    final future = _services.groups.reports(widget.group.id);
    setState(() {
      _future = future;
    });
    await future.catchError((_) => <GroupReport>[]);
  }

  Future<void> _act(GroupReport report, {required bool remove}) async {
    if (remove) {
      final confirmed = await confirmDelete(context, 'post');
      if (!confirmed || !mounted) return;
    }
    final services = _services;
    setState(() => _busy.add(report.id));
    try {
      if (remove) {
        await services.groups.removeReportedPost(report);
        // Drop it from the cached group feed too.
        await services.repository
            .refresh(FeedScope.group(widget.group.id))
            .catchError((_) {});
      } else {
        await services.groups.dismissReport(report);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(remove ? 'Post removed.' : 'Report dismissed.')),
      );
      await _reload();
    } catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCream,
      appBar: AppBar(
        backgroundColor: kCream,
        title: Text('Reports · ${widget.group.name}'),
      ),
      body: FutureBuilder<List<GroupReport>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorRetry(
              message: errorMessage(snapshot.error!),
              onRetry: _reload,
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: kGreen),
            );
          }
          final reports = snapshot.data!;
          return RefreshIndicator(
            color: kGreen,
            onRefresh: _reload,
            child: reports.isEmpty
                ? ListView(
                    children: [
                      SizedBox(height: 120),
                      Icon(
                        Icons.verified_user_outlined,
                        size: 40,
                        color: kGreen,
                      ),
                      SizedBox(height: 8),
                      Center(
                        child: Text(
                          'No reports to review.',
                          style: TextStyle(color: kSecondaryText),
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) => _ReportCard(
                      report: reports[index],
                      busy: _busy.contains(reports[index].id),
                      onRemove: () => _act(reports[index], remove: true),
                      onDismiss: () => _act(reports[index], remove: false),
                    ),
                  ),
          );
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onRemove,
    required this.onDismiss,
  });

  final GroupReport report;
  final bool busy;
  final VoidCallback onRemove;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reporter = report.reporter;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCardWhite,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.flag_rounded, color: kRed, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  report.reason.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kRed,
                  ),
                ),
              ),
              Text(
                timeAgo(report.createdAt),
                style: TextStyle(fontSize: 11, color: kMuted),
              ),
            ],
          ),
          if (report.details != null) ...[
            const SizedBox(height: 4),
            Text('"${report.details!}"'),
          ],
          if (reporter != null)
            InkWell(
              onTap: () => openProfile(context, reporter.id),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Reported by ${reporter.name}',
                  style: TextStyle(fontSize: 12, color: kSecondaryText),
                ),
              ),
            ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => openPost(context, report.postId),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7FB),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.postAuthor ?? 'Post',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (report.postContent?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      report.postContent!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (report.postMedia != null) ...[
                    const SizedBox(height: 6),
                    MediaView(
                      url: report.postMedia!.url,
                      type: report.postMedia!.type,
                      maxHeight: 160,
                      borderRadius: 10,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          busy
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onDismiss,
                      child: const Text('Keep post'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onRemove,
                      style: FilledButton.styleFrom(backgroundColor: kRed),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove post'),
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}
