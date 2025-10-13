################################################################################
# File : sim.py
# Auth : David Gussler
# Lang : python3
# ==============================================================================
# Common VUnit sim script
################################################################################

from vunit import VUnit
from pathlib import Path
import os
import sys
from enum import Enum

# Import test configurations
# ..they are in a separate file so that this common sim script can be
# maintained separately from repo-specific test configurations.
import sim_configs

################################################################################
# Setup
################################################################################

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent

class Simulator(Enum):
    GHDL = 1
    NVC = 2

#Execute from script directory
os.chdir(SCRIPT_DIR)

# Argument handling
argv = sys.argv[1:]
SIMULATOR = Simulator.GHDL

# Simulator Selection
# ..The environment variable VUNIT_SIMULATOR has precedence over the commandline
# options.
if "--ghdl" in sys.argv:
    SIMULATOR = Simulator.GHDL
    argv.remove("--ghdl")
if "--nvc" in sys.argv:
    SIMULATOR = Simulator.NVC
    argv.remove("--nvc")

# The simulator must be chosen before sources are added
if 'VUNIT_SIMULATOR' not in os.environ:    
    if SIMULATOR == Simulator.GHDL:
        os.environ['VUNIT_SIMULATOR'] = 'ghdl'
    elif SIMULATOR == Simulator.NVC:
        os.environ['VUNIT_SIMULATOR'] = 'nvc'

# Parse VUnit Arguments
vu = VUnit.from_argv(argv=argv)
vu.add_vhdl_builtins()
vu.add_com()
vu.add_osvvm()
vu.add_verification_components()

# Add source files
lib = vu.add_library("lib")
lib.add_source_files(ROOT_DIR / "src" / "**" / "hdl" / "*.vhd", allow_empty=True)
lib.add_source_files(ROOT_DIR / "lib" / "**" / "src" / "**" / "hdl" / "*.vhd", allow_empty=True)
lib.add_source_files(ROOT_DIR / "test" / "**" / "*.vhd", allow_empty=True)
lib.add_source_files(ROOT_DIR / "build" / "regs_out" / "**" / "hdl" / "*.vhd", allow_empty=True)


################################################################################
# Test bench configurations
################################################################################

sim_configs.add_configs(lib)


################################################################################
# Execution
################################################################################

lib.add_compile_option('ghdl.a_flags', ['-frelaxed-rules', '-Wno-hide', '-Wno-shared'])
lib.add_compile_option('nvc.a_flags', ['--relaxed'])
lib.set_sim_option('ghdl.elab_flags', ['-frelaxed'])
lib.set_sim_option('nvc.heap_size', '5000M')

# Run
vu.main()
