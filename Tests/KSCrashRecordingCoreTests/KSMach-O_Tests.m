//
//  KSMach-O_Tests.m
//
//
//  Created by Gleb Linnik on 24.05.2024.
//

#import <XCTest/XCTest.h>
#import <mach-o/loader.h>
#import "KSMach-O.h"

@interface KSMach_O_Tests : XCTestCase
@end

@implementation KSMach_O_Tests

- (void)testGetSegmentByNameFromHeader_TextSegment
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a segment
    segment_command_t seg1;
    seg1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    seg1.cmdsize = sizeof(segment_command_t);
    strcpy(seg1.segname, "__TEXT");

    // Copy the segment into the header memory
    uint8_t buffer[sizeof(header) + sizeof(seg1)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &seg1, sizeof(seg1));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the segment is found correctly
    const segment_command_t *result = ksmacho_getSegmentByNameFromHeader(testHeader, "__TEXT");
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(strcmp(result->segname, "__TEXT"), 0);
}

- (void)testGetSegmentByNameFromHeader_DataSegment
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a segment
    segment_command_t seg2;
    seg2.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    seg2.cmdsize = sizeof(segment_command_t);
    strcpy(seg2.segname, "__DATA");

    // Copy the segment into the header memory
    uint8_t buffer[sizeof(header) + sizeof(seg2)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &seg2, sizeof(seg2));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the segment is found correctly
    const segment_command_t *result = ksmacho_getSegmentByNameFromHeader(testHeader, "__DATA");
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(strcmp(result->segname, "__DATA"), 0);
}

- (void)testGetSegmentByNameFromHeader_NotFound
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a segment
    segment_command_t seg1;
    seg1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    seg1.cmdsize = sizeof(segment_command_t);
    strcpy(seg1.segname, "__TEXT");

    // Copy the segment into the header memory
    uint8_t buffer[sizeof(header) + sizeof(seg1)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &seg1, sizeof(seg1));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the segment is not found for an invalid name
    const segment_command_t *result = ksmacho_getSegmentByNameFromHeader(testHeader, "__INVALID");
    XCTAssertEqual(result, NULL);
}

- (void)testGetSegmentByNameFromHeader_InvalidHeader
{
    // Test with an invalid header
    const segment_command_t *result = ksmacho_getSegmentByNameFromHeader(NULL, "__TEXT");
    XCTAssertEqual(result, NULL);
}

- (void)testGetCommandByTypeFromHeader_SegmentArchDependent
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a command
    struct load_command cmd1;
    cmd1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    cmd1.cmdsize = sizeof(struct load_command);

    // Copy the command into the header memory
    uint8_t buffer[sizeof(header) + sizeof(cmd1)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &cmd1, sizeof(cmd1));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the command is found correctly
    const struct load_command *result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_SEGMENT_ARCH_DEPENDENT);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->cmd, LC_SEGMENT_ARCH_DEPENDENT);
}

- (void)testGetCommandByTypeFromHeader_Symtab
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a command
    struct load_command cmd2;
    cmd2.cmd = LC_SYMTAB;
    cmd2.cmdsize = sizeof(struct load_command);

    // Copy the command into the header memory
    uint8_t buffer[sizeof(header) + sizeof(cmd2)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &cmd2, sizeof(cmd2));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the command is found correctly
    const struct load_command *result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_SYMTAB);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->cmd, LC_SYMTAB);
}

- (void)testGetCommandByTypeFromHeader_NotFound
{
    // Create a test Mach-O header
    mach_header_t header;
    header.ncmds = 1;

    // Create a command
    struct load_command cmd1;
    cmd1.cmd = LC_SEGMENT_ARCH_DEPENDENT;
    cmd1.cmdsize = sizeof(struct load_command);

    // Copy the command into the header memory
    uint8_t buffer[sizeof(header) + sizeof(cmd1)];
    memcpy(buffer, &header, sizeof(header));
    memcpy(buffer + sizeof(header), &cmd1, sizeof(cmd1));

    const mach_header_t *testHeader = (mach_header_t *)buffer;

    // Verify that the command is not found for a different type
    const struct load_command *result = ksmacho_getCommandByTypeFromHeader(testHeader, LC_DYSYMTAB);
    XCTAssertEqual(result, NULL);
}

