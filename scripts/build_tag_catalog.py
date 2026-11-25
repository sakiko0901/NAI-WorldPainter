"""Build the Android-compatible offline tag catalog from pinned snapshots."""

import argparse
from contextlib import closing
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import tempfile


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = ROOT / 'assets' / 'tag_completion'
VERSION = '2026-11-25.1'
BASE_SOURCE = {
    'url': 'https://github.com/Aaalice233/Aaalice_NAI_Launcher',
    'commit': '60b2129308de8b04df0798dee36ce21e7e6f3872',
    'sha256': '9b9693af5f6cfafda2ed8d85488b0a6c3741b0c589da935291b20dff439a2288',
}
ZH_URL = 'https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table'
ZH_SOURCE = {
    'url': ZH_URL,
    'commit': '3049e201002a64702873d7f9f3cc7cb8c45ea325',
    'sha256': 'cd7aa3fa9a2b6153b04a1bce88f98ab3381c20bdabb6348b5fbf1005dad00870',
}
ZH_UPDATE_SOURCE = {
    'url': ZH_URL,
    'commit': '4418592b1eeafabdbd3ea882a69af71d1c1e2c4e',
    'sha256': '6d8c4e5bf8d1fa00c5400da7cb5530e317ad7ac80a4fccc0fda7df99d5733e3a',
}
REFERENCE_SOURCE = {
    'url': 'https://github.com/2786886095/novelai-image-desktop/releases/tag/tag-packs-2026-11-16',
    'commit': '1aebb6fd66c289df710be985469ec174d3cf5da9',
    'file': 'tags-2026-11-16-zh-CN.sqlite.gz',
    'sha256': '6de4da29a6447a994c86fe6038b2404f2fa0005edaa135abe74399ef6476f86d',
}
DANBOORU_SOURCE = {
    'url': 'https://danbooru.donmai.us/tags.json',
    'file': 'scripts/tag_catalog_sources/danbooru-2026-11-16-to-2026-11-25.json.gz',
    'sha256': '4b5716e251a84b9a5a2065f7c83a7dead69a663c66c43ebf2641f7a37b9d71e8',
}
VERIFIED_TRANSLATIONS = {
    'evanescia_(honkai:_star_rail)': '绯英',
    'jade_(honkai:_star_rail)': '翡翠',
}


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as data:
        for chunk in iter(lambda: data.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def verify_source(path, metadata):
    actual = sha256(path)
    if actual != metadata['sha256']:
        raise ValueError(f'SHA-256 mismatch for {path}: {actual}')


def read_database(path):
    return closing(sqlite3.connect(f'{path.as_uri()}?mode=ro', uri=True))


def load_base(base_path, zh_path):
    with read_database(base_path) as base, read_database(zh_path) as zh:
        tags = {
            name: [category, count, '']
            for name, category, count in base.execute(
                'SELECT name,category,post_count FROM tags')
        }
        base_count = len(tags)
        for name, category, count, translation in zh.execute(
                'SELECT name,category,post_count,cn_name FROM tags'):
            row = tags.setdefault(name, [category or 0, count or 0, ''])
            row[2] = translation or ''
        for name, translation, mode in base.execute(
                'SELECT tag,zh_cn,mode FROM zh_translations'):
            if name in tags and (mode == 1 or not tags[name][2]):
                tags[name][2] = translation
        aliases = base.execute('''
            SELECT a.alias,t.name FROM aliases a JOIN tags t ON t.id=a.tag_id
            ORDER BY a.alias,t.name
        ''').fetchall()
    return tags, aliases, base_count


def merge_reference(tags, archive, expanded):
    before = len(tags)
    with gzip.open(archive, 'rb') as source, expanded.open('wb') as database:
        shutil.copyfileobj(source, database)
    with read_database(expanded) as reference:
        count = 0
        for name, category, post_count in reference.execute(
                'SELECT tag,category,count FROM terms'):
            tags.setdefault(name, [category, post_count, ''])
            count += 1
    return dict(REFERENCE_SOURCE, tags=count, addedTags=len(tags) - before,
                fields=['tag', 'category', 'count'])


def merge_danbooru_delta(tags, delta_path):
    before = len(tags)
    with gzip.open(delta_path, 'rt', encoding='utf-8') as source:
        delta = json.load(source)
    active_aliases = set(delta['matchingActiveAliases'])
    records = delta['tags']
    canonical_count = 0
    for record in records:
        name = record['name']
        if record['is_deprecated'] or name in active_aliases:
            continue
        tags.setdefault(name, [record['category'], record['post_count'], ''])
        canonical_count += 1
    return dict(DANBOORU_SOURCE, createdFrom=delta['createdFrom'],
                createdThrough=delta['createdThrough'], maximumTagId=delta['maximumTagId'],
                capturedTags=len(records), tags=canonical_count, addedTags=len(tags) - before,
                excludedActiveAliases=len(active_aliases))


def fill_translations(tags, zh_update_path):
    added = 0
    with read_database(zh_update_path) as zh:
        for name, translation in zh.execute(
                "SELECT name,cn_name FROM tags WHERE cn_name IS NOT NULL AND trim(cn_name)<>''"):
            if name in tags and not tags[name][2]:
                tags[name][2] = translation
                added += 1
    for name, translation in VERIFIED_TRANSLATIONS.items():
        tags[name][2] = translation
    return added


def create_catalog(db_path, tags, aliases):
    # Stable insertion order makes SQLite pages independent of PYTHONHASHSEED.
    names = sorted(tags)
    ids = {name: index for index, name in enumerate(names, 1)}

    def terms():
        for name in names:
            yield name, ids[name], 0
            # Word suffixes make e.g. "hair" find "long_hair" via an index.
            for match in re.finditer('_', name):
                suffix = name[match.end():]
                if suffix:
                    yield suffix, ids[name], 2
        for alias, name in aliases:
            yield alias, ids[name], 1

    def grams():
        for name in names:
            translation = tags[name][2]
            chars = set(translation)
            pairs = {translation[index:index + 2] for index in range(len(translation) - 1)}
            for gram in sorted(chars | pairs):
                yield gram, ids[name]

    with closing(sqlite3.connect(db_path)) as db:
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
        db.executemany('INSERT INTO tags VALUES(?,?,?,?,?)',
                       ((ids[name], name, *tags[name]) for name in names))
        db.executemany('INSERT OR IGNORE INTO terms VALUES(?,?,?)', terms())
        db.executemany('INSERT OR IGNORE INTO zh_grams VALUES(?,?)', grams())
        db.commit()
        db.execute('ANALYZE')
        db.execute('VACUUM')
        if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
            raise ValueError(f'SQLite integrity check failed for {db_path}')


def build(base_path, zh_path, zh_update_path, reference_path, output_dir):
    delta_path = ROOT / DANBOORU_SOURCE['file']
    for path, source in (
            (base_path, BASE_SOURCE), (zh_path, ZH_SOURCE),
            (zh_update_path, ZH_UPDATE_SOURCE), (reference_path, REFERENCE_SOURCE),
            (delta_path, DANBOORU_SOURCE)):
        verify_source(path, source)
    tags, aliases, base_count = load_base(base_path, zh_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='worldpainter-tags-', dir=output_dir) as temp:
        work = Path(temp)
        reference = merge_reference(tags, reference_path, work / 'reference.sqlite')
        danbooru = merge_danbooru_delta(tags, delta_path)
        added_translations = fill_translations(tags, zh_update_path)
        db_path = work / 'catalog.db'
        create_catalog(db_path, tags, aliases)
        compressed_path = work / 'catalog.db.gz'
        with db_path.open('rb') as data, compressed_path.open('wb') as output:
            with gzip.GzipFile(filename='', fileobj=output, mode='wb', mtime=0) as compressed:
                shutil.copyfileobj(data, compressed)
        compressed_size = compressed_path.stat().st_size
        if compressed_size >= 100 * 1024 * 1024:
            raise ValueError('The bundled catalog exceeds the GitHub file size limit')
        manifest = dict(
            schemaVersion=1, version=VERSION,
            tags=len(tags), aliases=len(aliases),
            translations=sum(bool(row[2]) for row in tags.values()),
            size=db_path.stat().st_size, compressedSize=compressed_size,
            sha256=sha256(db_path), compressedSha256=sha256(compressed_path),
            sources=[
                dict(BASE_SOURCE, tags=base_count, aliases=len(aliases)),
                ZH_SOURCE,
                reference,
                danbooru,
                dict(ZH_UPDATE_SOURCE, translationsAdded=added_translations),
            ],
        )
        manifest_text = json.dumps(manifest, indent=2) + '\n'
        manifest_path = work / 'manifest.json'
        manifest_path.write_text(manifest_text, encoding='utf-8', newline='\n')
        compressed_path.replace(output_dir / compressed_path.name)
        manifest_path.replace(output_dir / manifest_path.name)
    print(manifest_text, end='')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--zh', type=Path, required=True)
    parser.add_argument('--zh-update', type=Path, required=True)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, default=OUTPUT_DIR)
    args = parser.parse_args()
    build(args.base.resolve(), args.zh.resolve(), args.zh_update.resolve(),
          args.reference.resolve(), args.output_dir.resolve())
