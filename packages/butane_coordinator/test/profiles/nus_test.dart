import 'package:butane_coordinator/butane_coordinator.dart';
import 'package:test/test.dart';

void main() {
  test('NusUuids constants match Nordic NUS', () {
    expect(NusUuids.service, '6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
    expect(NusUuids.rx,      '6E400002-B5A3-F393-E0A9-E50E24DCCA9E');
    expect(NusUuids.tx,      '6E400003-B5A3-F393-E0A9-E50E24DCCA9E');
  });

  test('buildAddServicePayload shape', () {
    final p = NusUuids.buildAddServicePayload();
    expect(p['uuid'], NusUuids.service);
    expect(p['isPrimary'], true);
    final chars = p['characteristics'] as List;
    expect(chars, hasLength(2));
    final rx = chars[0] as Map;
    expect(rx['uuid'], NusUuids.rx);
    expect((rx['properties'] as Map)['write'], true);
    expect((rx['properties'] as Map)['writeWithoutResponse'], true);
    expect((rx['permissions'] as Map)['writeable'], true);
    expect(rx.containsKey('value'), false);
    final tx = chars[1] as Map;
    expect((tx['properties'] as Map)['notify'], true);
    expect((tx['permissions'] as Map)['readable'], true);
    expect(tx.containsKey('value'), false);
  });
}
