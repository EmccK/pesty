# Paste 逆向档案

对 `/Applications/Paste.app` 做静态逆向得到的**可复用结论 + 原始证据 + 复现脚本**。
目的是让后续工作不必重跑分析，也不必重看会话记录。

- 建档时间：2026-10-25
- 分析对象：Paste 7.0.2（`CFBundleVersion` 29858846），宿主 macOS 27.0.1 / arm64
- 分析方式：**纯静态**。没有启动 Paste、没有调用它的 MCP server、没有读它的数据库
  （数据库是空的，见「已知未知」）。
- 本目录随仓库入库（`reference/paste-re/`）。仓库是公开的，所以这里**不放 Paste 的
  二进制**（20 MB 的 arm64 切片随时能 `lipo -thin` 重建）。
- 里面有 `artifacts/ghidra-dumps/`：11 个函数的 Ghidra 反编译结果，共约 1.8 万字符
  的 pseudocode，都是 ObjC/Swift 胶水代码，用途是证明卡片流用 NSTableView 池化 cell
  （见「结论四」）。这些是分析笔记，不是可编译的源码。
- 重新生成全部证据只需要一个已安装的 Paste.app 和下面的脚本。

## 指纹

| 对象 | 值 |
| --- | --- |
| `/Applications/Paste.app/Contents/MacOS/Paste` | universal（x86_64 + arm64） |
| thin arm64 slice（`lipo -thin arm64`） | 19,264,576 B |
| arm64 slice sha256 | `40659898a28854154e3bf0db0d9b29dffa539a047aeed90ac43be68b27be46e9` |
| `paste-strings.txt` | `6375a681b97144c87be18262cec81cf4c19c3c54e508da1eb78edb8e9259ddaf` |
| `paste-en.json` | `d345e0fed067f7361afd735335980a8f49f4884f38714cf445f3d8892b5575a6` |
| `paste-zh-Hans.json` | `9bea4adbcb6504cccf9d5d3d7e1aa4cb622ed8c88c1f3433af73e52d807ba2cd` |
| `mcp-strings.txt` | `f7f3e4924d892087e50082f73f90451ad52351cda157ef829f936edc3e179341` |
| `model-dump.txt` | `4f23bb051abeb41d353cf059bf9549fdfd12ad0143d81bb925101c51e0600b16` |
| `paste-v11-mom.xml` | `a7babd1b3068c4cc266ee9d050640da88ea164b675894a53f08500046b28e3b8` |

二进制本身没有归档：`lipo -thin arm64 /Applications/Paste.app/Contents/MacOS/Paste -output /tmp/paste-arm64`
随时能重建，且版本升级后旧二进制也没意义。分析时用的是 `/tmp/paste-arm64`。

`MANIFEST.sha256` 收录了 `artifacts/` 里全部证据文件与模型原件的 sha256，
随时可校验档案没被改动过：

```bash
cd reference/paste-re && shasum -a 256 -c MANIFEST.sha256
```

（首行是 thin arm64 二进制的 digest，需要先 `lipo -thin` 到 `/tmp/paste-arm64` 才能校验通过。）

## 目录

