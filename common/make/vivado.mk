# Check that given variables are set and all have non-empty values,
# die with an error otherwise.
#
# Params:
#   1. Variable name(s) to test.
#   2. (optional) Error message to print.
# c/o https://stackoverflow.com/questions/10858261/abort-makefile-if-variable-not-set
check_defined = \
    $(strip $(foreach 1,$1, \
        $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = \
    $(if $(value $1),, \
      $(error Undefined $1$(if $2, ($2))))

# variables that should be defined for all labs
$(call check_defined, SYNTH_SOURCES TOP_SYNTH_MODULE TESTBENCH TOP_TESTBENCH_MODULE, Each lab Makefile should define this)

ifdef TOP_IMPL_MODULE
$(call check_defined, IMPL_SOURCES TOP_IMPL_MODULE BITSTREAM_FILENAME CONSTRAINTS, Each implementation lab Makefile should define this)
endif

ifdef ZIP_SOURCES
$(call check_defined, ZIP_SOURCES ZIP_FILE, Each lab Makefile where a zip file is submitted should define this)
endif

ifndef CIS371_AUTOGRADER
XELAB_FLAGS=-cc gcc
endif

# shorthand variables for constraint files and Tcl scripts
# NB: COMMON_DIR is wrt the Makefile in each lab's directory, not wrt this file
COMMON_DIR=../common
TCL_DIR=$(COMMON_DIR)/tcl
SDBOOT_DIR=$(COMMON_DIR)/sdcard-boot
SDBOOT_BIF=.boot.bif

time=time -f "Vivado took %E m:s and %M KB"

# NB: the .set_testcase.v target does create a file .set_testcase.v, but we want it to run every time so we declare it phony
.PHONY: .set_testcase.v debug program pennsim boot clean extraclean

# if invoked with no explicit target, print out a help message
.DEFAULT: help
help:
	@echo -e "Valid targets are: synth test debug impl zip program boot clean"

# run synthesis to identify code errors/warnings
synth: setup-files $(SYNTH_SOURCES)
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	echo -n "synthesis" > .step
	$(time) vivado -mode batch -source $(TCL_DIR)/build.tcl

# run all tests
ifdef NEEDS_TEST_CASE
test: $(SYNTH_SOURCES) $(TESTBENCH) .set_testcase.v
else
test: $(SYNTH_SOURCES) $(TESTBENCH)
endif
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	rm -rf xsim.dir/
	echo -n verilog mylib $^ > .prj
	xelab $(XELAB_FLAGS) --debug off --prj .prj --snapshot snapshot.sim --lib mylib mylib.$(TOP_TESTBENCH_MODULE)
	xsim snapshot.sim --runall --stats -wdb sim.wdb

# run tests with Icarus Verilog simulator
ifdef NEEDS_TEST_CASE
iv-test: $(SYNTH_SOURCES) $(TESTBENCH) .set_testcase.v
else
iv-test: $(SYNTH_SOURCES) $(TESTBENCH)
endif
	@which iverilog || (echo "ERROR: can't find iverilog executable" && exit 1)
	iverilog -Wall -Iinclude -s $(TOP_TESTBENCH_MODULE) -DGENERATE_VCD=1 -o a.out $^
	./a.out


# investigate design via GUI debugger
ifdef NEEDS_TEST_CASE
debug: setup-files .set_testcase.v
else
debug: setup-files
endif
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	rm -rf .debug-project
#	echo -n " .set_testcase.v" >> .synthesis-source-files
	vivado -mode batch -source $(TCL_DIR)/debug.tcl

# run synthesis & implementation to generate a bitstream
impl: setup-files $(IMPL_SOURCES)
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	echo -n "implementation" > .step
	$(time) vivado -mode batch -source $(TCL_DIR)/build.tcl

# program the device with user-specified bitstream
program:
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	@echo -n "Specify .bit file to use to program FPGA, then press <ENTER> [leave blank for output/$(BITSTREAM_FILENAME)]: "
	@read bitfile && if [ -z "$$bitfile" ]; then export BITSTREAM_FILE="output/$(BITSTREAM_FILENAME)" ; else export BITSTREAM_FILE=$$bitfile; fi && echo $$BITSTREAM_FILE && $(time) vivado -mode batch -notrace -source $(TCL_DIR)/program.tcl

# create a zip archive of source code, bitstream, and power/performance/area reports. We filter out warnings because for the ALU-only version of the processor labs we pull in a bitstream, even though the bitstream is only for the full version of the lab
zip: $(ZIP_SOURCES)
	zip $(ZIP_FILE) $(ZIP_SOURCES) | grep -v warning

# place arguments to Tcl debug/synthesis/implementation scripts into hidden files
setup-files:
	echo -n $(SYNTH_SOURCES) > .synthesis-source-files
	echo -n $(IP_BLOCKS) > .ip-blocks
	echo -n $(TOP_SYNTH_MODULE) > .top-synth-module
	echo -n $(IMPL_SOURCES) > .implementation-source-files
	echo -n $(TOP_IMPL_MODULE) > .top-impl-module
	echo -n $(TESTBENCH) > .simulation-source-files
	echo -n $(TOP_TESTBENCH_MODULE) > .top-level-testbench
	echo -n $(CONSTRAINTS) > .constraint-files
	echo -n $(BITSTREAM_FILENAME) > .bitstream-filename

# find path to this Makefile (NB: MAKEFILE_LIST also contains vivado.mk as the 2nd entry)
THIS_MAKEFILE_PATH=$(dir $(realpath $(firstword $(MAKEFILE_LIST))))

# write paths to test input/output traces and memory contents
.set_testcase.v:
ifdef NEEDS_TEST_CASE
ifndef TEST_CASE
	$(error ERROR: you need to define TEST_CASE. Re-run with "TEST_CASE=... make $(MAKECMDGOALS)")
else
ifeq (TEST_CASE,)
	$(error ERROR: you need to define TEST_CASE. Re-run with "TEST_CASE=... make $(MAKECMDGOALS)")
else
	echo \`define INPUT_FILE \"$(THIS_MAKEFILE_PATH)test_data/$(TEST_CASE).ctrace\" > $@
	echo \`define OUTPUT_FILE \"$(THIS_MAKEFILE_PATH)test_data/$(TEST_CASE).output\" >> $@
	echo \`define ORIG_INPUT_FILE \"$(THIS_MAKEFILE_PATH)test_data/$(TEST_CASE).trace\" >> $@
	echo \`define MEMORY_IMAGE_FILE \"$(THIS_MAKEFILE_PATH)test_data/$(TEST_CASE).hex\" >> $@
	echo \`define TEST_CASE \"$(TEST_CASE)\" >> $@
	echo \`define VCD_FILE \"$(TEST_CASE).vcd\" >> $@
endif
endif
endif

pennsim:
	rm -f test_data/lab[345]-demo.hex
	java -jar $(COMMON_DIR)/pennsim/PennSim.jar -t -s $(PENNSIM_SCRIPT)

# make BOOT.BIN image for programming FPGA from an SD card
boot: output/$(BITSTREAM_FILENAME) $(SDBOOT_DIR)/zynq_fsbl_0.elf
ifndef XILINX_VIVADO
	$(error ERROR cannot find Vivado, run "source /home1/c/cis371/software/Vivado/2017.4/settings64.sh")
endif
	echo "the_ROM_image:{[bootloader]"$(SDBOOT_DIR)/zynq_fsbl_0.elf > $(SDBOOT_BIF)
	echo output/$(BITSTREAM_FILENAME)"}" >> $(SDBOOT_BIF)
	bootgen -image $(SDBOOT_BIF) -arch zynq -o output/BOOT.BIN

# remove Vivado logs and our hidden file
clean:
	rm -f webtalk*.log webtalk*.jou vivado*.log vivado*.jou xsim*.log xsim*.jou xelab*.log xelab*.jou vivado_pid*.str usage_statistics_webtalk.*ml
	rm -f .synthesis-source-files .simulation-source-files .implementation-source-files .ip-blocks .top-synth-module .top-impl-module .top-level-testbench .set_testcase.v .constraint-files .bitstream-filename .prj $(SDBOOT_BIF)
	rm -rf xsim.dir/ .Xil/ xelab.pb 

# clean, then remove output/ directory and all .vcd dumps: use with caution!
extraclean: clean
	rm -rf output/ *.vcd
