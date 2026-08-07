# M1 远征数据协议与经济决策

> 适用版本：v0.7-expedition-skeleton
>
> 目标：在不重做战斗规则的前提下，建立9层分叉地图、商店、卡牌移除与锻造升级的最小闭环。

本文件冻结M1的数据协议。后续实现可以调整字段的内部表示，但不能改变字段语义或绕过固定种子规则。

---

## 一、范围决策

### M1包含

- 9层固定结构、种子决定内容的分叉地图
- 战斗、精英、事件、商店、锻造、休整、Boss占位节点
- 商店购买卡牌、遗物与移除服务
- 卡牌固定升级路线
- 牌组查看、选择、移除和升级
- 现有战斗、奖励、事件接入地图节点

### M1不包含

- 正式删名者Boss逻辑（M2）
- 6事件/8遗物全部完成（M2/M3）
- 二选一卡牌升级（Demo后候选）
- 真正无限程序生成地图
- 美术地图与路径动画

---

## 二、MapNode协议

`MapNode`是图中一个稳定节点，同时保存该节点的最小运行状态。

```gdscript
class_name MapNode
extends RefCounted

enum NodeType {
    BATTLE,
    ELITE,
    EVENT,
    SHOP,
    FORGE,
    REST,
    BOSS,
}

var id: StringName                  # 稳定唯一ID，例如 d04_01
var node_type: NodeType
var depth: int                      # 1～9
var lane: int                       # 同层从左到右，0起
var connections: Array[StringName]  # 下一层节点ID，不使用数组索引
var enemy_id: StringName            # BATTLE/ELITE/BOSS专用
var event_id: StringName            # EVENT专用
var content_seed: int               # 节点内容的派生种子
var revealed: bool                  # 当前是否可见
var reachable: bool                 # 是否可从当前位置进入
var completed: bool
```

### 字段约束

- `id`生成后永久稳定，存档只引用ID，不引用数组位置。
- `connections`只能指向`depth + 1`，Boss无后继。
- 非对应节点类型的`enemy_id/event_id`必须为空。
- `content_seed`从远征种子、depth、lane派生，不使用全局时间。
- `completed`后不能再次获得节点奖励。

---

## 三、MapGraph协议

```gdscript
class_name MapGraph
extends RefCounted

var seed_value: int
var nodes_by_id: Dictionary         # StringName -> MapNode
var node_ids_by_depth: Dictionary   # int -> Array[StringName]
var start_node_ids: Array[StringName]
var boss_node_id: StringName
```

公共API：

```gdscript
func generate(seed_value: int) -> void
func get_node(node_id: StringName) -> MapNode
func get_nodes_at_depth(depth: int) -> Array[MapNode]
func get_reachable_nodes(current_id: StringName) -> Array[MapNode]
func validate() -> Array[String]
func digest() -> String
```

### M1固定结构

设计文档规定第2、4、6层分叉：

| 层 | 节点 |
| --- | --- |
| 1 | 普通战斗 |
| 2 | 普通战斗 / 事件 |
| 3 | 休整（含奖励/补给语义） |
| 4 | 普通战斗 / 商店 |
| 5 | 事件 |
| 6 | 精英 / 锻造 |
| 7 | 普通战斗 |
| 8 | 休整 |
| 9 | Boss占位 |

分叉层的两个节点都必须可达，下一层允许汇合。节点类型结构固定，敌人、事件、商店库存与奖励由种子决定。

### 生成约束

- 同种子`digest()`完全一致。
- 每个非Boss节点至少有1条后继。
- 每个非起点节点至少有1条前驱。
- 从起点能到Boss。
- 不允许跨层边、自环或孤立节点。
- M1不做真正随机层数与节点数量，避免地图生成成为独立项目。

---

## 四、RunState协议

现有`RunModel`继续作为远征状态真相源，不额外创建职责重复的第二对象；它在M1扩展为以下语义：

```gdscript
var schema_version: int
var seed_value: int
var map_graph: MapGraph
var current_node_id: StringName
var visited_node_ids: Array[StringName]
var available_node_ids: Array[StringName]

var player_hp: int
var player_max_hp: int
var ink_crystals: int
var deck_instances: Array[Dictionary]
var relics: Array[StringName]
var evidence: Array[String]

var shop_remove_count: int
var pending_shop_stock: Dictionary
var pending_node_resolution: Dictionary
```

### 牌组实例协议

```gdscript
{
    &"instance_id": int,       # 整个远征中不复用
    &"card_id": StringName,
    &"upgrade_id": StringName # 空值表示未升级
}
```

