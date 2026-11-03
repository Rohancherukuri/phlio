import json
import pytest
from fastapi import HTTPException
from app.api.v1.snap_decorations import parse_snap_decorations


def test_snap_layers_preserve_animation_music_and_position():
    layers = [
        {'type': 'gif', 'x': .2, 'y': .7, 'data': {'url': 'https://media.giphy.com/test.gif'}},
        {'type': 'music', 'data': {'title': 'Song', 'url': '/media/song.mp3'}},
        {'type': 'word', 'data': {'word': 'Hello', 'style': 'gradient'}},
        {'type': 'location', 'data': {'text': 'Hyderabad'}},
        {'type': 'sticker', 'sticker': 'foxy_wave'},
    ]
    result = parse_snap_decorations(json.dumps(layers))
    assert result[0]['data']['url'].endswith('.gif')
    assert result[0]['x'] == .2 and result[0]['y'] == .7
    assert result[1]['data']['url'] == '/media/song.mp3'
    assert result[2]['data']['word'] == 'Hello'
    assert result[4]['sticker'] == 'foxy_wave'


@pytest.mark.parametrize('layers', [
    {'unexpected': 'object'}, [None],
    [{'type': 'poll'}], [{'type': 'word', 'x': float('nan')}],
    [{'type': 'word', 'scale': 100}],
    [{'type': 'music', 'data': {'url': 'file:///private/audio.mp3'}}],
    [{'type': 'music', 'data': {'url': '/media/../secret'}}],
    [{'type': 'word'}] * 21,
    [{'type': 'music', 'data': {'url': 'https://example.org/song.mp3'}}] * 2,
])
def test_invalid_snap_layers_rejected(layers):
    with pytest.raises(HTTPException) as error:
        parse_snap_decorations(json.dumps(layers))
    assert error.value.status_code == 422
