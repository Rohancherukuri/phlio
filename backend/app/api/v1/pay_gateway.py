"""Sandbox-only merchant checkout and private CSV statement ledger."""
import asyncio
import csv
import hashlib
import hmac
import io
import json
import sqlite3
import uuid
from datetime import date, datetime, timezone
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Literal

import httpx
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File
from pydantic import BaseModel, Field
from app.api.deps import get_container, get_current_user

router = APIRouter(prefix='/pay/gateway', tags=['pay'])
_order_lock = asyncio.Lock()

def db(c):
    path = Path(c.settings.pay_gateway_database)
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    con.execute('CREATE TABLE IF NOT EXISTS entries (id TEXT PRIMARY KEY, owner TEXT NOT NULL, kind TEXT NOT NULL, data TEXT NOT NULL)')
    con.execute('CREATE INDEX IF NOT EXISTS entry_owner ON entries(owner,kind)')
    return con

def put(c, owner, kind, id, data):
    con = db(c)
    try:
        with con:
            con.execute('INSERT INTO entries VALUES (?,?,?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data WHERE entries.owner=excluded.owner',
                        (id, owner, kind, json.dumps(data)))
    finally: con.close()

def get(c, owner, id):
    con = db(c)
    try: row = con.execute('SELECT data FROM entries WHERE id=? AND owner=?', (id,owner)).fetchone()
    finally: con.close()
    if not row: raise HTTPException(404, 'Transaction not found.')
    return json.loads(row[0])

def rows(c, owner, kind):
    con = db(c)
    try: result = con.execute('SELECT data FROM entries WHERE owner=? AND kind=? ORDER BY rowid DESC LIMIT 1000', (owner,kind)).fetchall()
    finally: con.close()
    return [json.loads(r[0]) for r in result]

def configured(c):
    return c.settings.razorpay_key_id.startswith('rzp_test_') and bool(c.settings.razorpay_key_secret)

async def provider(c, method, path, payload=None):
    if not configured(c):
        raise HTTPException(503, 'Add Razorpay test credentials to enable sandbox checkout.')
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            res = await client.request(method, 'https://api.razorpay.com/v1/'+path,
                auth=(c.settings.razorpay_key_id,c.settings.razorpay_key_secret), json=payload)
        if res.status_code >= 400: raise HTTPException(502, 'Payment provider could not complete the request.')
        return res.json()
    except httpx.HTTPError as exc:
        raise HTTPException(503, 'Payment status unavailable. Check again before retrying.') from exc

@router.get('/config')
async def config(user=Depends(get_current_user), c=Depends(get_container)):
    return {'mode':'test', 'configured':configured(c), 'provider':'Razorpay'}

class OrderIn(BaseModel):
    amount_minor_units: int = Field(ge=100, le=10000000)
    request_id: uuid.UUID

@router.post('/orders')
async def order(body: OrderIn, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id, 'pay_order', 10)
    id = hashlib.sha256((user.id+str(body.request_id)).encode()).hexdigest()
    async with _order_lock:
        try:
            existing = get(c,user.id,id)
            if existing['amount'] != body.amount_minor_units: raise HTTPException(409,'Request amount changed.')
            if not existing.get('order_id'): raise HTTPException(409,'Order creation is unresolved. Do not repeat this request.')
            return {**existing, 'key_id': c.settings.razorpay_key_id}
        except HTTPException as exc:
            if exc.status_code != 404: raise
        if not configured(c): raise HTTPException(503,'Add Razorpay test credentials to enable sandbox checkout.')
        value = {'id':id, 'amount':body.amount_minor_units, 'currency':'INR', 'status':'processing',
                 'mode':'test', 'created_at':datetime.now(timezone.utc).isoformat()}
        con = db(c)
        try:
            with con:
                claimed = con.execute('INSERT OR IGNORE INTO entries VALUES (?,?,?,?)',
                    (id,user.id,'payment',json.dumps(value))).rowcount
        finally: con.close()
        if not claimed: raise HTTPException(409,'Order creation is already in progress.')
        # Never automatically retry POST: a timeout can happen after provider creation.
        result = await provider(c,'POST','orders', {'amount':body.amount_minor_units,'currency':'INR','receipt':id[:40]})
        value['order_id'] = result['id']
        put(c,user.id,'payment',id,value)
        return {**value,'key_id':c.settings.razorpay_key_id}

class VerifyIn(BaseModel):
    payment_id: str = Field(pattern=r'^pay_[A-Za-z0-9]+$')
    signature: str = Field(pattern=r'^[a-fA-F0-9]{64}$')

async def reconcile(c, user_id, item):
    if not item.get('order_id'): return item
    result = await provider(c,'GET',f"orders/{item['order_id']}/payments")
    payments = [p for p in result.get('items',[]) if p.get('order_id') == item['order_id']
                and p.get('amount') == item['amount'] and p.get('currency') == 'INR']
    captured = next((p for p in payments if p.get('status') == 'captured'), None)
    if captured:
        item.update(status='success', payment_id=captured['id'], method=captured.get('method',''))
    elif item['status'] != 'success':
        item['status'] = 'failed' if payments and all(p.get('status') == 'failed' for p in payments) else 'processing'
    put(c,user_id,'payment',item['id'],item)
    return item

