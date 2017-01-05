#include <jni.h>
#include <string>
#include "KSJNI.h"
#include "KSDate.h"
#include "KSCrashC.h"

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_install__Ljava_lang_String_2Ljava_lang_String_2(JNIEnv *env,
                                                                                  jobject instance,
                                                                                  jstring appName_,
                                                                                  jstring installDir_) {
    const char *appName = env->GetStringUTFChars(appName_, 0);
    const char *installDir = env->GetStringUTFChars(installDir_, 0);

    ksjni_init(env);
    kscrash_install(appName, installDir);

    env->ReleaseStringUTFChars(appName_, appName);
    env->ReleaseStringUTFChars(installDir_, installDir);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_deleteAllReports(JNIEnv *env, jobject instance) {
    kscrash_deleteAllReports();
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