import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:nai_huishi/data/repositories/character_reference_catalog_repository.dart';
import 'package:nai_huishi/domain/entities/character_reference_asset.dart';
import 'package:nai_huishi/presentation/pages/character_reference_library_page.dart';
import 'package:path/path.dart' as p;

const _orbit = CharacterReferenceAsset(
  id: 'orbit',
  game: '银河纪行',
  category: '角色',
  name: '旅人',
  variant: '默认衣装',
  width: 720,
  height: 1280,
  bytes: 1024 * 1024,
  thumbnailUrls: [],
  downloadUrls: [],
  aliases: ['Traveler', 'トラベラー'],
);

const _orbitAlt = CharacterReferenceAsset(
  id: 'orbit-alt',
  game: '银河纪行',
  category: '服装',
  name: '旅人',
  variant: '礼服',
  width: 720,
  height: 1280,
  bytes: 2 * 1024 * 1024,
  thumbnailUrls: [],
  downloadUrls: [],
  aliases: ['Traveler', 'トラベラー'],
);

const _forest = CharacterReferenceAsset(
  id: 'forest',
  game: '星林物语',
  category: '角色',
  name: '林间使者',
  variant: '',
  width: 600,
  height: 960,
  bytes: 1024,
  thumbnailUrls: [],
  downloadUrls: [],
);

