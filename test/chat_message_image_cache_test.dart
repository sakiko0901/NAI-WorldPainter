import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nai_huishi/domain/entities/llm_message.dart';
import 'package:nai_huishi/presentation/app_theme.dart';
import 'package:nai_huishi/presentation/widgets/llm_chat/chat_message_bubble.dart';

void main() {
  testWidgets('message updates reuse image bytes until the attachment changes',
      (tester) async {
    const source =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';
    const replacement =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/aWQAAAAASUVORK5CYII=';
    Future<void> pump(String text, String image) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildNaiHuishiTheme(Brightness.dark),
        home: Scaffold(
          body: ChatMessageBubble(
            message: LlmMessage(
              id: 1,
              sessionId: 'chat',
              role: LlmMessageRole.user,
              content: text,
              createdAt: DateTime(2026),
              imageBase64: image,
            ),
            messageIndex: 0,
            onRetry: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Uint8List bytes() {
      final provider = tester.widget<Image>(find.byType(Image)).image;
      return ((provider as ResizeImage).imageProvider as MemoryImage).bytes;
    }

    await pump('原始消息', source);
    final first = bytes();
    await pump('文字更新，图片不变', source);
    expect(identical(bytes(), first), isTrue);
    await tester.tap(find.byType(SelectableText));
    await tester.pumpAndSettle();
    expect(identical(bytes(), first), isTrue);
    await pump('更换参考图片', replacement);
    expect(identical(bytes(), first), isFalse);
    expect(tester.takeException(), isNull);
  });
}