- (void)testGetCommandByTypeFromHeader_InvalidHeader
{
    // Test with an invalid header
    const struct load_command *result = ksmacho_getCommandByTypeFromHeader(NULL, LC_SEGMENT_ARCH_DEPENDENT);
    XCTAssertEqual(result, NULL);
}

- (void)testGetSectionByTypeFlagFromSegment_NonLazySymbolPointers
{
    // Create a test segment
    segment_command_t segment;
    strcpy(segment.segname, "__DATA");
    segment.nsects = 1;

    // Create a section
    section_t sect1;
    strcpy(sect1.sectname, "__nl_symbol_ptr");
    sect1.flags = S_ATTR_PURE_INSTRUCTIONS | S_NON_LAZY_SYMBOL_POINTERS;

    // Copy the section into the segment memory
    uint8_t buffer[sizeof(segment) + sizeof(sect1)];
    memcpy(buffer, &segment, sizeof(segment));
    memcpy(buffer + sizeof(segment), &sect1, sizeof(sect1));

    const segment_command_t *testSegment = (segment_command_t *)buffer;

    // Verify that the section is found correctly
    const section_t *result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_NON_LAZY_SYMBOL_POINTERS);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->flags & SECTION_TYPE, S_NON_LAZY_SYMBOL_POINTERS);
    XCTAssertEqual(strcmp(result->sectname, "__nl_symbol_ptr"), 0);
}

- (void)testGetSectionByTypeFlagFromSegment_LazySymbolPointers
{
    // Create a test segment
    segment_command_t segment;
    strcpy(segment.segname, "__DATA");
    segment.nsects = 1;

    // Create a section
    section_t sect2;
    strcpy(sect2.sectname, "__la_symbol_ptr");
    sect2.flags = S_ATTR_SOME_INSTRUCTIONS | S_LAZY_SYMBOL_POINTERS;

    // Copy the section into the segment memory
    uint8_t buffer[sizeof(segment) + sizeof(sect2)];
    memcpy(buffer, &segment, sizeof(segment));
    memcpy(buffer + sizeof(segment), &sect2, sizeof(sect2));

    const segment_command_t *testSegment = (segment_command_t *)buffer;

    // Verify that the section is found correctly
    const section_t *result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_LAZY_SYMBOL_POINTERS);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->flags & SECTION_TYPE, S_LAZY_SYMBOL_POINTERS);
    XCTAssertEqual(strcmp(result->sectname, "__la_symbol_ptr"), 0);
}

- (void)testGetSectionByTypeFlagFromSegment_Regular
{
    // Create a test segment
    segment_command_t segment;
    strcpy(segment.segname, "__DATA");
    segment.nsects = 1;

    // Create a section
    section_t sect3;
    strcpy(sect3.sectname, "__const");
    sect3.flags = S_REGULAR;

    // Copy the section into the segment memory
    uint8_t buffer[sizeof(segment) + sizeof(sect3)];
    memcpy(buffer, &segment, sizeof(segment));
    memcpy(buffer + sizeof(segment), &sect3, sizeof(sect3));

    const segment_command_t *testSegment = (segment_command_t *)buffer;

    // Verify that the section is found correctly
    const section_t *result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_REGULAR);
    XCTAssertNotEqual(result, NULL);
    XCTAssertEqual(result->flags & SECTION_TYPE, S_REGULAR);
    XCTAssertEqual(strcmp(result->sectname, "__const"), 0);
}

