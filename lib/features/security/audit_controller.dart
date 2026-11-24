import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/supabase_providers.dart';
import 'data/audit_entry.dart';
import 'data/audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(ref.watch(supabaseClientProvider)),
);

class AuditState {
  const AuditState({
    this.entries = const [],
    this.names = const {},
    this.loading = false,
    this.hasMore = true,
    this.deniedOnly = false,
    this.error,
  });

  final List<AuditEntry> entries;
  final Map<String, String> names;
  final bool loading;
  final bool hasMore;
  final bool deniedOnly;
  final String? error;
}

/// autoDispose: the list is thrown away when the person signs out, so one
/// person's audit entries can never show up for the next person.
class AuditController extends AutoDisposeNotifier<AuditState> {
  static const int pageSize = 30;

  AuditRepository get _repo => ref.read(auditRepositoryProvider);

  @override
  AuditState build() {
    Future.microtask(refresh);
    return const AuditState(loading: true);
  }

  Future<void> refresh() async {
    final denied = state.deniedOnly;
    state = AuditState(
      entries: state.entries,
      names: state.names,
      deniedOnly: denied,
      loading: true,
    );
    try {
      final names = state.names.isEmpty ? await _repo.actorNames() : state.names;
      final rows = await _repo.fetch(offset: 0, limit: pageSize, deniedOnly: denied);
      state = AuditState(
        entries: rows,
        names: names,
        deniedOnly: denied,
        hasMore: rows.length == pageSize,
      );
    } catch (_) {
      state = AuditState(
        entries: state.entries,
        names: state.names,
        deniedOnly: denied,
        hasMore: state.hasMore,
        error: 'Could not load the audit log. Pull down to try again.',
      );
    }
  }

  Future<void> loadMore() async {
    if (state.loading || !state.hasMore) return;
    final denied = state.deniedOnly;
    state = AuditState(
      entries: state.entries,
      names: state.names,
      deniedOnly: denied,
      loading: true,
      hasMore: state.hasMore,
    );
    try {
      final rows = await _repo.fetch(
        offset: state.entries.length,
        limit: pageSize,
        deniedOnly: denied,
      );
      state = AuditState(
        entries: [...state.entries, ...rows],
        names: state.names,
        deniedOnly: denied,
        hasMore: rows.length == pageSize,
      );
    } catch (_) {
      state = AuditState(
        entries: state.entries,
        names: state.names,
        deniedOnly: denied,
        hasMore: state.hasMore,
        error: 'Could not load more entries.',
      );
    }
  }

  void setDeniedOnly(bool value) {
    if (state.deniedOnly == value) return;
    state = AuditState(names: state.names, deniedOnly: value, loading: true);
    refresh();
  }
}

final auditControllerProvider =
    AutoDisposeNotifierProvider<AuditController, AuditState>(AuditController.new);

class VerifyState {
  const VerifyState({this.running = false, this.result, this.error});

  final bool running;
  final ChainResult? result;
  final String? error;
}

class VerifyController extends AutoDisposeNotifier<VerifyState> {
  @override
  VerifyState build() => const VerifyState();

  Future<void> run() async {
    state = const VerifyState(running: true);
    try {
      final result = await ref.read(auditRepositoryProvider).verify();
      state = VerifyState(result: result);
    } catch (_) {
      state = const VerifyState(error: 'Could not reach the server. Try again.');
    }
  }
}

final verifyControllerProvider =
    AutoDisposeNotifierProvider<VerifyController, VerifyState>(VerifyController.new);