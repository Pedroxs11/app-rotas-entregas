Future<List<T>> mapBounded<T, S>(
  List<S> items,
  Future<T> Function(S item) worker, {
  int concurrency = 4,
}) async {
  if (concurrency < 1) {
    throw ArgumentError.value(concurrency, 'concurrency');
  }
  if (items.isEmpty) return <T>[];

  final results = List<T?>.filled(items.length, null);
  var next = 0;

  Future<void> runner() async {
    while (true) {
      final index = next++;
      if (index >= items.length) return;
      results[index] = await worker(items[index]);
    }
  }

  final workers = items.length < concurrency ? items.length : concurrency;
  await Future.wait(List.generate(workers, (_) => runner()));
  return results.cast<T>();
}
