################################################################################
# File : sim_configs.py
# Auth : David Gussler
# Lang : python3
# ==============================================================================
# Project-specific VUnit sim config definitions
################################################################################

import sim_utils
from itertools import product

################################################################################
# TB definitions and generic permutations
################################################################################
def add_configs(lib): 
    ## Stream Pipes
    tb = lib.test_bench('strm_pipes_tb')

    stagess = [1, 3]
    ready_pipes = [True, False]
    data_pipes = [True, False]
    stall_probs = [50]

    for stages, ready_pipe, data_pipe, stall_prob in product(stagess, ready_pipes, data_pipes, stall_probs):
      sim_utils.named_config(tb, {
            'G_STAGES': stages,
            'G_READY_PIPE': ready_pipe,
            'G_DATA_PIPE': data_pipe,
            'G_AXIS_STALL_PROB': stall_prob,
        })


    ## FIFO
    tb = lib.test_bench('fifo_tb')

    out_regs = [False]
    stall_probs = [50]

    for out_reg, stall_prob in product(out_regs, stall_probs):
        sim_utils.named_config(tb, {
            'G_OUT_REG': out_reg,
            'G_AXIS_STALL_PROB': stall_prob,
        })


    ## Async FIFO
    tb = lib.test_bench('fifo_async_tb')

    out_regs = [False]
    clk_ratios = [100, 50, 200, 150, 12, 432, 95]
    stall_probs = [50]

    for out_reg, clk_ratio, stall_prob in product(out_regs, clk_ratios, stall_probs):
        sim_utils.named_config(tb, {
            'G_OUT_REG': out_reg,
            'G_CLK_RATIO': clk_ratio,
            'G_AXIS_STALL_PROB': stall_prob,
        })



    ## CDC Vector
    tb = lib.test_bench('cdc_vector_tb')

    clk_ratios = [100, 50, 200, 150, 12, 432, 95]
    stall_probs = [50]

    for clk_ratio, stall_prob in product(clk_ratios, stall_probs):
        sim_utils.named_config(tb, {
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
        sim_utils.named_config(tb, {
            'G_RD_LATENCY': rd_latency,
            'G_AXIS_STALL_PROB': stall_prob,
        })


    ############################################################################
    tb = lib.test_bench('axis_mux_tb')

    enable_jitter = [True]
    low_area = [True, False]

    for enable_jitter, low_area in product(enable_jitter, low_area):
      sim_utils.named_config(tb, {
            'G_ENABLE_JITTER': enable_jitter,
            'G_LOW_AREA': low_area,
        })
      
    ############################################################################
    tb = lib.test_bench('axis_arb_tb')

    enable_jitter = [True]
    low_area = [False]

    for enable_jitter, low_area in product(enable_jitter, low_area):
      sim_utils.named_config(tb, {
            'G_ENABLE_JITTER': enable_jitter,
            'G_LOW_AREA': low_area,
        })

    ############################################################################
    tb = lib.test_bench('axis_demux_tb')

    enable_jitter = [True]
    low_area = [True, False]

    for enable_jitter, low_area in product(enable_jitter, low_area):
      sim_utils.named_config(tb, {
            'G_ENABLE_JITTER': enable_jitter,
            'G_LOW_AREA': low_area,
        })

    ############################################################################
    tb = lib.test_bench('axis_pipe_tb')

    enable_jitter = [True]
    ready_pipe = [True, False]
    data_pipe = [True, False]

    for enable_jitter, ready_pipe, data_pipe in product(enable_jitter, ready_pipe, data_pipe):
      sim_utils.named_config(tb, {
            'G_ENABLE_JITTER': enable_jitter,
            'G_READY_PIPE': ready_pipe,
            'G_DATA_PIPE': data_pipe,
        })

    ############################################################################
    tb = lib.test_bench('axis_resize_tb')

    enable_jitter = [True]
    s_dw = [8, 32, 64, 128]
    m_dw = [32]
    s_uw = [16]

    for enable_jitter, s_dw, m_dw, s_uw in product(enable_jitter, s_dw, m_dw, s_uw):
      sim_utils.named_config(tb, {
            'G_ENABLE_JITTER': enable_jitter,
            'G_S_DW': s_dw,
            'G_M_DW': m_dw,
            'G_S_UW': s_uw,
        })
