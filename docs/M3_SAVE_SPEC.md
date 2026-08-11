# M3 v1存档与继续协议

> 存档文件：`user://broken_ring_run_v1.json`
>
> 目标：只保存战斗外远征状态；关闭游戏后可从地图继续，损坏或不兼容存档不得阻止新游戏。

---

## 一、保存边界

M3 v1只允许在**节点完整结算并返回地图后**自动保存。

不保存：

- 战斗中牌堆、手牌、敌人生命和临时Boss删除；
- 未确认的奖励、商店、事件选牌；
- 只完成一半的后续事件战。

理由：战斗中完整快照会绑定大量效果队列和临时状态，容易导致版本升级后存档不可恢复。v1采用“战斗外检查点”，失败或强退后重新进入当前未完成节点。

---

## 二、顶层结构

```json
{
  "save_schema": 1,
  "run_schema": 4,
  "saved_at_unix": 0,
  "run": {}
}
```

Unix时间必须由运行时获得，仅用于显示，不参与规则。

---

## 三、RunModel持久字段

`run`必须包含：

- `seed_value`
- `run_profile_id` / `unlock_tier` / `unlocked_reward_ids`：本局冻结的局外解锁快照
- `run_seen_reward_ids`：奖励与商店防重复状态
- `current_node_id`
- `visited_node_ids`
- `available_node_ids`
- `current_node`
- `player_hp` / `player_max_hp`
- `ink_crystals`
- `deck_instances`：`instance_id/card_id/upgrade_id`
- `next_deck_instance_id`
- `acquired_card_ids`
- `relics`
- `evidence_records`：稳定ID为真相源；旧标题数组由加载时重建
- `completed_node_ids`
- `revealed_node_ids`
- `reward_round`
- `shop_remove_count`
- 下一战修正：缺名、阈值、力量、初始抽牌、奖励遗物
- 远征持续修正：裂解伤害、机构关系、事件历史隐藏、事件历史
- `completed_battles`
- `boss_ending_id` / `boss_ending_text` / `run_completed`

不持久化`pending_*`字段。载入后必须全部清空。

---

## 四、校验与恢复

加载顺序：

1. 解析JSON；
2. 检查`save_schema == 1`；`run_schema=4`直接加载，旧`run_schema=3`迁移为U3旧卡全开放并生成稳定远征标识；旧固定地图按已完成深度投影到同种子新版合法路径；
3. 先以种子重新生成MapGraph；
4. 校验所有节点ID、card_id、upgrade_id、relic_id和evidence_id；
5. 校验牌组实例ID唯一且`next_deck_instance_id`大于所有已有ID；
6. 应用节点完成/揭示状态，再恢复可达节点；
7. 清空全部pending状态；
8. `map_graph.validate()`必须通过。

任一步失败：返回错误，不覆盖内存中的当前run，不自动删除原文件。标题页显示“存档不可用”，仍允许新游戏；用户可点“删除损坏存档”。

---

## 五、写入安全

采用临时文件+替换：

1. 写`broken_ring_run_v1.tmp`；
2. flush并关闭；
3. 用临时文件内容覆盖正式存档；
4. 成功后清理临时文件。

保存失败不影响当前游戏，只显示可追踪错误。

---

## 六、UI

标题页：

- 有有效存档：显示“继续远征”、存档摘要、删除存档；
- 无存档：仅显示开始与机制测试场；
- 损坏/不兼容：显示原因、新游戏与删除存档。

继续后回到地图。Boss结算后自动清除存档，避免继续已结束远征。

---

## 七、测试

- 保存→新RunModel加载，摘要和持久字段一致；
- 地图完成/揭示/可达状态恢复；
- 同卡不同实例升级状态恢复；
- 结构化证据和旧标题数组同步；
- 下一战与远征持续修正恢复；
- pending状态不保存；
- 损坏JSON、不兼容版本、缺字段、未知节点/卡牌/证据、重复实例ID均安全失败；
- 加载失败不改变已有RunModel；
- UI继续按钮和损坏存档提示；
- Boss结算删除存档。
