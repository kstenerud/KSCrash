# Directories to search
SEARCH_DIRS = Sources Tests Samples/Common/Sources/CrashTriggers
SWIFT_SEARCH_DIRS = Sources Tests Samples

# File extensions to format
FILE_EXTENSIONS = c cpp h m mm

# Check for clang-format-18 first, then fall back to clang-format
CLANG_FORMAT := $(shell command -v clang-format-18 2> /dev/null || command -v clang-format 2> /dev/null)

# Swift format command (using toolchain)
SWIFT_FORMAT_CMD = swift format

# Define the default target
.PHONY: format check-format swift-format check-swift-format

all: format swift-format

format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format or clang-format-18 is not installed. Please install it and try again."
	@exit 1
else
	@echo "Using $(CLANG_FORMAT)"
	find $(SEARCH_DIRS) $(foreach ext,$(FILE_EXTENSIONS),-name '*.$(ext)' -o) -false | \
	xargs -r $(CLANG_FORMAT) -style=file -i
endif

check-format:
ifeq ($(CLANG_FORMAT),)
	@echo "Error: clang-format or clang-format-18 is not installed. Please install it and try again."
	@exit 1
else
	@echo "Checking format using $(CLANG_FORMAT)"
	@find $(SEARCH_DIRS) $(foreach ext,$(FILE_EXTENSIONS),-name '*.$(ext)' -o) -false | \
	xargs -r $(CLANG_FORMAT) -style=file -n -Werror
endif

swift-format:
	@echo "Formatting Swift files..."
	@{ find $(SWIFT_SEARCH_DIRS) -name '*.swift' -type f -not -path '*/.build/*'; \
	   [ -f Package.swift ] && echo Package.swift; } | \
	while read file; do \
		$(SWIFT_FORMAT_CMD) format --in-place --configuration .swift-format "$$file"; \
	done

check-swift-format:
	@echo "Checking Swift format..."
	@{ find $(SWIFT_SEARCH_DIRS) -name '*.swift' -type f -not -path '*/.build/*'; \
	   [ -f Package.swift ] && echo Package.swift; } | \
	while read file; do \
		$(SWIFT_FORMAT_CMD) lint --configuration .swift-format "$$file" --strict || exit 1; \
	done
