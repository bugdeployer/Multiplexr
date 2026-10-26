String audioTime(int ms) {
  final seconds = ms ~/ 1000;
  final h = seconds ~/ 3600, m = seconds ~/ 60 % 60, s = seconds % 60;
  return h > 0
      ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
      : '$m:${s.toString().padLeft(2, '0')}';
}
