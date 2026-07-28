import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:test/test.dart';

void main() {
  const valid = BurnOrderInputs(
    followerDevice: 'device',
    harnessDirectory: '/harness',
    leonardDrive: '/leonard',
  );

  test('returns valid inputs unchanged', () {
    const preflight = BurnPreflight(
      directoryExists: _directoryExists,
      fileExists: _fileExists,
    );

    expect(preflight.validate(valid), same(valid));
  });

  for (final entry in <({
    String name,
    BurnOrderInputs inputs,
    String error,
  })>[
    (
      name: 'missing device',
      inputs: const BurnOrderInputs(
        followerDevice: '',
        harnessDirectory: '/harness',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight missing burn.follower_device',
    ),
    (
      name: 'missing harness directory',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight invalid burn.harness_dir: ',
    ),
    (
      name: 'invalid harness directory',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/missing',
        leonardDrive: '/leonard',
      ),
      error: 'burn preflight invalid burn.harness_dir: /missing',
    ),
    (
      name: 'missing leonard drive',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '',
      ),
      error: 'burn preflight invalid burn.leonard_drive: ',
    ),
    (
      name: 'invalid leonard drive',
      inputs: const BurnOrderInputs(
        followerDevice: 'device',
        harnessDirectory: '/harness',
        leonardDrive: '/missing',
      ),
      error: 'burn preflight invalid burn.leonard_drive: /missing',
    ),
  ]) {
    test(entry.name, () {
      const preflight = BurnPreflight(
        directoryExists: _directoryExists,
        fileExists: _fileExists,
      );

      expect(
        () => preflight.validate(entry.inputs),
        throwsA(
          isA<StateError>()
              .having((error) => error.message, 'message', entry.error),
        ),
      );
    });
  }
}

bool _directoryExists(String path) => path == '/harness';
bool _fileExists(String path) => path == '/leonard';
