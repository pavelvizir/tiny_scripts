#!/usr/bin/env python
''' '''

from flask import Flask
import dns.reversename
import dns.resolver
import os
import re


app = Flask(__name__)


@app.route('/')
def return_ips():
    ip_list = os.popen('arp-scan --localnet --interface=br0 | awk \'{ print $1 }\' | grep -e \'[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\' | sort -V').read()
    return ip_list


@app.route('/full')
def return_ips_full():
    ip_list_full = os.popen('arp-scan --localnet --interface=br0 | sort -V').read()
    result = []
    for line in ip_list_full.split('\n'):
        try:
            found = re.search(r'^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s*((?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2}))([\s\t]*\((?:[0-9A-Fa-f]{2}[:-]){5}(?:[0-9A-Fa-f]{2})\))?\s*(.*)', line)
            if found.group(3):
                mac = '{}{}'.format(found.group(2), found.group(3))
            else:
                mac = found.group(2)
            
            ip = found.group(1)
            vendor = found.group(4)
            try:
                x = dns.reversename.from_address(ip)
                name = str(dns.resolver.query(x,"PTR")[0])
                result.append('{:14} {:41} {:37} {:50}'.format(ip, name, mac, vendor))
            except dns.resolver.NXDOMAIN:
                result.append('{:56} {:37} {:50}'.format(ip, mac, vendor))
            
        except AttributeError:
            pass

    return '<xmp>{}</xmp>'.format('\n'.join(result))


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9999)
