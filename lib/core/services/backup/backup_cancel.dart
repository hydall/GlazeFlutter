/// Cancellation token shared by [BackupService] and importers.
class ImportCancellationToken {
  final bool Function() _isCancelled;
  final void Function() _check;

  const ImportCancellationToken._(this._isCancelled, this._check);

  bool get isCancelled => _isCancelled();

  /// Throws [ImportCancelledException] if cancellation was requested.
  void check() => _check();
}

/// Throws [ImportCancelledException] if cancellation was requested.
class ImportCancelledException implements Exception {
  const ImportCancelledException();
  @override
  String toString() => 'ImportCancelledException';
}

/// Sentinel token used by importers that don't support cancellation.
const ImportCancellationToken noCancel = ImportCancellationToken._(
  _neverCancelled,
  _neverCheck,
);

bool _neverCancelled() => false;
void _neverCheck() {}
