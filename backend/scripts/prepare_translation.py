"""Download a pinned, data-only MADLAD-400 CTranslate2 conversion."""
from pathlib import Path
from huggingface_hub import snapshot_download
ROOT = Path(__file__).resolve().parents[1] / 'data' / 'translation' / 'madlad400'
if __name__ == '__main__':
    snapshot_download('santhosh/madlad400-3b-ct2', revision='c32ad0cf118807ea6258d14be137547155842723', local_dir=ROOT, allow_patterns=['model.bin','config.json','shared_vocabulary.json','sentencepiece.model','README.md'])
    print('Translation model ready.')
