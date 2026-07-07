#if canImport(Testing)
import Testing
#endif


#if !os(Windows) /* Test observation is not supported on Windows */ && false /* enableExperimentalTestOutput */
public import Foundation
#if canImport(XCTest)
public import XCTest

public final class __SwiftPMXCTestObserver: NSObject {
    let testOutputPath: String

    public init(testOutputPath: String) {
        self.testOutputPath = testOutputPath
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }
}

extension __SwiftPMXCTestObserver: XCTestObservation {
    private func write(record: any Encodable) {
        let lock = __SwiftPMFileLock(at: URL(fileURLWithPath: self.testOutputPath + ".lock"))
        _ = try? lock.withLock {
            self._write(record: record)
        }
    }

    private func _write(record: any Encodable) {
        if let data = try? JSONEncoder().encode(record) {
            if let fileHandle = FileHandle(forWritingAtPath: self.testOutputPath) {
                defer { fileHandle.closeFile() }
                fileHandle.seekToEndOfFile()
                fileHandle.write("\n".data(using: .utf8)!)
                fileHandle.write(data)
            } else {
                _ = try? data.write(to: URL(fileURLWithPath: self.testOutputPath))
            }
        }
    }

    public func __SwiftPMTestBundleWillStart(_ __SwiftPMTestBundle: Bundle) {
        let record = __SwiftPMTestBundleEventRecord(bundle: .init(__SwiftPMTestBundle), event: .start)
        write(record: __SwiftPMTestEventRecord(bundleEvent: record))
    }

    public func testSuiteWillStart(_ testSuite: XCTestSuite) {
        let record = __SwiftPMTestSuiteEventRecord(suite: .init(testSuite), event: .start)
        write(record: __SwiftPMTestEventRecord(suiteEvent: record))
    }

    public func testCaseWillStart(_ testCase: XCTestCase) {
        let record = __SwiftPMTestCaseEventRecord(testCase: .init(testCase), event: .start)
        write(record: __SwiftPMTestEventRecord(caseEvent: record))
    }

    #if canImport(Darwin)
    public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        let record = __SwiftPMTestCaseFailureRecord(testCase: .init(testCase), issue: .init(issue), failureKind: .unexpected)
        write(record: __SwiftPMTestEventRecord(caseFailure: record))
    }

    public func testCase(_ testCase: XCTestCase, didRecord expectedFailure: XCTExpectedFailure) {
        let record = __SwiftPMTestCaseFailureRecord(testCase: .init(testCase), issue: .init(expectedFailure.issue), failureKind: .expected(failureReason: expectedFailure.failureReason))
        write(record: __SwiftPMTestEventRecord(caseFailure: record))
    }
    #else
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        let issue = __SwiftPMTestIssue(description: description, inFile: filePath, atLine: lineNumber)
        let record = __SwiftPMTestCaseFailureRecord(testCase: .init(testCase), issue: issue, failureKind: .unexpected)
        write(record: __SwiftPMTestEventRecord(caseFailure: record))
    }
    #endif

    public func testCaseDidFinish(_ testCase: XCTestCase) {
        let record = __SwiftPMTestCaseEventRecord(testCase: .init(testCase), event: .finish)
        write(record: __SwiftPMTestEventRecord(caseEvent: record))
    }

    #if canImport(Darwin)
    public func testSuite(_ testSuite: XCTestSuite, didRecord issue: XCTIssue) {
        let record = __SwiftPMTestSuiteFailureRecord(suite: .init(testSuite), issue: .init(issue), failureKind: .unexpected)
        write(record: __SwiftPMTestEventRecord(suiteFailure: record))
    }

    public func testSuite(_ testSuite: XCTestSuite, didRecord expectedFailure: XCTExpectedFailure) {
        let record = __SwiftPMTestSuiteFailureRecord(suite: .init(testSuite), issue: .init(expectedFailure.issue), failureKind: .expected(failureReason: expectedFailure.failureReason))
        write(record: __SwiftPMTestEventRecord(suiteFailure: record))
    }
    #else
    public func testSuite(_ testSuite: XCTestSuite, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        let issue = __SwiftPMTestIssue(description: description, inFile: filePath, atLine: lineNumber)
        let record = __SwiftPMTestSuiteFailureRecord(suite: .init(testSuite), issue: issue, failureKind: .unexpected)
        write(record: __SwiftPMTestEventRecord(suiteFailure: record))
    }
    #endif

    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        let record = __SwiftPMTestSuiteEventRecord(suite: .init(testSuite), event: .finish)
        write(record: __SwiftPMTestEventRecord(suiteEvent: record))
    }

    public func __SwiftPMTestBundleDidFinish(_ __SwiftPMTestBundle: Bundle) {
        let record = __SwiftPMTestBundleEventRecord(bundle: .init(__SwiftPMTestBundle), event: .finish)
        write(record: __SwiftPMTestEventRecord(bundleEvent: record))
    }
}
#endif

