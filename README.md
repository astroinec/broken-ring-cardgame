# 断环/ Broken Ring

单人肉鸽牌组构筑游戏原型。Godot 4.7.x + typed GDScript，简体中文优先。

当前处于 **v0.9 Demo硬化（M3进行中）**：存档/继续、局外档案与四级解锁、25张正式卡、3种随机地图模板、奖励/商店防重复、8件遗物、界面安全余量、中文文案和键盘取消路径已完成自动审校；M3仅剩真人完整试玩与macOS/Windows导出。数值、机制与文本优先，美术与动画留到最后。

## 快速开始

需要 Godot 4.7.x 标准版（非 .NET 版），无第三方插件、无网络依赖。

macOS 日常游玩最简单的方法：在Finder中双击项目根目录的 `PLAY.command`。首次运行若系统询问是否打开，选择允许即可。也可以用Godot编辑器打开 `project.godot` 后按 `F6/F5`。

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJECT=.

# 导入并检查脚本解析
"$GODOT" --headless --path "$PROJECT" --editor --quit

# 核心规则与流程测试（CI还会运行地图、经济、UI、Boss和六事件专项测试）
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_combat.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_run.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_profile.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_cards_meta.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_save.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_flow.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_boss.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_events.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_relics.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_copy.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_accessibility.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_chinese_font.gd

# 确定性模拟（战斗平衡、远征经济、Boss与完整章节）
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_balance.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_relics.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_chapter.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_unassisted_chapter.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_replayability.gd

# 主场景冒烟
"$GODOT" --headless --path "$PROJECT" --quit-after 8

# 实际游玩
"$GODOT" --path "$PROJECT"
```

CI 在 GitHub Actions 上用固定 Godot 4.7.1 跑同一套命令，见 `.github/workflows/godot-tests.yml`。

## 目录结构

```
scripts/core/     规则层，不得访问场景节点
scripts/ui/       表现层，只读规则状态并派发输入
tests/            无头测试与数值模拟
design/           世界观、玩法与Demo内容设计
assets/fonts/     内置 Noto Sans SC 及 OFL 许可
docs/             协作与数值调整指引
```

## 架构约定

规则层是唯一真相源，UI 不持有任何战斗状态。

| 文件 | 职责 |
| --- | --- |
| `combat_model.gd` | 单场战斗状态与流程 |
| `run_model.gd` | 远征进度、冻结解锁池、牌组、奖励、事件、遗物及schema4存档字典校验 |
| `save_manager.gd` | `user://` 远征存档读写、检查、迁移、摘要与删除 |
| `profile_manager.gd` | 独立局外档案、幂等进度记录与原子替换 |
| `meta_catalog.gd` | U0～U3解锁条件与各层奖励卡池 |
| `card_catalog.gd` | 卡牌数据（25种正式牌） |
| `enemy_catalog.gd` | 敌人数据（9 种） |
| `relic_catalog.gd` | 8件遗物的名称、稀有度、效果、风味与来源 |
| `rule_engine.gd` | 数值修正管线、遗物触发状态与遥测 |
| `target_selector.gd` | 统一目标解析 |
| `pending_selection.gd` | 待玩家指定目标的请求 |

v1远征存档默认写入 `user://broken_ring_run_v1.json`。只保存战斗外节点检查点；进入战斗不会覆盖检查点，节点完整结算后自动保存，Boss结算后自动删除。独立局外档案写入 `user://broken_ring_profile_v1.json`，保留通关次数和U0～U3内容解锁。协议与兼容性规则见 `docs/M3_SAVE_SPEC.md` 与 `docs/M3_REPLAYABILITY_SPEC.md`。

三条硬性规则：

1. **一切可修正的数值都必须走 `RuleEngine`**，阶段顺序为
   `BASE → ATTACKER → DEFENDER → RELIC → CLAMP`，同阶段内先加后乘，乘法向下取整。
2. **敌人不得在 `CombatModel` 内写分支**，行为由 `EnemyCatalog` 数据描述。
3. **随机必须走带种子的 `RandomNumberGenerator`**，相同种子必须完整复现。

## 当前内容规模

- 1 名角色：载律者
- 25 种正式卡牌；7张精简初始牌组，21张奖励牌按U0～U3逐步开放
- 10 种敌人（6 个路径敌人 + 空名卫士 + 倒读者 + 精英装订刑具 + Boss删名者）
- 5 个关键词：超载、封存、回响、消逝、缺名
- 9层远征、3种地图模板和种子化稀疏连线 + 1个独立机制测试场
- 战斗、精英、事件、商店、锻造、休整与正式Boss节点；休整可选恢复生命、升级、搜寻残页或回收墨晶
- 删名者两阶段战斗、可逆卡牌信息删除、终结选择与最小章节结算
- 6 个文字事件、结构化证据档案与旧线索结算回收
- 种子固定的商店库存与价格、卡牌购买、实例移除、固定路线升级
- v1战斗外检查点：标题页继续、摘要、主动删除、损坏/版本不兼容安全降级；Boss结算自动删档
- 独立回收者档案：随机新局、种子复现、四级内容解锁、通关新卡预览和卡牌图鉴
- 8 件遗物全部接线；地图档案可查看稀有度、完整效果、来源与风味，战斗HUD显示本场触发次数
- 精英胜利固定获得30墨晶、1件未持有遗物及至少含1张罕见的三选一卡牌；遗物池取尽后改为50墨晶

## 引导原则

主线**不使用教学关标签**。机制通过地点、环境文字、敌人行为和获得的残页自然出现，每场最多首次引入一个核心关键词。

显式的机制说明只放在标题页的「机制测试场」，它独立于远征，不影响牌组、奖励与剧情。

## 给协作者与AI agent

改动前请先读：

1. `docs/ROADMAP.md`：项目阶段、依赖顺序、里程碑验收门槛与范围边界
2. `docs/BALANCE_AND_CONTRIBUTING.md`：数值口径、已定案决策、当前失衡疑点，以及**不要顺手改掉**的东西

只看代码容易改错方向：很多数字是刻意选的，很多缺口是刻意留的。

## 许可

代码与设计文本尚未选择开源许可，默认保留全部权利。

内置字体 Noto Sans SC 依SIL Open Font License 1.1 分发，许可见 `assets/fonts/OFL-NotoSansSC.txt`。