```
MANIFEST.sha256          全档案 sha256 清单（shasum -a 256 -c 可校验）
README.md                本文件
artifacts/
  momd/v5Paste.momd/      Core Data 模型 bundle 原件（v1..v11.mom + v11.omo + VersionInfo.plist）
  paste-v11-mom.xml       v11.mom 转成的可读 XML plist
  model-dump.txt          11 个 .mom 的可读转储（108 段：v1/v7-v11 各 9 实体，v2 十实体，v3-v6 十一实体）
  paste-strings.txt       主二进制的 printable strings（53,801 行）
  paste-syms.txt          nm 导出的符号表
  paste-demangled.txt     swift-demangle 后的符号
  paste-en.json           en.lproj/Localizable.strings → 扁平 JSON（533 键）
  paste-zh-Hans.json      zh-Hans.lproj → 扁平 JSON（533 键）
  mcp-strings.txt         paste-mcp-stdio 助手的 strings（357 行，工具描述原文）
  ghidra-dumps/           11 个函数的 Ghidra dossier JSON（Paste Stack 表格，含 pseudocode）
    dump.sh               重跑这批 dump 的脚本（含地址表）
scripts/
  dump_model.py           .mom → 可读文本（实体/属性/关系/唯一约束/索引）
  extract_paste_strings.py 从 .app 重新提取本地化 JSON + strings
  swtype.py swclass.py swmeta*.py swfield*.py swiftypes.py swiftmeta.py
                          __swift5_types / 字段描述符的裸解析（见下）
  objc.py objc2.py        __objc_classlist / __objc_methname 解析
  mom_parse.py momdump.py momparse.py idx.py rel.py uniq.py
                          模型解析的早期版本，保留以说明推导路径
  extract_types.py fieldmd.py fd2.py fd3.py fd4.py fixup*.py cls*.py
                          同上，逐步修 bug 的中间版本
tools/
  clk.swift wincount.swift frames.swift measure.sh latency.py
                          测量面板几何 / 合成点击 / 逐帧抓图的小工具
```

`scripts/` 里有很多同名变体（`swmeta` / `swmeta2` / `swmeta3` …）。这是逐步调对偏移量
留下的中间产物；**能跑出结果的是 `dump_model.py`、`extract_paste_strings.py`、
`swfield3.py`、`objc2.py`**，其余只当推导记录看。

## 复现

```bash
cd reference/paste-re

# 1. Core Data 模型（不需要二进制，读 .app 里的 .momd）
python3 scripts/dump_model.py artifacts/momd/v5Paste.momd/v11.mom

# 2. 本地化 + strings（读 .app，重写 artifacts/*.json 与 *-strings.txt）
python3 scripts/extract_paste_strings.py --app /Applications/Paste.app --out /tmp/re-verify

# 3. 二进制切片 + 符号
lipo -thin arm64 /Applications/Paste.app/Contents/MacOS/Paste -output /tmp/paste-arm64
nm /tmp/paste-arm64 | awk '{print $NF}' | sed 's/^_//' | grep '^\$s' | sort -u > /tmp/syms.txt
xcrun swift-demangle --simplified < /tmp/syms.txt > /tmp/demangled.txt

# 4. 顶栏 Swift 字段名（脚本里写死了文件偏移，换版本必须重算）
python3 scripts/swfield3.py     # 需要 /tmp/paste-arm64 存在
```

`model-dump.txt` 是 `python3 scripts/dump_model.py artifacts/momd/v5Paste.momd/v*.mom`
一次跑完 11 个版本得到的。注意 shell glob 按字典序展开（v1, v10, v11, v2, v3 …），
要逐字节复现 digest 就得用这个顺序，不要手写 `v1 v2 … v11`。

**已验证可复现（2026-10-25 实跑）**：`dump_model.py` 重跑结果 sha256 与
`model-dump.txt` 相同；上面的 `nm` 管道与 `xcrun swift-demangle --simplified`
分别复现 `paste-syms.txt`（4,566 行）与 `paste-demangled.txt`；
`extract_paste_strings.py` 重跑出的
`paste-en.json` / `paste-zh-Hans.json` / `paste-strings.txt` / `mcp-strings.txt`
四个文件 sha256 全部与 `artifacts/` 里的相同。所以这套档案是**能自证的**，
不用信任我当时的输出。

`swfield3.py` 里硬编码了 `0x100d8be28` / `0x100d8bfb0` / `0x100d8cdf4` / `0x100d8b254`
四个字段描述符地址，**这些是 7.0.2 arm64 的地址**，Paste 升级后必须重新定位。
（定位方法：在 `__swift5_types` 里按类名找 descriptor，字段描述符紧随其后。）

## 结论一：数据模型 = 一条内容一条记录

来源：`artifacts/model-dump.txt`（v11 段），可直接用 `dump_model.py` 复核。

