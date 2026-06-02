import 'dart:async';

class EventHub {
  static final Map<String, StreamController<Event>> _controllers = {};

  static void publish(String event, [dynamic data]) {
    final controller = _controllers[event];
    if (controller != null && !controller.isClosed) {
      controller.add(Event(event, data));
    }
  }

  static StreamSubscription<Event> subscribe(
      String event, void Function(dynamic data) onEvent) {
    _controllers.putIfAbsent(event, () => StreamController<Event>.broadcast());
    return _controllers[event]!.stream.listen((e) => onEvent(e.data));
  }

  static void dispose(String event) {
    final controller = _controllers[event];
    if (controller != null) {
      controller.close();
      _controllers.remove(event);
    }
  }

  static void closeAll() {
    for (final controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

class Event {
  final String name;
  final dynamic data;
  Event(this.name, this.data);
}
