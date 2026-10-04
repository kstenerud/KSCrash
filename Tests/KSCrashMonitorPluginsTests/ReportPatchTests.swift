//
//  ReportPatchTests.swift
//
//  Created by Alexander Cohen on 2026-09-27.
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

import KSCrashMonitorPlugins
import KSCrashReportModel
import XCTest

final class ReportPatchTests: XCTestCase {

    private let reportID = "5D8A6C1E-3F2B-4A7D-9E1C-0B6F4D2A8C31"

    private func makePatch() -> ReportPatch {
        ReportPatch([
            "report": [
                "id": reportID,
                "timestamp": "2026-09-27T12:00:00.000Z",
                "unknown_report_key": "kept",
            ],
            "system": [
                "thread_count": 3,
                "unknown_top": ["a": 1],
                "app_memory": [
                    "memory_footprint": 100,
                    "unknown_nested": "kept",
                ],
            ],
        ])
    }

    private func system(_ patch: ReportPatch) -> [String: Any] {
        patch.dictionary["system"] as? [String: Any] ?? [:]
    }

    // MARK: - value

    func testValueDecodesWhatIsThere() throws {
        let memory = try makePatch().value(AppMemoryInfo.self, at: "system", "app_memory")
        XCTAssertEqual(memory?.memoryFootprint, 100)
    }

    func testValueIsNilWhenNothingIsThere() throws {
        XCTAssertNil(try makePatch().value(AppMemoryInfo.self, at: "system", "missing"))
        XCTAssertNil(try makePatch().value(AppMemoryInfo.self, at: "missing", "deeper"))
    }

    func testValueThroughANonObjectThrowsThePath() {
        XCTAssertThrowsError(try makePatch().value(AppMemoryInfo.self, at: "system", "thread_count", "x")) {
            XCTAssertEqual(($0 as? ReportPatch.PathError)?.path, ["system", "thread_count"])
        }
    }

    // MARK: - update

    func testUpdateChangesTheEditedKey() throws {
        var patch = makePatch()
        try patch.update(SystemInfo.self, at: "system") { $0.threadCount = 5 }
        XCTAssertEqual(system(patch)["thread_count"] as? Int, 5)
    }

    func testUpdateKeepsKeysTheTypeDoesNotModelAtEveryDepth() throws {
        var patch = makePatch()
        try patch.update(SystemInfo.self, at: "system") {
            $0.threadCount = 5
            $0.appMemory?.memoryFootprint = 200
        }
        XCTAssertEqual(system(patch)["unknown_top"] as? [String: Int], ["a": 1])
        let memory = system(patch)["app_memory"] as? [String: Any]
        XCTAssertEqual(memory?["memory_footprint"] as? Int, 200)
        XCTAssertEqual(memory?["unknown_nested"] as? String, "kept")
    }

    func testUpdateLeavesUnchangedKeysExactlyAsTheyWere() throws {
        // The model reads this timestamp but writes it as microseconds; an edit elsewhere must
        // not rewrite it.
        var patch = makePatch()
        try patch.update(ReportInfo.self, at: "report") { $0.sessionId = "session" }
        let report = patch.dictionary["report"] as? [String: Any]
        XCTAssertEqual(report?["timestamp"] as? String, "2026-09-27T12:00:00.000Z")
        XCTAssertEqual(report?["session_id"] as? String, "session")
        XCTAssertEqual(report?["unknown_report_key"] as? String, "kept")
    }

    func testUpdateSettingAnOptionalToNilRemovesItsKey() throws {
        var patch = makePatch()
        try patch.update(SystemInfo.self, at: "system") { $0.threadCount = nil }
        XCTAssertNil(system(patch)["thread_count"])
        XCTAssertNotNil(system(patch)["unknown_top"])
    }

    func testUpdateCreatesTheValueWhenItAddsSomething() throws {
        var patch = makePatch()
        try patch.update(AppMemoryInfo.self, at: "system", "new_memory") { $0.memoryFootprint = 7 }
        let created = system(patch)["new_memory"] as? [String: Any]
        XCTAssertEqual(created?["memory_footprint"] as? Int, 7)
    }

