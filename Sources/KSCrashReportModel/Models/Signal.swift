//
//  Signal.swift
//
//  Created by Alexander Cohen on 2026-06-28.
//
//  Copyright (c) 2012 Karl Stenerud. All rights reserved.
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

import Foundation

/// A Unix signal, named after its `SIG*` symbol. The signal set is fixed, so this is a closed enum
/// encoded as its signal number.
// swift-format-ignore: AlwaysUseLowerCamelCase
public enum Signal: Int32, Codable, Sendable, CaseIterable {
    case SIGHUP = 1
    case SIGINT = 2
    case SIGQUIT = 3
    case SIGILL = 4
    case SIGTRAP = 5
    case SIGABRT = 6
    case SIGEMT = 7
    case SIGFPE = 8
    case SIGKILL = 9
    case SIGBUS = 10
    case SIGSEGV = 11
    case SIGSYS = 12
    case SIGPIPE = 13
    case SIGALRM = 14
    case SIGTERM = 15
    case SIGURG = 16
    case SIGSTOP = 17
    case SIGTSTP = 18
    case SIGCONT = 19
    case SIGCHLD = 20
    case SIGTTIN = 21
    case SIGTTOU = 22
    case SIGIO = 23
    case SIGXCPU = 24
    case SIGXFSZ = 25
    case SIGVTALRM = 26
    case SIGPROF = 27
    case SIGWINCH = 28
    case SIGINFO = 29
    case SIGUSR1 = 30
    case SIGUSR2 = 31
}
