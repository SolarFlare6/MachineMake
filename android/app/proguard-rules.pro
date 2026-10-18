# Keep llama_flutter_android classes and Kotlin Function1 callbacks invoked from JNI (jni_wrapper.cpp)
#noinspection ShrinkerUnresolvedReference
-keep class com.write4me.llama_flutter_android.** { *; }
#noinspection ShrinkerUnresolvedReference
-keep interface kotlin.jvm.functions.Function1 {
    public abstract java.lang.Object invoke(java.lang.Object);
}
#noinspection ShrinkerUnresolvedReference
-keep class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}
