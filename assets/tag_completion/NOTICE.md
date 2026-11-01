# Offline tag completion data

The catalog preserves all records in the pinned source snapshots. No
post-count/popularity cutoff is applied by WorldPainter. This is a versioned
snapshot, not a claim to contain every tag ever published on Danbooru/e621.

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

The resulting union contains 400,348 tags, 71,504 alias records, and 316,443
nonempty translations. Source and output checksums are in `manifest.json`.
WorldPainter's parser, database adapter, settings and UI are implemented locally;
the interaction design references NAI Launcher's completion workflow.

Rebuild: `python scripts/build_tag_catalog.py --base /path/to/tag_catalog.db --zh /path/to/tag.sqlite`.
The builder verifies both source hashes, checks SQLite integrity, retains all
source tags/aliases, and generates a deterministic gzip and manifest. Update
the pinned hashes and version together when changing snapshots. App upgrades
install each catalog version separately and preserve the last working version
if installation fails.
