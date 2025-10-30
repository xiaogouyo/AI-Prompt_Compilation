import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'models/group.dart';
import 'models/prompt.dart';
import 'providers/app_state.dart';
import 'services/storage_service.dart';
import 'pages/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Hive：Web 使用默认初始化，桌面/移动使用应用支持目录
  if (kIsWeb) {
    await Hive.initFlutter();
  } else {
    final Directory appSupportDir = await getApplicationSupportDirectory();
    await Hive.initFlutter(appSupportDir.path);
  }

  // 注册适配器并打开 Box
  Hive.registerAdapter(GroupAdapter());
  Hive.registerAdapter(PromptAdapter());
  await StorageService.instance.init();

  // 首次运行示例数据（可通过 --dart-define=ADD_SAMPLE_DATA=false 关闭）
  const bool addSample = bool.fromEnvironment('ADD_SAMPLE_DATA', defaultValue: true);
  if (addSample) {
    await _ensureSampleData();
  }

  runApp(const PromptApp());
}

Future<void> _ensureSampleData() async {
  final storage = StorageService.instance;
  if (storage.groupCount == 0 && storage.promptCount == 0) {
    // 人物分析 > 姿态 > 全身
    final root = await storage.createGroup('人物分析');
    final pose = await storage.createGroup('姿态', parentId: root.id);
    final fullBody = await storage.createGroup('全身', parentId: pose.id);

    await storage.createPrompt(
      title: '全身构图分析模板',
      content:
          '分析这张图的构图：主要描述，机位（仰视、平视、俯视）……\n包含 XYZ 旋转、角色姿态、空间关系等因素。',
      tags: const ['构图', 'XYZ旋转', '角色姿态'],
      description: '用于精确复现角色全身姿态',
      groupId: fullBody.id,
    );
  }
}

class PromptApp extends StatelessWidget {
  const PromptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(StorageService.instance)..bootstrap(),
      child: Consumer<AppState>(
        builder: (context, app, _) {
          return MaterialApp(
            title: 'AI Prompt Compilation',
            themeMode: app.themeMode,
            theme: _buildRoundedFlatTheme(app.seedColor, Brightness.light, app.compactDensity),
            darkTheme: _buildRoundedFlatTheme(app.seedColor, Brightness.dark, app.compactDensity),
            home: const HomePage(),
          );
        },
      ),
    );
  }
}

ThemeData _buildRoundedFlatTheme(Color seed, Brightness brightness, bool compactDensity) {
  final colorScheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  const radiusMd = 10.0;
  const radiusLg = 12.0;

  return ThemeData(
    colorScheme: colorScheme,
    useMaterial3: true,
    visualDensity: compactDensity ? VisualDensity.compact : VisualDensity.standard,
    // AppBar 扁平化
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    // 卡片统一圆角+无阴影
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
      ),
    ),
    // 对话框圆角+无表面着色
    dialogTheme: const DialogThemeData(
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
      ),
    ),
    // 输入框统一圆角与填充样式（扁平化边框）
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withOpacity(0.6),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(radiusMd)),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.4)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(radiusMd)),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
      ),
    ),
    // 按钮圆角+零阴影
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
          side: BorderSide(color: Colors.grey.withOpacity(0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
    // FAB 扁平化
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
      ),
    ),
    // SnackBar 圆角+浮动
    snackBarTheme: SnackBarThemeData(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(radiusLg)),
      ),
        backgroundColor: colorScheme.surface.withOpacity(0.95),
      contentTextStyle: TextStyle(color: colorScheme.onSurface),
    ),
    // ListTile密度与选中态可在组件级控制
  );
}