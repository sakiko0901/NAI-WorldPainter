/// The three persistent destinations in the Android app shell.
enum AppDestination {
  create,
  assistant,
  tools;

  String get label => switch (this) {
    AppDestination.create => '创作',
    AppDestination.assistant => 'AI 助手',
    AppDestination.tools => '工具',
  };

  /// Maps destinations used by older pages to the current app shell.
  /// Legacy index 0 is a Gallery route action handled by the app shell.
  static AppDestination? fromLegacyTabIndex(int index) => switch (index) {
    1 => AppDestination.create,
    2 => AppDestination.tools,
    _ => null,
  };
}
