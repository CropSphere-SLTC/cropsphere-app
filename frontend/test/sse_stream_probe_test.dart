// TEMPORARY DIAGNOSTIC PROBE — safe to delete after streaming diagnosis.
// Exercises the exact sendChatStream() logic (copied from api_service.dart,
// minus the Firebase-auth interceptor which cannot run in a VM test) against
// a local SSE server replaying the verified backend transcript, with
// adversarial chunking: events deliberately split mid-JSON across writes.
//
// Proves/disproves layers 1-3 of the streaming diagnosis on the dio IO
// adapter (= Android/iOS/desktop path). Web uses a different adapter.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

// Exact transcript shape produced by the verified backend
// (34 deltas in production; 5 here for brevity — same framing).
const _events = [
  '{"type": "text", "content": "Reasoning: "}',
  '{"type": "text", "content": "CropSphere dataset "}',
  '{"type": "text", "content": "(relevance 0.64)\\n\\n"}',
  '{"type": "text", "content": "Maha season "}',
  '{"type": "text", "content": "is best."}',
  '{"type": "metadata", "confidence": "Moderate confidence", "sources": ["CropSphere dataset: Carrot"], "suggested_followups": ["a", "b", "c"], "conversation_id": "conv-1"}',
];

Future<HttpServer> _startSseServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    req.response.headers.contentType = ContentType('text', 'event-stream');
    req.response.headers.set('Cache-Control', 'no-cache');
    req.response.bufferOutput = false;
    // Build the raw SSE payload, then send it in ADVERSARIAL chunks that
    // split events mid-JSON — simulates real TCP fragmentation.
    final payload = StringBuffer();
    for (final e in _events) {
      payload.write('data: $e\n\n');
    }
    payload.write('data: [DONE]\n\n');
    final raw = payload.toString();
    const chunkSize = 17; // prime-ish, guarantees ugly split points
    for (var i = 0; i < raw.length; i += chunkSize) {
      final end = (i + chunkSize < raw.length) ? i + chunkSize : raw.length;
      req.response.write(raw.substring(i, end));
      await req.response.flush();
      await Future.delayed(const Duration(milliseconds: 5));
    }
    await req.response.close();
  });
  return server;
}

/// Copy of ApiService.sendChatStream body (no auth interceptor).
Stream<Map<String, dynamic>> sendChatStreamProbe(
  Dio dio,
  Map<String, dynamic> requestJson, {
  required void Function(String) onRawChunk,
  required void Function(int, Map<String, String>) onResponse,
}) async* {
  ResponseBody body;
  try {
    final response = await dio.post<ResponseBody>(
      '/api/chat/stream',
      data: requestJson,
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
      ),
    );
    body = response.data!;
    onResponse(
      response.statusCode ?? 0,
      response.headers.map.map((k, v) => MapEntry(k, v.join(','))),
    );
  } on DioException catch (e) {
    yield {'type': 'error', 'code': 'dio:${e.type}'};
    return;
  }
  var buffer = '';
  var sawDone = false;
  try {
    await for (final chunk in body.stream.cast<List<int>>().transform(
      utf8.decoder,
    )) {
      onRawChunk(chunk);
      buffer += chunk;
      while (buffer.contains('\n\n')) {
        final idx = buffer.indexOf('\n\n');
        final raw = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 2);
        if (!raw.startsWith('data:')) continue;
        final payload = raw.substring(5).trim();
        if (payload == '[DONE]') {
          sawDone = true;
          yield {'type': 'done'};
          return;
        }
        yield jsonDecode(payload) as Map<String, dynamic>;
      }
    }
  } catch (_) {
    yield {'type': 'error', 'code': 'stream_interrupted'};
    return;
  }
  if (!sawDone) yield {'type': 'error', 'code': 'stream_interrupted'};
}

void main() {
  test('sendChatStream parses adversarially-chunked SSE on IO adapter', () async {
    final server = await _startSseServer();
    final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'));

    final rawChunks = <String>[];
    final received = <Map<String, dynamic>>[];
    final arrivals = <int>[];
    final sw = Stopwatch()..start();

    // ignore: avoid_print
    print('>>> STREAM START');
    await for (final event in sendChatStreamProbe(
      dio,
      {'message': 'best season for carrots in Nuwara Eliya', 'user_id': 'u'},
      onRawChunk: (c) => rawChunks.add(c),
      onResponse: (status, headers) =>
          // ignore: avoid_print
          print(
            '>>> RESPONSE status=$status content-type=${headers['content-type']}',
          ),
    )) {
      received.add(event);
      arrivals.add(sw.elapsedMilliseconds);
      // ignore: avoid_print
      print('>>> EVENT +${sw.elapsedMilliseconds}ms: $event');
    }

    // ignore: avoid_print
    print(
      '>>> raw chunk count: ${rawChunks.length} '
      '(first raw chunk: ${rawChunks.isNotEmpty ? rawChunks.first : "-"})',
    );

    // Layer 1: events flow
    expect(received.where((e) => e['type'] == 'text').length, 5);
    expect(received.where((e) => e['type'] == 'metadata').length, 1);
    expect(received.last['type'], 'done');
    // Layer 3: no parse errors despite mid-JSON chunk splits
    expect(received.where((e) => e['type'] == 'error'), isEmpty);
    // Incremental delivery: events spread over time, not one burst at the end
    expect(
      arrivals.last - arrivals.first,
      greaterThan(20),
      reason: 'events must arrive incrementally, not in one buffered lump',
    );

    await server.close(force: true);
  });
}
