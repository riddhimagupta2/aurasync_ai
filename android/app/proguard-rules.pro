# Flutter Wrapper rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Protect Google Generative AI (Gemini) Networking
-keep class com.google.ai.client.generativeai.** { *; }
-keep class com.google.ai.client.generativeai.type.** { *; }
-dontwarn com.google.ai.client.generativeai.**

# Protect internal HTTP networking and compression
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Protect Supabase models if needed
-keep class io.supabase.** { *; }

# Ignore missing Play Core classes (Flutter engine references them, but they are optional)
-dontwarn com.google.android.play.core.**