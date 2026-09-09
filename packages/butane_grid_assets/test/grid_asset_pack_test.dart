import 'dart:io';

import 'package:butane_grid_assets/butane_grid_assets.dart';
import 'package:grid_sdk/grid_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('GridAssetsPack', () {
    test('declares the public human burn skill', () {
      final definition = GridAssetsPack.definition;

      expect(definition.package, 'butane_grid_assets');
      expect(definition.assets, hasLength(1));
      expect(definition.assets.single, same(GridAssetsPack.skillBurn));

      final asset = definition.assets.single;
      expect(asset.assetKey.package, 'butane_grid_assets');
      expect(asset.assetKey.id, 'burn');
      expect(asset.assetKey.kind, AssetKind.skill);
      expect(asset.audience, AssetAudience.human);
      expect(asset.visibility, AssetVisibility.public);
      expect(asset.selector, isA<AlwaysApplies>());
      expect(asset.artifacts, hasLength(1));
      expect(asset.artifacts.single.target, AssetDeliveryTarget.claude);
      expect(
        asset.artifacts.single.path,
        'extension/station_overlay/claude/skills/burn/SKILL.md',
      );
      expect(GridAssetsPack.stationOverlayMappings, <String, String>{
        'claude': '.claude',
      });
    });

    test('generator check is byte-idempotent', () async {
      final dartDeclaration = File('lib/src/assets/grid_asset_pack.dart');
      final mcpMirror = File('extension/mcp/config.yaml');
      final dartBefore = dartDeclaration.readAsBytesSync();
      final mcpBefore = mcpMirror.readAsBytesSync();

      final result = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'tool/generate_grid_assets.dart',
        '--check',
      ], workingDirectory: Directory.current.path);

      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(
        result.stdout as String,
        contains('grid: 1 assets, 0 with an UNDECLARED selector'),
      );
      expect(result.stdout as String, isNot(contains('STALE ')));
      expect(dartDeclaration.readAsBytesSync(), dartBefore);
      expect(mcpMirror.readAsBytesSync(), mcpBefore);
    });

    test('generator refuses a malformed grid block loudly', () async {
      final fixture = Directory.systemTemp.createTempSync(
        'butane_grid_assets_grid_pack_test.',
      );
      addTearDown(() => fixture.deleteSync(recursive: true));
      _copyPackage(Directory.current, fixture);

      final copiedPubspec = File('${fixture.path}/pubspec.yaml');
      final pubspec = copiedPubspec.readAsStringSync();
      final gridBlockStart = pubspec.lastIndexOf('\ngrid:\n');
      expect(gridBlockStart, isNonNegative);
      copiedPubspec.writeAsStringSync(
        '${pubspec.substring(0, gridBlockStart + 1)}'
        'grid:\n'
        '  assets: malformed\n',
      );

      final packageConfig = _findWorkspacePackageConfig(Directory.current);
      final result = await Process.run(Platform.resolvedExecutable, <String>[
        '--packages=${packageConfig.path}',
        'run',
        'tool/generate_grid_assets.dart',
      ], workingDirectory: fixture.path);

      expect(result.exitCode, 2);
      expect(
        result.stderr as String,
        contains('grid: "butane_grid_assets": assets: must be a list'),
      );
    });
  });
}

void _copyPackage(Directory source, Directory destination) {
  for (final entity in source.listSync(followLinks: false)) {
    if (entity is Directory && _basename(entity.path) == '.dart_tool') {
      continue;
    }
    final targetPath = '${destination.path}/${_basename(entity.path)}';
    if (entity is Directory) {
      final target = Directory(targetPath)..createSync();
      _copyPackage(entity, target);
    } else if (entity is File) {
      entity.copySync(targetPath);
    } else if (entity is Link) {
      Link(targetPath).createSync(entity.targetSync());
    }
  }
}

File _findWorkspacePackageConfig(Directory start) {
  var directory = start.absolute;
  while (true) {
    final candidate = File('${directory.path}/.dart_tool/package_config.json');
    if (candidate.existsSync()) {
      return candidate;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('workspace .dart_tool/package_config.json not found');
    }
    directory = parent;
  }
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