// FIXME: Copied from `Lock.swift` in TSCBasic, would be nice if we had a better way

#if canImport(Glibc)
@_exported import Glibc
#elseif canImport(Musl)
@_exported import Musl
#elseif os(Windows)
@_exported import CRT
@_exported import WinSDK
#elseif os(WASI)
@_exported import WASILibc
#elseif canImport(Android)
@_exported import Android
#else
@_exported import Darwin.C
#endif

import Foundation

public final class __SwiftPMFileLock {
  #if os(Windows)
    private var handle: HANDLE?
  #else
    private var fileDescriptor: CInt?
  #endif

    private let lockFile: URL

    public init(at lockFile: URL) {
        self.lockFile = lockFile
    }

    public func lock() throws {
      #if os(Windows)
        if handle == nil {
            let h: HANDLE = lockFile.path.withCString(encodedAs: UTF16.self, {
                CreateFileW(
                    $0,
                    UInt32(GENERIC_READ) | UInt32(GENERIC_WRITE),
                    UInt32(FILE_SHARE_READ) | UInt32(FILE_SHARE_WRITE),
                    nil,
                    DWORD(OPEN_ALWAYS),
                    DWORD(FILE_ATTRIBUTE_NORMAL),
                    nil
                )
            })
            if h == INVALID_HANDLE_VALUE {
                throw FileSystemError(errno: Int32(GetLastError()), lockFile)
            }
            self.handle = h
        }
        var overlapped = OVERLAPPED()
        overlapped.Offset = 0
        overlapped.OffsetHigh = 0
        overlapped.hEvent = nil
        if !LockFileEx(handle, DWORD(LOCKFILE_EXCLUSIVE_LOCK), 0,
                           UInt32.max, UInt32.max, &overlapped) {
                throw ProcessLockError.unableToAquireLock(errno: Int32(GetLastError()))
            }
      #elseif os(WASI)
        // WASI doesn't support flock
      #else
        if fileDescriptor == nil {
            let fd = open(lockFile.path, O_WRONLY | O_CREAT | O_CLOEXEC, 0o666)
            if fd == -1 {
                fatalError("errno: \(errno), lockFile: \(lockFile)")
            }
            self.fileDescriptor = fd
        }
        while true {
            if flock(fileDescriptor!, LOCK_EX) == 0 {
                break
            }
            if errno == EINTR { continue }
            fatalError("unable to acquire lock, errno: \(errno)")
        }
      #endif
    }

    public func unlock() {
      #if os(Windows)
        var overlapped = OVERLAPPED()
        overlapped.Offset = 0
        overlapped.OffsetHigh = 0
        overlapped.hEvent = nil
        UnlockFileEx(handle, 0, UInt32.max, UInt32.max, &overlapped)
      #elseif os(WASI)
        // WASI doesn't support flock
      #else
        guard let fd = fileDescriptor else { return }
        flock(fd, LOCK_UN)
      #endif
    }

    deinit {
      #if os(Windows)
        guard let handle = handle else { return }
        CloseHandle(handle)
      #elseif os(WASI)
        // WASI doesn't support flock
      #else
        guard let fd = fileDescriptor else { return }
        close(fd)
      #endif
    }

    public func withLock<T>(_ body: () throws -> T) throws -> T {
        try lock()
        defer { unlock() }
        return try body()
    }

    public func withLock<T>(_ body: () async throws -> T) async throws -> T {
        try lock()
        defer { unlock() }
        return try await body()
    }
}

// FIXME: Copied from `XCTEvents.swift`, would be nice if we had a better way

struct __SwiftPMTestEventRecord: Codable {
    let caseFailure: __SwiftPMTestCaseFailureRecord?
    let suiteFailure: __SwiftPMTestSuiteFailureRecord?

    let bundleEvent: __SwiftPMTestBundleEventRecord?
    let suiteEvent: __SwiftPMTestSuiteEventRecord?
    let caseEvent: __SwiftPMTestCaseEventRecord?

