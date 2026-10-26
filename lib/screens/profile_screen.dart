import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/route_model.dart';
import '../services/route_storage_service.dart';
import '../services/sync_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
  });

  @override
  State<ProfileScreen> createState() =>
      _ProfileScreenState();
}

class _ProfileScreenState
    extends State<ProfileScreen> {
  final RouteStorageService _localStorage =
      RouteStorageService.instance;

  final SyncService _syncService =
      SyncService.instance;

  bool _isLoading = true;

  bool _cloudAvailable = true;

  String? _error;

  List<RouteModel> _routes = [];

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _loadProfile();
  }

  // =========================================================
  // ЗАВАНТАЖЕННЯ
  // =========================================================

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final result =
          await _syncService.syncAll();

      final routes =
          await _localStorage.getRoutes();

      if (!mounted) {
        return;
      }

      setState(() {
        _routes = routes;

        _cloudAvailable =
            result.cloudAvailable;

        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Помилка профілю: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;

        _error =
            'Не вдалося завантажити дані профілю';
      });
    }
  }

  // =========================================================
  // ЗАГАЛЬНА ВІДСТАНЬ
  // =========================================================

  double get _totalDistanceMeters {
    double total = 0;

    for (final route in _routes) {
      total +=
          route.statistics
                  ?.distanceMeters ??
              0;
    }

    return total;
  }

  double get _totalDistanceKm =>
      _totalDistanceMeters / 1000;

  // =========================================================
  // ЗАГАЛЬНИЙ ЧАС
  // =========================================================

  int get _totalDurationSeconds {
    int total = 0;

    for (final route in _routes) {
      total +=
          route.statistics
                  ?.durationSeconds ??
              0;
    }

    return total;
  }

  // =========================================================
  // СЕРЕДНЯ ШВИДКІСТЬ
  // =========================================================

  double get _averageSpeedKmh {
    if (_totalDurationSeconds <= 0) {
      return 0;
    }

    final hours =
        _totalDurationSeconds / 3600;

    if (hours <= 0) {
      return 0;
    }

    return _totalDistanceKm / hours;
  }

  // =========================================================
  // WAYPOINTS
  // =========================================================

  int get _totalWaypoints {
    int total = 0;

    for (final route in _routes) {
      total += route.waypoints.length;
    }

    return total;
  }

  // =========================================================
  // GPS POINTS
  // =========================================================

  int get _totalGpsPoints {
    int total = 0;

    for (final route in _routes) {
      total += route.points.length;
    }

    return total;
  }

  // =========================================================
  // ФОРМАТ ЧАСУ
  // =========================================================

  String _formatDuration(
    int seconds,
  ) {
    final duration =
        Duration(
      seconds: seconds,
    );

    final hours =
        duration.inHours;

    final minutes =
        duration.inMinutes % 60;

    if (hours > 0) {
      return '$hours год ${minutes.toString().padLeft(2, '0')} хв';
    }

    return '$minutes хв';
  }

  // =========================================================
  // ВИХІД
  // =========================================================

  Future<void> _logout() async {
    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title: const Text(
            'Вийти з акаунта?',
          ),
          content: const Text(
            'Ви зможете знову увійти '
            'за допомогою email та пароля.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(false);
              },
              child: const Text(
                'Скасувати',
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(
                  dialogContext,
                ).pop(true);
              },
              child: const Text(
                'Вийти',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      // Перед виходом ще раз
      // пробуємо синхронізувати pending.
      await _syncService
          .syncPendingRoutes();

      await Supabase
          .instance
          .client
          .auth
          .signOut();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop();
    } on AuthException catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        SnackBar(
          content: Text(
            'Помилка виходу: ${e.message}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося вийти з акаунта',
          ),
        ),
      );
    }
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final user =
        Supabase
            .instance
            .client
            .auth
            .currentUser;

    final email =
        user?.email ??
            'Невідомий користувач';

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Профіль',
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Оновити',
            onPressed: _loadProfile,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh:
                      _loadProfile,
                  child:
                      _buildContent(
                    email,
                  ),
                ),
    );
  }

  // =========================================================
  // CONTENT
  // =========================================================

  Widget _buildContent(
    String email,
  ) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.all(
        20,
      ),
      children: [
        // ===================================================
        // USER
        // ===================================================

        Center(
          child: CircleAvatar(
            radius: 45,
            child: Text(
              email.isNotEmpty
                  ? email[0]
                      .toUpperCase()
                  : '?',
              style: const TextStyle(
                fontSize: 34,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        Center(
          child: Text(
            email,
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(
          height: 10,
        ),

        Center(
          child: Container(
            padding:
                const EdgeInsets
                    .symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius
                      .circular(
                20,
              ),
              color:
                  _cloudAvailable
                      ? Colors.green
                          .withValues(
                          alpha:
                              0.12,
                        )
                      : Colors.orange
                          .withValues(
                          alpha:
                              0.15,
                        ),
            ),
            child: Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  _cloudAvailable
                      ? Icons
                          .cloud_done_outlined
                      : Icons
                          .cloud_off_outlined,
                  size: 18,
                  color:
                      _cloudAvailable
                          ? Colors.green
                          : Colors.orange,
                ),
                const SizedBox(
                  width: 6,
                ),
                Text(
                  _cloudAvailable
                      ? 'Синхронізація активна'
                      : 'Офлайн режим',
                  style: TextStyle(
                    color:
                        _cloudAvailable
                            ? Colors.green
                            : Colors.orange,
                    fontWeight:
                        FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(
          height: 32,
        ),

        const Text(
          'Загальна статистика',
          style: TextStyle(
            fontSize: 20,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(
          height: 16,
        ),

        // ===================================================
        // STAT CARDS
        // ===================================================

        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.route,
                title:
                    'Маршрути',
                value:
                    '${_routes.length}',
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.straighten,
                title:
                    'Відстань',
                value:
                    '${_totalDistanceKm.toStringAsFixed(2)} км',
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.timer_outlined,
                title:
                    'Час',
                value:
                    _formatDuration(
                  _totalDurationSeconds,
                ),
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.speed,
                title:
                    'Сер. швидкість',
                value:
                    '${_averageSpeedKmh.toStringAsFixed(1)} км/год',
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 12,
        ),

        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.gps_fixed,
                title:
                    'GPS-точки',
                value:
                    '$_totalGpsPoints',
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: _buildStatCard(
                icon:
                    Icons.location_pin,
                title:
                    'Позначки',
                value:
                    '$_totalWaypoints',
              ),
            ),
          ],
        ),

        const SizedBox(
          height: 32,
        ),

        // ===================================================
        // ACCOUNT
        // ===================================================

        const Text(
          'Акаунт',
          style: TextStyle(
            fontSize: 20,
            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        Card(
          child: ListTile(
            leading:
                const Icon(
              Icons.email_outlined,
            ),
            title:
                const Text(
              'Email',
            ),
            subtitle:
                Text(email),
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        SizedBox(
          width:
              double.infinity,
          child:
              OutlinedButton.icon(
            onPressed:
                _logout,
            icon:
                const Icon(
              Icons.logout,
            ),
            label:
                const Text(
              'Вийти з акаунта',
            ),
            style:
                OutlinedButton
                    .styleFrom(
              padding:
                  const EdgeInsets
                      .all(
                16,
              ),
              foregroundColor:
                  Colors.red,
            ),
          ),
        ),

        const SizedBox(
          height: 30,
        ),
      ],
    );
  }

  // =========================================================
  // STAT CARD
  // =========================================================

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Card(
      child: Padding(
        padding:
            const EdgeInsets.all(
          16,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 28,
            ),

            const SizedBox(
              height: 10,
            ),

            Text(
              value,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.bold,
              ),
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              title,
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                fontSize: 12,
                color:
                    Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // ERROR
  // =========================================================

  Widget _buildError() {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(
          24,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 60,
              color: Colors.grey,
            ),
            const SizedBox(
              height: 16,
            ),
            Text(
              _error!,
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(
              height: 16,
            ),
            FilledButton.icon(
              onPressed:
                  _loadProfile,
              icon:
                  const Icon(
                Icons.refresh,
              ),
              label:
                  const Text(
                'Спробувати ще раз',
              ),
            ),
          ],
        ),
      ),
    );
  }
}