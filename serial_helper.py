#!/usr/bin/env python3
import subprocess
import sys
import re

def clean_output(text):
    ansi_escape = re.compile(r'\x1B(?:[@-Z\-_]|[\[0-?]*[ -/]*[@-~])')
    text = ansi_escape.sub('', text)
    text = re.sub(r'--- \w+ \d+/\d+ \(END\) ---', '', text)
    text = re.sub(r'Press RETURN to continue', '', text)
    text = re.sub(r'Log file is already in use  \\(press RETURN\\)', '', text)
    text = text.replace('\r', '')
    return text.strip()

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: serial_helper.py <command_to_execute>")
        sys.exit(1)

    command = sys.argv[1]
    try:
        result = subprocess.run(
            command,
            shell=True,
            capture_output=True,
            text=True,
            check=True
        )
        cleaned_stdout = clean_output(result.stdout)
        cleaned_stderr = clean_output(result.stderr)

        if cleaned_stdout:
            print(cleaned_stdout)
        if cleaned_stderr:
            print(f"STDERR: {cleaned_stderr}")

    except subprocess.CalledProcessError as e:
        cleaned_stdout = clean_output(e.stdout)
        cleaned_stderr = clean_output(e.stderr)
        print(f"Command failed with exit code {e.returncode}")
        if cleaned_stdout:
            print(cleaned_stdout)
        if cleaned_stderr:
            print(f"STDERR: {cleaned_stderr}")
        sys.exit(e.returncode)
    except Exception as e:
        print(f"An error occurred: {e}")
        sys.exit(1)
