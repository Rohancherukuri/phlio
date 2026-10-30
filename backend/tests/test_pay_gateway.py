import hashlib
import hmac
import uuid
import pytest
from fastapi import HTTPException
from app.api.v1 import pay_gateway as gateway
from tests.test_messaging import login

CSV = b'date,description,amount,direction,method,account,reference\n2026-10-01,Cafe,120.50,debit,debit_card,Card 1234,ref1\n2026-10-02,Salary,40000,credit,bank,Bank 4567,ref2\n'

@pytest.mark.asyncio
async def test_statement_preview_import_private_and_deduplicated(client,auth_headers):
    preview=await client.post('/api/v1/pay/gateway/statements/preview',headers=auth_headers,files={'file':('statement.csv',CSV,'text/csv')})
    assert preview.status_code==200,preview.text
    token=preview.json()['token']
    assert preview.json()['items'][0]['amount_minor_units']==12050
    other=await login(client,'neha')
    assert (await client.post('/api/v1/pay/gateway/statements/import',headers=other,json={'token':token})).status_code==410
    result=await client.post('/api/v1/pay/gateway/statements/import',headers=auth_headers,json={'token':token})
    assert result.json()['imported']==2
    assert (await client.post('/api/v1/pay/gateway/statements/import',headers=auth_headers,json={'token':token})).json()['duplicates']==2
    assert (await client.get('/api/v1/pay/gateway/history',headers=other)).json()['statements']==[]
    history=(await client.get('/api/v1/pay/gateway/history',headers=auth_headers)).json()
    id=history['statements'][0]['id']
    await client.delete('/api/v1/pay/gateway/statements/'+id,headers=other)
    assert len((await client.get('/api/v1/pay/gateway/history',headers=auth_headers)).json()['statements'])==2

@pytest.mark.parametrize('value',['NaN','-12','12.345','Infinity'])
def test_bad_statement_money(value):
    with pytest.raises(HTTPException): gateway.parse_statement(CSV.replace(b'120.50',value.encode()))

@pytest.mark.asyncio
async def test_order_idempotency_signature_capture_and_ownership(client,auth_headers,settings,monkeypatch):
    settings.razorpay_key_id='rzp_test_example'
    settings.razorpay_key_secret='test-secret'
    calls=[]
    status='authorized'
    async def provider(c,method,path,payload=None):
        calls.append((method,path))
        if method=='POST': return {'id':'order_abc'}
        return {'items':[{'id':'pay_abc','order_id':'order_abc','currency':'INR','amount':100,'status':status,'method':'upi'}]}
    monkeypatch.setattr(gateway,'provider',provider)
    body={'amount_minor_units':100,'request_id':str(uuid.uuid4())}
    first=await client.post('/api/v1/pay/gateway/orders',headers=auth_headers,json=body)
    assert first.status_code==200,first.text
    item=first.json()
    assert (await client.post('/api/v1/pay/gateway/orders',headers=auth_headers,json=body)).json()==item
    assert len(calls)==1
    endpoint='/api/v1/pay/gateway/orders/'+item['id']
    other=await login(client,'neha')
    assert (await client.get(endpoint,headers=other)).status_code==404
    wrong={'payment_id':'pay_abc','signature':'0'*64}
    assert (await client.post(endpoint+'/verify',headers=auth_headers,json=wrong)).status_code==422
    signature=hmac.new(b'test-secret',b'order_abc|pay_abc',hashlib.sha256).hexdigest()
    valid={'payment_id':'pay_abc','signature':signature}
    assert (await client.post(endpoint+'/verify',headers=auth_headers,json=valid)).json()['status']=='processing'
    status='captured'
    assert (await client.get(endpoint,headers=auth_headers)).json()['status']=='success'
    status='failed'
    assert (await client.get(endpoint,headers=auth_headers)).json()['status']=='success'

@pytest.mark.asyncio
async def test_live_keys_disabled(client,auth_headers,settings):
    settings.razorpay_key_id='rzp_live_example'
    settings.razorpay_key_secret='secret'
    assert (await client.get('/api/v1/pay/gateway/config',headers=auth_headers)).json()['configured'] is False
