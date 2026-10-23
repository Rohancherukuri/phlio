from tests.test_messaging import login

async def test_inbox_folders_unread_and_owner_isolation(client,auth_headers):
    recipient=await login(client,'neha')
    outsider=await login(client,'artbykiara')
    sent=await client.post('/api/v1/messaging/peers/neha/messages',headers=auth_headers,json={'text':'Inbox test'})
    assert sent.status_code==201
    rows=(await client.get('/api/v1/messaging/conversations',headers=recipient)).json()
    assert rows[0]['folder']=='requests'
    assert rows[0]['unread_count']==1
    endpoint='/api/v1/messaging/peers/arjun/inbox'
    assert (await client.patch(endpoint,headers=outsider,json={'folder':'general'})).status_code==404
    assert (await client.patch(endpoint,headers=recipient,json={'folder':'general','read':True})).status_code==200
    rows=(await client.get('/api/v1/messaging/conversations',headers=recipient)).json()
    assert rows[0]['folder']=='general' and rows[0]['unread_count']==0
    other=(await client.get('/api/v1/messaging/conversations',headers=auth_headers)).json()
    assert other[0]['folder']=='primary'
    assert (await client.patch(endpoint,headers=recipient,json={'folder':'invalid'})).status_code==422
    await client.post('/api/v1/messaging/peers/neha/messages',headers=auth_headers,json={'text':'New message'})
    rows=(await client.get('/api/v1/messaging/conversations',headers=recipient)).json()
    assert rows[0]['unread_count']==1 and rows[0]['folder']=='general'
    await client.put('/api/v1/social/blocks/usr_arjun',headers=recipient)
    assert (await client.get('/api/v1/messaging/conversations',headers=recipient)).json()==[]
