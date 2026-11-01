import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Управляет текущей выбранной вкладкой левого бокового меню (проводник файлов, поиск, настройки и т.д.)
final drawerTabProvider = StateProvider<int>((ref) => 0);

/// Управляет открытием правой растягиваемой панели Чат-бота (Quantum AI Hub)
final rightAgentPanelOpenProvider = StateProvider<bool>((ref) => false);

/// Текущая ширина правой панели Чат-бота (растягивается перетаскиванием левой границы)
final rightAgentPanelWidthProvider = StateProvider<double>((ref) => 340.0);
