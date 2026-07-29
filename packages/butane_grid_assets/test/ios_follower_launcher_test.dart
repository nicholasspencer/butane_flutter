import 'dart:convert';
import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  test('selects flutter forwarded URI over device GRID_VM_URI', () {
    const transcript = '''
GRID_VM_URI=http://192.168.4.36:55720/device-auth/
A Dart VM Service on Nico's iPad mini is available at: http://127.0.0.1:49458/mac-auth/
''';

    expect(
      flutterForwardedVmServiceWsUri(transcript),
      'ws://127.0.0.1:49458/mac-auth/ws',
    );
  });

  test('probes exploration readiness through a loopback VM service', () async {
    var extensionRegistered = true;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path.endsWith('/getVM')) {
        request.response.write(
          jsonEncode(<String, Object>{
            'isolates': <Object>[
              <String, String>{'id': 'isolates/42'},
            ],
          }),
        );
      } else if (request.uri.path.endsWith('/getIsolate')) {
        expect(request.uri.queryParameters['isolateId'], 'isolates/42');
        request.response.write(
          jsonEncode(<String, Object>{
            'extensionRPCs': extensionRegistered
                ? <String>['ext.exploration.butane']
                : <String>[],
          }),
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await server.close(force: true);
      await serving.cancel();
    });
    final base = Uri.parse('http://127.0.0.1:${server.port}/auth/');

    expect(await isIosExplorationReady(base), isTrue);
    extensionRegistered = false;
    expect(await isIosExplorationReady(base), isFalse);
  });

  test('resolves every valid iOS mDNS address for every port', () {
    const lookupOutput = '''
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55433
 authCode=first
com.nicospencer.butaneHarness._dartVmService._tcp.local. can be reached at ipad.local.:55434
 authCode=second
''';
    const addressOutput = '''
10:11:12.000  Add  2  34 ipad.local.  0.0.0.0         0 No Such Record
10:11:12.001  Add  2  35 ipad.local.  169.254.243.58 120
10:11:12.002  Add  2  23 ipad.local.  192.168.4.36   120
10:11:12.003  Rmv  0  23 ipad.local.  10.0.0.8       120
10:11:12.004  Add  2  23 ipad.local.  10.0.0.9
10:11:12.005  Add  2  23 ipad.local.  999.1.1.1      120
''';

    final candidates = resolveIosMdnsCandidates(
      lookupOutput: lookupOutput,
      addressOutput: addressOutput,
    );

    expect(candidates, hasLength(4));
    expect(
      candidates,
      containsAll(<IosMdnsCandidate>[
        (ip: '169.254.243.58', port: 55433, authCode: 'first'),
        (ip: '192.168.4.36', port: 55433, authCode: 'first'),
        (ip: '169.254.243.58', port: 55434, authCode: 'second'),
        (ip: '192.168.4.36', port: 55434, authCode: 'second'),
      ]),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('0.0.0.0')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('10.0.0.8')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('10.0.0.9')),
    );
    expect(
      candidates.map((candidate) => candidate.ip),
      isNot(contains('999.1.1.1')),
    );
  });
}
