/// Persistent money values are integer paise. UI values are expressed in rupees.
class Money {
  static int toPaise(double rupees) {
    if (!rupees.isFinite) throw ArgumentError('Amount must be finite.');
    return (rupees * 100).round();
  }

  static double fromPaise(Object value) => (value as int) / 100;

  static double sum(Iterable<double> values) =>
      values.fold<int>(0, (sum, value) => sum + toPaise(value)) / 100;
}