    func testUpdateThatAddsNothingWhereThereWasNothingLeavesNothing() throws {
        var patch = makePatch()
        try patch.update(AppMemoryInfo.self, at: "system", "new_memory") { _ in }
        XCTAssertNil(system(patch)["new_memory"])
    }

    func testUpdateOfATypeWithRequiredFieldsThrowsWhereThereIsNothing() {
        var patch = makePatch()
        XCTAssertThrowsError(try patch.update(ReportInfo.self, at: "missing") { _ in }) {
            XCTAssertTrue($0 is DecodingError, "\($0)")
        }
    }

    func testUpdateThatThrowsLeavesThePatchUnchanged() {
        struct Stop: Error {}
        var patch = makePatch()
        let before = NSDictionary(dictionary: patch.dictionary)
        XCTAssertThrowsError(
            try patch.update(SystemInfo.self, at: "system") {
                $0.threadCount = 9
                throw Stop()
            })
        XCTAssertEqual(NSDictionary(dictionary: patch.dictionary), before)
    }

    func testUpdateOfAValueJSONCannotHoldThrowsInsteadOfTrapping() {
        var patch = makePatch()
        var system = system(patch)
        system["storage"] = Double.infinity
        patch.dictionary["system"] = system
        XCTAssertThrowsError(try patch.update(SystemInfo.self, at: "system") { $0.threadCount = 1 }) {
            XCTAssertTrue($0 is EncodingError, "\($0)")
        }
    }

    // MARK: - set and remove

    func testSetCreatesObjectsAlongThePath() throws {
        var patch = makePatch()
        try patch.set(["x": 1], at: "monitor_data", "battery")
        let monitorData = patch.dictionary["monitor_data"] as? [String: Any]
        XCTAssertEqual(monitorData?["battery"] as? [String: Int], ["x": 1])
    }

    func testSetReplacesTheValueWhole() throws {
        var patch = makePatch()
        try patch.set(["memory_footprint": 1], at: "system", "app_memory")
        let memory = system(patch)["app_memory"] as? [String: Any]
        XCTAssertEqual(memory?["memory_footprint"] as? Int, 1)
        XCTAssertNil(memory?["unknown_nested"])
    }

    func testSetThroughANonObjectThrowsThePath() {
        var patch = makePatch()
        XCTAssertThrowsError(try patch.set(1, at: "system", "thread_count", "x")) {
            XCTAssertEqual(($0 as? ReportPatch.PathError)?.path, ["system", "thread_count"])
        }
    }

    func testSetOfANilOptionalRemovesTheValue() throws {
        var patch = makePatch()
        let memory: AppMemoryInfo? = nil
        try patch.set(memory, at: "system", "app_memory")
        XCTAssertNil(system(patch)["app_memory"])
        XCTAssertNotNil(system(patch)["thread_count"])
        XCTAssertFalse(system(patch).values.contains { $0 is NSNull })
    }

    func testSetOfANilOptionalThroughANonObjectChangesNothing() throws {
        var patch = makePatch()
        let before = NSDictionary(dictionary: patch.dictionary)
        let memory: AppMemoryInfo? = nil
        try patch.set(memory, at: "system", "thread_count", "x")
        XCTAssertEqual(NSDictionary(dictionary: patch.dictionary), before)
    }

    func testSetOfANilOptionalWhereThereIsNothingChangesNothing() throws {
        var patch = makePatch()
        let before = NSDictionary(dictionary: patch.dictionary)
        let memory: AppMemoryInfo? = nil
        try patch.set(memory, at: "system", "missing")
        XCTAssertEqual(NSDictionary(dictionary: patch.dictionary), before)
    }

    func testRemoveTakesAwayOnlyThatValue() {
        var patch = makePatch()
        patch.remove(at: "system", "app_memory", "unknown_nested")
        let memory = system(patch)["app_memory"] as? [String: Any]
        XCTAssertNil(memory?["unknown_nested"])
        XCTAssertEqual(memory?["memory_footprint"] as? Int, 100)
    }

