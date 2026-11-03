"""Bounded, non-interactive snap decoration payloads (no local paths)."""
import json
import math
from urllib.parse import urlparse
from fastapi import HTTPException


def parse_snap_decorations(raw: str):
    try:
        if len(raw) > 50000:
            raise ValueError()
        layers = json.loads(raw)
        if not isinstance(layers, list) or len(layers) > 20:
            raise ValueError()
        result = []
        music = 0
        for layer in layers:
            kind = layer['type']
            if kind not in {'word', 'location', 'music', 'gif', 'sticker', 'clock', 'photo'}:
                raise ValueError()
            clean = {'type': kind, 'id': str(layer.get('id', ''))[:100]}
            for field, default, low, high in [('x', .5, 0, 1), ('y', .5, 0, 1),
                                              ('scale', 1, .5, 1.5), ('rotation', 0, -7, 7)]:
                value = float(layer.get(field, default))
                if not math.isfinite(value) or not low <= value <= high:
                    raise ValueError()
                clean[field] = value
            data = layer.get('data') or {}
            if not isinstance(data, dict):
                raise ValueError()
            clean['data'] = {}
            for field in ('text', 'word', 'style', 'title', 'artist', 'url', 'cover_url', 'time', 'shape'):
                if field not in data:
                    continue
                value = data[field]
                if not isinstance(value, str) or len(value) > (2048 if field.endswith('url') else 500):
                    raise ValueError()
                # https links, or images uploaded to Phlio (/media/post_uploads/…).
                uploaded = kind == 'photo' and field == 'url' and value.startswith('/media/post_uploads/') and '..' not in value
                if field.endswith('url') and value and not uploaded and urlparse(value).scheme != 'https':
                    raise ValueError()
                clean['data'][field] = value
            if kind == 'sticker':
                sticker = layer.get('sticker')
                if not isinstance(sticker, str) or len(sticker) > 100:
                    raise ValueError()
                clean['sticker'] = sticker
            if kind == 'music':
                music += 1
                if music > 1 or not clean['data'].get('url'):
                    raise ValueError()
            if kind in {'gif', 'photo'} and not clean['data'].get('url'):
                raise ValueError()
            result.append(clean)
        return result
    except (ValueError, TypeError, KeyError, OverflowError):
        raise HTTPException(422, 'Invalid snap decorations.') from None
