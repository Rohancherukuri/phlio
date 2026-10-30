"""Single local inference worker shared by both Phlio APIs. No external calls."""
import asyncio
import threading
from functools import lru_cache
from pathlib import Path
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import uvicorn

app = FastAPI(title='Phlio local translation')
_lock = threading.Lock()
_model = None
_tokenizer = None
ROOT = Path(__file__).resolve().parents[1] / 'data' / 'translation' / 'madlad400'

class Request(BaseModel):
    text: str = Field(min_length=1, max_length=2000)

@lru_cache(maxsize=256)
def infer(text):
    global _model, _tokenizer
    if not _lock.acquire(timeout=1):
        raise HTTPException(503, 'Translation is busy. Try again shortly.')
    try:
        if _model is None:
            import ctranslate2
            import sentencepiece
            if not (ROOT / 'model.bin').is_file():
                raise HTTPException(503, 'Translation model is not installed.')
            _tokenizer = sentencepiece.SentencePieceProcessor(model_file=str(ROOT / 'sentencepiece.model'))
            _model = ctranslate2.Translator(str(ROOT), device='cpu', compute_type='int8', inter_threads=1, intra_threads=4)
        tokens = _tokenizer.encode(text, out_type=str)
        # Chunk rather than silently discard the end of longer comments.
        chunks = [_tokenizer.encode('<2en> ' + _tokenizer.decode(tokens[i:i+384]), out_type=str) for i in range(0, len(tokens), 384)]
        results = _model.translate_batch(chunks, beam_size=4, repetition_penalty=1.1, max_decoding_length=512)
        return ' '.join(_tokenizer.decode(r.hypotheses[0]) for r in results).strip()
    finally:
        _lock.release()

@app.get('/health')
async def health():
    return {'ready': (ROOT / 'model.bin').is_file(), 'model': 'MADLAD-400-3B', 'loaded': _model is not None}

@app.post('/translate')
async def translate(body: Request):
    text = body.text.strip()
    if not text: raise HTTPException(422, 'No text to translate.')
    result = await asyncio.to_thread(infer, text)
    return {'text': result, 'target_language': 'en', 'model': 'MADLAD-400-3B'}

if __name__ == '__main__':
    uvicorn.run(app, host='127.0.0.1', port=8010)
