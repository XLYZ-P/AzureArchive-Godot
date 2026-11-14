# fixtures/aap 真实样本来源与校验

全部样本来自 GitHub 公开仓库 **systemannounce/BA_AAedit**（`main` 分支），
是作者用 AzureArchive 实际制作并保存的工程。文件按原字节下载、未做任何修改。

- 仓库：<https://github.com/systemannounce/BA_AAedit>
- 抓取时间：2026-11-14
- 抓取方式：`raw.githubusercontent.com` 直连（仓库 zip 亦已核对，二者一致）
- 文件格式：UTF-8 无 BOM、**压缩成单行的 JSON**（Newtonsoft `Formatting.None`），
  无结尾换行。见 `docs/spec/aap.md`。

## 清单

| 本地文件 | 字节 | sha256（前 16 位） | 源 URL |
|---|---:|---|---|
| `sample_kei_01.aap` | 294770 | `385dcf2a05a7da33…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E5%88%9D%E9%81%87.aap |
| `sample_kei_01.manifest.json` | 20052 | `eebeb55b43f2de5d…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E5%88%9D%E9%81%87/manifest.json |
| `sample_kei_02_multi_branch.aap` | 531176 | `6679977387a124ea…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%88%91%E4%BB%AC%E2%80%A6%E2%80%A6%E8%BF%98%E6%98%AF%E4%B8%8D%E8%A1%8C%E5%90%97%EF%BC%9F.aap |
| `sample_kei_02_multi_branch.manifest.json` | 35596 | `01bb562814120fed…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%88%91%E4%BB%AC%E2%80%A6%E2%80%A6%E8%BF%98%E6%98%AF%E4%B8%8D%E8%A1%8C%E5%90%97%EF%BC%9F/manifest.json |
| `sample_kei_02_multi_branch.voices.txt` | 27359 | `634dc5e1cdcc7e44…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%88%91%E4%BB%AC%E2%80%A6%E2%80%A6%E8%BF%98%E6%98%AF%E4%B8%8D%E8%A1%8C%E5%90%97%EF%BC%9F/voices/voices.txt |
| `sample_keiend_03_ending.aap` | 169759 | `8eaadb7f322d03aa…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiEnd-%E7%BB%88%E7%82%B9%E7%AB%99.aap |
| `sample_keiend_03_ending.manifest.json` | 10809 | `d0d0f24f0abb3e4e…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiEnd-%E7%BB%88%E7%82%B9%E7%AB%99/manifest.json |
| `sample_keiend_03_ending.voices.txt` | 10892 | `64be9d02b7a6edb1…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiEnd-%E7%BB%88%E7%82%B9%E7%AB%99/voices/voices.txt |
| `sample_kei_04_small.aap` | 82975 | `b60b7d74a808e3ee…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiTrinity-%E5%BA%8F%E7%AB%A0.aap |
| `sample_kei_04_small.manifest.json` | 5253 | `884591477202cc43…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiTrinity-%E5%BA%8F%E7%AB%A0/manifest.json |
| `sample_kei_04_small.voices.txt` | 4652 | `40f4e58d7f80787e…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/KeiTrinity-%E5%BA%8F%E7%AB%A0/voices/voices.txt |
| `sample_kei_05_large.aap` | 760123 | `446d5d819c74011a…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%8B%AF%E6%95%91%E7%88%B1%E4%B8%BD%E4%B8%9D.aap |
| `sample_kei_05_large.manifest.json` | 52542 | `3c8c9dd3ddc81b0f…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%8B%AF%E6%95%91%E7%88%B1%E4%B8%BD%E4%B8%9D/manifest.json |
| `sample_kei_05_large.voices.txt` | 41493 | `4dd0ccca9c2c81e7…` | https://raw.githubusercontent.com/systemannounce/BA_AAedit/main/Kei-%E6%8B%AF%E6%95%91%E7%88%B1%E4%B8%BD%E4%B8%9D/voices/voices.txt |

完整 sha256（可 `cd fixtures/aap && sha256sum -c SOURCES.sha256` 校验）：

```
385dcf2a05a7da33d661054e6e67386fe67fb2455888913f468c2f6cc6003b52  sample_kei_01.aap
eebeb55b43f2de5dbd8eb5357b9fa588c03271cee8ec319997f38a9dac1166e9  sample_kei_01.manifest.json
6679977387a124ea6b7e59b961c56dc042a0bde09b85a72433b5fcc62be61ec3  sample_kei_02_multi_branch.aap
01bb562814120fed5a56441d8920948dd0e02ad89b55106e68e205b86f11f46e  sample_kei_02_multi_branch.manifest.json
634dc5e1cdcc7e446b80e9906cf0dcd3dd1d0f484bf886fdcd822d4e20d723b5  sample_kei_02_multi_branch.voices.txt
8eaadb7f322d03aa25e5d9e0d74212a1f792c7a7dd72dff9e983ddf99ff671b0  sample_keiend_03_ending.aap
d0d0f24f0abb3e4ea6befe69cccf139dbd710e0129b28e9ed6cdff63f0bc4dcd  sample_keiend_03_ending.manifest.json
64be9d02b7a6edb162706219d5bd7e87ca472101efbc9227070fd54af3ac7999  sample_keiend_03_ending.voices.txt
b60b7d74a808e3eeea33085e49d250a21a0a16e1aff9d525fe9370981fd2dd4b  sample_kei_04_small.aap
884591477202cc434c5fb33f4254f030ed93b7db95fb89b93095167d305aaa21  sample_kei_04_small.manifest.json
40f4e58d7f80787e5adacd654a2db18162b1ebe07eebe624f8fb6155951d70c2  sample_kei_04_small.voices.txt
446d5d819c74011a890374fe893d94a5527827957f170ebc0dfbe1d622251b1c  sample_kei_05_large.aap
3c8c9dd3ddc81b0ff7ae7445aee4f3442d42862163d25de8c78a1d9f9bd9caf2  sample_kei_05_large.manifest.json
4dd0ccca9c2c81e72c4fed45f320fb9c4d7955063d156820f9e8f8f55c3ceee3  sample_kei_05_large.voices.txt
```

## 用途

| 样本 | 为什么选它 |
|---|---|
| `sample_kei_01` | 17 节点，含 5 个选择节点（2/1/2/1/1 个选项）、连续 2 个选择节点分支合并、Exit 带 `NeHeader`/`NeTitle`；manifest 有 5 个 `CharacterReference` 别名覆盖 |
| `sample_kei_02_multi_branch` | 531 KB，选项连线有 2~3 个且**含重复连线**（两个选项指向同一节点）、含 `BgOverrides`（8 张）/`SoundOverrides`（3 个，含 `.mp3`/`.ogg`） |
| `sample_keiend_03_ending` | `IsEnding: true` 的出口节点、`EndText` 结束语、`NeHeader/NeTitle` 下回预告（编译器据此生成 `#nextepisode;…`） |
| `sample_kei_04_small` | 82 KB / 4 节点，最小可读样本，适合单测与人工 diff |
| `sample_kei_05_large` | 760 KB 全库最大样本之一，节点 100+，覆盖大量 emoticon/action/appear/shapeOverride 取值 |
| `*.manifest.json` | 自定义资源清单真实样本；只有 `CharacterReference` 别名形式（全库 36 个工程均无 Spine 立绘覆盖） |
| `*.voices.txt` | 配音清单真实样本，格式 `<guid> => [角色] 台词` |

> 说明：仓库 36 个真实工程**没有一个**使用自定义 Spine 立绘或自定义 BGM/弹出图片，
> 因此 `SpinePortraitPath`、`BgmOverrides`、`PopupOverrides` 只能依据官方文档
> （research/aa-docs/p20）推断，见 `docs/spec/resources.md` 的「证据等级」标注。
