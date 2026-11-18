import '../studio_scroll_surface.dart';

/// Chat uses the same fixed glass header as the other workspaces.
class ChatScrollSurface extends StudioScrollSurface {
  const ChatScrollSurface({
    super.key,
    required super.header,
    super.initialHeaderHeight,
    super.footer,
    required super.bodyBuilder,
    super.onInsetsChanged,
    super.footerBottomInset,
    super.background,
  });
}
