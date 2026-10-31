import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Startup prompts wait until the home route is visible and other routes close.
class AppUpdateNavigationObserver extends NavigatorObserver {
  final _rootRouteCurrent = ValueNotifier<bool>(false);
  final _routes = <Route<dynamic>>[];
  final _exitingRoutes = <TransitionRoute<dynamic>>{};
  bool _disposed = false;

  ValueListenable<bool> get rootRouteCurrent => _rootRouteCurrent;

  void _publish() {
    if (_disposed) return;
    final top = _routes.isEmpty ? null : _routes.last;
    _rootRouteCurrent.value =
        _exitingRoutes.isEmpty && top != null && top.isFirst && top.isCurrent;
  }

  void _afterRemoval(Route<dynamic> route) {
    // A popped modal can still be fading out over the home page.
    if (route is TransitionRoute<dynamic>) {
      _exitingRoutes.add(route);
      _publish();
      route.completed.then((_) {
        _exitingRoutes.remove(route);
        _publish();
      });
    } else {
      _publish();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_disposed) return;
    _routes.add(route);
    _publish();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_disposed) return;
    _routes.remove(route);
    _afterRemoval(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_disposed) return;
    _routes.remove(route);
    _afterRemoval(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (_disposed) return;
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    _publish();
  }

  void dispose() {
    _disposed = true;
    _routes.clear();
    _exitingRoutes.clear();
    _rootRouteCurrent.dispose();
  }
}
