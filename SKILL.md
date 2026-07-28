---
name: rd-production-summary
description: 查询研发中心项目投产情况汇报数据，包括已上线项目概览、上线清单列表、拟上线清单、待投产需求点、上个月两项能力分析、业务/基础服务重点功能分析。用户询问"投产情况""上线汇报""已上线项目数""功能项数""待投产需求""拟上线清单""产品线分布""能力分析""重点功能分析"或需要生成月度投产汇报时使用；通过脚本调用接口获取实时数据并作答。
---
# 研发中心项目投产情况汇报 Skill

## 目标
调用研发效能平台接口，获取指定月份的投产汇报实时数据，回答用户对投产情况的查询与汇总诉求；完整月度汇报在出数后基于清单归纳能力分析与重点功能分析。

## 使用边界
1. 量化数据均来自接口实时返回，不依赖静态手册正文。
2. 用户未指定月份时，默认使用当前自然月（格式 `YYYY-MM`）。
3. 环境由脚本内部自动决定，回复中不提及任何环境相关信息。
4. 接口返回非 `M0200` 时，明确告知用户调用失败及错误信息，不编造数据。
5. 完整汇报中的分析模块允许基于接口清单做归纳表述，但必须可追溯到清单字段，禁止无依据编造银行名、功能或数量。

## 目录约定
- 核心规则：`SKILL.md`
- 接口脚本：`scripts/`
- 问答提示词：`prompt/`
- 参考手册：`references/`
- 素材资源：`assets/`

---

## 环境配置

| 环境 | base URL |
|------|----------|
| test | `http://172.16.32.110:8090/zqyl-pm-api` |
| prod | `http://172.16.18.30:58184/zqyl-pm-api` |

切换方式：所有脚本均支持 `--env test` 或 `--env prod`（默认 `prod`）。

---

## 接口一：投产概览

**用途**：查询指定月份的项目数、功能项数、排期项目数（按上线窗口类型分布）。

- 接口地址：`{BASE_URL}/report/productionSummary/overview`
- 请求方式：`GET`
- 参数：
  - `yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `viewType`（必填）：`LAUNCHED`（已上线）或 `PLANNED`（计划上线）
- 返回字段含义：
  - `viewType`：视图类型
  - `titleSuffix`：标题后缀
  - `projectCount`：项目数
  - `featureCount`：功能项数
  - `topLineTypeStats`：上线窗口类型统计列表（含 `typeName`、`count`）
  - `dailyDistribution`：按日期分布
  - `productLineDistribution`：按产品线分布
- 触发规则：
  - 用户询问"上线了多少项目""功能项数""投产概览""汇报数据"时，必须调用此接口。
  - `LAUNCHED` 用于查询已上线，`PLANNED` 用于查询计划上线。

## 接口二：上线清单

**用途**：获取已上线项目的详细列表（分页）。

- 接口地址：`{BASE_URL}/report/productionSummary/launchList`
- 请求方式：`GET`
- 参数：
  - `yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `viewType`：固定为 `LAUNCHED`
  - `page`（可选，默认 `1`）
  - `pageRow`（可选，默认 `20`）
- 返回字段含义：
  - `jiraNo`：项目编号
  - `projectName`：项目名称
  - `productLine`：产品线
  - `keyValue`：键值
  - `description`：项目描述
  - `windowType`：上线窗口类型
  - `onlineDate`：上线日期（时间戳），脚本输出时附加 `onlineDateYmd`（`YYYY-MM-DD`）
- 触发规则：
  - 用户询问"上线清单""已上线项目列表""哪些项目上线了"时调用。

## 接口三：拟上线清单

**用途**：获取计划上线月份的拟上线项目清单（按产品线分组，分页）。

- 接口地址：`{BASE_URL}/report/productionSummary/keyFeatures`
- 请求方式：`GET`
- 参数：
  - `yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `viewType`：固定为 `PLANNED`
  - `page`（可选，默认 `1`）
  - `pageRow`（可选，默认 `20`）
- 返回字段含义：
  - 数据按产品线分组，每组含 `productLine`、`total`、`items`
  - `items` 中每项含：`projectId`、`jiraId`、`projectName`、`keyValue`、`description`、`topLineType`、`onlineDate`
- 触发规则：
  - 用户询问"拟上线清单""计划上线项目列表""下月上线清单"时调用。

## 接口四：待投产需求点

**用途**：获取尚未投产的需求点列表，按产品线分组。

- 接口地址：`{BASE_URL}/report/productionSummary/pendingDemands`
- 请求方式：`GET`
- 参数：
  - `yearMonth`（必填）：月份，格式 `YYYY-MM`
- 返回字段含义：
  - 数据按产品线分组，每组含：
    - `productLine`：产品线名称
    - `count`：待投产总数
    - `items`：需求列表，每项含 `jiraNo`、`projectName`、`productLine`、`description`、`planOnlineTime`（时间戳）、`planOnlineDate`（`YYYY-MM-DD`）、`sourceDept`（需求来源部门）
- 触发规则：
  - 用户询问"待投产需求""待上线需求点""还有多少需求没上线"时调用。

---

## 接口调用方式

提供 PowerShell 和 Python 两套脚本，功能完全等价。

### 环境自动切换（PowerShell 推荐用法）

```powershell
# 会话开始时设置一次，之后所有脚本自动使用测试环境
$env:RD_ENV = "test"

