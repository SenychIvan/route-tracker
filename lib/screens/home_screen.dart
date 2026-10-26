import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_model.dart';
import '../models/route_statistics.dart';
import '../models/route_waypoint.dart';

import '../services/location_service.dart';
import '../services/route_storage_service.dart';
import '../services/supabase_route_service.dart';
import '../services/sync_service.dart';
import '../services/tracking_service.dart';

import '../widgets/statistic_item.dart';

import 'profile_screen.dart';
import 'route_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
  });

  @override
  State<HomeScreen> createState() =>
      _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // =========================================================
  // СЕРВІСИ
  // =========================================================

  final MapController _mapController =
      MapController();

  final LocationService _locationService =
      LocationService();

  final TrackingService _trackingService =
      TrackingService();

  final RouteStorageService _routeStorage =
      RouteStorageService.instance;

  final SupabaseRouteService _supabaseRouteService =
      SupabaseRouteService.instance;

  final SyncService _syncService =
      SyncService.instance;

  // =========================================================
  // ДАНІ
  // =========================================================

  final List<RouteWaypoint> _waypoints = [];

  // Позиція, яку показуємо на карті.
  Position? _currentPosition;

  // Найсвіжіша реальна GPS-позиція.
  // Вона оновлюється навіть під час паузи.
  Position? _latestPosition;

  StreamSubscription<Position>?
      _positionSubscription;

  Timer? _timer;

  DateTime? _routeStartTime;

  bool _isLoadingLocation = true;
  bool _isTracking = false;
  bool _isPaused = false;

  String? _locationError;

  int _elapsedSeconds = 0;

  double _currentSpeed = 0;

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _loadCurrentLocation();
    _syncPendingRoutesSilently();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _timer?.cancel();

    super.dispose();
  }

  // =========================================================
  // ФОНОВА СИНХРОНІЗАЦІЯ
  // =========================================================

  Future<void> _syncPendingRoutesSilently() async {
    try {
      final count =
          await _syncService.syncPendingRoutes();

      if (count > 0) {
        debugPrint(
          'Синхронізовано маршрутів: $count',
        );
      }
    } catch (e) {
      debugPrint(
        'Фонова синхронізація недоступна: $e',
      );
    }
  }

  // =========================================================
  // ПОТОЧНА GPS-ПОЗИЦІЯ
  // =========================================================

  Future<void> _loadCurrentLocation() async {
    try {
      final position =
          await _locationService
              .getCurrentPosition();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentPosition = position;
        _latestPosition = position;

        _isLoadingLocation = false;

        _locationError = null;
      });

      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) {
          _moveMapToCurrentLocation();
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoadingLocation = false;

        _locationError =
            e.toString();
      });
    }
  }

  // =========================================================
  // ЦЕНТРУВАННЯ КАРТИ
  // =========================================================

  void _moveMapToCurrentLocation() {
    if (_currentPosition == null) {
      return;
    }

    final point = LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    _mapController.move(
      point,
      16,
    );
  }

  // =========================================================
  // ПОЧАТОК МАРШРУТУ
  //
  // Перед кожним новим маршрутом беремо свіжу GPS-позицію,
  // щоб новий маршрут не починався з кінця попереднього.
  // =========================================================

  Future<void> _startRoute() async {
    try {
      final freshPosition =
          await _locationService
              .getCurrentPosition();

      if (!mounted) {
        return;
      }

      setState(() {
        _currentPosition =
            freshPosition;

        _latestPosition =
            freshPosition;

        _locationError =
            null;
      });

      _trackingService.start(
        freshPosition,
      );

      _routeStartTime =
          DateTime.now();

      setState(() {
        _isTracking = true;

        _isPaused = false;

        _elapsedSeconds = 0;

        _currentSpeed = 0;

        _waypoints.clear();
      });

      _mapController.move(
        LatLng(
          freshPosition.latitude,
          freshPosition.longitude,
        ),
        16,
      );

      _startTimer();

      _startLocationTracking();
    } catch (e) {
      debugPrint(
        'Не вдалося почати маршрут: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося отримати актуальну GPS-позицію',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ТАЙМЕР
  // =========================================================

  void _startTimer() {
    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(
        seconds: 1,
      ),
      (_) {
        if (!_isTracking ||
            _isPaused ||
            !mounted) {
          return;
        }

        setState(() {
          _elapsedSeconds++;
        });
      },
    );
  }

  // =========================================================
  // GPS STREAM
  // =========================================================

  void _startLocationTracking() {
    _positionSubscription?.cancel();

    _positionSubscription =
        _locationService
            .getPositionStream(
      distanceFilter: 3,
    )
            .listen(
      (
        Position position,
      ) {
        if (!mounted) {
          return;
        }

        // ---------------------------------------------------
        // Реальна GPS-позиція завжди оновлюється.
        // ---------------------------------------------------

        _latestPosition =
            position;

        // ---------------------------------------------------
        // ПАУЗА
        //
        // Під час паузи:
        // - не рухаємо синю точку;
        // - не додаємо точку маршруту;
        // - не збільшуємо відстань;
        // - швидкість залишається 0.
        // ---------------------------------------------------

        if (_isPaused) {
          return;
        }

        if (!_isTracking) {
          return;
        }

        // ---------------------------------------------------
        // АКТИВНИЙ ЗАПИС
        // ---------------------------------------------------

        _trackingService.addPosition(
          position,
        );

        setState(() {
          _currentPosition =
              position;

          if (position.speed >= 0) {
            _currentSpeed =
                position.speed * 3.6;
          } else {
            _currentSpeed = 0;
          }
        });

        final newPoint = LatLng(
          position.latitude,
          position.longitude,
        );

        _mapController.move(
          newPoint,
          _mapController.camera.zoom,
        );
      },
      onError: (
        error,
      ) {
        debugPrint(
          'Помилка GPS: $error',
        );
      },
    );
  }

  // =========================================================
  // ПАУЗА / ПРОДОВЖЕННЯ
  // =========================================================

  void _pauseRoute() {
    // =======================================================
    // ПРОДОВЖЕННЯ
    // =======================================================

    if (_isPaused) {
      final resumePosition =
          _latestPosition ??
              _currentPosition;

      if (resumePosition != null) {
        // TrackingService не додає до відстані
        // переміщення, яке відбулося під час паузи.
        _trackingService.resumeAt(
          resumePosition,
        );
      }

      setState(() {
        _isPaused = false;

        _currentSpeed = 0;

        // Після продовження показуємо
        // актуальну GPS-позицію.
        if (resumePosition != null) {
          _currentPosition =
              resumePosition;
        }
      });

      if (resumePosition != null) {
        _mapController.move(
          LatLng(
            resumePosition.latitude,
            resumePosition.longitude,
          ),
          _mapController.camera.zoom,
        );
      }

      return;
    }

    // =======================================================
    // ПОСТАНОВКА НА ПАУЗУ
    // =======================================================

    setState(() {
      _isPaused = true;

      _currentSpeed = 0;
    });
  }

  // =========================================================
  // ПІДТВЕРДЖЕННЯ ЗАВЕРШЕННЯ
  // =========================================================

  Future<void> _confirmFinishRoute() async {
    if (!_isTracking) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Завершити маршрут?',
          ),
          content: const Text(
            'Запис маршруту буде зупинено. '
            'Після цього ви зможете вказати '
            'його назву.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(
                  false,
                );
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
                  true,
                );
              },
              icon: const Icon(
                Icons.stop,
              ),
              label: const Text(
                'Завершити',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _finishRoute();
    }
  }

  // =========================================================
  // ВВЕДЕННЯ НАЗВИ МАРШРУТУ
  // =========================================================

  Future<String?> _askRouteName() async {
    String routeName = '';

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
                Icons.edit_road_outlined,
              ),
              SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Назва маршруту',
                ),
              ),
            ],
          ),
          content: TextField(
            autofocus: true,
            maxLength: 50,
            textCapitalization:
                TextCapitalization.sentences,
            onChanged: (
              value,
            ) {
              routeName = value;
            },
            onSubmitted: (
              value,
            ) {
              final name =
                  value.trim();

              Navigator.of(
                dialogContext,
              ).pop(
                name.isEmpty
                    ? null
                    : name,
              );
            },
            decoration:
                const InputDecoration(
              labelText:
                  'Назва',
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
                ).pop(
                  null,
                );
              },
              child: const Text(
                'Пропустити',
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                final name =
                    routeName.trim();

                Navigator.of(
                  dialogContext,
                ).pop(
                  name.isEmpty
                      ? null
                      : name,
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

    return result;
  }

  // =========================================================
  // ЗАВЕРШЕННЯ МАРШРУТУ
  // =========================================================

  Future<void> _finishRoute() async {
    if (!_isTracking) {
      return;
    }

    // -------------------------------------------------------
    // ЗУПИНЯЄМО GPS STREAM
    // -------------------------------------------------------

    final subscription =
        _positionSubscription;

    _positionSubscription = null;

    if (subscription != null) {
      await subscription.cancel();
    }

    // -------------------------------------------------------
    // ЗУПИНЯЄМО ТАЙМЕР
    // -------------------------------------------------------

    _timer?.cancel();

    _timer = null;

    final endTime =
        DateTime.now();

    // -------------------------------------------------------
    // КОПІЮЄМО ДАНІ
    // -------------------------------------------------------

    final routeStartTime =
        _routeStartTime ??
            endTime;

    final routePoints =
        List.of(
      _trackingService.routePoints,
    );

    final routeWaypoints =
        List.of(
      _waypoints,
    );

    final distanceMeters =
        _trackingService.distanceMeters;

    final durationSeconds =
        _elapsedSeconds;

    // -------------------------------------------------------
    // СТАТИСТИКА
    // -------------------------------------------------------

    final statistics =
        RouteStatistics.calculate(
      distanceMeters:
          distanceMeters,
      durationSeconds:
          durationSeconds,
    );

    if (!mounted) {
      return;
    }

    // -------------------------------------------------------
    // ЗАВЕРШУЄМО TRACKING
    // -------------------------------------------------------

    setState(() {
      _isTracking = false;

      _isPaused = false;

      _currentSpeed = 0;
    });

    // -------------------------------------------------------
    // НАЗВА
    // -------------------------------------------------------

    final routeName =
        await _askRouteName();

    if (!mounted) {
      return;
    }

    // -------------------------------------------------------
    // ROUTE MODEL
    // -------------------------------------------------------

    final route =
        RouteModel(
      id: DateTime.now()
          .microsecondsSinceEpoch
          .toString(),

      name:
          routeName,

      startTime:
          routeStartTime,

      endTime:
          endTime,

      points:
          routePoints,

      waypoints:
          routeWaypoints,

      statistics:
          statistics,
    );

    setState(() {
      _routeStartTime = null;
    });

    try {
      // =====================================================
      // SQLITE -> PENDING
      // =====================================================

      await _routeStorage.saveRoute(
        route,
      );

      if (!mounted) {
        return;
      }

      try {
        // ===================================================
        // SUPABASE
        // ===================================================

        await _supabaseRouteService
            .saveRoute(
          route,
        );

        // ===================================================
        // SQLITE -> SYNCED
        // ===================================================

        await _routeStorage
            .markAsSynced(
          route.id,
        );

        await _syncService
            .syncPendingRoutes();

        if (!mounted) {
          return;
        }

        final name =
            route.name?.trim();

        final message =
            name != null &&
                    name.isNotEmpty
                ? 'Маршрут "$name" '
                    'збережено локально та в хмарі.'
                : 'Маршрут збережено локально '
                    'та в хмарі.';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              '$message '
              '${statistics.distanceKm.toStringAsFixed(2)} км',
            ),
          ),
        );
      } catch (e) {
        // ===================================================
        // OFFLINE
        // ===================================================

        debugPrint(
          'Помилка Supabase: $e',
        );

        await _routeStorage
            .markAsPending(
          route.id,
        );

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'Маршрут збережено локально. '
              'Синхронізація з хмарою '
              'буде виконана пізніше.',
            ),
          ),
        );
      }
    } catch (e) {
      // =====================================================
      // SQLITE ERROR
      // =====================================================

      debugPrint(
        'Помилка SQLite: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося зберегти маршрут',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ДОДАВАННЯ WAYPOINT
  // =========================================================

  Future<void> _addWaypoint() async {
    if (_currentPosition == null) {
      return;
    }

    final waypointPosition =
        LatLng(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    String title = '';

    String description = '';

    final waypoint =
        await showDialog<RouteWaypoint>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Додати точку',
          ),
          content:
              SingleChildScrollView(
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (
                    value,
                  ) {
                    title = value;
                  },
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Назва',
                    hintText:
                        'Наприклад: Гарний краєвид',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
                TextField(
                  onChanged: (
                    value,
                  ) {
                    description =
                        value;
                  },
                  maxLines: 3,
                  decoration:
                      const InputDecoration(
                    labelText:
                        'Опис',
                    hintText:
                        'Опишіть це місце',
                    border:
                        OutlineInputBorder(),
                  ),
                ),
              ],
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
            FilledButton(
              onPressed: () {
                final waypointTitle =
                    title
                            .trim()
                            .isEmpty
                        ? 'Точка ${_waypoints.length + 1}'
                        : title
                            .trim();

                Navigator.of(
                  dialogContext,
                ).pop(
                  RouteWaypoint(
                    position:
                        waypointPosition,
                    title:
                        waypointTitle,
                    description:
                        description
                            .trim(),
                    createdAt:
                        DateTime.now(),
                  ),
                );
              },
              child: const Text(
                'Зберегти',
              ),
            ),
          ],
        );
      },
    );

    if (!mounted ||
        waypoint == null) {
      return;
    }

    setState(() {
      _waypoints.add(
        waypoint,
      );
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          'Точку "${waypoint.title}" додано',
        ),
      ),
    );
  }

  // =========================================================
  // ІНФОРМАЦІЯ ПРО WAYPOINT
  // =========================================================

  void _showWaypoint(
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
                color: Colors.red,
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
                '${waypoint.position.latitude.toStringAsFixed(5)}',
              ),
              const SizedBox(
                height: 4,
              ),
              Text(
                'Довгота: '
                '${waypoint.position.longitude.toStringAsFixed(5)}',
              ),
              const SizedBox(
                height: 8,
              ),
              Text(
                'Створено: '
                '${_formatDateTime(waypoint.createdAt)}',
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final confirmed =
                    await showDialog<bool>(
                  context:
                      dialogContext,
                  builder: (
                    confirmContext,
                  ) {
                    return AlertDialog(
                      title:
                          const Text(
                        'Видалити точку?',
                      ),
                      content:
                          Text(
                        'Точка "${waypoint.title}" '
                        'буде видалена.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(
                              confirmContext,
                            ).pop(
                              false,
                            );
                          },
                          child:
                              const Text(
                            'Скасувати',
                          ),
                        ),
                        FilledButton(
                          style:
                              FilledButton
                                  .styleFrom(
                            backgroundColor:
                                Colors.red,
                          ),
                          onPressed: () {
                            Navigator.of(
                              confirmContext,
                            ).pop(
                              true,
                            );
                          },
                          child:
                              const Text(
                            'Видалити',
                          ),
                        ),
                      ],
                    );
                  },
                );

                if (confirmed != true ||
                    !mounted ||
                    !dialogContext.mounted) {
                  return;
                }

                Navigator.of(
                  dialogContext,
                ).pop();

                setState(() {
                  _waypoints.remove(
                    waypoint,
                  );
                });

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Точку "${waypoint.title}" видалено',
                    ),
                  ),
                );
              },
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
              ),
              label: const Text(
                'Видалити',
                style: TextStyle(
                  color: Colors.red,
                ),
              ),
            ),
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
  // ІСТОРІЯ
  // =========================================================

  Future<void> _openHistory() async {
    await _syncService
        .syncPendingRoutes();

    if (!mounted) {
      return;
    }

    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (
          context,
        ) =>
            const RouteHistoryScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // ПРОФІЛЬ
  // =========================================================

  Future<void> _openProfile() async {
    if (_isTracking) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Спочатку завершіть активний маршрут',
          ),
        ),
      );

      return;
    }

    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (
          context,
        ) =>
            const ProfileScreen(),
      ),
    );

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // ФОРМАТ ДАТИ
  // =========================================================

  String _formatDateTime(
    DateTime dateTime,
  ) {
    final day =
        dateTime.day
            .toString()
            .padLeft(
              2,
              '0',
            );

    final month =
        dateTime.month
            .toString()
            .padLeft(
              2,
              '0',
            );

    final year =
        dateTime.year;

    final hour =
        dateTime.hour
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minute =
        dateTime.minute
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$day.$month.$year '
        '$hour:$minute';
  }

  // =========================================================
  // ФОРМАТ ЧАСУ
  // =========================================================

  String _formatTime(
    int seconds,
  ) {
    final duration =
        Duration(
      seconds: seconds,
    );

    final hours =
        duration.inHours
            .toString()
            .padLeft(
              2,
              '0',
            );

    final minutes =
        (duration.inMinutes % 60)
            .toString()
            .padLeft(
              2,
              '0',
            );

    final secs =
        (duration.inSeconds % 60)
            .toString()
            .padLeft(
              2,
              '0',
            );

    return '$hours:$minutes:$secs';
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final routePoints =
        _trackingService
            .routePoints
            .map(
              (
                point,
              ) =>
                  point.position,
            )
            .toList();

    return Scaffold(
      // =====================================================
      // APP BAR
      // =====================================================

      appBar: AppBar(
        title: const Text(
          'Route Tracker',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip:
                'Історія маршрутів',
            onPressed:
                _openHistory,
            icon: const Icon(
              Icons.history,
            ),
          ),
          IconButton(
            tooltip:
                'Профіль',
            onPressed:
                _openProfile,
            icon: const Icon(
              Icons.account_circle_outlined,
            ),
          ),
        ],
      ),

      // =====================================================
      // BODY
      // =====================================================

      body: Column(
        children: [
          // =================================================
          // КАРТА
          // =================================================

          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController:
                      _mapController,
                  options:
                      const MapOptions(
                    initialCenter:
                        LatLng(
                      48.9226,
                      24.7103,
                    ),
                    initialZoom:
                        13,
                  ),
                  children: [
                    // ---------------------------------------
                    // OPENSTREETMAP
                    // ---------------------------------------

                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.example.route_tracker',
                    ),

                    // ---------------------------------------
                    // ЛІНІЯ МАРШРУТУ
                    // ---------------------------------------

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

                    // ---------------------------------------
                    // МАРКЕРИ
                    // ---------------------------------------

                    MarkerLayer(
                      markers: [
                        // WAYPOINTS
                        ..._waypoints.map(
                          (
                            waypoint,
                          ) {
                            return Marker(
                              point:
                                  waypoint.position,
                              width:
                                  55,
                              height:
                                  55,
                              child:
                                  GestureDetector(
                                onTap: () {
                                  _showWaypoint(
                                    waypoint,
                                  );
                                },
                                child:
                                    const Icon(
                                  Icons.location_pin,
                                  size:
                                      50,
                                  color:
                                      Colors.red,
                                ),
                              ),
                            );
                          },
                        ),

                        // ПОТОЧНА GPS-ПОЗИЦІЯ
                        if (_currentPosition !=
                            null)
                          Marker(
                            point:
                                LatLng(
                              _currentPosition!
                                  .latitude,
                              _currentPosition!
                                  .longitude,
                            ),
                            width:
                                50,
                            height:
                                50,
                            child:
                                const Icon(
                              Icons.my_location,
                              size:
                                  38,
                              color:
                                  Colors.blue,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                // -------------------------------------------
                // GPS LOADING
                // -------------------------------------------

                if (_isLoadingLocation)
                  const Center(
                    child:
                        CircularProgressIndicator(),
                  ),

                // -------------------------------------------
                // GPS ERROR
                // -------------------------------------------

                if (_locationError != null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Card(
                      child: Padding(
                        padding:
                            const EdgeInsets.all(
                          12,
                        ),
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Text(
                              _locationError!,
                              textAlign:
                                  TextAlign.center,
                            ),
                            const SizedBox(
                              height: 8,
                            ),
                            FilledButton(
                              onPressed:
                                  _loadCurrentLocation,
                              child:
                                  const Text(
                                'Спробувати ще раз',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // -------------------------------------------
                // ЦЕНТРУВАННЯ
                // -------------------------------------------

                Positioned(
                  right: 16,
                  bottom: 16,
                  child:
                      FloatingActionButton.small(
                    heroTag:
                        'current_location',
                    onPressed:
                        _moveMapToCurrentLocation,
                    child:
                        const Icon(
                      Icons.my_location,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // =================================================
          // НИЖНЯ ПАНЕЛЬ
          // =================================================

          Container(
            padding:
                const EdgeInsets.all(
              20,
            ),
            child: Column(
              children: [
                // -------------------------------------------
                // СТАТУС ЗАПИСУ
                // -------------------------------------------

                if (_isTracking) ...[
                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          _isPaused
                              ? Colors.orange.withValues(
                                  alpha: 0.15,
                                )
                              : Colors.green.withValues(
                                  alpha: 0.15,
                                ),
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isPaused
                              ? Icons.pause_circle_outline
                              : Icons.fiber_manual_record,
                          size: 18,
                          color:
                              _isPaused
                                  ? Colors.orange
                                  : Colors.green,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Text(
                          _isPaused
                              ? 'Маршрут на паузі'
                              : 'Запис маршруту',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.w600,
                            color:
                                _isPaused
                                    ? Colors.orange
                                    : Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                ],

                // -------------------------------------------
                // СТАТИСТИКА
                // -------------------------------------------

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment.spaceAround,
                  children: [
                    StatisticItem(
                      title:
                          'Відстань',
                      value:
                          '${(_trackingService.distanceMeters / 1000).toStringAsFixed(2)} км',
                      icon:
                          Icons.route,
                    ),
                    StatisticItem(
                      title:
                          'Час',
                      value:
                          _formatTime(
                        _elapsedSeconds,
                      ),
                      icon:
                          Icons.timer_outlined,
                    ),
                    StatisticItem(
                      title:
                          'Швидкість',
                      value:
                          '${_currentSpeed.toStringAsFixed(1)} км/год',
                      icon:
                          Icons.speed,
                    ),
                  ],
                ),

                const SizedBox(
                  height: 24,
                ),

                // -------------------------------------------
                // ПОЧАТИ
                // -------------------------------------------

                if (!_isTracking)
                  SizedBox(
                    width:
                        double.infinity,
                    child:
                        FilledButton.icon(
                      onPressed:
                          _startRoute,
                      icon:
                          const Icon(
                        Icons.play_arrow,
                      ),
                      label:
                          const Text(
                        'Почати маршрут',
                      ),
                      style:
                          FilledButton.styleFrom(
                        padding:
                            const EdgeInsets.all(
                          16,
                        ),
                      ),
                    ),
                  ),

                // -------------------------------------------
                // АКТИВНИЙ МАРШРУТ
                // -------------------------------------------

                if (_isTracking)
                  Row(
                    children: [
                      // ПАУЗА
                      Expanded(
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              _pauseRoute,
                          icon:
                              Icon(
                            _isPaused
                                ? Icons.play_arrow
                                : Icons.pause,
                          ),
                          label:
                              Text(
                            _isPaused
                                ? 'Продовжити'
                                : 'Пауза',
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      // ТОЧКА
                      Expanded(
                        child:
                            OutlinedButton.icon(
                          onPressed:
                              _addWaypoint,
                          icon:
                              const Icon(
                            Icons.add_location_alt,
                          ),
                          label:
                              const Text(
                            'Точка',
                          ),
                        ),
                      ),

                      const SizedBox(
                        width: 8,
                      ),

                      // ЗАВЕРШИТИ
                      Expanded(
                        child:
                            FilledButton.icon(
                          onPressed:
                              _confirmFinishRoute,
                          icon:
                              const Icon(
                            Icons.stop,
                          ),
                          label:
                              const Text(
                            'Завершити',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}