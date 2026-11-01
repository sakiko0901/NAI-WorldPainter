"""Build the complete, Android-compatible offline completion catalog.

Usage: python scripts/build_tag_catalog.py --base PATH --zh PATH
Pinned source hashes are verified before reading. No popularity filtering.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE_SHA = '9b9693af5f6cfafda2ed8d85488b0a6c3741b0c589da935291b20dff439a2288'
ZH_SHA = 'cd7aa3fa9a2b6153b04a1bce88f98ab3381c20bdabb6348b5fbf1005dad00870'


def checked(path, expected):
    assert hashlib.sha256(path.read_bytes()).hexdigest() == expected, path
    return sqlite3.connect(f'{path.as_uri()}?mode=ro', uri=True)


def build(base_path, zh_path):
    base = checked(base_path, BASE_SHA)
    zh = checked(zh_path, ZH_SHA)
    print('Chinese schema:', zh.execute("SELECT sql FROM sqlite_master WHERE type='table'").fetchall())
    tags = {name: [cat, count, ''] for name, cat, count in
            base.execute('SELECT name,category,post_count FROM tags')}
    table = next(name for (name,) in zh.execute("SELECT name FROM sqlite_master WHERE type='table'")
                 if {'name', 'cn_name', 'category', 'post_count'} <=
                 {r[1] for r in zh.execute(f'PRAGMA table_info("{name}")')})
    for name, cat, count, translation in zh.execute(
            f'SELECT name,category,post_count,cn_name FROM "{table}"'):
        if name not in tags:
            tags[name] = [cat or 0, count or 0, translation or '']
        else:
            tags[name][2] = translation or ''
    for name, translation, mode in base.execute('SELECT tag,zh_cn,mode FROM zh_translations'):
        if name in tags and (mode == 1 or not tags[name][2]):
            tags[name][2] = translation
    aliases = base.execute('SELECT a.alias,t.name FROM aliases a JOIN tags t ON t.id=a.tag_id').fetchall()
    out = ROOT / 'assets' / 'tag_completion'
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='worldpainter-tags-') as temp:
        db_path = Path(temp) / 'catalog.db'
        db = sqlite3.connect(db_path)
        db.executescript('''
        PRAGMA journal_mode=OFF;
        PRAGMA synchronous=OFF;
        PRAGMA user_version=1;
        CREATE TABLE tags(id INTEGER PRIMARY KEY,name TEXT NOT NULL UNIQUE,
          category INTEGER NOT NULL,post_count INTEGER NOT NULL,translation TEXT NOT NULL);
        CREATE TABLE terms(term TEXT NOT NULL,tag_id INTEGER NOT NULL,kind INTEGER NOT NULL,
          PRIMARY KEY(term,tag_id,kind)) WITHOUT ROWID;
        CREATE TABLE zh_grams(gram TEXT NOT NULL,tag_id INTEGER NOT NULL,
          PRIMARY KEY(gram,tag_id)) WITHOUT ROWID;
        ''')
        ids = {name: i for i, name in enumerate(sorted(tags), 1)}
        db.executemany('INSERT INTO tags VALUES(?,?,?,?,?)',
                       ((ids[name], name, *tags[name]) for name in sorted(tags)))
        def terms():
            for name in sorted(tags):
                yield name, ids[name], 0
                # Word suffixes make e.g. "hair" find "long_hair" via an index.
                for match in re.finditer('_', name):
                    suffix = name[match.end():]
                    if suffix:
                        yield suffix, ids[name], 2
            for alias, name in aliases:
                yield alias, ids[name], 1
        db.executemany('INSERT OR IGNORE INTO terms VALUES(?,?,?)', terms())
        def grams():
            for name, (_, _, translation) in tags.items():
                chars = set(translation)
                pairs = {translation[i:i+2] for i in range(len(translation)-1)}
                for gram in chars | pairs:
                    yield gram, ids[name]
        db.executemany('INSERT OR IGNORE INTO zh_grams VALUES(?,?)', grams())
        db.commit()
        db.execute('ANALYZE')
        db.execute('VACUUM')
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        counts = dict(tags=len(tags), aliases=len(aliases),
                      translations=sum(bool(row[2]) for row in tags.values()))
        db.close()
        data = db_path.read_bytes()
        compressed = gzip.compress(data, compresslevel=9, mtime=0)
        (out / 'catalog.db.gz').write_bytes(compressed)
        manifest = dict(schemaVersion=1, version='2026-11-01.1', **counts,
                        size=len(data), compressedSize=len(compressed),
                        sha256=hashlib.sha256(data).hexdigest(),
                        compressedSha256=hashlib.sha256(compressed).hexdigest(),
                        sources=[
                            dict(url='https://github.com/Aaalice233/Aaalice_NAI_Launcher',
                                 commit='60b2129308de8b04df0798dee36ce21e7e6f3872', sha256=BASE_SHA,
                                 tags=221787, aliases=71504),
                            dict(url='https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table',
                                 commit='3049e201002a64702873d7f9f3cc7cb8c45ea325', sha256=ZH_SHA)])
        (out / 'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
        print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--zh', type=Path, required=True)
    args = parser.parse_args()
    build(args.base.resolve(), args.zh.resolve())