# 切回生产环境
$env:RD_ENV = "prod"
```

### PowerShell 调用示例

- 查询已上线概览（自动读取 `$env:RD_ENV`）：
  `powershell -ExecutionPolicy Bypass -File "scripts/get-production-overview.ps1" -YearMonth 2026-07`

- 单次指定测试环境：
  `powershell -ExecutionPolicy Bypass -File "scripts/get-production-overview.ps1" -Env test -YearMonth 2026-07 -ViewType PLANNED`

- 查询上线清单（第 1 页，每页 20 条）：
  `powershell -ExecutionPolicy Bypass -File "scripts/get-launch-list.ps1" -YearMonth 2026-07 -Page 1 -PageRow 20`

- 查询拟上线清单：
  `powershell -ExecutionPolicy Bypass -File "scripts/get-key-features.ps1" -YearMonth 2026-07`

- 查询待投产需求：
  `powershell -ExecutionPolicy Bypass -File "scripts/get-pending-demands.ps1" -YearMonth 2026-07`

### Python 调用示例（需安装 Python 3）

- 查询已上线概览（生产）：
  `python scripts/get-production-overview.py --yearMonth 2026-07 --viewType LAUNCHED`

- 查询计划上线概览（测试环境）：
  `python scripts/get-production-overview.py --env test --yearMonth 2026-07 --viewType PLANNED`

- 查询上线清单：
  `python scripts/get-launch-list.py --yearMonth 2026-07 --page 1 --pageRow 20`

- 查询拟上线清单：
  `python scripts/get-key-features.py --env test --yearMonth 2026-07`

- 查询待投产需求：
  `python scripts/get-pending-demands.py --yearMonth 2026-07`

---

## 完整汇报分析模块

仅在用户做 **月度投产汇报 / 完整投产数据汇总** 时，在量化数据之后强制输出；单点问数字等可不展开。  
**先列明细，再列分析。** 分析范围按查询意图判定：

| 查询范围 | 输出分析模块 |
|----------|--------------|
| 仅查询本月 | 仅「重点功能分析」 |
| 同时涉及上月以及本月 | 「上个月两项能力分析」+「重点功能分析」 |

| 模块 | 数据来源 | 输出结构 | 何时输出 |
|------|----------|----------|----------|
| 上个月两项能力分析 | 查询月的上个月已上线清单（`get-launch-list`，可选 overview） | 业务场景能力提升、基础服务能力夯实 | 仅当同时涉及上月以及本月 |
| 重点功能分析 | 查询月拟上线清单（`get-key-features`） | 业务重点功能分析、基础服务重点功能分析 | 完整汇报均输出 |

归类与文风见 `prompt/production-summary-qa.prompt.md`；版式见 `references/capability-analysis-template.md`。

完整汇报建议拉数顺序：
1. `overview(LAUNCHED)` 查询月
2. `launchList` 查询月
3. （仅当同时涉及上月以及本月）`overview` / `launchList` 上个月（`prevMonth`）
4. `get-key-features` 查询月
5. 按需 `pendingDemands`

## 执行流程

1. 识别用户意图（概览 / 上线清单 / 拟上线清单 / 待投产需求 / 月度完整汇报）。
2. 确认月份（用户未提供时取当前月，格式归一化为 `YYYY-MM`）；若完整汇报同时涉及上月以及本月，再计算 `prevMonth`。
3. 确认环境（用户未提及时默认 `prod`）。
4. 调用对应脚本，解析 JSON stdout 结果。
5. 以结构化方式展示关键字段，时间戳字段额外展示 `YYYY-MM-DD` 格式。
6. 完整汇报先列明细，再列分析：仅本月 → 只输出重点功能分析；上月以及本月 → 输出能力分析 + 重点功能分析。
7. 接口失败时明确报告错误，不猜测数据。

## 回答格式

单点查询默认结构：
1. 结论（1-2 句汇总）
2. 关键数据（表格或列表）
3. 注意事项（数据时效；不提及环境）

完整汇报输出顺序（先明细，后分析）：
1. 查询月投产概览与分布
2. 上线 / 拟上线 / 待投产等明细（按需）
3. （仅当同时涉及上月以及本月）上个月两项能力分析
   - 业务场景能力提升
   - 基础服务能力夯实
4. 重点功能分析（仅查本月时从本步起输出分析）
   - 业务重点功能分析
   - 基础服务重点功能分析

## 缺失信息处理

接口返回为空或字段缺失时，按以下格式反馈：
- 当前结论：接口返回暂无数据。
- 建议操作：确认月份是否正确，或切换环境后重试。
