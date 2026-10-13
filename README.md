# AstrBot 插件维护集合

这里集中列出当前独立维护的 AstrBot 插件。每个插件都有独立仓库，可分别安装与更新。

| 插件 | 维护仓库 | 原仓库 / 来源 | 初始基线 |
| --- | --- | --- | --- |
| `astrbot_plugin_bilivideo` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_bilivideo) | [原仓库](https://github.com/storyAura/astrbot_plugin_biliVideo) | [`7cfb5ef0c365`](https://github.com/storyAura/astrbot_plugin_biliVideo/commit/7cfb5ef0c365e35949e8afd5ff0eca7a513924cb) |
| `astrbot_plugin_error_pro` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_error_pro) | [原仓库](https://github.com/Chris95743/astrbot_plugin_error_pro) | [`e9f977e6858e`](https://github.com/Chris95743/astrbot_plugin_error_pro/commit/e9f977e6858eb4d984e0c6c9981659c63a4835e3) |
| `astrbot_plugin_local_help` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_local_help) | 本地原创 | 本机初始快照 |
| `astrbot_plugin_memelite` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_memelite) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_memelite) | [`f038e9fe3f1e`](https://github.com/Zhalslar/astrbot_plugin_memelite/commit/f038e9fe3f1edf81dfaa6e3e3839e4e1aee35de3) |
| `astrbot_plugin_pokepro` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_pokepro) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_pokepro) | [`64f1f9f70be4`](https://github.com/Zhalslar/astrbot_plugin_pokepro/commit/64f1f9f70be44757e0ee29246434545aaf3dcc52) |
| `astrbot_plugin_qqadmin` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_qqadmin) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_qqadmin) | [`4926faa5555a`](https://github.com/Zhalslar/astrbot_plugin_qqadmin/commit/4926faa5555aa98fdf3de709fd135cd62c1b4057) |
| `astrbot_plugin_relationship` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_relationship) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_relationship) | [`d10e963be321`](https://github.com/Zhalslar/astrbot_plugin_relationship/commit/d10e963be3218b7188c14cd6330c8567e19142dd) |
| `astrbot_plugin_reread` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_reread) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_reread) | [`71b4aa3282aa`](https://github.com/Zhalslar/astrbot_plugin_reread/commit/71b4aa3282aa48c0bd63c6870e675033156e4597) |
| `astrbot_plugin_wakepro` | [打开仓库](https://github.com/leekooyo/astrbot_plugin_wakepro) | [原仓库](https://github.com/Zhalslar/astrbot_plugin_wakepro) | [`0a7ee7f932e4`](https://github.com/Zhalslar/astrbot_plugin_wakepro/commit/0a7ee7f932e40175ecc1f0603c883f32944e475c) |
| `builtin_commands_extension` | [打开仓库](https://github.com/leekooyo/builtin_commands_extension) | [原仓库](https://github.com/AstrBotDevs/builtin_commands_extension) | [`410f99a72749`](https://github.com/AstrBotDevs/builtin_commands_extension/commit/410f99a72749cd90f85bf44aa7a0183c1da21de1) |
| `gatekeeper` | [打开仓库](https://github.com/leekooyo/gatekeeper) | 本地原创 | 本机初始快照 |
| `meme_manager` | [打开仓库](https://github.com/leekooyo/meme_manager) | [原仓库](https://github.com/anka-afk/astrbot_plugin_meme_manager) | [`c71b9bc8e1f2`](https://github.com/anka-afk/astrbot_plugin_meme_manager/commit/c71b9bc8e1f28eebd4aca02ef2edb1e751a24c57) |

## 更新约定

- 每个仓库的 `main` 仅在审查并合并本仓库 PR 后更新。
- 原作者的新版本不会自动同步；先查看差异、测试兼容性，再手动合并。
- 插件许可证、原作者和版权声明保留在各插件仓库。
- 运行配置、缓存和凭据不发布。

## 安装

在 AstrBot 插件管理中选择“通过仓库地址安装”，填入表中对应维护仓库 URL。当前机器已安装的插件来源由本机单独记录，迁移时会逐一切换。
