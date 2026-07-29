import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class ResumableDownloader {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    sendTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(hours: 2), // Большой таймаут для гигабайтных файлов
  ));

  /// Скачивает файл с возможностью докачки (.part).
  ///
  /// [url] — ссылка на файл (например, HuggingFace LFS).
  /// [savePath] — конечный путь сохранения файла.
  /// [cancelToken] — токен отмены Dio.
  /// [onProgress] — коллбек прогресса: (receivedBytes, totalBytes, speedBytesPerSecond).
  static Future<void> download({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required void Function(int received, int total, double speed) onProgress,
  }) async {
    final tempPath = '$savePath.part';
    final tempFile = File(tempPath);

    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    // 1. Запрашиваем размер удаленного файла через HEAD
    int totalBytes = 0;
    try {
      final headRes = await _dio.head(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      final contentLength = headRes.headers.value(Headers.contentLengthHeader);
      totalBytes = int.tryParse(contentLength ?? '') ?? 0;
    } catch (e) {
      debugPrint('[ResumableDownloader] HEAD request failed: $e. Trying GET Range...');
    }

    // 2. Если HEAD не дал размер, пробуем через GET Range=0-0
    if (totalBytes == 0) {
      try {
        final getRes = await _dio.get(
          url,
          options: Options(
            headers: {'Range': 'bytes=0-0'},
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        final contentRange = getRes.headers.value('content-range');
        if (contentRange != null) {
          final parts = contentRange.split('/');
          if (parts.length > 1) {
            totalBytes = int.tryParse(parts.last.trim()) ?? 0;
          }
        }
        if (totalBytes == 0) {
          final contentLength = getRes.headers.value(Headers.contentLengthHeader);
          totalBytes = int.tryParse(contentLength ?? '') ?? 0;
        }
      } catch (e) {
        debugPrint('[ResumableDownloader] GET Range request failed: $e');
      }
    }

    debugPrint('[ResumableDownloader] Size remote: $totalBytes, local temp: $existingBytes');

    // Если файл на сервере полностью совпадает с локальным temp, просто переименовываем
    if (totalBytes > 0 && existingBytes >= totalBytes) {
      final finalFile = File(savePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(savePath);
      onProgress(totalBytes, totalBytes, 0);
      return;
    }

    final headers = <String, dynamic>{
      'Connection': 'keep-alive',
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    };

    bool isResume = false;
    if (existingBytes > 0) {
      headers['Range'] = 'bytes=$existingBytes-';
      isResume = true;
      debugPrint('[ResumableDownloader] Requesting Range: bytes=$existingBytes-');
    }

    // 3. Запускаем стрим-загрузку
    final Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
        cancelToken: cancelToken,
      );
    } catch (e) {
      // Если при докачке Range выдал ошибку (например, 416 Range Not Satisfiable), пробуем с начала
      if (isResume) {
        debugPrint('[ResumableDownloader] Range request failed. Restarting download from scratch.');
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        return download(
          url: url,
          savePath: savePath,
          cancelToken: cancelToken,
          onProgress: onProgress,
        );
      }
      rethrow;
    }

    final responseBody = response.data;
    if (responseBody == null) {
      throw Exception('Response body is null');
    }

    final isPartial = response.statusCode == 206;
    final IOSink sink;
    int receivedBytes;

    if (isPartial && isResume) {
      debugPrint('[ResumableDownloader] Server accepted Range request (Status 206). Appending to file.');
      sink = tempFile.openWrite(mode: FileMode.writeOnlyAppend);
      receivedBytes = existingBytes;
    } else {
      debugPrint('[ResumableDownloader] Downloading file from scratch (Status ${response.statusCode}).');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      sink = tempFile.openWrite(mode: FileMode.write);
      receivedBytes = 0;
    }

    final startTime = DateTime.now().millisecondsSinceEpoch;
    int lastTime = startTime;
    int lastBytes = receivedBytes;

    try {
      await for (final chunk in responseBody.stream) {
        if (cancelToken.isCancelled) {
          await sink.close();
          throw DioException(
            requestOptions: response.requestOptions,
            type: DioExceptionType.cancel,
            message: 'Download cancelled by user',
          );
        }

        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now().millisecondsSinceEpoch;
        final elapsed = now - lastTime;
        if (elapsed > 400) { // Обновляем прогресс каждые 400мс
          final speed = (receivedBytes - lastBytes) * 1000.0 / elapsed; // байт/сек
          onProgress(receivedBytes, totalBytes > 0 ? totalBytes : receivedBytes, speed);
          lastTime = now;
          lastBytes = receivedBytes;
        }
      }

      await sink.flush();
      await sink.close();

      // Проверка целостности
      final finalTempSize = await tempFile.length();
      if (totalBytes > 0 && finalTempSize < totalBytes) {
        throw Exception('Downloaded file is incomplete: $finalTempSize of $totalBytes bytes');
      }

      final finalFile = File(savePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await tempFile.rename(savePath);
      onProgress(receivedBytes, totalBytes, 0);

    } catch (e) {
      await sink.close();
      rethrow;
    }
  }
}