@router.post('/orders/{id}/verify')
async def verify(id: str, body: VerifyIn, user=Depends(get_current_user), c=Depends(get_container)):
    item = get(c,user.id,id)
    if not configured(c) or not item.get('order_id'): raise HTTPException(409,'Checkout is not ready.')
    expected = hmac.new(c.settings.razorpay_key_secret.encode(),
                        f"{item['order_id']}|{body.payment_id}".encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected,body.signature): raise HTTPException(422,'Payment verification failed.')
    return await reconcile(c,user.id,item)

@router.get('/orders/{id}')
async def status(id: str, user=Depends(get_current_user), c=Depends(get_container)):
    await c.cache.rate_limit(user.id,'pay_status',60)
    return await reconcile(c,user.id,get(c,user.id,id))

@router.get('/history')
async def history(user=Depends(get_current_user), c=Depends(get_container)):
    return {'payments':rows(c,user.id,'payment'), 'statements':rows(c,user.id,'statement')}


def parse_statement(raw: bytes):
    try:
        reader = csv.DictReader(io.StringIO(raw.decode('utf-8-sig')))
        required = {'date','description','amount','direction','method','account'}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError('Use CSV columns: date, description, amount, direction, method, account. Optional: reference.')
        result, occurrences = [], {}
        for index, row in enumerate(reader,2):
            if any(not isinstance(row.get(k), str) for k in required): raise ValueError(f'Row {index}: missing values.')
            if index > 1001: raise ValueError('Import at most 1000 transactions at a time.')
            value = Decimal(row['amount'].strip())
            if not value.is_finite() or value <= 0 or value > 100000000 or value*100 != (value*100).to_integral_value():
                raise ValueError(f'Row {index}: use a positive amount with at most two decimal places.')
            direction, method = row['direction'].strip().lower(), row['method'].strip().lower()
            if direction not in ('debit','credit') or method not in ('upi','debit_card','credit_card','bank','cash','other'):
                raise ValueError(f'Row {index}: invalid direction or method.')
            item = dict(date=date.fromisoformat(row['date'].strip()).isoformat(), description=row['description'].strip()[:240],
                        amount_minor_units=int(value*100), direction=direction, method=method,
                        account=row['account'].strip()[:60], reference=(row.get('reference') or '').strip()[:80], source='imported')
            if not item['description'] or not item['account']: raise ValueError(f'Row {index}: description and account are required.')
            digest = hashlib.sha256(json.dumps(item,sort_keys=True).encode()).hexdigest()
            occurrences[digest] = occurrences.get(digest,0)+1
            item['fingerprint'] = digest+':'+str(occurrences[digest])
            result.append(item)
        if not result: raise ValueError('The statement has no transactions.')
        return result
    except (ValueError, InvalidOperation, TypeError, csv.Error) as exc:
        raise HTTPException(422,str(exc) if isinstance(exc,ValueError) else 'Invalid CSV statement.') from exc

@router.post('/statements/preview')
async def preview(file: UploadFile = File(...), user=Depends(get_current_user), c=Depends(get_container)):
    raw = await file.read(2*1024*1024+1)
    if len(raw)>2*1024*1024: raise HTTPException(413,'CSV must be smaller than 2 MB.')
    items = parse_statement(raw)
    con = db(c)
    try:
        with con: con.execute("DELETE FROM entries WHERE owner=? AND kind='preview'",(user.id,))
    finally: con.close()
    token = uuid.uuid4().hex
    put(c,user.id,'preview','preview:'+token,{'items':items,'expires':datetime.now(timezone.utc).timestamp()+600})
    return {'token':token,'count':len(items),'items':items}

class ImportIn(BaseModel):
    token: str = Field(pattern=r'^[a-f0-9]{32}$')

@router.post('/statements/import')
async def import_statement(body: ImportIn,user=Depends(get_current_user),c=Depends(get_container)):
    try: draft = get(c,user.id,'preview:'+body.token)
    except HTTPException: raise HTTPException(410,'Preview expired. Select the statement again.') from None
    if draft['expires'] < datetime.now(timezone.utc).timestamp(): raise HTTPException(410,'Preview expired. Select the statement again.')
    items = draft['items']
    con = db(c)
    imported = 0
    try:
        with con:
            for item in items:
                id = hashlib.sha256((user.id+item['fingerprint']).encode()).hexdigest()
                imported += con.execute('INSERT OR IGNORE INTO entries VALUES (?,?,?,?)',
                    (id,user.id,'statement',json.dumps({**item,'id':id}))).rowcount
    finally: con.close()
    return {'imported':imported,'duplicates':len(items)-imported}

@router.delete('/statements/{id}',status_code=204)
async def delete_statement(id: str,user=Depends(get_current_user),c=Depends(get_container)):
    con=db(c)
    try:
        with con: con.execute("DELETE FROM entries WHERE id=? AND owner=? AND kind='statement'",(id,user.id))
    finally: con.close()
