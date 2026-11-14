import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

bool usesAndroidGestureNavigation(BuildContext context) {
  return usesAndroidGestureNavigationFor(
    platform: defaultTargetPlatform,
    systemGestureInsets: MediaQuery.systemGestureInsetsOf(context),
  );
}

bool usesAndroidGestureNavigationFor({
  required TargetPlatform platform,
  required EdgeInsets systemGestureInsets,
}) {
  if (platform != TargetPlatform.android) {
    return false;
  }
  return systemGestureInsets.left > 0 ||
      systemGestureInsets.right > 0 ||
      systemGestureInsets.bottom > 0;
}

bool shouldApplyBottomSafeArea(BuildContext context) {
  return !usesAndroidGestureNavigation(context);
}

bool shouldApplyBottomSafeAreaFor({
  required TargetPlatform platform,
  required EdgeInsets systemGestureInsets,
}) {
  return !usesAndroidGestureNavigationFor(
    platform: platform,
    systemGestureInsets: systemGestureInsets,
  );
}

bool shouldPaintAndroidThreeButtonNavigationBackgroundFor({
  required TargetPlatform platform,
  required EdgeInsets systemGestureInsets,
}) {
  return platform == TargetPlatform.android &&
      !usesAndroidGestureNavigationFor(
        platform: platform,
        systemGestureInsets: systemGestureInsets,
      );
}

class AndroidThreeButtonNavigationBackground extends StatelessWidget {
  const AndroidThreeButtonNavigationBackground({
    required this.color,
    super.key,
  });

  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!shouldPaintAndroidThreeButtonNavigationBackgroundFor(
      platform: defaultTargetPlatform,
      systemGestureInsets: MediaQuery.systemGestureInsetsOf(context),
    )) {
      return const SizedBox.shrink();
    }
    final height = MediaQuery.viewPaddingOf(context).bottom;
    if (height <= 0) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: double.infinity,
          height: height,
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}
