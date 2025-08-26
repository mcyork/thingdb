#!/usr/bin/env python3
import serial
import time
import sys

def test_serial_connection(port='/dev/cu.usbserial-1420', baudrate=115200):
    print(f"Testing serial connection on {port} at {baudrate} baud")
    print("=" * 50)
    
    try:
        # Open serial port
        ser = serial.Serial(port, baudrate, timeout=1)
        print(f"✓ Serial port opened successfully")
        print(f"  Settings: {ser.baudrate} baud, {ser.bytesize} bits, {ser.parity} parity, {ser.stopbits} stop")
        
        # Clear any existing data
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
        print("\nWaiting for data from Pi (press Enter on Pi if you see a login prompt)...")
        print("Press Ctrl+C to stop\n")
        
        # Send a carriage return to trigger login prompt
        ser.write(b'\r\n')
        
        empty_reads = 0
        while True:
            # Check for incoming data
            if ser.in_waiting > 0:
                data = ser.read(ser.in_waiting)
                print(f"Received ({len(data)} bytes): {data}")
                print(f"As text: {data.decode('utf-8', errors='replace')}")
                empty_reads = 0
            else:
                empty_reads += 1
                if empty_reads == 3:
                    print("\nNo data received. Sending Enter key to trigger response...")
                    ser.write(b'\r\n')
                    empty_reads = 0
            
            time.sleep(0.5)
            
    except serial.SerialException as e:
        print(f"✗ Serial error: {e}")
        return False
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print("Serial port closed")
    
    return True

def test_loopback(port='/dev/cu.usbserial-1420', baudrate=115200):
    """Test if TX and RX are connected (loopback test)"""
    print("\n" + "=" * 50)
    print("LOOPBACK TEST (to check if TX/RX are shorted)")
    print("=" * 50)
    
    try:
        ser = serial.Serial(port, baudrate, timeout=0.5)
        ser.reset_input_buffer()
        
        test_string = b"LOOPBACK_TEST_123\r\n"
        ser.write(test_string)
        time.sleep(0.1)
        
        received = ser.read(100)
        
        if received == test_string:
            print("✓ Loopback detected! TX and RX are connected together")
            print("  This means either:")
            print("  1. TX/RX are shorted (for testing)")
            print("  2. TX/RX might be reversed at the Pi end")
            return True
        elif received:
            print(f"Received different data: {received}")
            print("  TX/RX are connected to something that's echoing different data")
            return False
        else:
            print("✓ No loopback detected (good - TX/RX are not shorted)")
            return False
            
    except Exception as e:
        print(f"Loopback test error: {e}")
        return False
    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()

if __name__ == "__main__":
    # First test for loopback
    has_loopback = test_loopback()
    
    if has_loopback:
        print("\n⚠️  WARNING: Loopback detected!")
        print("If you're trying to connect to the Pi, check your wiring:")
        print("  - Make sure TX from USB adapter goes to RX on Pi")
        print("  - Make sure RX from USB adapter goes to TX on Pi")
        print("  - Make sure GND is connected between USB adapter and Pi")
    
    # Then test normal connection
    test_serial_connection()