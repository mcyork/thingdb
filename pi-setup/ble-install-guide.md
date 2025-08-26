Manually Install Bluetooth Code on RPi
June 8, 2024

Current Version: 2.0 - March 10, 2025
I continue to make changes often based on early adopters comments and experiences. Check here often to see if I have posted a new version.

To check installed current version date on your Raspberry Pi, check the log file in terminal:

journalctl --unit=btwifiset.service -n 100 --no-pager
And look for the line that starts with: ******* Starting BTwifiSet - version date.

About
Note: These instructions are accurate but incomplete as certain new features have been added to the automated installation, especially for Android users. At this time, and until this notice is removed, it is recommended to use the automated method.

Step by Step (manually) install on your Raspberry Pi of a bluetooth BLE Server written in Python . BLE advertises a custom service that communicates with the IOS app to remotely set the wifi on a headless raspberry pi.

Requirements
Python3: version 3.7 or later must be installed on the Raspberry Pi.

General
All commands below are to be typed at the prompt in a terminal window on the Raspberry Pi.

If you are on a headless RPi - it is assumed you have SSH into the RPi from your computer in a terminal window.
If you are using the desktop version of the Pi OS - please open a terminal session.
Copy/paste or type the commands in the code blocks into your terminal on the RPi - one line at the time - and run them (hit return on keyboard)

Step 1 - get the Raspberry Pi ready
Check your Raspberry pi OS release (Look for VERSION-ID=):
sudo cat /etc/os-release
The software has been tested on Raspbian 10 & 11 & 12. Consider upgrading the RPI to a newer release if your release is below 10. (also tested on latest version of Armbian and Ubuntu with Network Manager).

Update the Raspberry Pi:
sudo apt-get update
sudo apt-get full-upgrade
sudo reboot
Check your version of python3 on the Rpi.
If you have the latest version of the RPi OS - you already have the correct version of Python. If you have an older version, or have installed different versions on you pi, use this command to check the version of python3 on your RPi:

python3 --version
If the version printed is less then Python 3.7, you must install a newer version of Python before continuing. Here is one way to install the newest python.

Step 2: download the python files
These instructions create the directory btwifiset in usr/local/ and copies the necessary files into it. You can pick a different directory, but in this case modify the "ExecStart" line in the btwifiset.service file (see Step 6) to use the location where you install the btwifiset.py file.

Navigate to /usr/local directory, create a directory named btwifiset, then navigate there:
cd /usr/local
sudo mkdir btwifiset
cd btwifiset
Download the python files into this directory. There are 3 files: btwifiset.py, btpassword.py, and passwordREADME.txt. Use these command: (use capital letter O in the option)
curl -O https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btwifiset.py  
curl -O https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/btpassword.py 
curl -O https://raw.githubusercontent.com/nksan/Rpi-SetWiFi-viaBluetooth/main/passwordREADME.txt 
Create the password file and password: Version 2 now supports Encryption and Lock The Pi. For this to work, a password needs to be created. To use the current hostname of your Raspberry Pi as the default password (see why), do:
hostname > /usr/local/btwifiset/crypto
or to make your own password (replace thw word password with your own selection):

echo password > /usr/local/btwifiset/crypto
Important: the file containing the password is named crypto (with no extension). Do not change this name as it is hard coded in the bluetooth Python code that looks for the password when connecting to the iPhone app. note: You can use view and/or change the password at anytime after the crypto file is created with this command

 sudo /usr/local/btwifiset/btpassword.py
Step 3 - Check for/Install Python modules:
The BLE server python script requires the use of three python modules not already included with python: dbus and GLib and Cryptography.

Glib is installed with apt. Dbus and cryptography may be installed with apt or pip3 - depending on how new your OS is.

GLib
Prepare for the installation of libpythonX.Y-dev. You need the first two digit of the python version . Run this command - it will return a python version in the format X.Y.Z (for example 3.9.2).
python3 --version
Write down the first number (X) and the second number (Y) of the python version that is returned, and replace X.Y in the command line below with these values. - keep everything else the same.

