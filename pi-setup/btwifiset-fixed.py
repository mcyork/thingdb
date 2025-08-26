#!/usr/bin/env python3
# Fixed version - only showing the patched sections

def changePassword(self, network, pw, hidden=False):
    """Fixed version with proper PSK quoting"""
    try:
        mLOG.log(f'changing Password for {network.ssid} to {pw}')
        psk = self.get_psk(network.ssid, pw)
        if len(psk) == 0:
            mLOG.log(f"Password {pw} has an illegal length: {len(psk)}")
            return False
        else:
            ssid_num = self.retrieve_network_numbers(network.ssid)
            if ssid_num >= 0:
                if psk == "psk=NONE":
                    # change network to open
                    out = subprocess.run(f'wpa_cli -i wlan0 set_network {ssid_num} key_mgmt {psk[4:]}',
                                       shell=True, capture_output=True, encoding='utf-8', text=True).stdout
                    mLOG.log('set key_mgmt to NONE', out)
                else:
                    # wpa_cli set_network 4 key_mgmt WPA-PSK
                    out = subprocess.run(f'wpa_cli -i wlan0 set_network {ssid_num} key_mgmt WPA-PSK',
                                       shell=True, capture_output=True, encoding='utf-8', text=True).stdout
                    mLOG.log('set key_mgmt to WPA_PSK', out)
                    # FIX: Properly quote the PSK value
                    out = subprocess.run(f'wpa_cli -i wlan0 set_network {ssid_num} psk "{psk[4:]}"',
                                       shell=True, capture_output=True, encoding='utf-8', text=True).stdout
                    mLOG.log('set psk', out)
                if hidden:
                    out = subprocess.run(f'wpa_cli -i wlan0 set_network {ssid_num} scan_ssid 1',
                                       shell=True, capture_output=True, encoding='utf-8', text=True).stdout
                    mLOG.log(f'set hidden network with scan_ssid=1: {out}')

                out = subprocess.run(f'wpa_cli -i wlan0 enable_network {ssid_num}',
                                   shell=True, capture_output=True, encoding='utf-8', text=True).stdout
                mLOG.log(f'enabling network {out}')
                return True
            else:
                mLOG.log(f'network number for {network.ssid} not set {ssid_num}')
                return False

    except Exception as e:
        mLOG.log(f'unknown error in changePassword: {e}')
        return False


def add_network(self, ssid, pw, hidden=False):
    """Fixed version with proper PSK quoting"""
    mLOG.log(f'adding network password:{pw}, ssid:{ssid}')
    if len(pw) == 0:
        psk = self.get_psk(ssid, 'NONE')  # forces open network
    else:
        psk = self.get_psk(ssid, pw)
    if len(psk) == 0:
        mLOG.log(f"Password {pw} has an illegal length: {len(pw)}")
        return None
    else:
        out = subprocess.run('wpa_cli -i wlan0 add_network',
                           shell=True, capture_output=True, encoding='utf-8', text=True).stdout
        network_num = out.rstrip()
        mLOG.log(f'add new network {network_num}')
        ssid_hex = ssid.encode('utf-8').hex()
        out = subprocess.run(f'wpa_cli -i wlan0 set_network {network_num} ssid {ssid_hex}',
                           shell=True, capture_output=True, encoding='utf-8', text=True).stdout
        mLOG.log(f'coded ssid: {ssid_hex} - setting network ssid {out}')
        if psk == "psk=NONE":
            out = subprocess.run(f'wpa_cli -i wlan0 set_network {network_num} key_mgmt {psk[4:]}',
                               shell=True, capture_output=True, encoding='utf-8', text=True).stdout
            mLOG.log(f'set network to Open {out}')
        else:
            # FIX: Properly quote the PSK value
            out = subprocess.run(f'wpa_cli -i wlan0 set_network {network_num} psk "{psk[4:]}"',
                               shell=True, capture_output=True, encoding='utf-8', text=True).stdout
            mLOG.log(f' set psk: {out}')
        if hidden:
            out = subprocess.run(f'wpa_cli -i wlan0 set_network {network_num} scan_ssid 1',
                               shell=True, capture_output=True, encoding='utf-8', text=True).stdout
            mLOG.log(f'set hidden network {ssid} scan_ssid=1: {out}')

        out = subprocess.run(f'wpa_cli -i wlan0 enable_network {network_num}',
                           shell=True, capture_output=True, encoding='utf-8', text=True).stdout
        mLOG.log(f'enabling network {out}')

        new_network = Wpa_Network(ssid, psk != 'psk=NONE', False, int(network_num))
        mLOG.log(f'created temporary wpa_network {new_network.info()}')

        return new_network