# UI 设计审查与改进记录

审查依据：Apple HIG（Dynamic Type / 分组列表 / 触控目标 / 减弱动态效果）+ `ui-ux-pro-max-skill` 的
`references/pro-rules.md`（原生移动端交付检查表）与 `styles.csv` 的 **Liquid Glass** 条目
（玻璃只用于导航与控件，内容层保持独立，尊重减弱透明度与减弱动态效果）。

## 一、审查发现的问题

### 设计与一致性

| # | 问题 | 后果 |
| --- | --- | --- |
| 1 | 字号是散落的 10/10.5/11.5/12/12.5/13/13.5/14/14.5/15/15.5/16/16.5/17/19/20/23/26/28/30/48 | 没有 Dynamic Type 层级，页面之间不统一，观感"手工" |
| 2 | 间距随手取 4/5/6/8/10/12/14/16/18/20/24/28 | 没有 4pt 节奏，分组关系读不出来 |
| 3 | 圆角混用 11/12/14/18/20/23/26/28/30/32 | 同级元素半径不同，像拼接 |
| 4 | 设置页只有"卡片 + 行"，没有分组标题层级、行间分隔与前置图形 | 不像系统设置，扫描成本高 |
| 5 | 首页所有操作权重相同（一个主按钮 + 三个同级文字按钮），统计卡数字 48pt 抢占视觉 | 主次不清 |
| 6 | 筛选/状态使用**强调色实心 chip**，一屏出现多个藏青块 | 主题色滥用，且和主按钮争夺视觉焦点 |
| 7 | 记录详情、登记表单的行直接铺在背景上，没有分组容器；备注输入框是纯黑方块 | 表单看起来未完成 |
| 8 | 历史时间戳直接显示 `2026-10-18T03:25:52.167536Z` | 数据噪声直接暴露给用户 |
| 9 | 列表行有的有箭头、有的同时有箭头和"…"，同一行两个操作暗示 | 交互歧义 |
| 10 | 日历格用 `GestureDetector`，按下无反馈；导航切换无触觉反馈 | 缺少 Apple 的按压/触觉反馈 |
| 11 | 顶部渐变标题栏未拦截点击，滚到下面的内容可能被"隔空"点中 | 误触 |

### 功能

| # | 问题 | 根因 |
| --- | --- | --- |
| 12 | 自研底部面板无法拉起软键盘 | `showGeneralDialog` 不会请求它自己的 `FocusScope`，`TextField(autofocus: true)` 拿不到 primary focus，因此不发起 IME 请求；另外面板未随键盘 inset 动画上移 |
| 13 | 面板内容在键盘弹出后可能被遮挡 | 面板没有 `AnimatedPadding(viewInsets)`，长表单也不能滚动 |
| 14 | 点面板空白处不能收键盘 | 缺少"点背景收键盘"的 iOS  habit |

## 二、本次落地的改动

### 1. 设计令牌（`lib/core/theme/design_tokens.dart`）

- `AppType`：Large Title 34 / Title3 20 / Headline·Body 17 / Callout 16 / Subhead 15 / Footnote 13 / Caption 12/11，并提供 `pageTitle / navTitle / sectionTitle / groupLabel / rowTitle / rowDetail / button / sheetTitle / sheetOption / metric / message` 组合样式。
- `Gap`：4 / 8 / 12 / 16 / 24 / 32。
- `Radii`：sheet 28 > card 20 > control 14 > field 12 > badge 9。
- `Sizes`：touch 44、row 48、cta 50、badge 30、icon 20、chevron 15。

全应用的标题、行、按钮、面板、日历字号与间距均改为引用令牌，删除散落数值。

### 2. 组件层

- `SettingRow`：44pt 最小高度、可选前置 `IconBadge`、标题 17 / 说明 13（最多两行省略）、单一尾部动作。
- `SettingsGroup` / `GroupLabel`：iOS 分组卡片 + 组标题 + 内缩分隔线（有前置图形时线从文字处开始）。
- `IconBadge`：30pt 圆角方块，14% 底色 + 同色图标，用于设置与首页"管理"分组。
- `SegmentedControl`：系统分段控件（中性轨道 + 浮起药丸 + 180ms 过渡），替换统计/请假/通知模板的实心 chip，藏青只留给主按钮。
- `PrimaryButton`：50pt 高、14 圆角、17 semibold、深藏青填充。
- `EmptyState`：增加单一操作入口，替换"空图标 + 文字 + 漂浮文字按钮"。

### 3. 页面

- 首页：概览卡压缩（数字 34pt）、主按钮 + 三个等宽快捷操作卡、`今日记录`/`管理` 两个区块（20pt 区块标题）、管理项使用图形徽标行。
- 设置：分组标题 + 分组卡 + 发丝分隔线 + 彩色图形徽标，作为 Apple 设置式信息架构的入口。
- 记录：搜索框 + 筛选圆钮同一行工具栏，结果数改为脚注，日期分组用组标题 + 人数。
- 记录详情：字段、审计历史、危险操作各自成组；时间戳格式化为 `2026-10-18 03:25`。
- 登记表单：字段分组、备注输入框改为填充式圆角输入域、清空时间改为行内次级操作、状态用状态药丸。
- 人员管理：主按钮 + 次级"导入" + 文字级"批量编辑"，避免三个同级按钮挤在一行。

### 4. 底部面板与键盘（问题 12–14）

```dart
Flexible(child: FocusScope(autofocus: true, child: child)),   // 让对话框路由拥有可聚焦的 scope
...
AnimatedPadding(duration: 180ms, padding: EdgeInsets.only(bottom: viewInsets.bottom), ...)
```
- 输入面板改为持有 `FocusNode`，在首帧后 `requestFocus()`，确保 IME 被真正请求；
- 面板高度上限 88%，内容可滚动，键盘弹出时整体上移而不是被遮住；
- 点面板背景收起键盘（不影响内部按钮）。

