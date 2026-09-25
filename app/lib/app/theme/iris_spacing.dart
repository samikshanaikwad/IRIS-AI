abstract final class IrisSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 16;
  static const double md = 24;
  static const double lg = 32;
  static const double xl = 48;

  static double pageHorizontal(double width) => width < 360 ? sm : md;
}
