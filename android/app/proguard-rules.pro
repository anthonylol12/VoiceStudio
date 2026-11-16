# ML Kit text recognition references optional script recognizers (Chinese,
# Devanagari, Japanese, Korean) that Voice Studio does not ship; only the
# Latin recognizer is used. Without these rules R8 fails the release build.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
