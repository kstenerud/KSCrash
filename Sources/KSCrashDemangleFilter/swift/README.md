# Vendored Swift Demangler

This folder contains a vendored subset of the [Swift Programming Language]. The Swift library is
reduced to the demangler only to reduce the size of this package.

The current version is **Swift 5.5.1**.

## Sentry Modifications

The library has been modified to add an option to hide function arguments during demangling. This
patch is maintained in `1-arguments.patch`.

## How to Update

1. **Check out the [latest release] of Swift:**
   1. Create a directory that will house swift and its dependencies:
      ```
      $ mkdir swift-source && cd swift-source
      ```
   2. Clone the swift repository into a subdirectory:
      ```
      $ git clone https://github.com/apple/swift.git
      ```
   3. Check out dependencies:
      ```
      $ ./swift/utils/update-checkout --clone
      ```
   4. Check out the release branch of the latest release:
      ```
      $ cd swift
      $ git checkout swift-5.5.1-RELEASE
      ```
   5. Build the complete swift project (be very patient, this may take long):
      ```
      $ ./utils/build-script --skip-build
      ```
2. **Copy updated sources and headers from the checkout to this library:**
   1. Run the update script in this directory (requires Python 3):
      ```
      $ ./update.py swift-source
      ```
   2. Check for modifications.
   3. Commit _"feat(demangle): Import libswift demangle x.x.x"_ before proceeding.
3. **Apply the patch:**
   1. Apply `1-arguments.patch`.
   2. Build the Rust library and ensure tests work.
   3. Commit the changes.
4. **Add tests for new mangling schemes:**
   1. Identify new mangling schemes. Skip if there are no known changes.
   2. Add test cases to `tests/swift.rs`
5. **Update Repository metadata**:
   1. Bump the Swift version number in this README.
   2. Check for changes in the license and update the files.
   3. Update the patch file with the commit generated in step 3:
      ```
      $ git show <commit> > 1-arguments.patch
      ```
6. **Create a pull request.**

[swift programming language]: https://github.com/apple/swift
[latest release]: https://github.com/apple/swift/releases/latest/
