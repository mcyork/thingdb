#!/usr/bin/env python3
import serial
import time

port = '/dev/cu.usbserial-1420'
baudrate = 115200

print(f"Quick serial test on {port} at {baudrate} baud")
print("=" * 50)

try:
    # Open serial port
    ser = serial.Serial(port, baudrate, timeout=0.5)
    print("✓ Port opened successfully")
    
    # Test 1: Check for loopback (TX connected to RX)
    print("\n1. LOOPBACK TEST:")
    ser.reset_input_buffer()
    test_msg = b"TEST123\r\n"
    ser.write(test_msg)
    time.sleep(0.1)
    received = ser.read(100)
    
    if received == test_msg:
        print("  ⚠️  LOOPBACK DETECTED - TX and RX are connected together!")
        print("  This could mean TX/RX are reversed at the Pi")
    elif received:
        print(f"  Received: {received}")
        print(f"  As text: {received.decode('utf-8', errors='replace')}")
    else:
        print("  ✓ No loopback (good)")
    
    # Test 2: Send Enter and check for response
    print("\n2. SENDING ENTER KEY:")
    ser.reset_input_buffer()
    ser.write(b'\r\n')
    time.sleep(0.5)
    response = ser.read(1000)
    
    if response:
        print(f"  Received {len(response)} bytes")
        text = response.decode('utf-8', errors='replace')
        print(f"  Response: {text[:200]}")
        if 'login:' in text.lower() or 'raspberry' in text.lower():
            print("  ✓ Pi console detected!")
    else:
        print("  No response")
    
    # Test 3: Check DTR/RTS control lines
    print("\n3. CONTROL LINES:")
    print(f"  DTR: {ser.dtr}")
    print(f"  RTS: {ser.rts}")
    
    ser.close()
    
except serial.SerialException as e:
    print(f"✗ Error: {e}")
    print("\nTroubleshooting:")
    print("1. Check that nothing else is using the port")
    print("2. Verify USB-serial adapter is properly connected")
    print("3. Check permissions (may need sudo on some systems)")
except Exception as e:
    print(f"Unexpected error: {e}")