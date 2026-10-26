import 'package:flutter/foundation.dart';

import 'route_storage_service.dart';
import 'supabase_route_service.dart';

class SyncResult {
  final int uploaded;
  final int downloaded;
  final bool cloudAvailable;

  const SyncResult({
    required this.uploaded,
    required this.downloaded,
    required this.cloudAvailable,
  });
}

class SyncService {
  SyncService._();

  static final SyncService instance =
      SyncService._();

  final RouteStorageService _localStorage =
      RouteStorageService.instance;

  final SupabaseRouteService _cloudStorage =
      SupabaseRouteService.instance;

  bool _isSyncing = false;

  // =========================================================
  // ТІЛЬКИ ВІДПРАВЛЕННЯ PENDING
  // =========================================================

  Future<int>
      syncPendingRoutes() async {
    if (_isSyncing) {
      return 0;
    }

    _isSyncing = true;

    try {
      return await _uploadPendingRoutes();
    } finally {
      _isSyncing = false;
    }
  }

  // =========================================================
  // ПОВНА СИНХРОНІЗАЦІЯ
  //
  // 1. SQLite pending -> Supabase
  // 2. Supabase -> SQLite
  // =========================================================

  Future<SyncResult>
      syncAll() async {
    if (_isSyncing) {
      return const SyncResult(
        uploaded: 0,
        downloaded: 0,
        cloudAvailable: true,
      );
    }

    _isSyncing = true;

    int uploaded = 0;
    int downloaded = 0;

    try {
      // -----------------------------------------------------
      // ЛОКАЛЬНІ PENDING -> SUPABASE
      // -----------------------------------------------------

      uploaded =
          await _uploadPendingRoutes();

      // -----------------------------------------------------
      // SUPABASE -> SQLITE
      // -----------------------------------------------------

      try {
        final cloudRoutes =
            await _cloudStorage
                .getRoutes();

        for (final route
            in cloudRoutes) {
          final localStatus =
              await _localStorage
                  .getSyncStatus(
            route.id,
          );

          // Якщо локально є pending,
          // він для нас важливіший.
          if (localStatus ==
              'pending') {
            continue;
          }

          await _localStorage
              .saveRoute(
            route,
            syncStatus:
                'synced',
          );

          if (localStatus ==
              null) {
            downloaded++;
          }
        }

        return SyncResult(
          uploaded: uploaded,
          downloaded: downloaded,
          cloudAvailable: true,
        );
      } catch (e) {
        debugPrint(
          'Не вдалося отримати '
          'маршрути з Supabase: $e',
        );

        // Інтернету може не бути.
        // Локальна історія все одно працює.
        return SyncResult(
          uploaded: uploaded,
          downloaded: downloaded,
          cloudAvailable: false,
        );
      }
    } finally {
      _isSyncing = false;
    }
  }

  // =========================================================
  // ВНУТРІШНЯ СИНХРОНІЗАЦІЯ PENDING
  // =========================================================

  Future<int>
      _uploadPendingRoutes() async {
    int count = 0;

    final pendingRoutes =
        await _localStorage
            .getPendingRoutes();

    for (final route
        in pendingRoutes) {
      try {
        await _cloudStorage
            .saveRoute(
          route,
        );

        await _localStorage
            .markAsSynced(
          route.id,
        );

        count++;
      } catch (e) {
        debugPrint(
          'Маршрут ${route.id} '
          'залишається pending: $e',
        );
      }
    }

    return count;
  }
}