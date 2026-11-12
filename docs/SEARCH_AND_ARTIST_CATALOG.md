# 搜索与艺人目录分页

## 需求与验收

- 搜索不再止于 10 条；歌曲、艺人、歌单分别可以续页。切换关键词后，旧请求不得覆盖新结果。
- 艺人主页保留预览，在歌曲和作品标题后增加圆形 `>` 入口，进入独立的完整目录页面。
- 专辑页面采用方形封面的响应式网格，显示名称和年份；歌曲页面采用封面、歌名、专辑与年份、更多菜单的纵向列表。
- 二级页面沿用当前 Tab 的 Navigator，保留播放器；返回时恢复艺人页。
- 空列表、首次加载失败、续页失败分开处理。续页失败保留已有内容，重试同一页；不将失败当作目录结束。

## 原因

原搜索请求在 Web API 和 Pathfinder 两条路径上均固定 `offset=0 / limit=10`，Provider 与界面也没有后续分页状态。仅提高 `limit` 仍会产生新的截断点。

2026-10-05 核对的官方文档规定，公开 API 的[搜索](https://developer.spotify.com/documentation/web-api/reference/search)和[艺人专辑](https://developer.spotify.com/documentation/web-api/reference/get-an-artists-albums)每页最多 10 项；[专辑曲目](https://developer.spotify.com/documentation/web-api/reference/get-an-albums-tracks)每页最多 50 项。因此公开 API 与 Pathfinder 的有效页大小分别处理，搜索也遵守公开 API 的最大 offset 1000。

艺人页使用的是热门曲目预览，而非全量歌曲目录；作品请求固定只取前 20 项。专辑曲目也固定只取前 50 项。原有列表方法还会把请求失败转为空列表，界面无法区分「暂无内容」与网络故障。

## 设计约定

- 在原有预览方法之外增加类型化分页接口，保留旧调用的兼容性。
- `CatalogPage<T>` 保存原始偏移量、下一页偏移量和可用的总数。偏移量依据服务端原始条目推进，不能依据去重或过滤后的展示数量推进。
- 搜索各类型独立保存续页状态；按 ID 去重只影响展示，不影响服务端游标。
- 全部歌曲不是通过艺人名字做模糊搜索，而是从热门曲目起步，逐页读取作品及其曲目，按艺人 ID 过滤署名。一次加载只推进有限的目录工作，不预先请求所有专辑。
- 「全部」指当前账号、地区与接口可访问的目录，不包含接口未提供或不可用的发行记录；热门歌曲排名不扩展为全目录排名。
- 复用现有主题、曲目菜单与播放上下文，不新增依赖，不更改认证、签名、发布流程。

## 代码位置

- 分页模型：`lib/models/catalog_page.dart`（`CatalogPage`、`SearchPage`、`ArtistTracksCursor`）。
- 数据层：`lib/services/spotify_api_service.dart`（Web API 与分发）、`lib/services/pathfinder/`（Pathfinder 查询与解析）。
- 搜索状态：`lib/providers/spotify_provider.dart`；搜索界面：`lib/ui/screens/search/search_screen.dart`。
- 艺人页入口与二级页面：`lib/ui/screens/detail/artist_detail_screen.dart`、`artist_catalog_screen.dart`、`widgets/artist_catalog_widgets.dart`。
- 回归测试位于 `test/`，新增分页参数均为可选，保持旧调用兼容。

## 复验命令

在仓库根目录执行（Flutter/Dart 使用现有锁定环境）：

```sh
flutter gen-l10n
flutter test --no-pub
flutter analyze --no-pub --no-fatal-infos lib test
flutter build macos --debug --no-pub
git -c core.whitespace=cr-at-eol diff --check
```

构建成功与合成数据测试不代表真实账号的联网目录和 DRM 播放已经验证，发布前仍需真机核对。
