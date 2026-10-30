import pytest
from app.domains.graph.store import SurrealGraphStore

CONFLICT='The query was not executed due to a failed transaction. Failed to commit transaction due to a read or write conflict. This transaction can be retried'
class FakeDB:
    def __init__(self, errors): self.errors=list(errors); self.calls=[]
    async def query(self, query, params):
        self.calls.append((query,params))
        if self.errors: raise self.errors.pop(0)
    async def select(self,key): return {'id':key}

@pytest.mark.asyncio
@pytest.mark.parametrize('delete',[False,True])
async def test_commit_conflicts_retry_whole_atomic_transaction(delete):
    db=FakeDB([RuntimeError(CONFLICT),RuntimeError(CONFLICT)])
    store=SurrealGraphStore(db)
    if delete: await store.delete('social_moment:test')
    else: await store.put('social_moment:test',{'caption':'test'})
    assert len(db.calls)==3
    assert db.calls[0]==db.calls[1]==db.calls[2]
    assert 'graph_outbox' in db.calls[0][0] and 'graph_meta:revision' in db.calls[0][0]

@pytest.mark.asyncio
async def test_other_failures_are_not_retried():
    db=FakeDB([RuntimeError('connection closed')])
    with pytest.raises(RuntimeError,match='connection closed'):
        await SurrealGraphStore(db).put('social_moment:test',{'caption':'test'})
    assert len(db.calls)==1

@pytest.mark.asyncio
async def test_retries_are_bounded(monkeypatch):
    async def no_sleep(_): pass
    monkeypatch.setattr('app.domains.graph.store.asyncio.sleep',no_sleep)
    db=FakeDB([RuntimeError(CONFLICT)]*8)
    with pytest.raises(RuntimeError,match='conflict'):
        await SurrealGraphStore(db).put('social_moment:test',{'caption':'test'})
    assert len(db.calls)==8
