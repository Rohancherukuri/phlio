from tests.test_messaging import login

async def test_giphy_references_and_private_recents(client, auth_headers):
    payload = {'giphy_id': 'abc123', 'kind': 'sticker'}
    assert (await client.post('/api/v1/messaging/giphy/recents', headers=auth_headers, json=payload)).status_code == 200
    assert (await client.post('/api/v1/messaging/giphy/recents', headers=auth_headers, json=payload)).status_code == 200
    rows = (await client.get('/api/v1/messaging/giphy/recents?kind=sticker', headers=auth_headers)).json()
    assert len(rows) == 1 and rows[0]['giphy_id'] == 'abc123'
    other = await login(client, 'neha')
    assert (await client.get('/api/v1/messaging/giphy/recents?kind=sticker', headers=other)).json() == []
    response = await client.post('/api/v1/messaging/peers/neha/messages', headers=auth_headers,
        json={'attachments':[{'name':'Test sticker','kind':'sticker','value':'giphy:sticker:abc123'}]})
    assert response.status_code == 201, response.text
    assert (await client.post('/api/v1/messaging/giphy/recents', headers=auth_headers,
        json={'giphy_id':'../../bad','kind':'sticker'})).status_code == 422
    assert (await client.post('/api/v1/messaging/peers/neha/messages', headers=auth_headers,
        json={'attachments':[{'name':'Test sticker','kind':'sticker','value':'giphy:gif:abc123'}]})).status_code == 422


async def test_giphy_config_requires_login_and_is_not_cached(client, auth_headers):
    assert (await client.get('/api/v1/messaging/giphy/config')).status_code == 401
    response = await client.get('/api/v1/messaging/giphy/config', headers=auth_headers)
    assert response.status_code == 200
    assert response.headers['cache-control'] == 'no-store'
    assert isinstance(response.json()['api_key'], str)
