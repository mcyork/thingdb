import sys

file_path = '/usr/local/btwifiset/btwifiset.py'

with open(file_path, 'r') as f:
    content = f.read()

content = content.replace('return network_manager_is_running', 'return False  # Force wpa_supplicant method')

with open(file_path, 'w') as f:
    f.write(content)