Paste 用 Core Data，最新模型 v11 有 9 个实体。v3–v6 曾有 11 个 —— 多出来的
`ChangeToken` 与 `ObjectChange` 是同步用的变更追踪实体，后来被去掉。
跟剪贴板内容相关的是三个：

```
ItemEntity     identifier / checksum / timestamp(Date?) / rawType / title(String?)
               createdAt / updatedAt / displayOrderInPinboard / rawPreview(Binary?)
               rel data              -> ItemDataEntity   to-one, Cascade
               rel sourceApplication -> ApplicationEntity to-one, optional, Nullify
               rel list              -> ListEntity        to-one, optional, Nullify
               rel device            -> DeviceEntity      to-one, optional, Nullify
               UNIQUE [identifier]    INDEX byChecksum[checksum], byIdentifier
ItemDataEntity rawPasteboardItems(Binary)   rel item -> ItemEntity, Nullify
ListEntity     identifier / name / rawType(Int64) / rawAttributes / rawShareRecord
               rel items    -> ItemEntity        to-many, Nullify
               rel metadata -> ListMetadataEntity to-one, Cascade
               UNIQUE [identifier]
```

关键点：

1. **一条内容只有一条 `ItemEntity`**，`checksum` 上有索引（非唯一），去重是应用层
   按 checksum 查的，不是数据库约束。`V9LegacyDuplicateCleanup`（`paste-strings.txt:48043`）说明 v9
   迁移时专门清理过历史重复数据，进一步印证去重归应用层。
2. `list` 是 **to-one、optional、Nullify**。一条 item 最多属于一个列表。
3. `timestamp` 是 **optional**。它不是「创建时间」（另有 `createdAt`），语义见下。
4. `displayOrderInPinboard` 是 Item 自己的字段，不是 List 里的数组下标 ——
   固定板内排序不靠关系顺序。
5. v7 已经有完全相同的字段与关系，v11 才加上 `NSUniqueTuples`。→ 「一条内容一条记录」
   的结构从 v7 起就稳定。

`ListEntity.rawType` 区分 clipboard / pinboard。字符串池里 `clipboard` / `pinboard`
两个 case 名存在（`paste-strings.txt:14135-14136`），但**具体 raw 数值无法从字符串表
确定**，属于未知。

## 结论二：固定 = 叠加指向，条目仍留在历史

来源：`artifacts/paste-strings.txt:48730-48800`，Paste 自带 MCP server 的工具描述原文
（`create_item` 在 :48738，`delete_item` 在 :48749，`delete_pinboard` 在 :48755-48757）。
这是本档案里最强的语义证据 —— 它比模型更能说明「用户可见行为」。

- `create_item`：*"Without `list_id` it is added to clipboard history… With `list_id`
  … it is pinned to that pinboard: **if the same content is already in history the
  existing item is pinned (and stays in history)**, otherwise a new pinned-only item
  is created that is not added to history."*
- `create_item`：*"`timestamp` is absent when the item is pinned to a pinboard only
  (not in history)."*
- `delete_pinboard`：*"**Pinned items stay in clipboard history.**"*
- `remove_item_from_pinboard`：*"The item stays in clipboard history if it was there;
  only the pinning is removed."*
- `add_item_to_pinboard`：*"Idempotent — adding the same item twice keeps it pinned once."*
- `delete_item`：*"Delete a saved item entirely and irreversibly — from clipboard
  history **and** the pinboard it's pinned to, removing the underlying record for good.
  … To only unpin an item while keeping it, use remove_item_from_pinboard."*
- `search`：*"`timestamp` is when the item entered clipboard history (ISO-8601),
  absent for pinned-only items"*；可按 `pinboard_id` / `type` / `app` / `device` /
  `title` / `date_from` / `date_to` 过滤，最多 100 条，newest first。

由此得出三条可实现的规则：

