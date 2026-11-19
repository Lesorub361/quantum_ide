-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**

# Keep compression libraries and app native bridge
-keep class com.github.luben.zstd.** { *; }
-dontwarn com.github.luben.zstd.**
-keep class org.apache.commons.compress.** { *; }
-dontwarn org.apache.commons.compress.**
-keep class com.example.quantum_ide.** { *; }
-dontwarn com.example.quantum_ide.**

