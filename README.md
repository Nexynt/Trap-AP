# Trap-AP

A Python-based Evil Twin tool that creates a fake Wi-Fi access point (AP) to mimic a nearby legitimate SSID. It automatically redirects connected clients to a captive portal login page to capture passwords or any user-entered credentials.

## Prerequisites

Before running the script, make sure you have the required packages installed on your Kali Linux system:

```bash
sudo apt update
sudo apt install -y aircrack-ng hostapd dnsmasq psmisc



⚠️ Important Note: Ensure that your system's date and time are accurately set. Incorrect time settings can cause issues during the execution of the tool.

Hardware Requirements
To run this tool, you need a Wi-Fi dongle (USB adapter) that supports Access Point (AP) mode.

Tested Adapter: TP-LINK TL-WN8200ND
Connection: Plug the dongle into your system via USB. If you are using a virtual machine (like VMware), ensure the dongle is properly connected to the virtual machine and recognized by Kali Linux.
Installation and Usage
Follow these steps to run the tool:

Clone the repository:
Clone the tool into your Kali Linux system using the following command:
bash

Line Wrapping

Collapse
Copy
1
git clone https://github.com/Nexynt/Trap-AP.git
Enter the directory:
Navigate into the tool's directory:
bash

Line Wrapping

Collapse
Copy
1
cd Trap-AP
Run the script:
Execute the main script with sudo privileges:
bash

Line Wrapping

Collapse
Copy
1
sudo ./evil_twin_open.sh
Select your wireless interface:
The script will display a list of your network interfaces. Select your wireless interface (it's usually named wlan0 or similar).
If your wireless interface is not listed:
Unplug the Wi-Fi dongle and plug it back in. Make sure it is properly connected to your Kali VM (e.g., in VMware). Then, run the script again.
Select the target:
Wait for about 15-20 seconds for the script to scan for nearby Wi-Fi networks. Once the scan is complete, a list of SSIDs will be displayed. Select the network you want to mimic.
How It Works
After you select a target, the tool creates a fake access point with the exact same name (SSID) as the target network.
Any user who mistakenly connects to this fake Wi-Fi network will be automatically redirected to the index.html page you have provided.
If the user is tricked into entering their password in the login field and clicking the submit button, their password will be immediately displayed on your terminal.
Log File
All captured credentials are saved in a file named captured_credentials.log inside the project directory. You can review this file later to see the captured information.

⚠️ Warning & Disclaimer
Social Engineering: The success of this attack heavily depends on the target's awareness and the realism of your index.html page. Design the page to look as convincing as possible, like a legitimate router's login portal.
Authorized Use Only: This tool is intended for educational purposes and for testing on networks you own or have explicit, written permission to test. The developer is not responsible for any misuse or illegal activity conducted with this tool. Use it responsibly and ethically.
