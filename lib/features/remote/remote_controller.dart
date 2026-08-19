import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:toolbox/features/remote/remote_models.dart';
import 'package:toolbox/features/remote/remote_store.dart';

final remoteStoreProvider = Provider<RemoteStore>((ref) => RemoteStore());

final sshConnectionsProvider =
    NotifierProvider<RemoteController, List<SshConnection>>(
  RemoteController.new,
);

/// SSH 连接信息状态：启动加载，每次变更立即持久化。
class RemoteController extends Notifier<List<SshConnection>> {
  @override
  List<SshConnection> build() => ref.watch(remoteStoreProvider).load();

  void _persist() => ref.read(remoteStoreProvider).save(state);

  SshConnection _byId(String id) => state.firstWhere(
        (c) => c.id == id,
        orElse: () => throw StateError('连接不存在: $id'),
      );

  void add(SshConnection connection) {
    state = [...state, connection];
    _persist();
  }

  void update(SshConnection connection) {
    _byId(connection.id);
    state = [
      for (final c in state)
        if (c.id == connection.id) connection else c,
    ];
    _persist();
  }

  void delete(String id) {
    state = state.where((c) => c.id != id).toList();
    _persist();
  }
}
