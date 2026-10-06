import 'dart:io';
import 'package:dio/dio.dart';
import 'backoff_calculator.dart';

class ResilienceInterceptor extends Interceptor {
  final Dio dio;
  final BackoffCalculator backoffCalculator;
  final int maxRetries;
  final Future<void> Function(Duration duration)? sleepFunction;

  ResilienceInterceptor({
    required this.dio,
    BackoffCalculator? backoffCalculator,
    this.maxRetries = 3,
    this.sleepFunction,
  }) : backoffCalculator = backoffCalculator ?? BackoffCalculator();

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = Map<String, dynamic>.from(err.requestOptions.extra);
    final int retryCount = (extra['retry_count'] as int? ?? 0);

    if (_shouldRetry(err) && retryCount < maxRetries) {
      final nextRetry = retryCount + 1;
      extra['retry_count'] = nextRetry;

      final delay = backoffCalculator.calculateFullJitter(retryCount: nextRetry);

      if (sleepFunction != null) {
        await sleepFunction!(delay);
      } else if (delay.inMilliseconds > 0) {
        await Future<void>.delayed(delay);
      }

      try {
        final options = Options(
          method: err.requestOptions.method,
          headers: err.requestOptions.headers,
          responseType: err.requestOptions.responseType,
          contentType: err.requestOptions.contentType,
          extra: extra,
        );

        final response = await dio.request<dynamic>(
          err.requestOptions.path,
          data: err.requestOptions.data,
          queryParameters: err.requestOptions.queryParameters,
          options: options,
        );

        return handler.resolve(response);
      } on DioException catch (retryError) {
        return handler.next(retryError);
      } catch (e) {
        return handler.next(
          DioException(
            requestOptions: err.requestOptions,
            error: e,
          ),
        );
      }
    }

    return handler.next(err);
  }

  bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }

    if (err.error is SocketException) {
      return true;
    }

    final statusCode = err.response?.statusCode;
    if (statusCode != null) {
      return statusCode >= 500 && statusCode <= 504;
    }

    return false;
  }
}
