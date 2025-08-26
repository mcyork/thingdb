import serial
import time

SERIAL_PORT = '/dev/tty.usbserial-1420'
BAUD_RATE = 9600

try:
    ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=1)
    print("Successfully opened serial port {}".format(SERIAL_PORT))

    test_string = b"Hello\r\n"
    ser.write(test_string)
    print("Sent: {}".format(test_string.decode().strip()))

    time.sleep(0.1) # Give a very short moment for echo
    response = ser.read_all().decode().strip()
    if response:
        print("Received echo:")
        print(response)
    else:
        print("No echo received.")

except serial.SerialException as e:
    print("Error opening or communicating with serial port: {}".format(e))
except Exception as e:
    print("An unexpected error occurred: {}".format(e))
finally:
    if 'ser' in locals() and ser.is_open:
        ser.close()
        print("Serial port closed.")