# ML Kit : les modèles chinois/japonais/coréen/devanagari ne sont pas inclus
# (seul le script latin est utilisé). On indique à R8 de ne pas les exiger.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
-keep class com.google.mlkit.** { *; }
