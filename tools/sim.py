from vunit import VUnit
from pathlib import Path
import os
import sys
from enum import Enum
from itertools import product

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent

class Simulator(Enum):
    GHDL = 1
    NVC = 2
    QUESTASIM = 3

#Execute from script directory
os.chdir(SCRIPT_DIR)

# Argument handling
argv = sys.argv[1:]
SIMULATOR = Simulator.GHDL
USE_COVERAGE = False
GUI = False

# Simulator Selection
# ..The environment variable VUNIT_SIMULATOR has precedence over the commandline
# options.
if "--ghdl" in sys.argv:
    SIMULATOR = Simulator.GHDL
    argv.remove("--ghdl")
if "--nvc" in sys.argv:
    SIMULATOR = Simulator.NVC
    argv.remove("--nvc")
if "--questasim" in sys.argv:    
    SIMULATOR = Simulator.QUESTASIM
    argv.remove("--questasim")
if "--coverage" in sys.argv:
    USE_COVERAGE = True
    argv.remove("--coverage")
    if SIMULATOR != Simulator.QUESTASIM:
        raise "Coverage is only allowed with --questasim"
if "--gui" in sys.argv:
    GUI = True

# The simulator must be chosen before sources are added
if 'VUNIT_SIMULATOR' not in os.environ:    
    if SIMULATOR == Simulator.GHDL:
        os.environ['VUNIT_SIMULATOR'] = 'ghdl'
    elif SIMULATOR == Simulator.NVC:
        os.environ['VUNIT_SIMULATOR'] = 'nvc'
    else:
        os.environ['VUNIT_SIMULATOR'] = 'questasim'

# Parse VUnit Arguments
vu = VUnit.from_argv(argv=argv)
vu.add_vhdl_builtins()
vu.add_com()
vu.add_osvvm()
vu.add_verification_components()

# Libraries
axi_lite = vu.add_library("axi_lite")
register_file = vu.add_library("register_file")
lib = vu.add_library("lib")

lib.add_source_files(ROOT_DIR / "src" / "**" / "hdl" / "*.vhd")
lib.add_source_files(ROOT_DIR / "test" / "**" / "*.vhd")
lib.add_source_files(ROOT_DIR / "build" / "regs_out" / "**" / "hdl" / "*.vhd")

axi_lite.add_source_files(ROOT_DIR / "src" / "hdlm" / "hdl" / "axi_lite_pkg.vhd")

register_file.add_source_files(ROOT_DIR / "src" / "hdlm" / "hdl" / "axi_lite_register_file.vhd")
register_file.add_source_files(ROOT_DIR / "src" / "hdlm" / "hdl" / "register_file_pkg.vhd")


################################################################################
# Shared Functions
################################################################################
def named_config(tb, map : dict):
    cfg_name = "-".join([f"{k}={v}" for k, v in map.items()])
    tb.add_config(name=cfg_name, generics = map)


################################################################################
# TB definitions and generic permutations
################################################################################

## Stream Pipes
tb = lib.test_bench('strm_pipes_tb')

stagess = [1, 3]
ready_pipes = [True, False]
data_pipes = [True, False]
stall_probs = [0, 50]

for stages, ready_pipe, data_pipe, stall_prob in product(stagess, ready_pipes, data_pipes, stall_probs):
    named_config(tb, {
        'G_STAGES': stages,
        'G_READY_PIPE': ready_pipe,
        'G_DATA_PIPE': data_pipe,
        'G_AXIS_STALL_PROB': stall_prob,
    })


## FIFO
tb = lib.test_bench('fifo_tb')

out_regs = [True, False]
stall_probs = [0, 50]

for out_reg, stall_prob in product(out_regs, stall_probs):
    named_config(tb, {
        'G_OUT_REG': out_reg,
        'G_AXIS_STALL_PROB': stall_prob,
    })


## Async FIFO
tb = lib.test_bench('fifo_async_tb')

out_regs = [True, False]
clk_ratios = [100, 50, 200, 150, 12, 432, 95]
stall_probs = [0, 50]

for out_reg, clk_ratio, stall_prob in product(out_regs, clk_ratios, stall_probs):
    named_config(tb, {
        'G_OUT_REG': out_reg,
        'G_CLK_RATIO': clk_ratio,
        'G_AXIS_STALL_PROB': stall_prob,
    })



## CDC Vector
tb = lib.test_bench('cdc_vector_tb')

clk_ratios = [100, 50, 200, 150, 12, 432, 95]
stall_probs = [0, 50]

for clk_ratio, stall_prob in product(clk_ratios, stall_probs):
    named_config(tb, {
        'G_CLK_RATIO': clk_ratio,
        'G_AXIS_STALL_PROB': stall_prob,
    })


# tb = lib.test_bench('axil_stdver_tb')
# named_config(tb, {})


## AXIL RAM
tb = lib.test_bench('axil_ram_tb')

rd_latencys = [1, 2, 3, 4]
stall_probs = [0, 50]

for rd_latency, stall_prob in product(rd_latencys, stall_probs):
    named_config(tb, {
        'G_RD_LATENCY': rd_latency,
        'G_AXIS_STALL_PROB': stall_prob,
    })


################################################################################
# Execution
################################################################################
lib.add_compile_option('ghdl.a_flags', ['-frelaxed-rules', '-Wno-hide', '-Wno-shared'])
lib.add_compile_option('nvc.a_flags', ['--relaxed'])
lib.set_sim_option('ghdl.elab_flags', ['-frelaxed'])
lib.set_sim_option('nvc.heap_size', '5000M')


# Enable debugging options if we are viewing waveforms with the gui
if GUI:
    lib.add_compile_option("modelsim.vcom_flags", ["+acc",  "-O0"])


if USE_COVERAGE:
    lib.set_compile_option('modelsim.vcom_flags', ['+cover=bs'])
    lib.set_compile_option('modelsim.vlog_flags', ['+cover=bs'])
    lib.set_sim_option("enable_coverage", True)

    def post_run(results):
        results.merge_coverage(file_name='coverage_data')
else:
    def post_run(results):
        pass

# Run
vu.main(post_run=post_run)