sudo apt install python3-gi libdbus-glib-1-dev libpythonX.Y-dev
Replace X.Y above by the first two digit of python version. For example: if your version showed something like 3.9.2, run libpython3.9-dev above.

Dbus
1.Under Step 1 you checked the Raspberry Pi OS release. If you have version 11 or greater for your Raspberry Pi OS (or a new-ish version of Ubuntu) - use apt install:

sudo apt install python3-dbus
If the above did not work or if you have version 10 (buster) or less for Raspberry Pi OS, then install the Python module dbus using pip
Check if you have pip3 installed:

sudo python3 -m pip --version
If you get: module does not exists error, then install pip:

sudo apt install python3-pip
And finally install dbus:

sudo python3 -m pip install dbus-python
Sudo is important. if you install without sudo the package will be installed in your user .local/lib and the systemd service we create later will not find it.

Cryptography
Under Step 1 you checked the Raspberry Pi OS release. If you have version 11 or greater for your Raspberry Pi OS (or a new-ish version of Ubuntu) - use apt install:
sudo apt install python3-cryptography
If the above has an error, or you have Raspberry Pi OS version 10 or less, you must use pip3:
i) First check/install pip3 (see dbus heading - bullet 2 above for instructions).
ii) Next check if you have cryptography already installed:

sudo pip3 show cryptography
If the version is 3.3.2 or above - no need to install. Move to test your modules

If show cryptography responds with a version is less than 3.3.2, upgrade cryptography like this:

sudo pip3 install --upgrade cryptography
If show cryptography responds with package not found - just install it:

sudo pip3 install cryptography
test your modules installation with python
Run the following code to verify that python module were installed correctly. If you get no response, the module is installed correctly.
python3 -c 'import dbus'
python3 -c 'from gi.repository import GLib'
python3 -c 'import cryptography'
Step 4 - Modify the BlueZ service (and symlinks):
The system service for bluetooth needs to be modified to run BLE, and to stop it from constantly requesting the battery status of the iphone/ipad that will connect to it (default behavior).

Copy the existing bluetooth.service file to /etc/systemd/system and navigate there:
sudo cp /lib/systemd/system/bluetooth.service /etc/systemd/system
cd /etc/systemd/system
Open the copied .service file in your preferred editor - here we use nano:
sudo nano bluetooth.service
Find the line that starts with ExecStart and add the following at the end of the line - on the same line, leaving a space before the two hyphens:
  --experimental -P battery
Save the file (for nano: Ctrl o + return) and exit (for nano: Ctrl x)
Update the symlink bluetooth.target.wants to point to our versions of bluetooth.service
the line should read something like:
ExecStart=/usr/lib/bluetooth/bluetoothd --experimental -P battery

sudo rm -f /etc/systemd/system/bluetooth.target.wants/bluetooth.service
sudo ln -s /etc/systemd/system/bluetooth.service /etc/systemd/system/bluetooth.target.wants/bluetooth.service
Similarly update symlink for bluez service:
sudo rm -f /etc/systemd/system/dbus-org.bluez.service
sudo ln -s /etc/systemd/system/bluetooth.service /etc/systemd/system/dbus-org.bluez.service
Reboot the Raspberry Pi for changes to take effect:
sudo reboot
step 5 - Verify that wpa_supplicant.conf exists
This step is not necessary if Network Manager is installed and running on your OS (typically Raspberry OS Bookworm (version 12) and Ubuntu). To test if you have Network manager installed run:

nmcli
Note: nmcli may exists on your system - but if you get "Error: NetworkManager is not running." then you must carry on with the rest of step 5.

If your pi has ever connected to wifi, it should have a file named wpa_supplicant.conf. If not, we need to create it. Run this command to check if you have this file on your Raspberry Pi:

sudo cat /etc/wpa_supplicant/wpa_supplicant.conf
If you get a message with : No such file or directory, The file does not exists and you need to create it (see below: If the file does not exists).