| 动作 | 语义 |
| --- | --- |
| 固定 | 给既有记录加 `list` 指向，**记录仍在历史里**，历史里照样能看到 |
| 取消固定 | 只清 `list`，记录不动 |
| 删除条目 | 记录整条消失，历史与固定板同时看不到 |
| 删除固定板 | 板消失，**板内条目回落到历史**，不删记录 |

`timestamp` 的作用也清楚了：它标记「这条进过历史」。pinned-only 的条目
（从没进过历史，只由 MCP 直接创建到板上）没有 `timestamp`。

配套的本地化键（`paste-en.json`）：`general.action.unpin = "Unpin"`、
`general.clipboard-history = "Clipboard History"`、`general.pinboards = "Pinboards"`、
`alert.delete-pinboard.text = "The Pinboard and all its content will be deleted.
This action cannot be undone."`、`empty-state.pinboard = "Pinboard is empty"`、
`search.filters.section.pinboard = "Pinboard"`。

## 结论三：顶栏结构（SwiftUI + 少量 AppKit）

来源：`__swift5_types` 类型描述符 + 字段描述符裸解析（`scripts/swfield3.py`）。
这是**字段名级**证据，不是反编译出来的实现。

```
Toolbar    (16 字段) viewModel / picksProvider / picksTurnOff / isPicksOffered /
                     $__lazy_storage_$_searchBar / $_tabBar / $_createPinboardButton /
                     $_menuButton / picksIcon / $_picksButton / $_picksMenu /
                     $_notificationBar / $_indicatorsAfterPicks /
                     $_indicatorsAtLeadingEdge / activeSearchConstraints
SearchBar  (12 字段) isActive / onActivate / onDismiss / onResignKey /
                     inputCoordinator / viewModel / cancellables / suggestionsTask /
                     filterSuggestionsMenu / filterBrowserPopover / $_searchButton
SearchField(13 字段) onShowFilters / onTextShouldChange / onSelectionChange /
                     onEndEditing / onEnter / onCancel / onClear / onUndo / onRedo /
                     canAcceptFocus / $_searchIconView / $_inputView
TabBar     (10 字段) isCollapsed / $_scrollView / $_stackView / viewModel /
                     cancellables / applier / _previousPinboardShortcut /
                     _nextPinboardShortcut / isSearchActive
```

`__objc_methname` 里的选择器补上了行为侧证据：
`$_searchButton`、`$_compactWidthConstraint`、`$_iconWidthConstraint`、
`activeSearchConstraints`、`onWidthChange`、`onEditingWidthChange`、
`isSearchActive`、`setAnimates:`、`animatesDifferences`、`searchResetTimer`、
`pendingFocus`、`$_pinboards`、`$_pinboardViewTrailingConstraint`、
`$_labelsStackViewTrailingConstraint`、`collapsedItemLimit`、`isCollapsed`、
`setCanCollapse:`。

组合起来能确定的：搜索态是**约束组切换 + 宽度动画**（`activeSearchConstraints` /
`compactWidthConstraint` / `onWidthChange` / `animatesDifferences`），失焦后由
`searchResetTimer` 延迟收起，搜索时 TabBar 进入 `isCollapsed` 把标签折成点。
**不能确定**的：具体动画时长、曲线、`collapsedItemLimit` 的数值。

视觉尺寸是从截图量的（Paste 真截图 5120×704 @2x）：选中 source 胶囊 154×28 pt；
展开搜索框约 470.5×39.5 pt（含焦点环），填充 RGB(228,228,228)，占位符 RGB(123,123,123)；
整排是居中簇：放大镜 → 各来源标签 → 加号，右侧只有省略号。

## 结论四：Paste Stack（卡片流）用 NSTableView

来源：`artifacts/ghidra-dumps/` 的 11 个函数 + 符号表。

`PasteStackWindow` / `PasteStackWindowController` / `PasteStackTableView` /
`PasteStackSnippetCell` 这套命名，加上 `numberOfRowsInTableView:`、
`viewForTableColumn:row:`、`rowActionsForRow:edge:`、`shouldSelectRow:`、
`toggleStackDirection` 这些选择器，说明卡片流是 **NSTableView + 池化 cell**，
不是 SwiftUI 列表。这解释了它滚动为什么稳：同一批 NSView 反复改数据。

