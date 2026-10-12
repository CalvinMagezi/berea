# ONNX Runtime looks up its Java classes from native code by name; R8 must not rename them.
-keep class ai.onnxruntime.** { *; }
