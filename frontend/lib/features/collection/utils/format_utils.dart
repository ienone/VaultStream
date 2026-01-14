class FormatUtils {
  static String formatCount(dynamic count) {
    if (count == null) {
      return '0';
    }
    int val = 0;
    if (count is int) {
      val = count;
    } else if (count is String) {
      val = int.tryParse(count) ?? 0;
    } else {
      val = (count as num).toInt();
    }

    if (val >= 10000) {
      return '${(val / 10000).toStringAsFixed(1)}w';
    }
    if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}k';
    }
    return val.toString();
  }
}
