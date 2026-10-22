#!/usr/bin/env python3
"""One-time Beszel local agent enrollment (PocketBase API, stdlib only).
Reads credentials from environment. Prints ONLY the public SSH key to stdout.
"""
import json, os, sys, urllib.request, urllib.error
url = 'http://127.0.0.1:8090'
email = os.environ['AODIEUVPS_BESZEL_USER']
password = os.environ['AODIEUVPS_BESZEL_PASSWORD']

def request(path, data=None, token=None):
    headers = {'Content-Type': 'application/json'}
    if token: headers['Authorization'] = token
    req = urllib.request.Request(url + path, data=(json.dumps(data).encode() if data is not None else None), headers=headers, method=('POST' if data is not None else 'GET'))
    with urllib.request.urlopen(req, timeout=15) as res:
        return json.load(res)

def main():
    auth = request('/api/collections/users/auth-with-password', {'identity': email, 'password': password})
    token = auth['token']
    uid = auth['record']['id']
    key = request('/api/beszel/getkey', token=token)['key']
    if not key.startswith('ssh-ed25519 '): raise RuntimeError('Unexpected agent SSH public key')
    listing = request('/api/collections/systems/records?perPage=100', token=token)
    if not any(r.get('name') == 'AodieuVPS Local Server' and r.get('host') == '127.0.0.1' for r in listing.get('items', [])):
        request('/api/collections/systems/records', {'name': 'AodieuVPS Local Server', 'host':'127.0.0.1', 'port':'45876','users':[uid]}, token)
    print(key)

if __name__=='__main__':
    try: main()
    except (KeyError, RuntimeError, urllib.error.URLError, ValueError) as err:
        print('Beszel enrollment failed: '+str(err),file=sys.stderr)
        sys.exit(1)