- (void)testGetSectionByTypeFlagFromSegment_NotFound
{
    // Create a test segment
    segment_command_t segment;
    strcpy(segment.segname, "__DATA");
    segment.nsects = 1;

    // Create a section
    section_t sect1;
    strcpy(sect1.sectname, "__nl_symbol_ptr");
    sect1.flags = S_ATTR_PURE_INSTRUCTIONS | S_NON_LAZY_SYMBOL_POINTERS;

    // Copy the section into the segment memory
    uint8_t buffer[sizeof(segment) + sizeof(sect1)];
    memcpy(buffer, &segment, sizeof(segment));
    memcpy(buffer + sizeof(segment), &sect1, sizeof(sect1));

    const segment_command_t *testSegment = (segment_command_t *)buffer;

    // Verify that the section is not found for a different type flag
    const section_t *result = ksmacho_getSectionByTypeFlagFromSegment(testSegment, S_ATTR_DEBUG);
    XCTAssertEqual(result, NULL);
}

- (void)testGetSectionByTypeFlagFromSegment_InvalidSegment
{
    // Test with an invalid segment
    const section_t *result = ksmacho_getSectionByTypeFlagFromSegment(NULL, S_NON_LAZY_SYMBOL_POINTERS);
    XCTAssertEqual(result, NULL);
}

- (void)testGetSectionProtection_ReadOnlyProtection
{
    // Create a memory region with read-only protection
    vm_address_t address;
    vm_size_t size = getpagesize();
    vm_prot_t expectedProtection = VM_PROT_READ;
    kern_return_t result = vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE);
    XCTAssertEqual(result, KERN_SUCCESS);

    result = vm_protect(mach_task_self(), address, size, FALSE, expectedProtection);
    XCTAssertEqual(result, KERN_SUCCESS);

    // Call the function under test
    vm_prot_t actualProtection = ksmacho_getSectionProtection((void *)address);

    // Verify the expected protection
    XCTAssertEqual(actualProtection, expectedProtection);

    // Deallocate the memory region
    result = vm_deallocate(mach_task_self(), address, size);
    XCTAssertEqual(result, KERN_SUCCESS);
}

- (void)testGetSectionProtection_ExecutableProtection
{
    // Create a memory region with executable protection
    vm_address_t address;
    vm_size_t size = getpagesize();
    vm_prot_t expectedProtection = VM_PROT_READ | VM_PROT_EXECUTE;
    kern_return_t result = vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE);
    XCTAssertEqual(result, KERN_SUCCESS);

    result = vm_protect(mach_task_self(), address, size, FALSE, expectedProtection);
    XCTAssertEqual(result, KERN_SUCCESS);

    // Call the function under test
    vm_prot_t actualProtection = ksmacho_getSectionProtection((void *)address);

    // Verify the expected protection
    XCTAssertEqual(actualProtection, expectedProtection);

    // Deallocate the memory region
    result = vm_deallocate(mach_task_self(), address, size);
    XCTAssertEqual(result, KERN_SUCCESS);
}

- (void)testGetSectionProtection_NoAccessProtection
{
    // Create a memory region with no access protection
    vm_address_t address;
    vm_size_t size = getpagesize();
    vm_prot_t expectedProtection = VM_PROT_NONE;
    kern_return_t result = vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE);
    XCTAssertEqual(result, KERN_SUCCESS);

    result = vm_protect(mach_task_self(), address, size, FALSE, expectedProtection);
    XCTAssertEqual(result, KERN_SUCCESS);

    // Call the function under test
    vm_prot_t actualProtection = ksmacho_getSectionProtection((void *)address);

    // Verify the expected protection
    XCTAssertEqual(actualProtection, expectedProtection);

    // Deallocate the memory region
    result = vm_deallocate(mach_task_self(), address, size);
    XCTAssertEqual(result, KERN_SUCCESS);
}

- (void)testGetSectionProtection_FailureScenario
{
    // Call the function under test with an invalid memory address
    vm_address_t invalidAddress = 0xFFFFFFFFFFFFFFFFULL;
    vm_prot_t actualProtection = ksmacho_getSectionProtection((void *)invalidAddress);

    // Verify the expected default protection value
    XCTAssertEqual(actualProtection, VM_PROT_READ, @"Expected default protection value of VM_PROT_READ");
}

@end
