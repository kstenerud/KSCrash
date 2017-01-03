#include <jni.h>
#include <string>
#include "KSJNI.h"
#include "KSDate.h"

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_install(JNIEnv *env, jobject instance) {
    ksjni_init(env);

}

extern "C"
jstring
Java_org_stenerud_kscrash_MainActivity_stringFromJNI(
        JNIEnv *env,
        jobject /* this */) {
    std::string hello = "Hello from C++";
    return env->NewStringUTF(hello.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_stenerud_kscrash_MainActivity_stringFromTimestamp(JNIEnv *env, jobject instance,
                                                           jlong timestamp) {
    char buffer[21];
    buffer[0] = 0;
    ksdate_utcStringFromTimestamp(timestamp, buffer);
    return env->NewStringUTF(buffer);
}