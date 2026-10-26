import 'package:flutter/material.dart';

import '../models/route_model.dart';
import '../services/route_storage_service.dart';
import '../services/supabase_route_service.dart';
import '../services/sync_service.dart';

import 'route_details_screen.dart';

class RouteHistoryScreen extends StatefulWidget {
  const RouteHistoryScreen({
    super.key,
  });

  @override
  State<RouteHistoryScreen> createState() =>
      _RouteHistoryScreenState();
}

class _RouteHistoryScreenState
    extends State<RouteHistoryScreen> {
  // =========================================================
  // СЕРВІСИ
  // =========================================================

  final RouteStorageService _localStorage =
      RouteStorageService.instance;

  final SupabaseRouteService _cloudStorage =
      SupabaseRouteService.instance;

  final SyncService _syncService =
      SyncService.instance;

  // =========================================================
  // ДАНІ
  // =========================================================

  List<RouteModel> _routes = [];

  final Map<String, String> _syncStatuses = {};

  bool _isLoading = true;

  bool _cloudAvailable = true;

  String? _error;

  // =========================================================
  // INIT
  // =========================================================

  @override
  void initState() {
    super.initState();

    _loadRoutes();
  }

  // =========================================================
  // ЗАВАНТАЖЕННЯ
  // =========================================================

  Future<void> _loadRoutes() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      // -----------------------------------------------------
      // SQLITE <-> SUPABASE
      // -----------------------------------------------------

      final result =
          await _syncService.syncAll();

      // -----------------------------------------------------
      // UI ЧИТАЄ З SQLITE
      // -----------------------------------------------------

      final routes =
          await _localStorage.getRoutes();

      final statuses =
          <String, String>{};

      for (final route in routes) {
        final status =
            await _localStorage
                .getSyncStatus(
          route.id,
        );

        statuses[route.id] =
            status ?? 'pending';
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _routes = routes;

        _syncStatuses
          ..clear()
          ..addAll(
            statuses,
          );

        _cloudAvailable =
            result.cloudAvailable;

        _isLoading = false;
      });
    } catch (e) {
      debugPrint(
        'Помилка історії: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;

        _error =
            'Не вдалося завантажити '
            'локальну історію маршрутів';
      });
    }
  }

  // =========================================================
  // НАЗВА
  // =========================================================

  String _getRouteName(
    RouteModel route,
    int index,
  ) {
    final name =
        route.name?.trim();

    if (name != null &&
        name.isNotEmpty) {
      return name;
    }

    return 'Маршрут ${_routes.length - index}';
  }

  // =========================================================
  // РЕДАГУВАННЯ НАЗВИ
  // =========================================================

  Future<void> _editRouteName(
    RouteModel route,
  ) async {
    String newName =
        route.name?.trim() ?? '';

    final result =
        await showDialog<String?>(
      context: context,

      barrierDismissible:
          false,

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

          content:
              TextFormField(
            initialValue:
                newName,

            autofocus:
                true,

            maxLength:
                50,

            textCapitalization:
                TextCapitalization
                    .sentences,

            onChanged: (
              value,
            ) {
              newName =
                  value;
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
                  'Наприклад: Ранкова прогулянка',

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

              child:
                  const Text(
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

              icon:
                  const Icon(
                Icons.save_outlined,
              ),

              label:
                  const Text(
                'Зберегти',
              ),
            ),
          ],
        );
      },
    );

    // Скасування
    if (result == null) {
      return;
    }

    try {
      // -----------------------------------------------------
      // 1. SQLITE
      // -----------------------------------------------------

      await _localStorage
          .updateRouteName(
        route.id,
        result,
      );

      // -----------------------------------------------------
      // 2. ПРОБУЄМО СИНХРОНІЗУВАТИ
      // -----------------------------------------------------

      await _syncService
          .syncPendingRoutes();

      // -----------------------------------------------------
      // 3. ПЕРЕЧИТУЄМО ІСТОРІЮ
      // -----------------------------------------------------

      await _loadRoutes();

      if (!mounted) {
        return;
      }

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
            'Не вдалося змінити назву маршруту',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ДАТА
  // =========================================================

  String _formatDate(
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
  // ВИДАЛЕННЯ
  // =========================================================

  Future<void> _deleteRoute(
    RouteModel route,
  ) async {
    final status =
        _syncStatuses[
            route.id] ??
        'pending';

    final confirmed =
        await showDialog<bool>(
      context:
          context,

      builder: (
        dialogContext,
      ) {
        return AlertDialog(
          title:
              const Text(
            'Видалити маршрут?',
          ),

          content:
              Text(
            status == 'synced'
                ? 'Маршрут буде видалено '
                    'з пристрою та хмари.'
                : 'Маршрут буде видалено '
                    'з пристрою.',
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
                  dialogContext,
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

    if (confirmed != true) {
      return;
    }

    try {
      // -----------------------------------------------------
      // SUPABASE
      // -----------------------------------------------------

      if (status == 'synced') {
        await _cloudStorage
            .deleteRoute(
          route.id,
        );
      } else {
        try {
          await _cloudStorage
              .deleteRoute(
            route.id,
          );
        } catch (_) {}
      }

      // -----------------------------------------------------
      // SQLITE
      // -----------------------------------------------------

      await _localStorage
          .deleteRoute(
        route.id,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _routes.removeWhere(
          (
            item,
          ) =>
              item.id ==
              route.id,
        );

        _syncStatuses.remove(
          route.id,
        );
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Маршрут видалено',
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Помилка видалення: $e',
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Не вдалося видалити маршрут',
          ),
        ),
      );
    }
  }

  // =========================================================
  // ДЕТАЛІ
  // =========================================================

  Future<void> _openRouteDetails(
    RouteModel route,
  ) async {
    await Navigator.of(
      context,
    ).push(
      MaterialPageRoute(
        builder: (
          context,
        ) =>
            RouteDetailsScreen(
          route:
              route,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    // Після повернення оновлюємо список.
    await _loadRoutes();
  }

  // =========================================================
  // UI
  // =========================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar:
          AppBar(
        title:
            const Text(
          'Історія маршрутів',
        ),

        centerTitle:
            true,

        actions: [
          IconButton(
            tooltip:
                'Синхронізувати',

            onPressed:
                _loadRoutes,

            icon:
                const Icon(
              Icons.sync,
            ),
          ),
        ],
      ),

      body:
          _buildBody(),
    );
  }

  // =========================================================
  // BODY
  // =========================================================

  Widget _buildBody() {
    // =======================================================
    // LOADING
    // =======================================================

    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize:
              MainAxisSize.min,

          children: [
            CircularProgressIndicator(),

            SizedBox(
              height: 16,
            ),

            Text(
              'Завантаження маршрутів...',
            ),
          ],
        ),
      );
    }

    // =======================================================
    // ERROR
    // =======================================================

    if (_error != null) {
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

                size:
                    65,

                color:
                    Colors.grey,
              ),

              const SizedBox(
                height:
                    16,
              ),

              Text(
                _error!,

                textAlign:
                    TextAlign.center,
              ),

              const SizedBox(
                height:
                    16,
              ),

              FilledButton.icon(
                onPressed:
                    _loadRoutes,

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

    // =======================================================
    // EMPTY
    // =======================================================

    if (_routes.isEmpty) {
      return Column(
        children: [
          if (!_cloudAvailable)
            _buildOfflineBanner(),

          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,

                children: [
                  Icon(
                    Icons.route,

                    size:
                        70,

                    color:
                        Colors.grey,
                  ),

                  SizedBox(
                    height:
                        16,
                  ),

                  Text(
                    'Маршрутів поки немає',

                    style:
                        TextStyle(
                      fontSize:
                          18,

                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),

                  SizedBox(
                    height:
                        8,
                  ),

                  Text(
                    'Ваші маршрути '
                    'зʼявляться тут.',

                    textAlign:
                        TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // =======================================================
    // LIST
    // =======================================================

    return Column(
      children: [
        if (!_cloudAvailable)
          _buildOfflineBanner(),

        Expanded(
          child:
              RefreshIndicator(
            onRefresh:
                _loadRoutes,

            child:
                ListView.separated(
              padding:
                  const EdgeInsets.all(
                16,
              ),

              itemCount:
                  _routes.length,

              separatorBuilder:
                  (
                context,
                index,
              ) =>
                      const SizedBox(
                height:
                    10,
              ),

              itemBuilder:
                  (
                context,
                index,
              ) {
                final route =
                    _routes[index];

                final statistics =
                    route.statistics;

                final status =
                    _syncStatuses[
                            route.id] ??
                        'pending';

                final synced =
                    status ==
                        'synced';

                final routeName =
                    _getRouteName(
                  route,
                  index,
                );

                return Card(
                  clipBehavior:
                      Clip.antiAlias,

                  child:
                      InkWell(
                    onTap:
                        () {
                      _openRouteDetails(
                        route,
                      );
                    },

                    child:
                        Padding(
                      padding:
                          const EdgeInsets.all(
                        16,
                      ),

                      child:
                          Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.center,

                        children: [
                          // ===============================
                          // ICON
                          // ===============================

                          CircleAvatar(
                            radius:
                                25,

                            child:
                                Icon(
                              synced
                                  ? Icons.route
                                  : Icons
                                      .cloud_upload_outlined,
                            ),
                          ),

                          const SizedBox(
                            width:
                                16,
                          ),

                          // ===============================
                          // DATA
                          // ===============================

                          Expanded(
                            child:
                                Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,

                              children: [
                                // ---------------------------
                                // NAME
                                // ---------------------------

                                Text(
                                  routeName,

                                  maxLines:
                                      2,

                                  overflow:
                                      TextOverflow.ellipsis,

                                  style:
                                      const TextStyle(
                                    fontSize:
                                        17,

                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),

                                const SizedBox(
                                  height:
                                      6,
                                ),

                                // ---------------------------
                                // DATE
                                // ---------------------------

                                Text(
                                  _formatDate(
                                    route.startTime,
                                  ),
                                ),

                                const SizedBox(
                                  height:
                                      6,
                                ),

                                // ---------------------------
                                // STATISTICS
                                // ---------------------------

                                if (statistics !=
                                    null)
                                  Text(
                                    '${statistics.distanceKm.toStringAsFixed(2)} км'
                                    '  •  '
                                    '${statistics.formattedDuration}'
                                    '  •  '
                                    '${statistics.averageSpeedKmh.toStringAsFixed(1)} км/год',
                                  ),

                                const SizedBox(
                                  height:
                                      6,
                                ),

                                // ---------------------------
                                // POINTS
                                // ---------------------------

                                Text(
                                  'GPS-точок: '
                                  '${route.points.length}'
                                  '  •  '
                                  'Позначок: '
                                  '${route.waypoints.length}',
                                ),

                                const SizedBox(
                                  height:
                                      7,
                                ),

                                // ---------------------------
                                // SYNC
                                // ---------------------------

                                Row(
                                  children: [
                                    Icon(
                                      synced
                                          ? Icons
                                              .cloud_done_outlined
                                          : Icons
                                              .cloud_upload_outlined,

                                      size:
                                          16,

                                      color:
                                          synced
                                              ? Colors.grey
                                              : Colors.orange,
                                    ),

                                    const SizedBox(
                                      width:
                                          5,
                                    ),

                                    Expanded(
                                      child:
                                          Text(
                                        synced
                                            ? 'Збережено в хмарі'
                                            : 'Очікує синхронізації',

                                        style:
                                            TextStyle(
                                          fontSize:
                                              12,

                                          color:
                                              synced
                                                  ? Colors.grey
                                                  : Colors.orange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // ===============================
                          // EDIT / DELETE
                          // ===============================

                          Column(
                            mainAxisSize:
                                MainAxisSize.min,

                            children: [
                              IconButton(
                                tooltip:
                                    'Змінити назву',

                                onPressed:
                                    () {
                                  _editRouteName(
                                    route,
                                  );
                                },

                                icon:
                                    const Icon(
                                  Icons.edit_outlined,
                                ),
                              ),

                              IconButton(
                                tooltip:
                                    'Видалити',

                                onPressed:
                                    () {
                                  _deleteRoute(
                                    route,
                                  );
                                },

                                icon:
                                    const Icon(
                                  Icons.delete_outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // OFFLINE BANNER
  // =========================================================

  Widget _buildOfflineBanner() {
    return Container(
      width:
          double.infinity,

      padding:
          const EdgeInsets.symmetric(
        horizontal:
            16,
        vertical:
            10,
      ),

      color:
          Colors.orange.withValues(
        alpha:
            0.15,
      ),

      child:
          const Row(
        children: [
          Icon(
            Icons.cloud_off,
            size:
                20,
          ),

          SizedBox(
            width:
                10,
          ),

          Expanded(
            child:
                Text(
              'Офлайн режим. '
              'Показано локальні маршрути.',
            ),
          ),
        ],
      ),
    );
  }
}