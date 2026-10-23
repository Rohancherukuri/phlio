import pytest

@pytest.mark.asyncio
async def test_poll_publish_vote_and_validation(client,auth_headers):
    payload={'text':'Which one?', 'poll':{'choices':[{'text':'First'},{'text':'Second'}],'minutes':1440}}
    created=await client.post('/api/v1/social/posts',json=payload,headers=auth_headers)
    assert created.status_code==201,created.text
    path='/api/v1/social/posts/'+created.json()['id']+'/poll'
    poll=await client.get(path,headers=auth_headers)
    assert poll.json()['total']==0
    assert len(poll.json()['choices'])==2
    for choice in [0,0,1]:
        voted=await client.put(path+'/vote',json={'choice':choice},headers=auth_headers)
        assert voted.status_code==200,voted.text
        assert voted.json()['total']==1
        assert voted.json()['selected']==choice
    assert voted.json()['counts']==[0,1]
    bad=await client.put(path+'/vote',json={'choice':3},headers=auth_headers)
    assert bad.status_code==422
    payload['poll']['choices'][1]['text']=' First '
    bad=await client.post('/api/v1/social/posts',json=payload,headers=auth_headers)
    assert bad.status_code==422
    assert (await client.put(path+'/vote',json={'choice':0})).status_code==401
