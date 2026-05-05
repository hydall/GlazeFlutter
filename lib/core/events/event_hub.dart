import 'dart:async';

class EventHub {
  static final _controllers = <String, StreamController<_Event>>{};

  static void publish(String event, [dynamic data]) {
    final controller = _controllers[event];
    if (controller != null && !controller.isClosed) {
      controller.add(_Event(event, data));
    }
  }

  static StreamSubscription subscribe(
      String event, void Function(dynamic data) onEvent) {
    _controllers.putIfAbsent(event, () => StreamController<_Event>.broadcast());
    return _controllers[event]!.stream.listen((e) => onEvent(e.data));
  }

  static void dispose(String event) {
    _controllers[event]?.close();
    _controllers.remove(event);
  }
}

class _Event {
  final String name;
  final dynamic data;
  _Event(this.name, this.data);
}
