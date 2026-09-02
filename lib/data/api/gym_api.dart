part of '../vivrant_api.dart';

/// Gym catalog, sessions, and AI training programs.
extension VivrantGymApi on VivrantApi {
  Future<Map<String, dynamic>> gymOverview() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/gym');
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<Map<String, dynamic>>> gymExercises({String? equipment}) async {
    final res = await _client.get<Map<String, dynamic>>(
      '/api/mobile/gym/exercises',
      query: {if (equipment != null) 'equipment': equipment},
    );
    return (res.data?['exercises'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<List<GymSession>> gymSessions() async {
    final res =
        await _client.get<Map<String, dynamic>>('/api/mobile/gym/sessions');
    return (res.data?['sessions'] as List? ?? [])
        .map((e) => GymSession.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<GymSession> logGymSession(Map<String, dynamic> body) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/gym/sessions',
      data: body,
    );
    return GymSession.fromJson(
      Map<String, dynamic>.from(res.data?['session'] ?? res.data ?? {}),
    );
  }

  Future<void> deleteGymSession(int id) async {
    await _client.delete('/api/mobile/gym/sessions/$id');
  }

  Future<Map<String, dynamic>> createAiGymPlan({
    int? daysPerWeek,
    List<int>? trainingDays,
    int? sessionMinutes,
    String? level,
    List<String>? knownMachineSlugs,
    List<String>? knownCustomExercises,
    List<String>? avoidTargets,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/gym/plans/ai',
      data: {
        if (daysPerWeek != null) 'days_per_week': daysPerWeek,
        if (trainingDays != null && trainingDays.isNotEmpty) 'training_days': trainingDays,
        if (sessionMinutes != null) 'session_minutes': sessionMinutes,
        if (level != null && level.isNotEmpty) 'level': level,
        if (knownMachineSlugs != null && knownMachineSlugs.isNotEmpty)
          'known_machine_slugs': knownMachineSlugs,
        if (knownCustomExercises != null && knownCustomExercises.isNotEmpty)
          'known_custom_exercises': knownCustomExercises,
        if (avoidTargets != null && avoidTargets.isNotEmpty)
          'avoid_targets': avoidTargets,
      },
      options: ApiClient.aiOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>?> gymProgramDraft() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/gym/plans/draft');
    final draft = res.data?['draft'];
    return draft is Map ? Map<String, dynamic>.from(draft) : null;
  }

  Future<Map<String, dynamic>> gymProgramDraftAction({
    required String action,
    int? iso,
  }) async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/gym/plans/draft',
      data: {
        'action': action,
        if (iso != null) 'iso': iso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> commitGymProgramDraft() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/gym/plans/draft/commit',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> discardGymProgramDraft() async {
    await _client.delete('/api/mobile/gym/plans/draft');
  }

  Future<Map<String, dynamic>> saveGymProgramDraft(Map<String, dynamic> body) async {
    final res = await _client.put<Map<String, dynamic>>(
      '/api/mobile/gym/plans/draft',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['draft'] ?? res.data ?? {});
  }

  Future<Map<String, dynamic>?> gymLiveSession() async {
    final res = await _client.get<Map<String, dynamic>>('/api/mobile/gym/sessions/live');
    final session = res.data?['session'];
    return session is Map ? Map<String, dynamic>.from(session) : null;
  }

  Future<void> saveGymLiveSession(Map<String, dynamic> body) async {
    await _client.put('/api/mobile/gym/sessions/live', data: body);
  }

  Future<void> clearGymLiveSession() async {
    await _client.delete('/api/mobile/gym/sessions/live');
  }

  Future<List<Map<String, dynamic>>> gymPlans() async {
    final res =
        await _client.get<Map<String, dynamic>>('/api/mobile/gym/plans');
    return (res.data?['plans'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> deleteGymPlan(int id) async {
    await _client.delete('/api/mobile/gym/plans/$id');
  }

  Future<Map<String, dynamic>> updateGymPlan(int id, Map<String, dynamic> body) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/api/mobile/gym/plans/$id',
      data: body,
    );
    return Map<String, dynamic>.from(res.data?['plan'] ?? res.data ?? {});
  }

  Future<GymSession> updateGymSession(int id, Map<String, dynamic> body) async {
    final res = await _client.patch<Map<String, dynamic>>(
      '/api/mobile/gym/sessions/$id',
      data: body,
    );
    return GymSession.fromJson(
      Map<String, dynamic>.from(res.data?['session'] ?? res.data ?? {}),
    );
  }

  Future<Map<String, dynamic>> recommendMachinesAi() async {
    final res = await _client.post<Map<String, dynamic>>(
      '/api/mobile/gym/machines/recommend',
      options: ApiClient.aiOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> identifyMachineFromPhoto(String photoPath) async {
    final name = photoPath.split(RegExp(r'[\\/]')).last;
    final mime = imageMediaType(name);
    final form = FormData.fromMap({
      'photo': await MultipartFile.fromFile(
        photoPath,
        filename: imageUploadFilename(name, prefix: 'machine'),
        contentType: mime,
      ),
    });
    final res = await _client.postMultipart<Map<String, dynamic>>(
      '/api/mobile/gym/machines/identify',
      form,
      options: ApiClient.aiOptions,
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }
}
