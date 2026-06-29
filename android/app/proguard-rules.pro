# Keep Pigeon generated classes for google_sign_in_android
-keep class io.flutter.plugins.googlesignin.** { *; }
-keep class io.flutter.plugins.firebase.auth.** { *; }
-keep class io.flutter.plugins.firebase.core.** { *; }

# Keep all other Flutter plugins safe from R8 minification stripping
-keep class io.flutter.plugins.** { *; }
-keep class com.shounakmulay.flutter_sms_inbox.** { *; }
-keep class com.baseflow.permissionhandler.** { *; }