奖励、购买、移除、升级、战斗建立牌组都必须按`instance_id`操作。相同`card_id`的两张牌可以有不同升级状态。

### 节点推进协议

1. `enter_node(node_id)`验证节点可达并冻结选择。
2. UI根据`node_type`进入对应模式。
3. 节点规则层完成后调用`complete_current_node()`。
4. 标记节点完成，更新可达节点；奖励只能结算一次。
5. Boss占位在M1只显示“章节终点尚未接入”，不伪装成完整Boss。

---

## 五、CardUpgradeCatalog协议

### M1决策：固定升级路线

M1每张牌只有一个默认升级，验证“改造已有牌”的远征循环。数据结构仍预留多分支：

```gdscript
{
    &"card_id": StringName,
    &"upgrades": [
        {
            &"id": StringName,
            &"title_suffix": "+",
            &"description": String,
            &"modifiers": Dictionary,
            &"enabled_in_m1": bool,
        }
    ]
}
```

M1只启用每张牌`upgrades[0]`；未来增加二选一不改变实例或存档结构。

### 升级原则

- 一张实例只能升级一次。
- 每次只强化一个主要维度：伤害、格挡、费用、超载、封存倒计时或比例。
- 不彻底改变卡牌身份。
- 升级通过CardData字段/修正数据生效，不通过标题字符串判断。
- `CardCatalog.create_card`必须能接收`upgrade_id`并生成正确战斗实例。

19张牌的M1固定升级沿用`design/DEMO_CONTENT_V0.1.md`现有定义。

---

## 六、商店协议与定价理由

### 商店库存

每次进入商店，按节点`content_seed`确定生成：

- 3张不重复卡牌：至少2张普通，至多1张罕见
- 1件遗物（M1可以只从已接线遗物中抽取）
- 1次移除服务

售出项目不补货，离开商店后库存冻结并随节点完成消失。

### 定价

| 项目 | 价格 | 理由 |
| --- | ---: | --- |
| 普通卡 | 35～45 | 约3场普通战收入（3×12=36），需要在立即加强和继续存钱之间选择 |
| 罕见卡 | 65～80 | 约5～6场收入，通常要求跳过普通卡或获得事件墨晶 |
| 遗物 | 130～170 | 正常短路线通常买不起，主要用于事件高额墨晶后的边缘机会；遗物主来源仍是精英 |
| 首次移除 | 75 | 明显高于普通卡，精简牌组是主动投资，不是无脑操作 |
| 后续移除 | 每次+25 | 防止商店把初始牌组快速清空，保持奖励与精简之间的张力 |

### 价格生成

同一商品和同一节点种子价格固定。普通/罕见/遗物在区间内通过节点RNG生成整数价格；不得每次刷新界面重新随机。

### 墨晶收入

M1沿用当前普通战固定12墨晶；精英暂使用30墨晶。M1结束前用远征模拟检查：

- 玩家在第4层商店通常能买1张普通卡，或选择继续攒钱。
- 不通过事件高额收益时，通常买不起遗物。
- 首次移除需要牺牲至少一次卡牌购买机会。

---

## 七、锻造协议

- 每个锻造节点免费升级1张未升级牌。
- 玩家按实例选择，不能只按`card_id`选择。
- 没有可升级牌时允许离开，但节点仍可完成。
- M1不提供二选一；界面显示升级前后差异。

---

## 八、REST节点协议

M1的休整节点提供二选一：

- 恢复最大生命的20%（向下取整，至少1）
- 升级1张未升级牌（与锻造相同，但作为休整机会成本）

第3层可用于补给，第8层用于Boss前准备。玩家也可以不使用并离开。

---

## 九、M1测试清单

### 地图

- 同种子地图digest一致，不同种子至少内容不同
- 9层结构、分叉层、节点类型符合固定表
- 无孤立、跨层、自环，起点可达Boss
- 完成节点后只开放合法后继

### 牌组实例

- 奖励/购买生成唯一实例ID
- 移除只移除指定实例
- 升级只升级指定实例
- 相同card_id实例可有不同升级状态
- 进入战斗后升级效果生效

### 经济

- 同种子商店库存和价格一致
- 买不起时不扣钱、不改库存
- 购买成功只扣一次、库存售罄
- 移除费用75/100/125递增
- 遗物不重复购买

### 流程

- 战斗、奖励、事件、商店、锻造、休整都能完成并返回地图
- 不可达节点无法进入
- 已完成节点无法重复领取
- 固定种子可从第1层推进到第9层Boss占位