If the file exists:
At this point, you are seeing the content of the file in the terminal window. Please check that both of the following lines appear at the top of the file (order is not important) - XX is a country code such as US, GB, CA etc.

country=XX     
update_config=1
If either (or both) of these lines are missing - open the file in an editor and add the missing lines below the first line of the file. To edit the file:

sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
Then add the missing lines from above to the file. For country code - make sure you use your own country code

If the file does exists:
Create the file and open it in an editor:

sudo touch /etc/wpa_supplicant/wpa_supplicant.conf
sudo nano /etc/wpa_supplicant/wpa_supplicant.conf
Then copy/paste the following at the top of the file - making sure to replace the country code XX with your correct country code

ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
country=US
update_config=1

Save the file and exit the editor.

Step 6 - Create the btwifiset.service file
This creates a Systemd service file that will automatically starts btwifiset.py when your RPi boots up. This is assumed to be the desired behavior for a RPi in headless mode. (If your RPi is connected to a terminal and keyboard - you don't need to set the wifi using an iphone app and bluetooth...)

These instructions assume that you installed (step 2) the btwifiset.py file in /usr/local/btwifiset. If you used a different location, replace /usr/local/btwifiset/ with the full path location to where you installed it.

These instructions also assume that python3 resides in /usr/bin/ - which is typical of the python that comes with RPi OS. You can test this by running:

/usr/bin/python3 --version
which should return the version of python. If this fails and python3 is not in /usr/bin/ run this:

command -v python3
this will return the location of python3 - Substitute this location to the /usr/bin/python3 on the ExecStart line below.

Command Line switches: btwifiset accepts the following command line switches - which you can modify on the ExecStart line below. The installation shown here uses the --syslog switch to store log entries in syslog. This can be modified as below:

--syslog (Logs messages to syslog).
--console (Logs messages to console - this should not be used in the service file).
--logfile /path/to/filename.log (Logs messages to specified file using absolute path).
--timeout x (where x is the number of minutes btwifiset will run after booting up, before shuting down).

Timeout defaults to 15 minutes if --timeout x switch is not included. The timeout is the number of minutes that btwifiset will run after booting up if it does not receives any command from the IOS app (timeout resets to 15 min each time a command is received). The idea behind timeout is that a headless RPi that requires to have its wifi set-up will do this upon boot - after which the set wifi via bluetooth function is not needed, since it is then possible to ssh into the RPi using the wifi. Since other bluetooth programs may be running on the pi - it is prudent to shutdown btwifiset if it is not used.

Now, Create the btwifiset.service file and open it in an editor:
sudo  touch /etc/systemd/system/btwifiset.service
sudo nano /etc/systemd/system/btwifiset.service
Copy the below and insert in the editor: (this uses the --syslog option for logging)
[Unit]
Description=btwifiset Wi-Fi Configuration over Bluetooth
After= bluetooth.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/btwifiset/btwifiset.py --syslog

[Install]
WantedBy=multi-user.target
3
Save the file and exit the editor.

Run the following commands:

sudo systemctl daemon-reload
sudo systemctl enable btwifiset
Now reboot the RPi:
sudo reboot
At this point, the bluetooth BLE service is running automatically upon boot of the RPi.
you can check it's status with:
systemctl status btwifiset.service
If you want to stop it :
sudo systemctl stop btwifiset.service</span>
If you want to start it again :
sudo systemctl restart btwifiset.service</span>
Remember, unless you modified the timeout using the --timeout x switch, btwifiset will run for 15 minutes and then shut down unless you connect to it with the companion IOS app.

The BTBerryWifi App for iOS is on the (Apple App Store), and for Android is on the Google Play Store.
You can also find it by typing: BtBerryWifi , in your store search bar.

Checking the log if things are not working
After reboot, to check if the btwifiset service has started and is running:
systemctl status btwifiset
To check the log - to track down a possible fault:
Look for a line that says active

journalctl --unit=btwifiset.service -n 100 --no-pager
= = = = End of manual install instructions. = = = =