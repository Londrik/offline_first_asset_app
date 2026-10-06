import 'dart:math';

class BackoffCalculator {
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;

  BackoffCalculator({
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    Random? random,
  }) : _random = random ?? Random();

  /// Fórmula de Full Jitter:
  /// delay = Uniform_Random(0, min(maxDelay, baseDelay * 2^retry))
  Duration calculateFullJitter({required int retryCount}) {
    if (retryCount < 0) retryCount = 0;

    final baseMs = baseDelay.inMilliseconds;
    final maxMs = maxDelay.inMilliseconds;

    // Previne overflow de potenciação usando limite seguro de shift
    final int safeShift = min(retryCount, 30);
    final int exponentialFactor = 1 << safeShift;

    // Calcula teto exponencial limitado pelo cap (maxDelay)
    final int calculatedCeilingMs = (baseMs * exponentialFactor) > maxMs
        ? maxMs
        : (baseMs * exponentialFactor);

    if (calculatedCeilingMs <= 0) return Duration.zero;

    // Sorteio uniforme no intervalo [0, calculatedCeilingMs]
    final int jitteredMs = _random.nextInt(calculatedCeilingMs + 1);

    return Duration(milliseconds: jitteredMs);
  }
}