    init(
        caseFailure: __SwiftPMTestCaseFailureRecord? = nil,
        suiteFailure: __SwiftPMTestSuiteFailureRecord? = nil,
        bundleEvent: __SwiftPMTestBundleEventRecord? = nil,
        suiteEvent: __SwiftPMTestSuiteEventRecord? = nil,
        caseEvent: __SwiftPMTestCaseEventRecord? = nil
    ) {
        self.caseFailure = caseFailure
        self.suiteFailure = suiteFailure
        self.bundleEvent = bundleEvent
        self.suiteEvent = suiteEvent
        self.caseEvent = caseEvent
    }
}

// MARK: - Records

struct __SwiftPMTestAttachment: Codable {
    let name: String?
    // TODO: Handle `userInfo: [AnyHashable : Any]?`
    let uniformTypeIdentifier: String
    let payload: Data?
}

struct __SwiftPMTestBundleEventRecord: Codable {
    let bundle: __SwiftPMTestBundle
    let event: __SwiftPMTestEvent
}

struct __SwiftPMTestCaseEventRecord: Codable {
    let testCase: __SwiftPMTestCase
    let event: __SwiftPMTestEvent
}

struct __SwiftPMTestCaseFailureRecord: Codable, CustomStringConvertible {
    let testCase: __SwiftPMTestCase
    let issue: __SwiftPMTestIssue
    let failureKind: __SwiftPMTestFailureKind

    var description: String {
        return "\(issue.sourceCodeContext.description)\(testCase) \(issue.compactDescription)"
    }
}

struct __SwiftPMTestSuiteEventRecord: Codable {
    let suite: __SwiftPMTestSuiteRecord
    let event: __SwiftPMTestEvent
}

struct __SwiftPMTestSuiteFailureRecord: Codable {
    let suite: __SwiftPMTestSuiteRecord
    let issue: __SwiftPMTestIssue
    let failureKind: __SwiftPMTestFailureKind
}

// MARK: Primitives

struct __SwiftPMTestBundle: Codable {
    let bundleIdentifier: String?
    let bundlePath: String
}

struct __SwiftPMTestCase: Codable {
    let name: String
}

struct __SwiftPMTestErrorInfo: Codable {
    let description: String
    let type: String
}

enum __SwiftPMTestEvent: Codable {
    case start
    case finish
}

enum __SwiftPMTestFailureKind: Codable, Equatable {
    case unexpected
    case expected(failureReason: String?)

    var isExpected: Bool {
        switch self {
        case .expected: return true
        case .unexpected: return false
        }
    }
}

struct __SwiftPMTestIssue: Codable {
    let type: __SwiftPMTestIssueType
    let compactDescription: String
    let detailedDescription: String?
    let associatedError: __SwiftPMTestErrorInfo?
    let sourceCodeContext: __SwiftPMTestSourceCodeContext
    let attachments: [__SwiftPMTestAttachment]
}

enum __SwiftPMTestIssueType: Codable {
    case assertionFailure
    case performanceRegression
    case system
    case thrownError
    case uncaughtException
    case unmatchedExpectedFailure
    case unknown
}

struct __SwiftPMTestLocation: Codable, CustomStringConvertible {
    let file: String
    let line: Int

    var description: String {
        return "\(file):\(line) "
    }
}

struct __SwiftPMTestSourceCodeContext: Codable, CustomStringConvertible {
    let callStack: [__SwiftPMTestSourceCodeFrame]
    let location: __SwiftPMTestLocation?

    var description: String {
        return location?.description ?? ""
    }
}

struct __SwiftPMTestSourceCodeFrame: Codable {
    let address: UInt64
    let symbolInfo: __SwiftPMTestSourceCodeSymbolInfo?
    let symbolicationError: __SwiftPMTestErrorInfo?
}

struct __SwiftPMTestSourceCodeSymbolInfo: Codable {
    let imageName: String
    let symbolName: String
    let location: __SwiftPMTestLocation?
}

struct __SwiftPMTestSuiteRecord: Codable {
    let name: String
}

// MARK: XCTest compatibility

extension __SwiftPMTestIssue {
    init(description: String, inFile filePath: String?, atLine lineNumber: Int) {
        let location: __SwiftPMTestLocation?
        if let filePath = filePath {
            location = .init(file: filePath, line: lineNumber)
        } else {
            location = nil
        }
        self.init(type: .assertionFailure, compactDescription: description, detailedDescription: description, associatedError: nil, sourceCodeContext: .init(callStack: [], location: location), attachments: [])
    }
}

#if canImport(XCTest)
public import XCTest

#if canImport(Darwin) // XCTAttachment is unavailable in swift-corelibs-xctest.
extension __SwiftPMTestAttachment {
    init(_ attachment: XCTAttachment) {
        self.init(
            name: attachment.name,
            uniformTypeIdentifier: attachment.uniformTypeIdentifier,
            payload: attachment.value(forKey: "payload") as? Data
        )
    }
}
#endif
#endif

