import '../application/clock.dart';

class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}
