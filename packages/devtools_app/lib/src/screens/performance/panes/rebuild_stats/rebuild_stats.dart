// Copyright 2022 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/service.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../service/service_extension_widgets.dart';
import '../../../../service/service_extensions.dart' as extensions;
import '../../../../service/vm_service_wrapper.dart';
import '../../../../shared/analytics/constants.dart' as gac;
import '../../../../shared/globals.dart';
import '../../../../shared/primitives/utils.dart';
import '../../../../shared/table/table.dart';
import '../../../../shared/table/table_data.dart';
import '../../../../shared/ui/common_widgets.dart';
import '../flutter_frames/flutter_frame_model.dart';
import 'rebuild_stats_model.dart';

class RebuildStatsView extends StatefulWidget {
  const RebuildStatsView({
    super.key,
    required this.model,
    required this.selectedFrame,
  });

  final RebuildCountModel model;
  final ValueListenable<FlutterFrame?> selectedFrame;

  @override
  State<RebuildStatsView> createState() => _RebuildStatsViewState();
}

class _RebuildStatsViewState extends State<RebuildStatsView>
    with AutoDisposeMixin {
  var metricNames = const <String>[];
  var metrics = const <RebuildLocationStats>[];
  var metricTotals = const <int>[];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant RebuildStatsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model != widget.model ||
        oldWidget.selectedFrame != widget.selectedFrame) {
      cancelListeners();
      _init();
    }
  }

  void _init() {
    addAutoDisposeListener(widget.model.locationStats, computeMetrics);
    addAutoDisposeListener(widget.selectedFrame, computeMetrics);
    computeMetrics();
  }

  void computeMetrics() {
    final names = <String>[];
    final data = <List<RebuildLocation>>[];
    final selectedFrame = widget.selectedFrame.value;

    List<RebuildLocation>? rebuildsForFrame;
    if (selectedFrame != null) {
      rebuildsForFrame = widget.model.rebuildsForFrame(selectedFrame.id);
    }
    if (rebuildsForFrame != null) {
      names.add('Selected frame');
      data.add(rebuildsForFrame);
    } else if (selectedFrame == null) {
      final rebuildsForLastFrame = widget.model.rebuildsForLastFrame;
      if (rebuildsForLastFrame != null) {
        names.add('Latest frame');
        data.add(rebuildsForLastFrame);
      }
    }

    names.add('Overall');
    data.add(widget.model.locationStats.value);

    final totals = data
        .map((list) => list.fold<int>(0, (sum, r) => sum + r.buildCount))
        .toList();

    setState(() {
      metrics = combineStats(data);
      metricNames = names;
      metricTotals = totals;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlineDecoration.onlyBottom(
          child: Padding(
            padding: const EdgeInsets.all(denseSpacing),
            child: Row(
              children: [
                ClearButton(
                  gaScreen: gac.performance,
                  gaSelection: gac.PerformanceEvents.clearRebuildStats.name,
                  onPressed: widget.model.clearAllCounts,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: denseSpacing,
                    ),
                    child: ServiceExtensionCheckbox(
                      serviceExtension: extensions.countWidgetBuilds,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ValueListenableBuilder<ServiceExtensionState>(
            valueListenable: serviceConnection
                .serviceManager
                .serviceExtensionManager
                .getServiceExtensionState(
                  extensions.countWidgetBuilds.extension,
                ),
            builder: (context, state, _) {
              if (metrics.isEmpty && !state.enabled) {
                return const Center(
                  child: Text(
                    'Count widget builds must be enabled to see data.',
                  ),
                );
              }
              if (metrics.isEmpty) {
                return const Center(
                  child: Text('Interact with the app to trigger rebuilds.'),
                );
              }
              return Column(
                children: [
                  if (metricTotals.isNotEmpty && metricTotals.first > 0)
                    _TopBottlenecksBanner(
                      metrics: metrics,
                      metricIndex: 0,
                      total: metricTotals.first,
                      frameLabel: metricNames.first,
                    ),
                  Expanded(
                    child: RebuildTable(
                      key: const Key('Rebuild Table'),
                      metricNames: metricNames,
                      metrics: metrics,
                      metricTotals: metricTotals,
                      includeBorder: false,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Banner showing the top rebuilding widgets for the current frame so users
/// can quickly spot potential performance bottlenecks without scanning the
/// full table.
class _TopBottlenecksBanner extends StatelessWidget {
  const _TopBottlenecksBanner({
    required this.metrics,
    required this.metricIndex,
    required this.total,
    required this.frameLabel,
  });

  final List<RebuildLocationStats> metrics;
  final int metricIndex;
  final int total;
  final String frameLabel;

  @override
  Widget build(BuildContext context) {
    final top = (metrics
              .where((m) => m.buildCounts[metricIndex] > 0)
              .toList()
            ..sort(
              (a, b) => b.buildCounts[metricIndex].compareTo(
                a.buildCounts[metricIndex],
              ),
            ))
        .take(3)
        .toList();

    if (top.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return OutlineDecoration.onlyBottom(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: denseSpacing,
          vertical: denseSpacing,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.trending_up_rounded,
              size: defaultIconSize,
              color: Colors.deepOrange,
            ),
            const SizedBox(width: denseSpacing),
            Text(
              'Top rebuilders ($frameLabel): ',
              style: theme.regularTextStyle.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: denseSpacing,
                children: [
                  for (int i = 0; i < top.length; i++)
                    _BottleneckChip(
                      name: top[i].location.name ?? '<unknown>',
                      count: top[i].buildCounts[metricIndex],
                      share: top[i].buildCounts[metricIndex] / total,
                      showSeparator: i > 0,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottleneckChip extends StatelessWidget {
  const _BottleneckChip({
    required this.name,
    required this.count,
    required this.share,
    required this.showSeparator,
  });

  final String name;
  final int count;
  final double share;
  final bool showSeparator;

  @override
  Widget build(BuildContext context) {
    final pct = (share * 100).round();
    final color =
        share >= 0.5
            ? Colors.red
            : share >= 0.25
            ? Colors.deepOrange
            : Theme.of(context).colorScheme.onSurface;
    return Text(
      '${showSeparator ? '· ' : ''}$name ($count rebuilds, $pct%)',
      style: Theme.of(
        context,
      ).regularTextStyle.copyWith(color: color),
    );
  }
}

class RebuildTable extends StatefulWidget {
  const RebuildTable({
    super.key,
    required this.metricNames,
    required this.metrics,
    this.metricTotals = const [],
    this.includeBorder = true,
  });

  final List<String> metricNames;
  final List<RebuildLocationStats> metrics;

  /// Total rebuild counts per metric column, used to compute percentage share.
  /// When empty, percentage display is suppressed.
  final List<int> metricTotals;

  final bool includeBorder;

  @override
  State<RebuildTable> createState() => _RebuildTableState();
}

class _RebuildTableState extends State<RebuildTable> {
  SortDirection sortDirection = SortDirection.descending;

  /// Cache of columns so we don't confuse the Table by returning different
  /// column objects for the same column.
  final _columnCache = <String, _RebuildCountColumn>{};

  VmServiceWrapper? get _service => serviceConnection.serviceManager.service;

  List<_RebuildCountColumn> get _metricsColumns {
    final columns = <_RebuildCountColumn>[];
    for (var i = 0; i < widget.metricNames.length; i++) {
      final name = widget.metricNames[i];
      var cached = _columnCache[name];
      if (cached == null || cached.metricIndex != i) {
        cached = _RebuildCountColumn(name, i);
        _columnCache[name] = cached;
      }
      // Update total on each build so percentage display stays current.
      cached.total =
          i < widget.metricTotals.length ? widget.metricTotals[i] : 0;
      columns.add(cached);
    }
    return columns;
  }

  static const _widgetColumn = _WidgetColumn();
  static const _locationColumn = _LocationColumn();

  List<ColumnData<RebuildLocationStats>> get _columns => [
    _widgetColumn,
    ..._metricsColumns,
    _locationColumn,
  ];

  @override
  Widget build(BuildContext context) {
    final table = FlatTable<RebuildLocationStats>(
      dataKey: 'RebuildMetricsTable',
      columns: _columns,
      data: widget.metrics,
      keyFactory: (RebuildLocationStats location) =>
          ValueKey<String?>('${location.location.id}'),
      defaultSortColumn: _metricsColumns.first,
      defaultSortDirection: sortDirection,
      onItemSelected: (item) async {
        final location = item?.location;
        if (location?.fileUriString != null) {
          await _service?.navigateToCode(
            fileUriString: location?.fileUriString ?? '',
            line: location?.line ?? 0,
            column: location?.column ?? 0,
            source: 'devtools.rebuildStats',
          );
        }
      },
    );
    return widget.includeBorder ? OutlineDecoration(child: table) : table;
  }
}

class _WidgetColumn extends ColumnData<RebuildLocationStats> {
  const _WidgetColumn() : super('Widget', fixedWidthPx: 200);

  @override
  String getValue(RebuildLocationStats dataObject) {
    return dataObject.location.name ?? '<unknown>';
  }
}

class _LocationColumn extends ColumnData<RebuildLocationStats> {
  const _LocationColumn() : super.wide('Location');

  @override
  String getValue(RebuildLocationStats dataObject) {
    final fileUriString = dataObject.location.fileUriString;
    if (fileUriString == null) {
      return '<resolving location>';
    }

    return '${fileNameFromUri(fileUriString)}:${dataObject.location.line}';
  }

  @override
  String getTooltip(RebuildLocationStats dataObject) {
    if (dataObject.location.fileUriString == null) {
      return '<resolving location>';
    }

    return '${dataObject.location.fileUriString}:${dataObject.location.line}';
  }
}

class _RebuildCountColumn extends ColumnData<RebuildLocationStats> {
  _RebuildCountColumn(super.name, this.metricIndex) : super(fixedWidthPx: 160);

  final int metricIndex;

  /// Total rebuild count for this metric; set by [_RebuildTableState] before
  /// each build so that percentage share can be computed per row.
  int total = 0;

  @override
  bool get numeric => true;

  @override
  int getValue(RebuildLocationStats dataObject) =>
      dataObject.buildCounts[metricIndex];

  @override
  String getDisplayValue(RebuildLocationStats dataObject) {
    final count = dataObject.buildCounts[metricIndex];
    if (total <= 0 || count == 0) return '$count';
    final pct = (count / total * 100).round();
    return '$count ($pct%)';
  }

  /// Color-codes rows by their share of the total rebuild count so that
  /// performance bottlenecks are immediately visible.
  @override
  Color? getTextColor(RebuildLocationStats dataObject) {
    if (total <= 0) return null;
    final share = dataObject.buildCounts[metricIndex] / total;
    if (share >= 0.5) return Colors.red;
    if (share >= 0.25) return Colors.deepOrange;
    return null;
  }
}
