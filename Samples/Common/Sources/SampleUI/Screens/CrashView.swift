//
//  CrashView.swift
//
//  Created by Nikolay Volosatov on 2024-07-07.
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

import SwiftUI
import CrashTriggers

public typealias CrashTriggerId = CrashTriggers.CrashTriggerId

private typealias Helper = CrashTriggersHelper

private struct CrashTrigger: Identifiable {
    var id: CrashTriggerId
    var name: String
    var body: () -> Void

    func passes(filter: String) -> Bool {
        id.rawValue == filter || name.contains(filter)
    }
}

private struct CrashGroup: Identifiable {
    var id: String
    var name: String
    var triggers: [CrashTrigger]
}

struct CrashView: View {
    @State var filter: String = ""

    private static let groups: [CrashGroup] = {
        Helper.groupIds().map { groupId in
                .init(
                    id: groupId,
                    name: Helper.name(forGroup: groupId),
                    triggers: Helper.triggers(forGroup: groupId).map { triggerId in
                            .init(
                                id: triggerId,
                                name: Helper.name(forTrigger: triggerId),
                                body: { Helper.runTrigger(triggerId) }
                            )
                    }
                )
        }
    }()

    private func groupView(for group: CrashGroup) -> some View {
        Section(header: Text(group.name)) {
            ForEach(group.triggers) { trigger in
                if filter.isEmpty || trigger.passes(filter: filter) {
                    triggerView(for: trigger)
                }
            }
        }
    }

    private func triggerView(for trigger: CrashTrigger) -> some View {
        Button(trigger.name, action: trigger.body)
            .testId(.id(trigger.id.rawValue))
    }

    var body: some View {
        List {
            TextField("Search", text: $filter)
                .testId(.crashView(.searchTextInput))
            ForEach(Self.groups) { group in
                if filter.isEmpty || group.triggers.contains(where: { $0.passes(filter: filter) }) {
                    groupView(for: group)
                }
            }
        }
        .navigationTitle("Crash")
    }
}

public extension TestElementId {
    enum CrashViewElements: String {
        case searchTextInput
    }

    static func crashView(_ element: Self.CrashViewElements) -> Self {
        return .id("crash.\(element)")
    }
}
