import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nai_huishi/presentation/widgets/studio_background.dart';

/// A continuous ambient background beneath both the page and its glass header.
class StudioScaffold extends StatelessWidget {
  const StudioScaffold(
      {super.key,
      required this.appBar,
      required this.body,
      this.bottomNavigationBar});
  final PreferredSizeWidget appBar;
  final Widget body;
  final Widget? bottomNavigationBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Theme(
      data: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
      )),
      child: ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: Stack(children: [
          const Positioned.fill(child: StudioBackground()),
          Scaffold(
              backgroundColor: Colors.transparent,
              appBar: appBar,
              body: body,
              bottomNavigationBar: bottomNavigationBar),
        ]),
      ),
    );
  }
}
