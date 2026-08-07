# 断环/ Broken Ring

单人肉鸽牌组构筑游戏原型。Godot 4.7.x + typed GDScript，简体中文优先。

当前处于**规则原型阶段**：数值、机制与文本优先，美术与动画留到最后。界面为纯色、无图片、无动画。

## 快速开始

需要 Godot 4.7.x 标准版（非 .NET 版），无第三方插件、无网络依赖。

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
PROJECT=.

# 导入并检查脚本解析
"$GODOT" --headless --path "$PROJECT" --editor --quit

# 全部规则测试
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_combat.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_run.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_flow.gd
"$GODOT" --headless --path "$PROJECT" --script res://tests/test_chinese_font.gd

# 确定性数值模拟（含平衡阈值断言）
"$GODOT" --headless --path "$PROJECT" --script res://tests/sim_balance.gd

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
| `run_model.gd` | 远征进度、牌组、奖励、事件、遗物 |
| `card_catalog.gd` | 卡牌数据（19种） |
| `enemy_catalog.gd` | 敌人数据（9 种） |
| `rule_engine.gd` | 数值修正管线与遗物 |
| `target_selector.gd` | 统一目标解析 |
| `pending_selection.gd` | 待玩家指定目标的请求 |

三条硬性规则：

1. **一切可修正的数值都必须走 `RuleEngine`**，阶段顺序为
   `BASE → ATTACKER → DEFENDER → RELIC → CLAMP`，同阶段内先加后乘，乘法向下取整。
2. **敌人不得在 `CombatModel` 内写分支**，行为由 `EnemyCatalog` 数据描述。
3. **随机必须走带种子的 `RandomNumberGenerator`**，相同种子必须完整复现。

## 当前内容规模

- 1 名角色：载律者
- 19 种卡牌（4 种初始 + 15 种可获得）
- 9 种敌人（6 个主线节点 + 空名卫士 + 倒读者 + 精英装订刑具）
- 5 个关键词：超载、封存、回响、消逝、缺名
- 9 层固定结构分叉地图 + 1 个独立机制测试场
- 战斗、精英、事件、商店、锻造、休整与Boss占位节点
- 3 个文字事件
- 种子固定的商店库存与价格、卡牌购买、实例移除、固定路线升级
- 2 件已接线遗物，6 件留数据位

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
