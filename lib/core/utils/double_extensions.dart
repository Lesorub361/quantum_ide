/// Safe clamping helpers for [double] values that guard against `NaN`
/// and inverted bounds.
extension SafeClampDouble on double {
  /// Clamps this value between [lower] and [upper], swapping bounds if needed
  /// and returning the lower bound when `isNaN` is true.
  double safeClamp(double lower, double upper) {
    final effectiveMin = lower < upper ? lower : upper;
    final effectiveMax = lower < upper ? upper : lower;
    if (isNaN) return effectiveMin;
    if (this < effectiveMin) return effectiveMin;
    if (this > effectiveMax) return effectiveMax;
    return this;
  }
}
