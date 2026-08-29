part of '../vivrant_api.dart';

/// Profile, goals, health history, archive, settings, support, and search.
extension VivrantProfileApi on VivrantApi {
  Future<Profile> getProfile() async {
    final res =
        await _client.get<Map<String, dynamic>>('/api/mobile/profile');
    return Profile.fromJson(
      Map<String, dynamic>.from(res.data?['profile'] ?? res.data ?? {}),
    );
  }

  Future<Profile> updateProfile(Map<String, dynamic> body) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/api/mobile/profile',
      data: body,
    );
    return Profile.fromJson(
      Map<String, dynamic>.from(res.data?['profile'] ?? res.data ?? {}),
    );
  }

  Future<String> uploadAvatar(String filePath, {String? filename}) async {
    final name = filename ?? filePath.split(RegExp(r'[\\/]')).last;
    final mime = imageMediaType(name);
    final form = FormData.fromMap({
      'avatar': await MultipartFile.fromFile(
        filePath,
        filename: imageUploadFilename(name, prefix: 'avatar'),
        contentType: mime,
      ),
    });
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/api/mobile/profile/avatar',
      form,
    );
    final url = res.data?['avatar_url'] as String?;
    if (url == null || url.isEmpty) {
      throw StateError('Avatar upload succeeded but no URL was returned.');
    }
    return url;
  }

  Future<void> deleteAvatar() async {
    await _client.delete('/api/mobile/profile/avatar');
  }

  Future<Map<String, dynamic>> getPreferences() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/settings/preferences',
    );
    return Map<String, dynamic>.from(
      res.data?['settings'] as Map? ?? res.data ?? {},
    );
  }

  Future<void> saveListOrder(String module, List<int> ids) async {
    await _client.patch(
      '/api/mobile/settings/preferences',
      data: {'module': module, 'ids': ids},
    );
  }

  Future<List<HealthGoal>> listGoals() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/goals');
    return (res.data?['goals'] as List? ?? [])
        .map((e) => HealthGoal.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<HealthGoal> addGoal(Map<String, dynamic> body) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/goals',
      data: body,
    );
    return HealthGoal.fromJson(
      Map<String, dynamic>.from(res.data?['goal'] ?? res.data ?? {}),
    );
  }

  Future<void> updateGoalStatus(int id, String status) async {
    await _client.patch('/api/mobile/goals/$id', data: {'status': status});
  }

  Future<HealthGoal> updateGoal(int id, Map<String, dynamic> body) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/api/mobile/goals/$id',
      data: body,
    );
    return HealthGoal.fromJson(
      Map<String, dynamic>.from(res.data?['goal'] ?? res.data ?? {}),
    );
  }

  Future<void> deleteGoal(int id) async {
    await _client.delete('/api/mobile/goals/$id');
  }

  /// BMI-aware goal suggestions.
  Future<List<Map<String, dynamic>>> suggestGoalsAi() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/goals/suggest',
      options: ApiClient.aiOptions,
    );
    return (res.data?['goals'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<HealthGoal> acceptSuggestedGoal(Map<String, dynamic> body) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/goals/accept',
      data: body,
    );
    return HealthGoal.fromJson(
      Map<String, dynamic>.from(res.data?['goal'] ?? res.data ?? {}),
    );
  }

  /// Refresh health_goals.current_value from the member's live logs.
  Future<Map<String, dynamic>> refreshGoalProgress() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/goals/refresh-progress',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<Map<String, dynamic>>> healthHistory() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/health-history',
    );
    return (res.data?['entries'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> addHealthHistory(Map<String, dynamic> body) async {
    await _client.post('/api/mobile/health-history', data: body);
  }

  Future<void> deleteHealthHistory(int id) async {
    await _client.delete('/api/mobile/health-history/$id');
  }

  Future<String> archiveItems({
    required String entity,
    required List<int> ids,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/archive/bulk',
      data: {'op': 'archive', 'entity': entity, 'ids': ids},
    );
    return (res.data?['message'] as String?) ?? 'Archived.';
  }

  Future<String> restoreArchivedBulk(List<int> ids) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/archive/bulk',
      data: {'op': 'restore', 'ids': ids},
    );
    return (res.data?['message'] as String?) ?? 'Restored.';
  }

  /// BMI-aware health history analysis.
  Future<Map<String, dynamic>> analyzeHealthHistoryAi() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/health-history/analyze',
      options: ApiClient.aiOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> savePreferences(Map<String, dynamic> body) async {
    await _client.put('/api/mobile/settings/preferences', data: body);
  }

  Future<void> submitSupportTicket(Map<String, dynamic> body) async {
    await _client.post('/api/mobile/support/tickets', data: body);
  }

  Future<List<Map<String, dynamic>>> listSupportTickets() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/support/tickets',
    );
    return (res.data?['tickets'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<AppNotification>> listNotifications() async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/notifications',
    );
    return (res.data?['notifications'] as List? ?? [])
        .map(
          (e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  Future<void> markNotificationRead(int id) async {
    await _client.post('/api/mobile/notifications/$id/read');
  }

  Future<void> markAllNotificationsRead() async {
    await _client.post('/api/mobile/notifications/read-all');
  }

  Future<Map<String, dynamic>> search(String q) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/search',
      query: {'q': q},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    await _client.post(
      '/api/device-tokens',
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> unregisterDeviceToken(String token) async {
    await _client.delete('/api/device-tokens', data: {'token': token});
  }

  Future<List<Map<String, dynamic>>> listArchived() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/archive');
    final items = res.data?['items'];
    if (items is! List) return [];
    return [
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }

  Future<String> restoreArchived(int id) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/archive',
      data: {'id': id},
    );
    return (res.data?['message'] as String?) ?? 'Restored.';
  }

  Future<Map<String, dynamic>> exportBackup() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/archive/export');
    return Map<String, dynamic>.from(res.data?['dump'] ?? res.data ?? {});
  }

  Future<List<Map<String, dynamic>>> listActivity({String? entity}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/activity',
      query: {
        if (entity != null && entity.isNotEmpty) 'entity': entity,
      },
    );
    final items = res.data?['items'];
    if (items is! List) return [];
    return [
      for (final item in items)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
}
