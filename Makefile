# Directories to search
SEARCH_DIRS = Sources Tests Samples/Common/Sources/CrashTriggers
SWIFT_SEARCH_DIRS = Sources Tests Samples Benchmarks

# File extensions to format
FILE_EXTENSIONS = c cpp h m mm

# Check for clang-format-20 first, then fall back to clang-format
CLANG_FORMAT := $(shell command -v clang-format-20 2> /dev/null || command -v clang-format 2> /dev/null)

# Swift format command (using toolchain)
SWIFT_FORMAT_CMD = swift format

# Find all C/C++/ObjC files
FIND_C_FILES = find $(SEARCH_DIRS) \( $(foreach ext,$(FILE_EXTENSIONS),-name '*.$(ext)' -o) -false \)

# Find all Swift files
FIND_SWIFT_FILES = { find $(SWIFT_SEARCH_DIRS) -name '*.swift' -type f -not -path '*/.build/*' -not -path '*/DerivedData/*'; [ -f Package.swift ] && echo Package.swift; }

.PHONY: all format check-format swift-format check-swift-format namespace namespace-check

all: format swift-format
	@echo ""
	@echo "All done!"

format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format is not installed. Please install it and try again."
	@exit 1
else
	@echo "[1/2] Formatting C/C++/ObjC files..."
	@echo "      $(CLANG_FORMAT) ($$($(CLANG_FORMAT) --version))"
	@COUNT=$$($(FIND_C_FILES) | wc -l | tr -d ' '); \
	$(FIND_C_FILES) | xargs -r $(CLANG_FORMAT) -style=file -i; \
	echo "      $$COUNT files formatted."
endif

check-format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format is not installed. Please install it and try again."
	@exit 1
else
	@echo "[1/2] Checking C/C++/ObjC formatting..."
	@echo "      $(CLANG_FORMAT) ($$($(CLANG_FORMAT) --version))"
	@COUNT=$$($(FIND_C_FILES) | wc -l | tr -d ' '); \
	if $(FIND_C_FILES) | xargs -r $(CLANG_FORMAT) -style=file -n -Werror; then \
		echo "      $$COUNT files checked. All clean!"; \
	else \
		echo ""; \
		echo "      $$COUNT files checked. Issues found."; \
		exit 1; \
	fi
endif

swift-format:
	@echo "[2/2] Formatting Swift files..."
	@echo "      $(SWIFT_FORMAT_CMD) (v$$($(SWIFT_FORMAT_CMD) --version))"
	@COUNT=$$($(FIND_SWIFT_FILES) | wc -l | tr -d ' '); \
	$(FIND_SWIFT_FILES) | xargs $(SWIFT_FORMAT_CMD) format --in-place --configuration .swift-format; \
	echo "      $$COUNT files formatted."

check-swift-format:
	@echo "[2/2] Checking Swift formatting..."
	@echo "      $(SWIFT_FORMAT_CMD) (v$$($(SWIFT_FORMAT_CMD) --version))"
	@COUNT=$$($(FIND_SWIFT_FILES) | wc -l | tr -d ' '); \
	if $(FIND_SWIFT_FILES) | xargs $(SWIFT_FORMAT_CMD) lint --configuration .swift-format --strict; then \
		echo "      $$COUNT files checked. All clean!"; \
	else \
		echo ""; \
		echo "      $$COUNT files checked. Issues found."; \
		exit 1; \
	fi

namespace:
	namespacer/generate.sh

namespace-check:
	namespacer/namespace-check.sh
