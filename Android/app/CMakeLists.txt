# Sets the minimum version of CMake required to build the native
# library. You should either keep the default value or only pass a
# value of 3.4.0 or lower.

cmake_minimum_required(VERSION 3.4.1)

# Creates and names a library, sets it as either STATIC
# or SHARED, and provides the relative paths to its source code.
# You can define multiple libraries, and CMake builds it for you.
# Gradle automatically packages shared libraries with your APK.

include_directories(${CMAKE_SOURCE_DIR}/../Source)
include_directories(${CMAKE_SOURCE_DIR}/../Source/monitors)
include_directories(${CMAKE_SOURCE_DIR}/../Source/tools)
include_directories(${CMAKE_SOURCE_DIR}/../../Source/KSCrash)
include_directories(${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording)
include_directories(${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors)
include_directories(${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools)

add_library( # Sets the name of the library.
             kscrash-lib

             # Sets the library as a shared library.
             SHARED

             # Provides a relative path to your source file(s).
             # Associated headers in the same location as their source
             # file are automatically included.
             ${CMAKE_SOURCE_DIR}/../Source/kscrash-lib.cpp
             ${CMAKE_SOURCE_DIR}/../Source/KSCrashCachedData.c
             ${CMAKE_SOURCE_DIR}/../Source/KSJNI.cpp
             ${CMAKE_SOURCE_DIR}/../Source/monitors/KSCrashMonitor_System.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSCPU.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSDebug.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSDynamicLinker.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSID.cpp
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSMachineContext.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSMemory.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSStackCursor_SelfThread.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSSymbolicator.c
             ${CMAKE_SOURCE_DIR}/../Source/tools/KSThread.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/KSCrashC.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/KSCrashReport.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/KSCrashReportFixer.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/KSCrashReportStore.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitor.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitor_AppState.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitor_CPPException.cpp
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitor_Signal.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitor_User.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Monitors/KSCrashMonitorType.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSDate.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSDemangle_CPP.cpp
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSFileUtils.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSJSONCodec.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSLogger.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSSignalInfo.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSStackCursor.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSStackCursor_Backtrace.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSStackCursor_MachineContext.c
             ${CMAKE_SOURCE_DIR}/../../Source/KSCrash/Recording/Tools/KSString.c
           )

# Searches for a specified prebuilt library and stores the path as a
# variable. Because system libraries are included in the search path by
# default, you only need to specify the name of the public NDK library
# you want to add. CMake verifies that the library exists before
# completing its build.

find_library( # Sets the name of the path variable.
              log-lib

              # Specifies the name of the NDK library that
              # you want CMake to locate.
              log )

# Specifies libraries CMake should link to your target library. You
# can link multiple libraries, such as libraries you define in the
# build script, prebuilt third-party libraries, or system libraries.

target_link_libraries( # Specifies the target library.
                       kscrash-lib

                       # Links the target library to the log library
                       # included in the NDK.
                       ${log-lib} )
