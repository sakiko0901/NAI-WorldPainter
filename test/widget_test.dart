import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/presentation/navigation/app_destination.dart';
import 'package:nai_huishi/presentation/pages/home_page.dart';

void main() {
  test('home page defaults to the create destination', () {
    expect(HomePage.initialIndex, AppDestination.create.index);
  });

  test('legacy tab indices map to the matching persistent destinations', () {
    expect(AppDestination.fromLegacyTabIndex(1), AppDestination.create);
    expect(AppDestination.fromLegacyTabIndex(2), AppDestination.tools);
    expect(AppDestination.fromLegacyTabIndex(0), isNull);
    expect(AppDestination.fromLegacyTabIndex(3), isNull);
  });
}
