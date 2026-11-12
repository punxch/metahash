/// A value that can be initialized once and read until it is taken.
final class RoCell<T> {
  RoCell() : _value = _unset;
  RoCell.initialized(T value) : _value = value;

  static final _unset = Object();
  Object? _value;

  bool get isInitialized => !identical(_value, _unset);

  T get value {
    if (!isInitialized) throw StateError('RoCell is uninitialized');
    return _value as T;
  }

  void init(T value) {
    if (isInitialized) throw StateError('RoCell is already initialized');
    _value = value;
  }

  void initWith(T Function() create) {
    if (isInitialized) throw StateError('RoCell is already initialized');
    init(create());
  }

  T take() {
    final current = value;
    _value = _unset;
    return current;
  }
}
