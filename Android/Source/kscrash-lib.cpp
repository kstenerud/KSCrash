//
//  Copyright (c) 2017 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

#include <jni.h>
#include <string>
#include "KSJNI.h"
#include "KSDate.h"
#include "KSCrashC.h"

static jclass java_util_ArrayList;
static jmethodID java_util_ArrayList_;
static jmethodID java_util_ArrayList_add;

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_internalReportUserException(JNIEnv *env, jobject instance,
                                                              jstring name_, jstring reason_,
                                                              jstring language_, jstring lineOfCode_,
                                                              jstring stackTraceJSON_,
                                                              jboolean shouldLogAllThreads,
                                                              jboolean shouldTerminateProgram) {
    const char *name = env->GetStringUTFChars(name_, 0);
    const char *reason = env->GetStringUTFChars(reason_, 0);
    const char *language = env->GetStringUTFChars(language_, 0);
    const char *lineOfCode = env->GetStringUTFChars(lineOfCode_, 0);
    const char *stackTraceJSON = env->GetStringUTFChars(stackTraceJSON_, 0);

    kscrash_reportUserException(name, reason, language, lineOfCode, stackTraceJSON, shouldLogAllThreads, shouldTerminateProgram);

    env->ReleaseStringUTFChars(name_, name);
    env->ReleaseStringUTFChars(reason_, reason);
    env->ReleaseStringUTFChars(language_, language);
    env->ReleaseStringUTFChars(lineOfCode_, lineOfCode);
    env->ReleaseStringUTFChars(stackTraceJSON_, stackTraceJSON);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_notifyAppInForeground(JNIEnv *env, jobject instance,
                                                        jboolean isInForeground) {
    kscrash_notifyAppInForeground(isInForeground);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_notifyAppActive(JNIEnv *env, jobject instance,
                                                  jboolean isActive) {
    kscrash_notifyAppActive(isActive);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_notifyAppCrash(JNIEnv *env, jobject instance) {
    kscrash_notifyAppCrash();
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_notifyAppTerminate(JNIEnv *env, jobject instance) {
    kscrash_notifyAppTerminate();
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_internalAddUserReportJSON(JNIEnv *env, jobject instance,
                                                            jstring userReportJSON_) {
    const char *userReportJSON = env->GetStringUTFChars(userReportJSON_, 0);
    kscrash_addUserReport(userReportJSON, (int)strlen(userReportJSON));
    env->ReleaseStringUTFChars(userReportJSON_, userReportJSON);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_internalSetActiveMonitors(JNIEnv *env, jobject instance,
                                                            jint activeMonitors) {
    kscrash_setMonitoring((KSCrashMonitorType)activeMonitors);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_internalSetUserInfoJSON(JNIEnv *env, jobject instance,
                                                          jstring userInfoJSON_) {
    const char *userInfoJSON = env->GetStringUTFChars(userInfoJSON_, 0);
    kscrash_setUserInfoJSON(userInfoJSON);
    env->ReleaseStringUTFChars(userInfoJSON_, userInfoJSON);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_initJNI(JNIEnv *env, jobject instance) {
    static bool isInitialized = false;
    if(!isInitialized) {
        ksjni_init(env);
        java_util_ArrayList = static_cast<jclass>(env->NewGlobalRef(
                env->FindClass("java/util/ArrayList")));
        java_util_ArrayList_ = env->GetMethodID(java_util_ArrayList, "<init>", "(I)V");
        java_util_ArrayList_add = env->GetMethodID(java_util_ArrayList, "add",
                                                   "(Ljava/lang/Object;)Z");
        isInitialized = true;
    }
}

extern "C" JNIEXPORT jobject JNICALL
Java_org_stenerud_kscrash_KSCrash_internalGetAllReports(JNIEnv *env, jobject instance) {
    int reportCount = kscrash_getReportCount();
    int64_t reportIDs[reportCount];
    reportCount = kscrash_getReportIDs(reportIDs, reportCount);
    jobject array = env->NewObject(java_util_ArrayList, java_util_ArrayList_, reportCount);
    for(int i = 0; i < reportCount; i++) {
        const char* report = kscrash_readReport(reportIDs[i]);
        if(report != NULL) {
            jstring element = env->NewStringUTF(report);
            env->CallBooleanMethod(array, java_util_ArrayList_add, element);
            env->DeleteLocalRef(element);
        }
    }
    return array;
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_setMaxReportCount(JNIEnv *env, jobject instance,
                                                    jint maxReportCount) {
    kscrash_setMaxReportCount(maxReportCount);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_setIntrospectMemory(JNIEnv *env, jobject instance,
                                                      jboolean shouldIntrospectMemory) {
    kscrash_setIntrospectMemory(shouldIntrospectMemory);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_setAddConsoleLogToReport(JNIEnv *env, jobject instance,
                                                           jboolean shouldAddConsoleLogToReport) {
    kscrash_setAddConsoleLogToReport(shouldAddConsoleLogToReport);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_install__Ljava_lang_String_2Ljava_lang_String_2(JNIEnv *env,
                                                                                  jobject instance,
                                                                                  jstring appName_,
                                                                                  jstring installDir_) {
    const char *appName = env->GetStringUTFChars(appName_, 0);
    const char *installDir = env->GetStringUTFChars(installDir_, 0);

    kscrash_install(appName, installDir);

    env->ReleaseStringUTFChars(appName_, appName);
    env->ReleaseStringUTFChars(installDir_, installDir);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_KSCrash_deleteAllReports(JNIEnv *env, jobject instance) {
    kscrash_deleteAllReports();
}

extern "C" JNIEXPORT jstring JNICALL
Java_org_stenerud_kscrash_MainActivity_stringFromTimestamp(JNIEnv *env, jobject instance,
                                                           jlong timestamp) {
    char buffer[21];
    buffer[0] = 0;
    ksdate_utcStringFromTimestamp(timestamp, buffer);
    return env->NewStringUTF(buffer);
}

extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_MainActivity_causeNativeCrash(JNIEnv *env, jobject instance) {
    char* str = "hello";
    char* ptr = NULL;
    strcpy(ptr, str);
}

#import <exception>
class MyException: public std::exception
{
public:
    virtual const char* what() const _GLIBCXX_USE_NOEXCEPT;
};
const char* MyException::what() const _GLIBCXX_USE_NOEXCEPT
{
    return "Something bad happened...";
}
extern "C" JNIEXPORT void JNICALL
Java_org_stenerud_kscrash_MainActivity_causeCPPException(JNIEnv *env, jobject instance) {
    throw MyException();
}
