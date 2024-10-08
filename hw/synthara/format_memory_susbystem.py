from mako.template import Template
import sys
import os


# This script is just meant to test the formatting of the output file memory_subsystem_temp.sv 
# When launching the make mcu-gen-snt, the formatted file will be in another file path #
# Define the paths relative to the folder where this script is
script_dir = os.path.dirname(os.path.abspath(__file__))
template_path = os.path.join(script_dir, 'memory_subsystem.sv.tpl')
output_path = os.path.join(script_dir, 'memory_subsystem_temp.sv')

# Load the template
with open(template_path, 'r') as template_file:
    template_content = template_file.read()

# Create a Mako template
template = Template(template_content)

# Add the parent directory to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../util')))

# Now you can import the modules
from x_heep_gen.linker_section import LinkerSection
from x_heep_gen.system import XHeep, BusType

system = XHeep(BusType.NtoM)

# second is the bank size in KiB
# TODO: FOR NOW IS HARDCODED TO 4KiB!!! change!!!
NUM_BANKS = 2
system.add_ram_banks([32] * NUM_BANKS, str([16] * NUM_BANKS))

system.add_linker_section(LinkerSection.by_size("code", 0, 0x00000C800))
system.add_linker_section(LinkerSection("data", 0x00000C800, None))

# Here the system is build,
# The missing gaps are filled, like the missing end address of the data section.
system.build()

# # Define the context variables
# context = {
#     'system': system
# }

# Render the template with the context variables
rendered_content = template.render(xheep=system)

# Write the rendered content to the output file
with open(output_path, 'w') as output_file:
    output_file.write(rendered_content)