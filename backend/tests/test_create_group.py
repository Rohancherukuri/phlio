from tests.test_messaging import login

async def test_standalone_group_membership_and_validation(client, auth_headers):
    registered = await client.post('/api/v1/auth/register', json={
        'full_name': 'Outside User', 'username': 'outsideuser',
        'email': 'outside@example.com', 'password': 'correct-horse-battery'})
    outsider = {'Authorization': 'Bearer ' + registered.json()['tokens']['access_token']}
    response = await client.post('/api/v1/messaging/groups', headers=auth_headers,
        json={'name': 'Weekend plans', 'members': ['neha', 'artbykiara']})
    assert response.status_code == 201, response.text
    gid = response.json()['id']
    assert any(g['id'] == gid for g in (await client.get('/api/v1/messaging/groups', headers=auth_headers)).json())
    assert (await client.post(f'/api/v1/messaging/groups/{gid}/messages', headers=auth_headers, json={'text': 'Hello everyone'})).status_code == 201
    assert (await client.get(f'/api/v1/messaging/groups/{gid}/messages', headers=outsider)).status_code == 404
    assert (await client.post('/api/v1/messaging/groups', headers=auth_headers,
        json={'name': 'Duplicates', 'members': ['neha', 'neha']})).status_code == 422
    assert (await client.post('/api/v1/messaging/groups', headers=auth_headers,
        json={'name': ' ', 'members': ['neha', 'artbykiara']})).status_code == 422
