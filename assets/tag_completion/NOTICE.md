# Offline tag completion data

WorldPainter merges canonical English names by exact match from the snapshots
below and preserves the base catalog's aliases. Post counts are carried through
without a popularity threshold. The catalog's coverage follows these snapshots.

- Base: 221,787 canonical tags and 71,504 aliases from NAI Launcher's catalog,
  commit `60b2129308de8b04df0798dee36ce21e7e6f3872`.
  [Database release](https://github.com/Aaalice233/Aaalice_NAI_Launcher/releases/download/autocomplete-data-tag-catalog-125148ac-v1/tag_catalog.db).
  Its underlying merged CSV is from ComfyUI-Lora-Manager commit
  `42f35be9d394ff62fc9e9a39b8c500b8f9b67bfe`,
  [data source](https://raw.githubusercontent.com/willmiao/ComfyUI-Lora-Manager/42f35be9d394ff62fc9e9a39b8c500b8f9b67bfe/refs/danbooru_e621_merged.csv),
  SHA256 `71297f7e4adaeae005cba1259b25a10374ed01e071cb4801a6195e709c32a9e5`.
  Original data: [dbr-e621-lists-archive](https://github.com/DraconicDragon/dbr-e621-lists-archive), Unlicense.
  Only data is used from that source; no GPL application code is incorporated.
- Translations and additional tags: complete `tags` table from
  [ffdkj's Chinese-English translation table](https://github.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table),
  commit `3049e201002a64702873d7f9f3cc7cb8c45ea325`, MIT.
  [Pinned database](https://raw.githubusercontent.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table/3049e201002a64702873d7f9f3cc7cb8c45ea325/tag.sqlite).
  MIT notice preserved from commit `95a027553823ad6bb5141c7190530d7afcd78461`
  (the earlier data commit predates LICENSE). Translations may contain errors.
- NAI Launcher's 517 supplemental translations are applied for missing
  translations, with its two explicit overrides respected. MIT notice retained.
- Additional canonical names, categories and counts from the
  [novelai-image-desktop tag packs](https://github.com/2786886095/novelai-image-desktop/releases/tag/tag-packs-2026-11-16),
  tag at commit `1aebb6fd66c289df710be985469ec174d3cf5da9`.
  The selected package contains 510,084 non-artist tags sourced from Danbooru,
  including 337,941 additions to WorldPainter.
  [Pinned zh-CN package](https://github.com/2786886095/novelai-image-desktop/releases/download/tag-packs-2026-11-16/tags-2026-11-16-zh-CN.sqlite.gz).
- Recent canonical tags from the [Danbooru tags API](https://danbooru.donmai.us/tags.json),
  captured from 2026-11-16 00:00 through 2026-11-25 12:30 UTC at tag ID
  2,785,880 or below. The capture used `search[created_at]` for the interval,
  `search[id]=..2785880` and `search[order]=date`, paging with `limit=1000`
  and `page=b<last-id>`. It cross-checked active antecedents from the
  [tag aliases API](https://danbooru.donmai.us/tag_aliases.json) using
  `search[status]=active` and `search[updated_at]` for the same interval.
  Of 7,145 returned tag records, 7,081 qualified for the merge and 7,020
  added unique names. The pinned snapshot is stored under
  `scripts/tag_catalog_sources/` so rebuilds work without a live API query.
- The updated MIT-licensed ffdkj table at commit
  `4418592b1eeafabdbd3ea882a69af71d1c1e2c4e` supplied 11,850 missing
  translations for names in the merged catalog. Existing nonempty translations
  take precedence. [Pinned updated database](https://raw.githubusercontent.com/ffdkj/ffdkj-Danbooru_Tag-Chinese-English-Translation-Table/4418592b1eeafabdbd3ea882a69af71d1c1e2c4e/tag.sqlite).
- Two reviewed character names take precedence over the imported text:
  `evanescia_(honkai:_star_rail)` → 绯英 and `jade_(honkai:_star_rail)` → 翡翠.
  [Honkai: Star Rail 4.2 update](https://sr.mihoyo.com/news/163630),
  [official character page](https://sr.mihoyo.com/main?nav=world).

The resulting union contains 745,309 tags, 71,504 alias records, and 328,293
nonempty translations. Source and output checksums are in `manifest.json`.
WorldPainter's implementation references NAI Launcher's completion workflow.

To rebuild, save the pinned updated translation database as `tag-update.sqlite`
and run the builder from the repository root.

```sh
python scripts/build_tag_catalog.py --base tag_catalog.db --zh tag.sqlite --zh-update tag-update.sqlite --reference tags-2026-11-16-zh-CN.sqlite.gz
```

The builder verifies all source hashes and SQLite integrity. Byte-for-byte
rebuild was checked with Python 3.12.10, SQLite 3.49.1, and zlib 1.3.1. Update
the pinned inputs, hashes, and version together when changing snapshots.
App upgrades install each catalog version separately and preserve the last
working version if installation fails.
