import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_model.dart';
import '../models/route_waypoint.dart';
import '../services/route_storage_service.dart';
import '../services/sync_service.dart';

class RouteDetailsScreen extends StatefulWidget {
  final RouteModel route;

  const RouteDetailsScreen({
    super.key,
    required this.route,
  });

  @override
  State<RouteDetailsScreen> createState() =>
      _RouteDetailsScreenState();
}

class _RouteDetailsScreenState
    extends State<RouteDetailsScreen> {
  // =========================================================
  // СЕРВІСИ
  // =========================================================

  final RouteStorageService _localStorage =
      RouteStorageService.instance;

  final SyncService _syncService =
      SyncService.instance;

  // =========================================================
  // ДАНІ
  // =========================================================

  late String? _routeName;

  @override
  void initState() {
    super.initState();

    _routeName = widget.route.name;
  }

  // =========================================================
  // НАЗВА ДЛЯ ВІДОБРАЖЕННЯ
  // =========================================================

  String get _displayName {
    final name = _routeName?.trim();

    if (name != null &&
        name.isNotEmpty) {
      return name;
    }

    return 'Маршрут';
  }

  // =========================================================
  // РЕДАГУВАННЯ НАЗВИ
  // =========================================================

  Future<void> _editRouteName() async {
    String newName =
        _routeName?.trim() ?? '';

    final result =
        await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.edit_outlined,
              ),
              SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Змінити назву маршруту',
                ),
              ),
            ],
          ),

          content: TextFormField(
            initialValue: newName,
            autofocus: true,
            maxLength: 50,
            textCapitalization:
                TextCapitalization.sentences,

            onChanged: (
              value,
            ) {
              newName = value;
            },

            onFieldSubmitted: (
              value,
            ) {
              Navigator.of(
                dialogContext,
              ).pop(
                value.trim(),
              );
            },

            decoration:
                const InputDecoration(
              labelText:
                  'Назва маршруту',
              hintText:
                  'Наприклад: Вечірня прогулянка',
              border:
                  OutlineInputBorder(),
              prefixIcon:
                  Icon(
                Icons.route,
              ),
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Скасувати',
              ),
            ),

            FilledButton.icon(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  newName.trim(),
                );
              },
              icon: const Icon(
                Icons.save_outlined,
              ),
              label: const Text(
                'Зберегти',
              ),
            ),
          ],
        );
      },
    );

    if (result == null) {
      return;
    }

    try {
      // =====================================================
      // SQLITE
      // =====================================================

      await _localStorage
          .updateRouteName(
        widget.route.id,
        result,
      );

      // =====================================================
      // SUPABASE
      // =====================================================

      await _syncService
          .syncPendingRoutes();

      if (!mounted) {
        return;
      }

      setState(() {
        _routeName =
            result.trim().isEmpty
                ? null
                : result.trim();
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Назву маршруту оновлено',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Помилка зміни назви: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося змінити назву',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ФОРМАТ ДАТИ
  // =========================================================

  String _formatDateTime(
    DateTime dateTime,
  ) {
    final day = dateTime.day
        .toString()
        .padLeft(
          2,
          '0',
        );

    final month = dateTime.month
        .toString()
        .padLeft(
          2,
          '0',
        );

    final year =
        dateTime.year;

    final hour = dateTime.hour
        .toString()
        .padLeft(
          2,
          '0',
        );

    final minute = dateTime.minute
        .toString()
        .padLeft(
          2,
          '0',
        );

    final second = dateTime.second
        .toString()
        .padLeft(
          2,
          '0',
        );

    return '$day.$month.$year '
        '$hour:$minute:$second';
  }

  // =========================================================
  // WAYPOINT INFO
  // =========================================================

  void _showWaypointInfo(
    RouteWaypoint waypoint,
  ) {
    showDialog(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(
                Icons.location_pin,
                color: Colors.orange,
              ),
              const SizedBox(
                width: 8,
              ),
              Expanded(
                child: Text(
                  waypoint.title,
                ),
              ),
            ],
          ),

          content: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              if (waypoint
                  .description
                  .isNotEmpty) ...[
                Text(
                  waypoint.description,
                  style:
                      const TextStyle(
                    fontSize: 16,
                  ),
                ),

                const SizedBox(
                  height: 16,
                ),
              ],

              Text(
                'Широта: '
                '${waypoint.latitude.toStringAsFixed(6)}',
              ),

              const SizedBox(
                height: 5,
              ),

              Text(
                'Довгота: '
                '${waypoint.longitude.toStringAsFixed(6)}',
              ),

              const SizedBox(
                height: 10,
              ),

              Text(
                'Створено: '
                '${_formatDateTime(waypoint.createdAt)}',
              ),
            ],
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: const Text(
                'Закрити',
              ),
            ),
          ],
        );
      },
    );
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final route =
        widget.route;

    final routePoints =
        route.points
            .map(
              (
                point,
              ) =>
                  point.position,
            )
            .toList();

    final statistics =
        route.statistics;

    final LatLng initialCenter;

    if (routePoints.isNotEmpty) {
      initialCenter =
          routePoints.first;
    } else {
      initialCenter =
          const LatLng(
        48.9226,
        24.7103,
      );
    }

    return Scaffold(
      // =====================================================
      // APP BAR
      // =====================================================

      appBar: AppBar(
        title: Text(
          _displayName,
        ),

        centerTitle: true,

        actions: [
          IconButton(
            tooltip:
                'Змінити назву',
            onPressed:
                _editRouteName,
            icon: const Icon(
              Icons.edit_outlined,
            ),
          ),
        ],
      ),

      body: ListView(
        children: [
          // =================================================
          // MAP
          // =================================================

          SizedBox(
            height: 380,
            child: FlutterMap(
              options: MapOptions(
                initialCenter:
                    initialCenter,
                initialZoom:
                    15,
              ),

              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName:
                      'com.example.route_tracker',
                ),

                // ===========================================
                // ROUTE LINE
                // ===========================================

                if (routePoints.length >= 2)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points:
                            routePoints,
                        strokeWidth:
                            5,
                        color:
                            Colors.blue,
                      ),
                    ],
                  ),

                // ===========================================
                // MARKERS
                // ===========================================

                MarkerLayer(
                  markers: [
                    // START
                    if (routePoints.isNotEmpty)
                      Marker(
                        point:
                            routePoints.first,
                        width:
                            50,
                        height:
                            50,
                        child:
                            const Icon(
                          Icons.play_circle_fill,
                          size:
                              42,
                          color:
                              Colors.green,
                        ),
                      ),

                    // END
                    if (routePoints.length >= 2)
                      Marker(
                        point:
                            routePoints.last,
                        width:
                            50,
                        height:
                            50,
                        child:
                            const Icon(
                          Icons.flag_circle,
                          size:
                              42,
                          color:
                              Colors.red,
                        ),
                      ),

                    // WAYPOINTS
                    ...route.waypoints.map(
                      (
                        waypoint,
                      ) {
                        return Marker(
                          point:
                              waypoint.position,
                          width:
                              50,
                          height:
                              50,
                          child:
                              GestureDetector(
                            onTap: () {
                              _showWaypointInfo(
                                waypoint,
                              );
                            },
                            child:
                                const Icon(
                              Icons.location_pin,
                              size:
                                  44,
                              color:
                                  Colors.orange,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // =================================================
          // NAME
          // =================================================

          Padding(
            padding:
                const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              0,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.route,
                  size: 28,
                ),

                const SizedBox(
                  width: 10,
                ),

                Expanded(
                  child: Text(
                    _displayName,
                    style:
                        const TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),

                IconButton(
                  tooltip:
                      'Змінити назву',
                  onPressed:
                      _editRouteName,
                  icon: const Icon(
                    Icons.edit_outlined,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          // =================================================
          // DATE/TIME
          // =================================================

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 20,
            ),
            child: Card(
              child: Column(
                children: [
                  ListTile(
                    leading:
                        const Icon(
                      Icons.play_arrow,
                    ),
                    title:
                        const Text(
                      'Початок',
                    ),
                    subtitle:
                        Text(
                      _formatDateTime(
                        route.startTime,
                      ),
                    ),
                  ),

                  if (route.endTime != null)
                    ListTile(
                      leading:
                          const Icon(
                        Icons.stop,
                      ),
                      title:
                          const Text(
                        'Завершення',
                      ),
                      subtitle:
                          Text(
                        _formatDateTime(
                          route.endTime!,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          // =================================================
          // STATISTICS
          // =================================================

          if (statistics != null)
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Card(
                child: Padding(
                  padding:
                      const EdgeInsets.all(
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Статистика',
                        style:
                            TextStyle(
                          fontSize: 19,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                      const SizedBox(
                        height: 18,
                      ),

                      _buildStatisticRow(
                        icon:
                            Icons.straighten,
                        title:
                            'Відстань',
                        value:
                            '${statistics.distanceKm.toStringAsFixed(2)} км',
                      ),

                      const Divider(),

                      _buildStatisticRow(
                        icon:
                            Icons.timer_outlined,
                        title:
                            'Тривалість',
                        value:
                            statistics.formattedDuration,
                      ),

                      const Divider(),

                      _buildStatisticRow(
                        icon:
                            Icons.speed,
                        title:
                            'Середня швидкість',
                        value:
                            '${statistics.averageSpeedKmh.toStringAsFixed(1)} км/год',
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(
            height: 12,
          ),

          // =================================================
          // ROUTE DATA
          // =================================================

          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 20,
            ),
            child: Card(
              child: Padding(
                padding:
                    const EdgeInsets.all(
                  16,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Дані маршруту',
                      style:
                          TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    const SizedBox(
                      height: 18,
                    ),

                    _buildStatisticRow(
                      icon:
                          Icons.gps_fixed,
                      title:
                          'GPS-точки',
                      value:
                          '${route.points.length}',
                    ),

                    const Divider(),

                    _buildStatisticRow(
                      icon:
                          Icons.location_pin,
                      title:
                          'Позначки',
                      value:
                          '${route.waypoints.length}',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // =================================================
          // WAYPOINT LIST
          // =================================================

          if (route.waypoints.isNotEmpty) ...[
            const SizedBox(
              height: 12,
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Card(
                child: Column(
                  children: [
                    const Padding(
                      padding:
                          EdgeInsets.fromLTRB(
                        16,
                        16,
                        16,
                        8,
                      ),
                      child: Align(
                        alignment:
                            Alignment.centerLeft,
                        child: Text(
                          'Позначки маршруту',
                          style:
                              TextStyle(
                            fontSize: 19,
                            fontWeight:
                                FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    ...route.waypoints.map(
                      (
                        waypoint,
                      ) {
                        return ListTile(
                          leading:
                              const Icon(
                            Icons.location_pin,
                            color:
                                Colors.orange,
                          ),
                          title:
                              Text(
                            waypoint.title,
                          ),
                          subtitle:
                              waypoint
                                      .description
                                      .isEmpty
                                  ? Text(
                                      '${waypoint.latitude.toStringAsFixed(5)}, '
                                      '${waypoint.longitude.toStringAsFixed(5)}',
                                    )
                                  : Text(
                                      waypoint.description,
                                    ),
                          trailing:
                              const Icon(
                            Icons.chevron_right,
                          ),
                          onTap: () {
                            _showWaypointInfo(
                              waypoint,
                            );
                          },
                        );
                      },
                    ),

                    const SizedBox(
                      height: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(
            height: 30,
          ),
        ],
      ),
    );
  }

  // =========================================================
  // STATISTIC ROW
  // =========================================================

  Widget _buildStatisticRow({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 5,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 24,
          ),

          const SizedBox(
            width: 14,
          ),

          Expanded(
            child: Text(
              title,
            ),
          ),

          Text(
            value,
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}