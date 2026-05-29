import requests

BASE = 'http://localhost:8001/api'
resp = requests.post(f'{BASE}/auth/login', json={'username': 'admin', 'password': 'admin123'})
token = resp.json()['access_token']
h = {'Authorization': f'Bearer {token}'}

# List approvals
resp = requests.get(f'{BASE}/hr/approvals', headers=h, params={'limit': 5})
items = resp.json()['items']
if items:
    a = items[0]
    aid = a['id']
    current = a['status']
    new_status = 'rejected' if current == 'approved' else 'approved'
    print(f'Approval {aid[:8]}... status={current} -> {new_status}')
    resp = requests.put(f'{BASE}/hr/approvals/{aid}', headers=h, json={'status': new_status, 'comment': 'modification test'})
    print(f'Result: {resp.status_code} status={resp.json().get("status")}')
else:
    print('No approvals - creating test...')
    resp = requests.post(f'{BASE}/hr/approvals', headers=h, json={'approval_type': 'leave', 'content': 'test'})
    aid = resp.json()['id']
    # Approve
    resp = requests.put(f'{BASE}/hr/approvals/{aid}', headers=h, json={'status': 'approved', 'comment': 'pass'})
    print(f'Approve: status={resp.json().get("status")}')
    # Change to rejected
    resp = requests.put(f'{BASE}/hr/approvals/{aid}', headers=h, json={'status': 'rejected', 'comment': 'changed'})
    print(f'Change to rejected: status={resp.json().get("status")}')
