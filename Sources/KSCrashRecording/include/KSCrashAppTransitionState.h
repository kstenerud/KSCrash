//
//  KSCrashAppTransitionState.h
//
//  Created by Alexander Cohen on 2024-05-20.
//
//  Copyright (c) 2024 Alexander Cohen. All rights reserved.
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
#ifndef KSCrashAppTransitionState_h
#define KSCrashAppTransitionState_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/** States of transition for the application */
enum {
    KSCrashAppTransitionStateStartup = 0,
    KSCrashAppTransitionStateStartupPrewarm,
    KSCrashAppTransitionStateLaunching,
    KSCrashAppTransitionStateForegrounding,
    KSCrashAppTransitionStateActive,
    KSCrashAppTransitionStateDeactivating,
    KSCrashAppTransitionStateBackground,
    KSCrashAppTransitionStateTerminating,
    KSCrashAppTransitionStateExiting,
};
typedef uint8_t KSCrashAppTransitionState;

/**
 * Returns true if the transition state is user perceptible.
 */
bool ksapp_transition_state_is_user_perceptible(KSCrashAppTransitionState state);

/**
 * Returns a string for the app state passed in.
 */
const char *ksapp_transition_state_to_string(KSCrashAppTransitionState state);

#ifdef __cplusplus
}
#endif

#endif /* KSCrashAppTransitionState_h */
