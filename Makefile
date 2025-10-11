################################################################################
# File     : Makefile
# Author   : David Gussler
# Language : gnu make
# ==============================================================================
# Project maintenance commands
# ..Windows users: Run from git bash, mysys2, or WSL2 prompt.
################################################################################

# Project Settings
PROJ_NAME := sblib
PART_NUM := xc7z020clg400-1

# Library Version
# Use semantic versioning with respect to the module HDL interfaces.
# Update the version and add appropriate notes to the CHANGELOG.md each time 
# a new library version is tagged and released.
VER_MAJOR := 0
VER_MINOR := 1
VER_PATCH := 0

# Number of processor threads to use. To use all available threads, set to 0
JOBS ?= 0

# Required project build tool versions
REQUIRE_REGS_VER   := 8.0.0
REQUIRE_VSG_VER    := 3.30.0
REQUIRE_VUNIT_VER  := 5.0.0.dev6


################################################################################
MAKEFILE_DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
SRC_DIR := $(MAKEFILE_DIR)src
TEST_DIR := $(MAKEFILE_DIR)test
BUILD_DIR := $(MAKEFILE_DIR)build
BUILD_NAME := $(PRJ_NAME)_v$(VER_MAJOR)_$(VER_MINOR)_$(VER_PATCH)
RELEASE_DIR := $(BUILD_DIR)/$(BUILD_NAME)
REGS_SRC := $(SRC_DIR)/**/regs/*.toml
STYLE_SRC := $(SRC_DIR)/**/hdl/*.vhd $(TEST_DIR)/**/*.vhd
NEW_TAG := v$(VER_MAJOR).$(VER_MINOR).$(VER_PATCH)

.PHONY: package build release sim regs style style-fix tool-check clean

# Check versions of required build tools
tool-check:
	@if [ $(shell python3 -m pip show hdl_registers | grep Version: | awk '{print $$2}') != $(REQUIRE_REGS_VER) ]; then \
		echo "ERROR: Requires hdl_registers $(REQUIRE_REGS_VER)"; \
		exit 1; \
	fi

	@if [ $(shell python3 -m pip show vsg | grep Version: | awk '{print $$2}') != $(REQUIRE_VSG_VER) ]; then \
		echo "ERROR: Requires vsg $(REQUIRE_VSG_VER)"; \
		exit 1; \
	fi

	@if [ $(shell python3 -m pip show vunit_hdl | grep Version: | awk '{print $$2}') != $(REQUIRE_VUNIT_VER) ]; then \
		echo "ERROR: Requires vunit_hdl $(REQUIRE_VUNIT_VER)"; \
		exit 1; \
	fi
	@echo "INFO: Tool check passed."

# Create a release package with all of the built output products
package: regs
	mkdir -p $(RELEASE_DIR)
	cp $(BUILD_DIR)/regs_out/*/*.h* $(RELEASE_DIR)
	cd $(BUILD_DIR) && tar -czvf $(BUILD_NAME).tar.gz $(RELEASE_DIR)

# Run the VUnit simulation
sim: regs
	cd tools && python sim.py --xunit-xml $(BUILD_DIR)/sim_report.xml -p $(JOBS)

# Check the coding style of the src files
style:
	mkdir -p $(BUILD_DIR)
	vsg -f $(STYLE_SRC) -c ./tools/vsg_rules.yaml -of vsg --all_phases --quality_report $(BUILD_DIR)/style_report.json

# Check AND FIX the coding style of the src files
style-fix:
	mkdir -p $(BUILD_DIR)
	vsg -f $(STYLE_SRC) -c ./tools/vsg_rules.yaml -of vsg --fix

# Generate the register output products
regs:
	cd tools && python regs.py $(REGS_SRC)

# Create a new git tag and Github release for this version of the code. A Github
# action will generate the release from source.
release:
	@if ! git diff-index --quiet HEAD --; then \
		echo "ERROR: Uncommitted changes detected. Commit them before proceeding." >&2; \
		exit 1; \
	fi
	@echo "Last tag: $(shell git describe --tags --abbrev=0 2>/dev/null || echo "NA")"
	@echo "New tag : $(NEW_TAG)"
	@echo
	@echo "NOTICE: If the value for the new tag is unacceptable, then the tag"
	@echo "may be changed by modifying the VER_* Makefile variables."
	@echo
	@echo "NOTICE: Before proceeding, don't forget to update CHANGELOG.md with the"
	@echo "details of this release."
	@echo
	@echo "NOTICE: A Github action that builds and releases this version of the FPGA"
	@echo "will be triggered."
	@echo
	@read -p "Do you want to proceed? (y/n): " user_input; \
	if [ "$$user_input" != "y" ]; then \
		echo "Aborting..."; \
		exit 1; \
	fi
	git tag -a $(NEW_TAG) -m "Release $(NEW_TAG)" 
	git push origin $(NEW_TAG)

clean:
	rm -rf build
