################################################################################
# File : sim_utils.py
# Auth : David Gussler
# Lang : python3
# ==============================================================================
# Common VUnit sim utilities
################################################################################

def named_config(tb, map : dict):
    cfg_name = "-".join([f"{k}={v}" for k, v in map.items()])
    tb.add_config(name=cfg_name, generics = map)
