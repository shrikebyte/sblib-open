import sys
import os
from pathlib import Path

from hdl_registers.parser.toml import from_toml
from hdl_registers.generator.vhdl.axi_lite.wrapper import VhdlAxiLiteWrapperGenerator
from hdl_registers.generator.vhdl.record_package import VhdlRecordPackageGenerator
from hdl_registers.generator.vhdl.register_package import VhdlRegisterPackageGenerator
from hdl_registers.generator.vhdl.simulation.check_package import VhdlSimulationCheckPackageGenerator
from hdl_registers.generator.vhdl.simulation.read_write_package import VhdlSimulationReadWritePackageGenerator
from hdl_registers.generator.vhdl.simulation.wait_until_package import VhdlSimulationWaitUntilPackageGenerator
from hdl_registers.generator.c.header import CHeaderGenerator
from hdl_registers.generator.cpp.header import CppHeaderGenerator
from hdl_registers.generator.cpp.implementation import CppImplementationGenerator
from hdl_registers.generator.cpp.interface import CppInterfaceGenerator
from hdl_registers.generator.html.constant_table import HtmlConstantTableGenerator
from hdl_registers.generator.html.page import HtmlPageGenerator
from hdl_registers.generator.html.register_table import HtmlRegisterTableGenerator
from hdl_registers.generator.python.accessor import PythonAccessorGenerator
from hdl_registers.generator.python.pickle import PythonPickleGenerator

THIS_DIR = Path(__file__).parent

################################################################################
# Register generator text replacement
# ..Modify the generated VHDL to better fit this library.
################################################################################
def replace_first_occurrence(file_path, old_text, new_text):
    path = Path(file_path)
    text = path.read_text()

    # Replace only the first occurrence
    new_content = text.replace(old_text, new_text, 1)

    if new_content == text:
        #print("No match found.")
        return

    path.write_text(new_content)
    #print(f"Replaced first occurrence of:\n{old_text}\nwith:\n{new_text} in file:\n{path}")




OLD_TEXT_AXI_LITE_1 = """-- This VHDL file is a required dependency:
-- https://github.com/hdl-modules/hdl-modules/blob/main/modules/axi_lite/src/axi_lite_pkg.vhd
-- See https://hdl-registers.com/rst/generator/generator_vhdl.html for dependency details.
library axi_lite;
use axi_lite.axi_lite_pkg.all;

-- This VHDL file is a required dependency:
-- https://github.com/hdl-modules/hdl-modules/blob/main/modules/register_file/src/axi_lite_register_file.vhd
-- See https://hdl-registers.com/rst/generator/generator_vhdl.html for dependency details.
library register_file;"""

NEW_TEXT_AXI_LITE_1 = """use work.axi_lite_pkg.all;
use work.util_pkg.all;
use work.hdlm_conv_pkg.all;
"""




OLD_TEXT_AXI_LITE_2 = """    --# {}
    --# Register control bus.
    axi_lite_m2s : in axi_lite_m2s_t;
    axi_lite_s2m : out axi_lite_s2m_t := axi_lite_s2m_init;
"""

NEW_TEXT_AXI_LITE_2 = """    --# {}
    --# Register control bus.
    s_axil_req  : in    axil_req_t;
    s_axil_rsp  : out   axil_rsp_t;
"""




OLD_TEXT_AXI_LITE_3 = """
begin

  ------------------------------------------------------------------------------
  -- Instantiate the generic register file implementation:
  -- https://github.com/hdl-modules/hdl-modules/blob/main/modules/register_file/src/axi_lite_register_file.vhd
  -- See https://hdl-registers.com/rst/generator/generator_vhdl.html for dependency details.
  axi_lite_register_file_inst : entity register_file.axi_lite_register_file"""

NEW_TEXT_AXI_LITE_3 = """
  signal axi_lite_m2s : axi_lite_m2s_t;
  signal axi_lite_s2m : axi_lite_s2m_t;

begin

  axi_lite_m2s <= to_hdlm(s_axil_req);
  s_axil_rsp   <= to_hdlm(axi_lite_s2m);

  ------------------------------------------------------------------------------
  -- Instantiate the generic register file implementation
  axi_lite_register_file_inst : entity work.axi_lite_register_file"""




OLD_TEXT_RECORD_PKG = """library register_file;
use register_file.register_file_pkg.register_t;"""

NEW_TEXT_RECORD_PKG = "use work.register_file_pkg.register_t;"




OLD_TEXT_REGS_PKG = """library register_file;
use register_file.register_file_pkg.all;"""

NEW_TEXT_REGS_PKG = "use work.register_file_pkg.all;"


################################################################################
# Main
################################################################################
def main(toml_files: list[Path]):
    """
    Create register artifacts from a toml file
    """

    for toml_file in toml_files:
        name = toml_file.stem
        output_dir = Path(THIS_DIR.parent / "build" / "regs_out" / name)
        hdl_output_dir = Path(output_dir / "hdl")

        register_list = from_toml(name=name, toml_file=toml_file)

        # VHDL
        VhdlRegisterPackageGenerator(register_list=register_list, output_folder=hdl_output_dir).create_if_needed()
        VhdlRecordPackageGenerator(register_list=register_list, output_folder=hdl_output_dir).create_if_needed()
        VhdlAxiLiteWrapperGenerator(register_list=register_list, output_folder=hdl_output_dir).create_if_needed()
        # We make some small edits to the generated VHDL so that it does not
        # depend on pre-defined VHDL namespaces
        replace_first_occurrence(Path(hdl_output_dir / f"{name}_register_file_axi_lite.vhd"), OLD_TEXT_AXI_LITE_1, NEW_TEXT_AXI_LITE_1)
        replace_first_occurrence(Path(hdl_output_dir / f"{name}_register_file_axi_lite.vhd"), OLD_TEXT_AXI_LITE_2, NEW_TEXT_AXI_LITE_2)
        replace_first_occurrence(Path(hdl_output_dir / f"{name}_register_file_axi_lite.vhd"), OLD_TEXT_AXI_LITE_3, NEW_TEXT_AXI_LITE_3)
        replace_first_occurrence(Path(hdl_output_dir / f"{name}_register_record_pkg.vhd"), OLD_TEXT_RECORD_PKG, NEW_TEXT_RECORD_PKG)
        replace_first_occurrence(Path(hdl_output_dir / f"{name}_regs_pkg.vhd"), OLD_TEXT_REGS_PKG, NEW_TEXT_REGS_PKG)

        # C Header
        CHeaderGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()

        # C++
        # CppInterfaceGenerator(register_list=register_list, output_folder=output_dir / "include").create_if_needed()
        # CppHeaderGenerator( register_list=register_list, output_folder=output_dir / "include").create_if_needed()
        # CppImplementationGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()

        # HTML
        HtmlPageGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()
        # HtmlRegisterTableGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()
        # HtmlConstantTableGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()

        # Python
        # PythonPickleGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()
        # PythonAccessorGenerator(register_list=register_list, output_folder=output_dir).create_if_needed()


if __name__ == "__main__":
    main(toml_files=[Path(s) for s in sys.argv[1:] if os.path.exists(s)])
