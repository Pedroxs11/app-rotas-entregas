import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_rotas_entregas/services/bounded_async.dart';

void main() {
  test('preserves input order while running concurrently', () async {
    final result = await mapBounded<int, int>(
      [1, 2, 3, 4, 5],
      (item) async {
        await Future<void>.delayed(Duration(milliseconds: (6 - item) * 2));
        return item * 10;
      },
      concurrency: 3,
    );

    expect(result, [10, 20, 30, 40, 50]);
  });

  test('never exceeds configured concurrency', () async {
    var active = 0;
    var peak = 0;

    await mapBounded<int, int>(
      List.generate(24, (i) => i),
      (item) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return item;
      },
      concurrency: 4,
    );

    expect(peak, lessThanOrEqualTo(4));
    expect(peak, greaterThan(1));
  });

  test('supports empty lists and rejects invalid concurrency', () async {
    expect(
      await mapBounded<int, int>(<int>[], (item) async => item),
      isEmpty,
    );

    expect(
      () => mapBounded<int, int>([1], (item) async => item, concurrency: 0),
      throwsArgumentError,
    );
  });
}