void main() {
  late Directory fixtures;
  late File fixtureImage;

  setUp(() {
    fixtures = Directory.systemTemp.createTempSync('reference-library-');
    fixtureImage = File(p.join(fixtures.path, 'reference.png'))
      ..writeAsBytesSync(img.encodePng(img.Image(width: 2, height: 2)));
  });

  tearDown(() {
    fixtureImage.deleteSync();
    fixtures.deleteSync();
  });

  testWidgets('multilingual search and scoped filters survive switching tabs',
      (tester) async {
    _usePhoneViewport(tester);
    final repository = _CatalogFake(fixtureImage.path)..store(_forest);
    await _openLibrary(tester, repository);

    final orbit = find.byKey(const ValueKey('orbit'));
    final alt = find.byKey(const ValueKey('orbit-alt'));
    final forest = find.byKey(const ValueKey('forest'));
    expect(orbit, findsOneWidget);
    expect(alt, findsOneWidget);
    expect(tester.getTopLeft(orbit).dy, tester.getTopLeft(alt).dy);

    final search = find.byKey(const ValueKey('reference-search-online'));
    await tester.enterText(search, 'トラベラー');
    await tester.pumpAndSettle();
    expect(orbit, findsOneWidget);
    expect(alt, findsOneWidget);
    expect(forest, findsNothing);
    await _select(tester, 'reference-game-filter', '银河纪行');
    await _select(tester, 'reference-category-filter', '服装');
    expect(orbit, findsNothing);
    expect(alt, findsOneWidget);

    await _tap(tester, find.text('已保存'));
    expect(forest, findsOneWidget);
    await _tap(tester, find.text('在线目录'));
    expect(tester.widget<TextField>(search).controller!.text, 'トラベラー');
    expect(alt, findsOneWidget);
    expect(orbit, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('batch download continues from saved files after cancellation',
      (tester) async {
    _usePhoneViewport(tester);
    final repository = _CatalogFake(fixtureImage.path)..cancelId = _orbitAlt.id;
    await _openLibrary(tester, repository);

    await _select(tester, 'reference-game-filter', '银河纪行');
    await _select(tester, 'reference-category-filter', '角色');
    await _tap(tester, find.text('下载整部作品'));
    expect(find.textContaining('2 张参考图待下载，约 3.0 MB'), findsOneWidget);
    await _tap(tester, find.text('开始下载'));
    expect(repository.downloads, ['orbit', 'orbit-alt']);
    expect(find.textContaining('正在下载 2/2'), findsOneWidget);
    await _tap(tester, find.text('取消下载'));
    expect(repository.saved.keys, ['orbit']);
    expect(find.text('已取消下载，本次保存 1 张'), findsOneWidget);

    repository.cancelId = null;
    await _tap(tester, find.text('下载整部作品'));
    expect(find.textContaining('1 张参考图待下载，约 2.0 MB'), findsOneWidget);
    await _tap(tester, find.text('开始下载'));
    expect(repository.downloads, ['orbit', 'orbit-alt', 'orbit-alt']);
    expect(repository.saved.keys, ['orbit', 'orbit-alt']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved references remain available when online loading fails',
      (tester) async {
    _usePhoneViewport(tester);
    final repository = _CatalogFake(fixtureImage.path)
      ..offline = true
      ..store(_orbit);
    await _openLibrary(tester, repository);
    expect(find.text('网络暂不可用'), findsOneWidget);
    await _tap(tester, find.byTooltip('目录来源'));
    expect(find.text(CharacterReferenceCatalogRepository.sourceName),
        findsOneWidget);
    expect(find.text(CharacterReferenceCatalogRepository.sourceResources),
        findsOneWidget);
    await _tap(tester, find.text('关闭'));

    await _tap(tester, find.text('已保存'));
    await _tap(tester, find.byKey(const ValueKey('orbit')));
    expect(find.textContaining('已保存，可离线使用'), findsOneWidget);
    expect(repository.previews, isEmpty);
    await _tap(tester, find.byTooltip('移除已保存的参考图'));
    await _tap(tester, find.text('取消'));
    expect(repository.saved.keys, ['orbit']);
    await _tap(tester, find.byTooltip('移除已保存的参考图'));
    await _tap(tester, find.text('移除'));
    expect(repository.saved, isEmpty);
    expect(find.textContaining('还没有已保存的参考图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picked images are named and grouped in the saved tab',
      (tester) async {
    _usePhoneViewport(tester);
    final repository = _CatalogFake(fixtureImage.path);
    await _openLibrary(tester, repository, picker: _PickerFake());
    await _tap(tester, find.text('已保存'));
    await _tap(tester, find.text('导入图片'));
    expect(find.text('已选 2 张图片，角色名取自文件名。'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('reference-import-game')), '  我的小队  ');
    await _tap(tester, find.text('导入'));

    expect(repository.imports, [
      (p.join('chapter', '新角色.png'), '新角色', '我的小队', '本地导入'),
      (p.join('chapter', '替补.jpg'), '替补', '我的小队', '本地导入'),
    ]);
    expect(find.text('新角色'), findsOneWidget);
    expect(find.text('替补'), findsOneWidget);
    expect(find.text('我的小队'), findsWidgets);
    expect(find.text('本地导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('async apply guards back, stays on cancel and returns on success',
      (tester) async {
    _usePhoneViewport(tester);
    final repository = _CatalogFake(fixtureImage.path)..store(_orbit);
    final response = Completer<bool>();
    var didReturn = false;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                didReturn = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (libraryContext) =>
                            CharacterReferenceLibraryPage(
                          repository: repository,
                          onApplyPrecise: (saved) async {
                            calls++;
                            expect(saved.asset, _orbit);
                            if (calls == 1) return response.future;
                            return await showDialog<bool>(
                                  context: libraryContext,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('切换为角色精确参考？'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(dialogContext)
                                                .pop(true),
                                        child: const Text('确认切换'),
                                      ),
                                    ],
                                  ),
                                ) ==
                                true;
                          },
                        ),
                      ),
                    ) ==
                    true;
              },
              child: const Text('打开工作台预设'),
            ),
          ),
        ),
      ),
    ));

    await _tap(tester, find.text('打开工作台预设'));
    await _tap(tester, find.text('已保存'));
    await _tap(tester, find.byKey(const ValueKey('orbit')));
    final apply = find.text('用作角色精确参考');
    expect(find.text('用作氛围转移'), findsNothing);
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pump();
    expect(calls, 1);
    expect(find.text('正在应用参考图…'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(apply, findsOneWidget);
    response.complete(false);
    await tester.pumpAndSettle();
    expect(apply, findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(didReturn, isFalse);

    await tester.tap(apply);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('切换为角色精确参考？'), findsOneWidget);
    await _tap(tester, find.text('确认切换'));
    expect(calls, 2);
    expect(didReturn, isTrue);
    expect(find.text('打开工作台预设'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CatalogFake extends CharacterReferenceCatalogRepository {
  _CatalogFake(this.imagePath);

  final String imagePath;
  bool offline = false;
  String? cancelId;
  final saved = <String, SavedCharacterReference>{};
  final downloads = <String>[];
  final previews = <String>[];
  final imports = <(String, String, String, String)>[];

  SavedCharacterReference store(CharacterReferenceAsset asset) =>
      saved[asset.id] = SavedCharacterReference(asset: asset, path: imagePath);

  @override
  Future<List<CharacterReferenceAsset>> load({bool refresh = false}) async {
    if (offline) throw StateError('网络暂不可用');
    return const [_orbit, _orbitAlt, _forest];
  }

  @override
  Future<List<SavedCharacterReference>> listSaved() async =>
      saved.values.toList();

  @override
  Future<String?> previewPath(CharacterReferenceAsset asset) async {
    previews.add(asset.id);
    return null;
  }

  @override
  Future<SavedCharacterReference> download(
    CharacterReferenceAsset asset, {
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(asset.id);
    onProgress?.call(1, 2);
    if (asset.id == cancelId) throw await cancelToken!.whenCancel;
    return store(asset);
  }

  @override
  Future<SavedCharacterReference> importLocal({
    required String path,
    required String name,
    String game = '其他',
    String category = '本地导入',
    String variant = '',
  }) async {
    imports.add((path, name, game, category));
    return store(CharacterReferenceAsset(
      id: path,
      game: game,
      category: category,
      name: name,
      variant: variant,
      width: 2,
      height: 2,
      bytes: 1,
      thumbnailUrls: const [],
      downloadUrls: const [],
    ));
  }

  @override
  Future<void> remove(SavedCharacterReference reference) async {
    saved.remove(reference.asset.id);
  }
}

class _PickerFake extends ImagePicker {
  @override
  Future<List<XFile>> pickMultiImage({
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    int? limit,
    bool requestFullMetadata = true,
  }) async =>
      [
        XFile(p.join('chapter', '新角色.png')),
        XFile(p.join('chapter', '替补.jpg')),
      ];
}

Future<void> _openLibrary(WidgetTester tester, _CatalogFake repository,
    {ImagePicker? picker}) async {
  await tester.pumpWidget(MaterialApp(
    home: CharacterReferenceLibraryPage(repository: repository, picker: picker),
  ));
  await tester.pumpAndSettle();
}

void _usePhoneViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String key, String value) async {
  final control = find.descendant(
    of: find.byKey(ValueKey(key)),
    matching: find.byType(DropdownButton<String>),
  );
  await _tap(tester, control);
  await _tap(tester, find.text(value).last);
}
