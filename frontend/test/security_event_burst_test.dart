// test/security_event_burst_test.dart
// Grouping rules for the admin Security event timeline. A burst of identical
// events is one incident; rendering it as N identical rows buries everything
// else, so these pin down exactly what may and may not be collapsed.

import 'package:flutter_test/flutter_test.dart';
import 'package:cropsphere_app/models/admin_models.dart';

SecurityEvent _event({
  required String type,
  required DateTime at,
  String ip = '1.2.3.4',
  String uid = '',
  String email = '',
  String endpoint = '/api/chat',
  Map<String, dynamic>? details,
}) {
  return SecurityEvent(
    id: '${type}_${at.toIso8601String()}',
    type: type,
    uid: uid,
    email: email,
    ipAddress: ip,
    endpoint: endpoint,
    details: details ?? const {},
    timestamp: at.toIso8601String(),
  );
}

/// Newest-first, the order the timeline builds before grouping.
List<SecurityEvent> _descending(List<SecurityEvent> events) =>
    events..sort((a, b) => b.timestamp.compareTo(a.timestamp));

void main() {
  final t0 = DateTime.utc(2026, 8, 6, 14, 0);

  group('SecurityEventBurst.group', () {
    test('collapses a repeated attempt from one source into one row', () {
      final events = _descending([
        for (var i = 0; i < 8; i++)
          _event(
            type: 'failed_login',
            at: t0.add(Duration(seconds: i * 20)),
          ),
      ]);

      final bursts = SecurityEventBurst.group(events);

      expect(bursts.length, 1);
      expect(bursts.first.count, 8);
      expect(bursts.first.isBurst, isTrue);
    });

    test('a lone event is a burst of one and renders as an ordinary row', () {
      final bursts = SecurityEventBurst.group([
        _event(type: 'failed_login', at: t0),
      ]);

      expect(bursts.length, 1);
      expect(bursts.first.count, 1);
      expect(bursts.first.isBurst, isFalse);
    });

    test('different IPs stay separate — two attackers are not one', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0, ip: '1.1.1.1'),
        _event(
          type: 'failed_login',
          at: t0.add(const Duration(seconds: 10)),
          ip: '2.2.2.2',
        ),
      ]);

      expect(SecurityEventBurst.group(events).length, 2);
    });

    test('different event types stay separate', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0),
        _event(
          type: 'rate_limit_violation',
          at: t0.add(const Duration(seconds: 10)),
        ),
      ]);

      expect(SecurityEventBurst.group(events).length, 2);
    });

    test('different actors stay separate even from the same IP', () {
      final events = _descending([
        _event(type: 'banned_access_attempt', at: t0, email: 'a@x.com'),
        _event(
          type: 'banned_access_attempt',
          at: t0.add(const Duration(seconds: 10)),
          email: 'b@x.com',
        ),
      ]);

      expect(SecurityEventBurst.group(events).length, 2);
    });

    test('an identical event outside the window is a separate incident', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0),
        _event(
          type: 'failed_login',
          at: t0.add(SecurityEventBurst.window + const Duration(minutes: 1)),
        ),
      ]);

      expect(SecurityEventBurst.group(events).length, 2);
    });

    test('only adjacent events group, so the timeline stays chronological', () {
      // Same attacker either side of an unrelated event: three rows, in order,
      // not two with the middle one hoisted out of sequence.
      final events = _descending([
        _event(type: 'failed_login', at: t0),
        _event(
          type: 'rate_limit_violation',
          at: t0.add(const Duration(seconds: 30)),
        ),
        _event(type: 'failed_login', at: t0.add(const Duration(minutes: 1))),
      ]);

      final bursts = SecurityEventBurst.group(events);

      expect(bursts.length, 3);
      expect(bursts.map((b) => b.type).toList(), [
        'failed_login',
        'rate_limit_violation',
        'failed_login',
      ]);
    });

    test('keeps the newest event as the row and the oldest as the start', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0),
        _event(type: 'failed_login', at: t0.add(const Duration(minutes: 2))),
      ]);

      final burst = SecurityEventBurst.group(events).single;

      expect(
        burst.latest.timestamp,
        t0.add(const Duration(minutes: 2)).toIso8601String(),
      );
      expect(burst.firstTimestamp, t0.toIso8601String());
    });

    test('unparseable timestamps are never merged', () {
      final broken = SecurityEvent(
        id: 'x',
        type: 'failed_login',
        uid: '',
        email: '',
        ipAddress: '1.2.3.4',
        endpoint: '/api/chat',
        details: const {},
        timestamp: 'not-a-date',
      );

      expect(SecurityEventBurst.group([broken, broken]).length, 2);
    });

    test('empty input yields no rows', () {
      expect(SecurityEventBurst.group([]), isEmpty);
    });
  });

  group('SecurityEventBurst.endpointLabel', () {
    test('shows the shared endpoint when the burst hit only one', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0, endpoint: '/api/chat'),
        _event(
          type: 'failed_login',
          at: t0.add(const Duration(seconds: 10)),
          endpoint: '/api/chat',
        ),
      ]);

      expect(
        SecurityEventBurst.group(events).single.endpointLabel,
        '/api/chat',
      );
    });

    test('counts endpoints when one source sprayed several', () {
      final events = _descending([
        _event(type: 'failed_login', at: t0, endpoint: '/api/chat'),
        _event(
          type: 'failed_login',
          at: t0.add(const Duration(seconds: 10)),
          endpoint: '/api/yield/predict',
        ),
      ]);

      expect(
        SecurityEventBurst.group(events).single.endpointLabel,
        '2 endpoints',
      );
    });

    test('is empty when no endpoint was recorded', () {
      final bursts = SecurityEventBurst.group([
        _event(type: 'failed_login', at: t0, endpoint: ''),
      ]);

      expect(bursts.single.endpointLabel, '');
    });
  });
}