extension __SwiftPMTestBundle {
    init(_ testBundle: Bundle) {
        self.init(
            bundleIdentifier: testBundle.bundleIdentifier,
            bundlePath: testBundle.bundlePath
        )
    }
}

#if canImport(XCTest)
extension __SwiftPMTestCase {
    init(_ testCase: XCTestCase) {
        self.init(name: testCase.name)
    }
}
#endif

extension __SwiftPMTestErrorInfo {
    init(_ error: any Swift.Error) {
        self.init(description: "\(error)", type: "\(Swift.type(of: error))")
    }
}

#if canImport(XCTest)
#if canImport(Darwin) // XCTIssue is unavailable in swift-corelibs-xctest.
extension __SwiftPMTestIssue {
    init(_ issue: XCTIssue) {
        self.init(
            type: .init(issue.type),
            compactDescription: issue.compactDescription,
            detailedDescription: issue.detailedDescription,
            associatedError: issue.associatedError.map { .init($0) },
            sourceCodeContext: .init(issue.sourceCodeContext),
            attachments: issue.attachments.map { .init($0) }
        )
    }
}

extension __SwiftPMTestIssueType {
    init(_ type: XCTIssue.IssueType) {
        switch type {
        case .assertionFailure: self = .assertionFailure
        case .thrownError: self = .thrownError
        case .uncaughtException: self = .uncaughtException
        case .performanceRegression: self = .performanceRegression
        case .system: self = .system
        case .unmatchedExpectedFailure: self = .unmatchedExpectedFailure
        @unknown default: self = .unknown
        }
    }
}
#endif

#if canImport(Darwin) // XCTSourceCodeLocation/XCTSourceCodeContext/XCTSourceCodeFrame/XCTSourceCodeSymbolInfo is unavailable in swift-corelibs-xctest.
extension __SwiftPMTestLocation {
    init(_ location: XCTSourceCodeLocation) {
        self.init(
            file: location.fileURL.absoluteString,
            line: location.lineNumber
        )
    }
}

extension __SwiftPMTestSourceCodeContext {
    init(_ context: XCTSourceCodeContext) {
        self.init(
            callStack: context.callStack.map { .init($0) },
            location: context.location.map { .init($0) }
        )
    }
}

extension __SwiftPMTestSourceCodeFrame {
    init(_ frame: XCTSourceCodeFrame) {
        self.init(
            address: frame.address,
            symbolInfo: (try? frame.symbolInfo()).map { .init($0) },
            symbolicationError: frame.symbolicationError.map { .init($0) }
        )
    }
}

extension __SwiftPMTestSourceCodeSymbolInfo {
    init(_ symbolInfo: XCTSourceCodeSymbolInfo) {
        self.init(
            imageName: symbolInfo.imageName,
            symbolName: symbolInfo.symbolName,
            location: symbolInfo.location.map { .init($0) }
        )
    }
}
#endif

extension __SwiftPMTestSuiteRecord {
    init(_ testSuite: XCTestSuite) {
        self.init(name: testSuite.name)
    }
}
#endif
#endif

#if canImport(XCTest)

#endif

@main
@available(macOS 10.15, iOS 11, watchOS 4, tvOS 11, visionOS 1, *)
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
struct __SwiftPMGeneratedTestRunner {
    private static func testingLibrary() -> String {
        var iterator = CommandLine.arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--testing-library", let libraryName = iterator.next() {
                return libraryName.lowercased()
            }
        }

        // Fallback if not specified: run XCTest (legacy behavior)
        return "xctest"
    }

    private static func testOutputPath() -> String? {
        var iterator = CommandLine.arguments.makeIterator()
        while let argument = iterator.next() {
            if argument == "--testing-output-path", let outputPath = iterator.next() {
                return outputPath
            }
        }
        return nil
    }

    
    #if os(Linux)
    @_silgen_name("$ss13_runAsyncMainyyyyYaKcF")
    private static func _runAsyncMain(_ asyncFun: @Sendable @escaping () async throws -> ())

    static func main() {
        
        let testingLibrary = Self.testingLibrary()
        #if canImport(Testing)
        if testingLibrary == "swift-testing" {
            _runAsyncMain {
                await Testing.__swiftPMEntryPoint() as Never
            }
        }
        #endif
        
    }
    #else
    static func main() async {
        
        let testingLibrary = Self.testingLibrary()
        #if canImport(Testing)
        if testingLibrary == "swift-testing" {
            await Testing.__swiftPMEntryPoint() as Never
        }
        #endif
        
    }
    #endif
}