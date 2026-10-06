import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_first_asset_app/core/resilience/backoff_calculator.dart';

class StubRandom implements Random {
  final double nextDoubleValue;
  final int nextIntValue;

  StubRandom({this.nextDoubleValue = 0.5, this.nextIntValue = 0});

  @override
  bool nextBool() => true;

  @override
  double nextDouble() => nextDoubleValue;

  @override
  int nextInt(int max) => nextIntValue.clamp(0, max - 1);
}

void main() {
  group('BackoffCalculator - Full Jitter Mathematical Properties', () {
    const baseDelay = Duration(milliseconds: 200);
    const maxDelay = Duration(seconds: 5);

    test('deve respeitar estritamente o limite superior min(maxDelay, base * 2^retry)', () {
      final calculator = BackoffCalculator(baseDelay: baseDelay, maxDelay: maxDelay);

      for (int retry = 0; retry < 15; retry++) {
        final expectedMaxMs = min(
          maxDelay.inMilliseconds,
          baseDelay.inMilliseconds * (1 << min(retry, 30)),
        );

        for (int sample = 0; sample < 50; sample++) {
          final jittered = calculator.calculateFullJitter(retryCount: retry);
          expect(jittered.inMilliseconds, greaterThanOrEqualTo(0));
          expect(jittered.inMilliseconds, lessThanOrEqualTo(expectedMaxMs));
        }
      }
    });

    test('deve estabilizar no cap quando o retry ultrapassar o maxDelay (prevencao Thundering Herd)', () {
      final calculator = BackoffCalculator(baseDelay: baseDelay, maxDelay: maxDelay);

      for (int sample = 0; sample < 100; sample++) {
        final jittered = calculator.calculateFullJitter(retryCount: 20);
        expect(jittered.inMilliseconds, lessThanOrEqualTo(maxDelay.inMilliseconds));
        expect(jittered.inMilliseconds, greaterThanOrEqualTo(0));
      }
    });

    test('deve tratar retries negativos como retry 0', () {
      final calculator = BackoffCalculator(baseDelay: baseDelay, maxDelay: maxDelay);
      final jittered = calculator.calculateFullJitter(retryCount: -5);

      expect(jittered.inMilliseconds, greaterThanOrEqualTo(0));
      expect(jittered.inMilliseconds, lessThanOrEqualTo(baseDelay.inMilliseconds));
    });

    test('deve utilizar a injecao de Random para resolucao deterministica em testes', () {
      final stubRandom = StubRandom(nextIntValue: 150);
      final calculator = BackoffCalculator(
        baseDelay: baseDelay,
        maxDelay: maxDelay,
        random: stubRandom,
      );

      final jittered = calculator.calculateFullJitter(retryCount: 1);
      expect(jittered.inMilliseconds, equals(150));
    });
  });
}