    func testRemoveOfNothingChangesNothing() {
        var patch = makePatch()
        let before = NSDictionary(dictionary: patch.dictionary)
        patch.remove(at: "missing", "deeper")
        patch.remove(at: "system", "thread_count", "x")
        XCTAssertEqual(NSDictionary(dictionary: patch.dictionary), before)
    }

    // MARK: - JSON types

    // A change of JSON type is a change, even where NSNumber calls the values equal.
    private func user(_ patch: ReportPatch) -> [String: Any] {
        patch.dictionary["user"] as? [String: Any] ?? [:]
    }

    private func isBoolean(_ value: Any?) -> Bool {
        (value as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
    }

    func testUpdateTurningABoolIntoANumberWritesTheNumber() throws {
        var patch = ReportPatch(["user": ["flag": true, "off": false]])
        try patch.update(Metadata.self, at: "user") {
            $0.set(1, forKey: "flag")
            $0.set(0, forKey: "off")
        }
        XCTAssertFalse(isBoolean(user(patch)["flag"]))
        XCTAssertEqual(user(patch)["flag"] as? Int, 1)
        XCTAssertFalse(isBoolean(user(patch)["off"]))
        XCTAssertEqual(user(patch)["off"] as? Int, 0)
    }

    func testUpdateTurningANumberIntoABoolWritesTheBool() throws {
        var patch = ReportPatch(["user": ["flag": 1]])
        try patch.update(Metadata.self, at: "user") { $0.set(true, forKey: "flag") }
        XCTAssertTrue(isBoolean(user(patch)["flag"]))
    }

    func testUpdateSeesTypeChangesInsideObjectsAndArrays() throws {
        var patch = ReportPatch(["user": ["nested": ["b": true], "list": [true]]])
        try patch.update(Metadata.self, at: "user") {
            $0.set(MetadataValue.object(["b": .integer(1)]), forKey: "nested")
            $0.set(MetadataValue.array([.integer(1)]), forKey: "list")
        }
        XCTAssertFalse(isBoolean((user(patch)["nested"] as? [String: Any])?["b"]))
        XCTAssertFalse(isBoolean((user(patch)["list"] as? [Any])?.first))
    }

    // MARK: - Sections

    func testSectionsFindWhatTheModelWrites() throws {
        let decoder = JSONDecoder()
        let memory = try decoder.decode(AppMemoryInfo.self, from: Data(#"{"memory_footprint": 1}"#.utf8))
        let stats = try decoder.decode(ApplicationStats.self, from: Data(#"{"application_active": true}"#.utf8))
        let hang = try decoder.decode(
            HangInfo.self,
            from: Data(
                #"{"hang_start_nanos": 1, "hang_start_role": "foreground", "hang_end_nanos": 2, "hang_end_role": "foreground"}"#
                    .utf8))
        var system = try decoder.decode(SystemInfo.self, from: Data("{}".utf8))
        system.appMemory = memory
        system.applicationStats = stats
        let id = try XCTUnwrap(Report.ID(reportID))
        var report = Report(crash: .init(error: CrashError(type: .signal)), report: .init(id: id))
        report.system = system
        report.crash.error.hang = hang

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(report))
        let patch = ReportPatch(try XCTUnwrap(json as? [String: Any]))
        XCTAssertEqual(try patch.value(.report)?.id, id)
        XCTAssertNotNil(try patch.value(.system))
        XCTAssertEqual(try patch.value(.appMemory), memory)
        XCTAssertEqual(try patch.value(.applicationStats)?.applicationActive, true)
        XCTAssertEqual(try patch.value(.crashError)?.type, .signal)
        XCTAssertEqual(try patch.value(.hang)?.hangEndNanos, 2)
    }

    func testSectionUpdateEditsInPlace() throws {
        var patch = makePatch()
        try patch.update(.appMemory) { $0.memoryFootprint = 300 }
        let memory = system(patch)["app_memory"] as? [String: Any]
        XCTAssertEqual(memory?["memory_footprint"] as? Int, 300)
        XCTAssertEqual(memory?["unknown_nested"] as? String, "kept")
    }

    func testWholeReportEditsTheRootAndKeepsItsUnmodeledKeys() throws {
        let id = try XCTUnwrap(Report.ID(reportID))
        let report = Report(crash: .init(error: CrashError(type: .signal)), report: .init(id: id))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
        json["unknown_root"] = ["kept": true]
        var patch = ReportPatch(json)

        try patch.update(.wholeReport) { $0.crash.error.isFatal = true }

        XCTAssertEqual(try patch.value(.wholeReport).crash.error.isFatal, true)
        XCTAssertEqual((patch.dictionary["unknown_root"] as? [String: Bool])?["kept"], true)
    }

    func testSectionRemoveTakesTheSectionAway() {
        var patch = makePatch()
        patch.remove(.appMemory)
        XCTAssertNil(system(patch)["app_memory"])
        XCTAssertNotNil(system(patch)["thread_count"])
    }

    func testSectionSetReplacesTheSectionWhole() throws {
        var patch = makePatch()
        var memory = try XCTUnwrap(try patch.value(.appMemory))
        memory.memoryFootprint = 400
        try patch.set(memory, at: .appMemory)
        XCTAssertEqual(try patch.value(.appMemory)?.memoryFootprint, 400)
        XCTAssertNil((system(patch)["app_memory"] as? [String: Any])?["unknown_nested"])
    }

    // MARK: - Nested objects

    private struct Outer: Codable {
        struct Inner: Codable {
            var a: Int?
            var b: Int?
        }
        var inner: Inner
    }

    func testUpdateRemovesANestedKeyAndKeepsItsSiblings() throws {
        var patch = ReportPatch(["x": ["inner": ["a": 1, "b": 2, "extra": 3]]])
        try patch.update(Outer.self, at: "x") { $0.inner.a = nil }
        let inner = (patch.dictionary["x"] as? [String: Any])?["inner"] as? [String: Any]
        XCTAssertNil(inner?["a"])
        XCTAssertEqual(inner?["b"] as? Int, 2)
        XCTAssertEqual(inner?["extra"] as? Int, 3)
    }

    /// A value that is either a number or an object, to change a nested key between the two.
    private enum Shape: Codable, Equatable {
        case number(Int)
        case object([String: Int])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                self = .number(number)
            } else {
                self = .object(try container.decode([String: Int].self))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .number(let number): try container.encode(number)
            case .object(let object): try container.encode(object)
            }
        }
    }

    private struct Holder: Codable {
        var v: Shape
    }

    func testUpdateTurnsANestedObjectIntoAScalar() throws {
        var patch = ReportPatch(["x": ["v": ["k": 1, "unmodeled": 2], "extra": 1]])
        try patch.update(Holder.self, at: "x") { $0.v = .number(5) }
        let x = patch.dictionary["x"] as? [String: Any]
        XCTAssertEqual(x?["v"] as? Int, 5)
        XCTAssertEqual(x?["extra"] as? Int, 1)
    }

    func testUpdateTurnsANestedScalarIntoAnObject() throws {
        var patch = ReportPatch(["x": ["v": 5, "extra": 1]])
        try patch.update(Holder.self, at: "x") { $0.v = .object(["k": 1]) }
        let x = patch.dictionary["x"] as? [String: Any]
        XCTAssertEqual(x?["v"] as? [String: Int], ["k": 1])
        XCTAssertEqual(x?["extra"] as? Int, 1)
    }

    // MARK: - Arrays

    private struct Frame: Codable {
        var name: String
    }

    private struct Frames: Codable {
        var frames: [Frame]
    }

    private func frames(_ patch: ReportPatch) -> [[String: Any]] {
        (patch.dictionary["x"] as? [String: Any])?["frames"] as? [[String: Any]] ?? []
    }

    private func makeFramesPatch() -> ReportPatch {
        ReportPatch(["x": ["frames": [["name": "a", "extra": 1], ["name": "b", "extra": 2]], "other": 3]])
    }

    func testUpdateWritesAChangedArrayAsTheEditLeftIt() throws {
        var patch = makeFramesPatch()
        try patch.update(Frames.self, at: "x") { $0.frames[0].name = "z" }
        XCTAssertEqual(frames(patch).map { $0["name"] as? String }, ["z", "b"])
        XCTAssertTrue(frames(patch).allSatisfy { $0["extra"] == nil })
    }

    func testUpdateThatReordersAnArrayKeepsNoKeyOnTheWrongElement() throws {
        var patch = makeFramesPatch()
        try patch.update(Frames.self, at: "x") { $0.frames.reverse() }
        XCTAssertEqual(frames(patch).map { $0["name"] as? String }, ["b", "a"])
        XCTAssertTrue(frames(patch).allSatisfy { $0["extra"] == nil })
    }

    func testUpdateKeepsAnArrayItDidNotChangeExactly() throws {
        var patch = makeFramesPatch()
        try patch.update(Frames.self, at: "x") { _ in }
        XCTAssertEqual(frames(patch).map { $0["extra"] as? Int }, [1, 2])
        XCTAssertEqual((patch.dictionary["x"] as? [String: Any])?["other"] as? Int, 3)
    }

    // MARK: - Lossy reads

    func testUpdateCannotClearAValueTheTypeCannotRead() throws {
        var patch = ReportPatch(["report": ["id": reportID, "timestamp": "garbage"]])
        try patch.update(.report) { $0.timestamp = nil }
        XCTAssertEqual((patch.dictionary["report"] as? [String: Any])?["timestamp"] as? String, "garbage")

        patch.remove(at: "report", "timestamp")
        XCTAssertNil((patch.dictionary["report"] as? [String: Any])?["timestamp"])
    }

    // MARK: - Nulls

    private struct Tagged: Codable {
        var a: Int?
        var tags: [String: Int?]
        var list: [Int?]
    }

    private struct Optionals: Codable {
        var a: Int?
    }

    private func x(_ patch: ReportPatch) -> [String: Any]? {
        patch.dictionary["x"] as? [String: Any]
    }

    func testSetLeavesOutANilNestedInTheValue() throws {
        var patch = ReportPatch([:])
        try patch.set(Tagged(a: 1, tags: ["k": nil, "j": 2], list: [1, nil, 3]), at: "x")
        XCTAssertEqual(x(patch)?["tags"] as? [String: Int], ["j": 2])
        XCTAssertEqual(x(patch)?["list"] as? [Int], [1, 3])
    }

    func testSetLeavesOutANullMetadataMember() throws {
        var patch = ReportPatch([:])
        try patch.set(["gone": MetadataValue.null, "kept": .integer(1)], at: "x")
        XCTAssertEqual(x(patch)?.keys.sorted(), ["kept"])
    }

    func testUpdateLeavesOutANilItPutsInsideTheValue() throws {
        var patch = ReportPatch(["x": ["a": 1, "tags": ["k": 1], "list": [1]]])
        try patch.update(Tagged.self, at: "x") {
            $0.tags["k"] = .some(nil)
            $0.list.append(nil)
        }
        XCTAssertEqual(x(patch)?["tags"] as? [String: Int], [:])
        XCTAssertEqual(x(patch)?["list"] as? [Int], [1])
    }

    func testUpdateOfAnOptionalTypeToNilRemovesTheValue() throws {
        var patch = ReportPatch(["x": ["a": 1], "other": 2])
        try patch.update(Optionals?.self, at: "x") { $0 = nil }
        XCTAssertNil(patch.dictionary["x"])
        XCTAssertEqual(patch.dictionary["other"] as? Int, 2)
    }

    func testUpdateOfAnOptionalTypeToNilWhereThereIsNothingAddsNothing() throws {
        var patch = ReportPatch(["other": 2])
        try patch.update(Optionals?.self, at: "y") { $0 = nil }
        XCTAssertNil(patch.dictionary["y"])
        XCTAssertEqual(patch.dictionary.keys.sorted(), ["other"])
    }

    func testUpdateOfAnOptionalScalarWithNothingThereStartsAsNil() throws {
        var patch = ReportPatch(["report": ["id": reportID]])
        var started: String?? = .none
        try patch.update(String?.self, at: "report", "session_id") {
            started = .some($0)
            $0 = "abc"
        }
        XCTAssertEqual(started, .some(nil))
        XCTAssertEqual((patch.dictionary["report"] as? [String: Any])?["session_id"] as? String, "abc")
    }

    func testUpdateOfAnOptionalArrayWithNothingThereStartsAsNil() throws {
        var patch = ReportPatch([:])
        try patch.update([Int]?.self, at: "list") {
            XCTAssertNil($0)
            $0 = [1]
        }
        XCTAssertEqual(patch.dictionary["list"] as? [Int], [1])
    }

    func testUpdateOfAnOptionalStructWithNothingThereStartsAsNil() throws {
        var patch = ReportPatch([:])
        try patch.update(Optionals?.self, at: "x") {
            XCTAssertNil($0)
            $0 = Optionals(a: 1)
        }
        XCTAssertEqual(x(patch)?["a"] as? Int, 1)
    }

    func testUpdateOfANonOptionalArrayWithNothingThereThrows() {
        var patch = ReportPatch([:])
        XCTAssertThrowsError(try patch.update([Int].self, at: "list") { $0.append(1) })
        XCTAssertNil(patch.dictionary["list"])
    }

    func testUpdateDoesNotWriteBackANullAlreadyInTheValue() throws {
        var patch = ReportPatch(["x": ["a": NSNull(), "b": 1]])
        try patch.update(Optionals.self, at: "x") { _ in }
        XCTAssertFalse(x(patch)?.values.contains { $0 is NSNull } ?? true)
        XCTAssertEqual(x(patch)?["b"] as? Int, 1)
    }

    func testANullAtThePathReadsAsAbsent() throws {
        var patch = ReportPatch(["system": ["app_memory": NSNull()]])
        XCTAssertNil(try patch.value(.appMemory))
        try patch.update(.appMemory) { $0.memoryFootprint = 1 }
        XCTAssertEqual((system(patch)["app_memory"] as? [String: Any])?["memory_footprint"] as? Int, 1)
    }

    func testANullOnThePathReadsAsAbsent() throws {
        var patch = ReportPatch(["system": NSNull()])
        XCTAssertNil(try patch.value(.appMemory))
        try patch.set(Optionals(a: 1), at: "system", "x")
        XCTAssertEqual((system(patch)["x"] as? [String: Any])?["a"] as? Int, 1)
    }

    // MARK: - Dates

    private struct Stamp: Codable, Equatable {
        var at: Date
    }

    private let stampDate = Date(timeIntervalSince1970: 1_700_000_000)

    func testDatesAreWrittenAsSecondsSince1970() throws {
        var patch = ReportPatch([:])
        try patch.set(Stamp(at: stampDate), at: "user")
        let user = try XCTUnwrap(patch.dictionary["user"] as? [String: Any])
        XCTAssertEqual(user["at"] as? Double, 1_700_000_000)

        let metadata = try JSONDecoder().decode(Metadata.self, from: JSONSerialization.data(withJSONObject: user))
        XCTAssertEqual(try metadata.decoded(as: Stamp.self), Stamp(at: stampDate))
    }

    func testDatesAreReadAsSecondsSince1970() throws {
        let metadata = try Metadata.from(Stamp(at: stampDate))
        let user = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata))
        let patch = ReportPatch(["user": user])
        XCTAssertEqual(try patch.value(Stamp.self, at: "user"), Stamp(at: stampDate))
    }

    // MARK: - dictionary

    func testDirectEditsAreSeenByTypedReads() throws {
        var patch = makePatch()
        patch.dictionary["system"] = ["thread_count": 11]
        XCTAssertEqual(try patch.value(SystemInfo.self, at: "system")?.threadCount, 11)
    }
}
