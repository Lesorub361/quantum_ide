import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Управляет текущей выбранной вкладкой бокового меню (проводник файлов, поиск, настройки и т.д.)
final drawerTabProvider = StateProvider<int>((ref) => 0);
