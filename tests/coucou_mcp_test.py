#!/usr/bin/env python3
"""coucou-mcp, the script Coucou installs (App/CoucouMCP.swift), spoken to over stdio like an agent
would, against a fake Coucou on a temporary socket."""
import json, os, re, socket, subprocess, sys, tempfile, threading

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
source = open(os.path.join(ROOT, 'NotchBuddy/Sources/App/CoucouMCP.swift')).read()
script = re.search(r'serverScript = #"""\n(.*?)\n"""#', source, re.S).group(1)

tmp = tempfile.mkdtemp()
sock_path = os.path.join(tmp, 's.sock')
script_path = os.path.join(tmp, 'coucou-mcp')
open(script_path, 'w').write(script.replace('__SOCKET__', sock_path).replace('__VERSION__', '9.9'))
os.chmod(script_path, 0o755)

failures = 0
def check(label, ok):
    global failures
    print(('  ✓ ' if ok else '  ✗ ') + label)
    failures += 0 if ok else 1

received = []
reply = {'ok': True, 'result': [{'id': 'A1', 'title': 'Interview prep'}]}
def fake_coucou(server):
    while True:
        try:
            conn, _ = server.accept()
        except OSError:
            return
        data = b''
        while not data.endswith(b'\n'):
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        received.append(json.loads(data))
        conn.sendall((json.dumps(reply) + '\n').encode())
        conn.close()

def session(messages):
    """Runs the server on these JSON-RPC messages; its replies by id."""
    proc = subprocess.run([script_path], input='\n'.join(json.dumps(m) for m in messages) + '\n',
                          capture_output=True, text=True, timeout=20)
    out = [json.loads(l) for l in proc.stdout.splitlines() if l.strip()]
    return {m.get('id'): m for m in out}, out

def call(i, name, args=None):
    return {'jsonrpc': '2.0', 'id': i, 'method': 'tools/call', 'params': {'name': name, 'arguments': args or {}}}

print('without Coucou running')
replies, _ = session([call(1, 'list_recordings')])
check('a tool error, not a crash', replies[1]['result'].get('isError') is True
      and 'not running' in replies[1]['result']['content'][0]['text'])

server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(8)
threading.Thread(target=fake_coucou, args=(server,), daemon=True).start()

print('handshake')
replies, out = session([
    {'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
     'params': {'protocolVersion': '2025-03-26', 'capabilities': {}, 'clientInfo': {'name': 't', 'version': '1'}}},
    {'jsonrpc': '2.0', 'method': 'notifications/initialized'},
    {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'},
    {'jsonrpc': '2.0', 'id': 3, 'method': 'ping'},
    {'jsonrpc': '2.0', 'id': 4, 'method': 'resources/list'},
])
init = replies[1]['result']
check('echoes the client protocol version', init['protocolVersion'] == '2025-03-26')
check('offers tools', 'tools' in init['capabilities'] and init['serverInfo']['version'] == '9.9')
check('notification gets no reply', len(out) == 4)
names = [t['name'] for t in replies[2]['result']['tools']]
check('four tools', names == ['list_recordings', 'get_summary', 'get_transcript', 'get_todos'])
check('all read-only', all(t['annotations']['readOnlyHint'] for t in replies[2]['result']['tools']))
check('id required where needed', [t['inputSchema'].get('required') for t in replies[2]['result']['tools']]
      == [None, ['id'], ['id'], None])
check('ping', replies[3]['result'] == {})
check('unknown method → -32601', replies[4]['error']['code'] == -32601)

print('tool calls')
replies, _ = session([call(5, 'list_recordings', {'query': 'resume', 'limit': 5})])
check('asks Coucou as a query', received[-1] == {'coucou_kind': 'query', 'tool': 'list_recordings',
                                                  'arguments': {'query': 'resume', 'limit': 5}})
check('result as JSON text', json.loads(replies[5]['result']['content'][0]['text']) == reply['result'])
check('not an error', not replies[5]['result'].get('isError'))
reply = {'ok': False, 'error': "Coucou's MCP server is off"}
replies, _ = session([call(6, 'get_summary', {'id': 'A1'})])
check("Coucou's refusal reaches the agent", replies[6]['result']['isError'] is True
      and 'off' in replies[6]['result']['content'][0]['text'])
replies, _ = session([call(7, 'delete_everything')])
check('unknown tool → -32602, nothing asked', replies[7]['error']['code'] == -32602 and len(received) == 2)
replies, out = session([call(8, 'get_todos')])  # still answers after an error
check('keeps going after errors', 8 in replies)

server.close()
if failures:
    print('%d failure(s)' % failures)
    sys.exit(1)
print('All coucou-mcp tests passed.')
