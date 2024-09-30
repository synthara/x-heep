from mako.template import Template

# Define the paths
template_path = '/home/vcl/Desktop/workspace/xheep/chimera/design/subsys/xhp/hw/synthara/memory_subsystem.sv.tpl'
output_path = '/home/vcl/Desktop/workspace/xheep/chimera/design/subsys/xhp/hw/synthara/memory_subsystem.sv'

# Load the template
with open(template_path, 'r') as template_file:
    template_content = template_file.read()

# Create a Mako template
template = Template(template_content)

# Render the template with any necessary context variables
# For example, if you have variables to pass, you can do it like this:
# rendered_content = template.render(variable1=value1, variable2=value2)
import sys
import os

# Add the parent directory to the Python path
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../util')))

# Now you can import the modules
from x_heep_gen.linker_section import LinkerSection
from x_heep_gen.system import XHeep, BusType

# Your code here

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