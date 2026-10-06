import 'dart:io';
import 'package:dio/dio.dart';

enum FaultType {
  none,
  serviceUnavailable, // HTTP 503
  networkFailure,     // SocketException
  timeout,            // Connection timeout
  corruptedPayload,   // 200 OK com corpo corrompido
}

class FaultInjectionInterceptor extends Interceptor {
  FaultType currentFault;
  int faultOccurrences;
  int _triggeredCount = 0;

  FaultInjectionInterceptor({
    this.currentFault = FaultType.none,
    this.faultOccurrences = 1,
  });

  int get triggeredCount => _triggeredCount;

  void reset() {
    _triggeredCount = 0;
    currentFault = FaultType.none;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (currentFault == FaultType.none || _triggeredCount >= faultOccurrences) {
      return handler.next(options);
    }

    _triggeredCount++;

    switch (currentFault) {
      case FaultType.serviceUnavailable:
        return handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 503,
              statusMessage: 'Chaos Service Unavailable',
            ),
            type: DioExceptionType.badResponse,
          ),
          true, // true propaga o erro atraves da cadeia reversa de interceptors
        );

      case FaultType.networkFailure:
        return handler.reject(
          DioException(
            requestOptions: options,
            error: const SocketException('Flapping Network Connection Aborted'),
            type: DioExceptionType.connectionError,
          ),
          true,
        );

      case FaultType.timeout:
        return handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionTimeout,
            message: 'Chaos Connection Timeout Injected',
          ),
          true,
        );

      case FaultType.corruptedPayload:
        return handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: '<<<INVALID_MALFORMED_NON_JSON_CORRUPTED_STREAM>>>',
          ),
          true,
        );

      case FaultType.none:
        return handler.next(options);
    }
  }
}