真机验证：`dumpsys input_method` 显示 `mShowRequested=true / mInputShown=true`，且
`mServedInputConnection` 绑定到 FlutterView，说明应用侧已正确发起输入请求。
（该测试机的输入法被配置为不显示软键盘，页面级搜索框同样不弹出，属于设备侧设置。）

### 5. 交互细节

- 日历格改用 `CupertinoButton`，按下有透明度反馈；
- 底部导航切换触发 `HapticFeedback.selectionClick()`；
- 顶部标题栏整条吸收点击，只有动作按钮可交互；
- 卡片按下统一使用 0.55–0.6 的 opacity 反馈，不改布局尺寸。

## 三、键盘与面板抖动（问题 12–14 的最终结论）

原因分两层，必须分开看：

1. **应用层**：`showGeneralDialog` 的页内容在 `pageBuilder` 里，输入框若在面板入场动画期间就 `autofocus`，
   IME 的 inset 会在面板还在滑动时到来，形成两段同时进行的位移——这就是"面板拉起时抖动"；
   而过早请求焦点或焦点被内部 `FocusScope` 抢走时，输入框拿不到 primary focus，IME 请求根本不会发出。
2. **设备层**：测试机的 Fcitx5 输入法处于"只剩候选条"的坏状态。
   证据：`dumpsys window windows` 中 InputMethod 窗口存在，但 `mGivenContentInsets=[0,2260]`（内容区仅 44px）；
   在同一台机器的**系统文件选择器搜索框**里同样不弹键盘；`adb shell ime disable/enable/set` 复位后立刻恢复。

对应修改：

```dart
showGeneralDialog(..., requestFocus: true);          // 路由必须显式请求焦点
// 面板入场 260ms 结束后（300ms）才挂载输入框，占位块保持同高避免位移
Future.delayed(const Duration(milliseconds: 300), () => setState(() => ready = true));
CupertinoTextField(focusNode: focusNode, autofocus: true, ...);
// 面板随 viewInsets 动画上移；点面板空白收键盘
AnimatedPadding(padding: EdgeInsets.only(bottom: viewInsets.bottom), ...);
```

真机结果（复位输入法后）：面板随键盘上移、输入框获得焦点、可直接输入并保存，截图见
`screenshots/final_keyboard.png`。若用户设备上仍然不弹，先按下文"设备侧排查"复位输入法。

### 设备侧排查（不弹键盘时）

```bash
adb shell dumpsys window windows | grep -A9 InputMethod   # 看 mGivenContentInsets
adb shell ime disable <ime-id> && adb shell ime enable <ime-id> && adb shell ime set <ime-id>
```

## 四、检查表结论（pro-rules.md）

- 触控目标：全部 ≥44pt（圆钮 44、行 48、主按钮 50）。
- 文字对比度：主文本 `label`、次文本 `secondaryLabel` 均满足 4.5:1；分隔线在深浅色下都有 8% 明暗对比。
- 深浅色：两套主题分别截图核对，`#101010` 背景 + 藏青强调色。
- 安全区：标题栏、底部胶囊、面板均处理了 `MediaQuery.padding`。
- 减弱动态/无障碍导航：玻璃自动降级为不透明，动画使用 180–260ms 的 easeOut。
- 触觉与按压反馈：导航切换、日历、按钮均已覆盖。

## 五、仍待改进（下一轮）

1. 大标题随滚动收缩为 17pt 导航标题（目前大/紧凑两档切换，没有连续过渡）。
2. 首页"今日记录"支持左滑快捷编辑/删除（需配合撤销 toast）。
3. 统计页图表化（类型分布目前是条形，可升级为环形/柱状）。
4. Dynamic Type 最大档位下的布局回归测试。

## 首次引导与隐私政策

- 网关：`needsOnboarding(store)` 在 `onboarded != true` 或 `policyVersion != kPolicyVersion` 时把 `home` 换成 `OnboardingPage`；完成后写 `settings['onboarded']` 与 `settings['policyVersion']`，随 SQLite 持久化，重启不再出现。
- 引导四页：数据在本机 / 每日登记 / 请假与考勤锁 / 可选云同步；最后一页必须勾选「我已阅读并同意《隐私政策》」，链接直接打开全文。
- 文案与政策在 `lib/core/config/legal_text.dart`，用现有 `MarkdownView` 渲染。注意该渲染器**不支持 Markdown 表格**，权限说明等结构化内容请用列表表达。
- 设置 → 关于 增加「使用指南」「隐私政策」两个入口，政策行展示当前版本号。
- 测试：`test/onboarding_test.dart` 覆盖首次展示、未勾选不能进入、勾选后进入主界面、跳过也记录版本、政策升级后重新询问、两类正文可渲染。
## 人员选择与关于页（本轮）

- 请假等单选人员场景统一走 `showPersonPickerSheet`（`lib/core/widgets/person_picker.dart`）：面板顶部带搜索框，按姓名或工号过滤，支持 `disabledIds` 置灰、`selectedId` 回显勾选。考勤批量登记仍用带性别筛选的整页选择器。
- 设置 → 关于 增加 GitHub / Gitee 仓库两行，链接来自 `UpdateDefaults`，点击打开 `showLinkSheet`（复制链接 / 系统分享）。不引入 url_launcher：企业分发与内网环境里 ACTION_VIEW 经常被 ROM 拦截，复制+分享更稳。
- 测试：`test/picker_about_test.dart` 覆盖搜索过滤（姓名、工号、无结果）、输入框聚焦后弹出键盘、关于页仓库行与链接面板。