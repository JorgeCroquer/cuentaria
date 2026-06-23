import 'package:contabilidad/application/cascade/cascade.dart';
import 'package:contabilidad/application/cascade/cascade_repository.dart';

/// In-memory adapter for [CascadeRepository].  Used in tests and as a fallback
/// before the database is available.
class InMemoryCascadeRepository implements CascadeRepository {
  Cascade? _cascade;

  @override
  Future<Cascade?> load() async => _cascade;

  @override
  Future<void> save(Cascade cascade) async {
    _cascade = _cascade != null ? _cascade!.mergeWith(cascade) : cascade;
  }
}
