//
//  KSMach-O_Tests.m
//
//
//  Created by Gleb Linnik on 24.05.2024.
//

#import "KSMach-O.h"
#import <XCTest/XCTest.h>
#import <mach-o/loader.h>

@interface KSMachOTests : XCTestCase @end

@implementation KSMachOTests

- (void)testGetSegmentByNameFromHeader
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 2;

    // Create segments
    segment_command_t seg1;
    seg1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    seg1.cmdsize = sizeof(segment_command_t);
    strcpy(seg1.segname, "__TEXT");

    segment_command_t seg2;
    seg2.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    seg2.cmdsize = sizeof(segment_command_t);
    strcpy(seg2.segname, "__DATA");

    // Copy segments into the header memory
    uint8_t buffer[sizeof(header) + sizeof(seg1) + sizeof(seg2)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &seg1, sizeof(seg1));
    memcpy(buffer + sizeof(header) + sizeof(seg1), &seg2, sizeof(seg2));

    const mach_header_t* testHeader = (mach_header_t*)buffer;

    // Verify that segments are found correctly
    const segment_command_t* result = ksmacho_getSegmentByNameFromHeader(testHeader, "__TEXT");
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(strcmp(result->segname, "__TEXT"), 0);

    result = ksmacho_getSegmentByNameFromHeader(testHeader, "__DATA");
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(strcmp(result->segname, "__DATA"), 0);

    result = ksmacho_getSegmentByNameFromHeader(testHeader, "__INVALID");
    XCTAssertEqual(result, NULL);
}

- (void)testGetCommandByTypeFromHeader
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 2;

    // Create commands
    struct load_command cmd1;
    cmd1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    cmd1.cmdsize = sizeof(struct load_command);

    struct load_command cmd2;
    cmd2.cmd = LC_SYMTAB;
    cmd2.cmdsize = sizeof(struct load_command);

    // Copy commands into the header memory
    uint8_t buffer[sizeof(header) + sizeof(cmd1) + sizeof(cmd2)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &cmd1, sizeof(cmd1));
    memcpy(buffer + sizeof(header) + sizeof(cmd1), &cmd2, sizeof(cmd2));

    const mach_header_t* testHeader = (mach_header_t*)buffer;

    // Verify that commands are found correctly
    const struct load_command* result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_SEGMENT_ARCH_DEPENDENT);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->cmd, LC_SEGMENT_ARCH_DEPENDENT);

    result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_SYMTAB);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->cmd, LC_SYMTAB);

    result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_DYSYMTAB);
    XCTAssertEqual(result, NULL);
}

- (void)testGetSectionByTypeFlagFromSegment
{
    // Create a test segment
    segment_command_t segment;
    strcpy(segment.segname, "__DATA");
    segment.nsects = 2;

    // Create sections
    section_t sect1;
    sect1.flags = S_ATTR_PURE_INSTRUCTIONS | S_NON_LAZY_SYMBOL_POINTERS;

    section_t sect2;
    sect2.flags = S_ATTR_SOME_INSTRUCTIONS | S_LAZY_SYMBOL_POINTERS;

    // Copy sections into the segment memory
    uint8_t buffer[sizeof(segment) + sizeof(sect1) + sizeof(sect2)];
    memcpy(buffer, &segment, sizeof(segment));
    memcpy(buffer + sizeof(segment), &sect1, sizeof(sect1));
    memcpy(buffer + sizeof(segment) + sizeof(sect1), &sect2, sizeof(sect2));

    const segment_command_t* testSegment = (segment_command_t*)buffer;

    // Verify that sections are found correctly
    const section_t* result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_NON_LAZY_SYMBOL_POINTERS);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->flags & SECTION_TYPE, S_NON_LAZY_SYMBOL_POINTERS);

    result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_LAZY_SYMBOL_POINTERS);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->flags & SECTION_TYPE, S_LAZY_SYMBOL_POINTERS);

    result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_ATTR_DEBUG);
    XCTAssertEqual(result, NULL);
}

@end