`__viewDidLoad_body`（`0x100089108`）里能看到先 `objc_msgSendSuper2(..., "viewDidLoad")`
再装配子视图的顺序。

注意：Ghidra 12.1.4 在 Paste 这个镜像上做**全量分析会超时**（`Ghidra startup
deadline elapsed`），且 `Exception: Unsupported Objective C type encoding: T`。
这批 dump 是侥幸跑出来的局部结果，不要指望批量反编译。

## 已知未知

- `ListEntity.rawType` 的具体数值（clipboard=?, pinboard=?）。字符串表只能给出 case 名。
- checksum 的算法。`~/Library/Group Containers/4788TTJ39Y.com.wiheads.paste-group`
  与 `group.com.wiheads.paste` 都是空目录，全盘 `~/Library` 下没有 `*paste*.sqlite`，
  没有真实数据可对照。
- 顶栏动画的具体时长/曲线/`collapsedItemLimit` 数值。
- MCP server 的完整 JSON Schema（只从 strings 里拿到描述文本）。
- Ghidra 对 Paste 的全量分析（不可行，见上）。

## 陷阱

- `.mom` 是 NSKeyedArchiver 的二进制 plist。`NSClassNameForEntity` 的值是 UID，
  要先 `plistlib` 的 `UID` 转成对象再取 `.data` 解出文本，否则拿到的是数字。
  `NSIndexName` 同理。
- Paste 的 `Localizable.strings` 是 UTF-16 但 XML 声明写 `encoding="UTF-8"`，
  `plistlib.load` 会抛 `ExpatError: encoding specified in XML declaration is incorrect`。
  `extract_paste_strings.py` 里做了 BOM / `<\x00` 嗅探转码后再 `plistlib.loads`。
- `--languages` 决定输出文件名（`paste-<lang>.json`），zh-Hans 就是
  `paste-zh-Hans.json`。
- **主二进制必须先 `lipo -thin arm64` 再 `strings`**。直接对 fat 文件跑 `strings -a`
  得到 220,205 行，与存档的 53,801 行对不上；只有 arm64 slice 才复现
  `6375a681…` 这个 digest。`extract_paste_strings.py` 已内置这一步。
- `paste-mcp-stdio` 是另一个单架构二进制，不需要 thin。
- `swift-demangle` 要带 `--simplified`，且走 `xcrun`。裸 `swift-demangle < file`
  会静默输出空文件（exit 0），很容易以为符号表有问题。
- `swfield3.py` 的四个地址是硬编码的 7.0.2 偏移。

## Pesty 侧的对应实现

这份档案被用来指导 Pesty 的以下改造：

| 结论 | Pesty 落点 |
| --- | --- |
| 一条内容一条记录 | `Sources/Pesty/Store/ClipboardStore.swift` 的 `private(set) var items: [ClipItem]` 是唯一真表 |
| 固定 = 叠加指向 | `ClipItem.list: UUID?` + `pinnedAt: Date?`；`saveToPinboard` 改 list 不复制；`removeFromPinboard` 清 list |
| 删板 = 回落历史 | `ClipboardStore.deletePinboard` 只把该板条目的 `list`/`pinnedAt` 置 nil |
| 删条目 = 删记录 | `ClipboardStore.delete` 统一从 `items` 移除并 push undo |
| 历史含已固定条目 | `var history: [ClipItem] { items }`（不再按 list 过滤） |
| 顶栏居中簇 + 胶囊 | `Sources/Pesty/UI/PinboardTabs.swift` |
| 搜索 = 宽度动画 + 约束切换 | `Sources/Pesty/UI/BarView.swift` 的 `searchField` |
| 搜索时标签折成点 | `PinboardTabs(collapsed:)` |
| 卡片流池化 | 仍是 SwiftUI `LazyHStack`（未照搬 NSTableView，见 CHANGELOG 的性能说明） |
