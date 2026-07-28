# scripts 目录说明

该目录提供两套等价脚本（PowerShell 和 Python），每个脚本对应一个接口，均支持测试/生产环境切换（默认 `prod`）。

## 环境自动切换（推荐）

PowerShell 脚本优先读取环境变量 `$env:RD_ENV`，设置一次后当前会话所有脚本自动使用对应环境：

```powershell
$env:RD_ENV = "test"   # 切到测试环境
$env:RD_ENV = "prod"   # 切回生产环境（默认）
```

也可以通过 `-Env` 参数单次指定：`-Env test`

## 版本对照

| 脚本 | PowerShell | Python |
|------|-----------|--------|
| 投产概览 | `get-production-overview.ps1` | `get-production-overview.py` |
| 上线清单 | `get-launch-list.ps1` | `get-launch-list.py` |
| 拟上线清单 | `get-key-features.ps1` | `get-key-features.py` |
| 待投产需求 | `get-pending-demands.ps1` | `get-pending-demands.py` |

Python 版仅依赖标准库（无需 pip），PowerShell 版依赖系统内置 `curl.exe`（Windows 10+ 自带）。

---

## 脚本清单

### `get-production-overview.py`

- 作用：查询指定月份的投产概览数据（项目数、功能项数、排期统计）。
- 接口：`/report/productionSummary/overview`
- 参数：
  - `--yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `--viewType`（可选，默认 `LAUNCHED`）：`LAUNCHED`=已上线，`PLANNED`=计划上线
  - `--env`（可选，默认 `prod`）：`test` 或 `prod`
- 用法：
  - `python scripts/get-production-overview.py --yearMonth 2026-07`
  - `python scripts/get-production-overview.py --yearMonth 2026-07 --viewType PLANNED`
  - `python scripts/get-production-overview.py --env test --yearMonth 2026-07 --viewType LAUNCHED`

---

### `get-launch-list.py`

- 作用：查询已上线项目清单（按产品线分组，分页）。
- 接口：`/report/productionSummary/launchList`
- 参数：
  - `--yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `--page`（可选，默认 `1`）：页码
  - `--pageRow`（可选，默认 `20`）：每页条数
  - `--env`（可选，默认 `prod`）：`test` 或 `prod`
- 输出要点：
  - `grandTotal`：已上线项目总数
  - `groups`：按产品线分组（`productLine` / `total` / `items`）
  - `list`：平铺列表
  - 字段映射：`jiraId`←接口 `jiraId`；`description`←`projectDescribe`；`windowType`←`topLineTypeName`；`onlineDate` 多为 `MM.DD` 字符串
- 用法：
  - `python scripts/get-launch-list.py --yearMonth 2026-07`
  - `python scripts/get-launch-list.py --yearMonth 2026-07 --page 2 --pageRow 50`
  - `python scripts/get-launch-list.py --env test --yearMonth 2026-07`

---

### `get-key-features.py`

- 作用：查询拟上线清单（按产品线分组，分页）。
- 接口：`/report/productionSummary/keyFeatures`
- 参数：
  - `--yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `--page`（可选，默认 `1`）：页码
  - `--pageRow`（可选，默认 `20`）：每页条数
  - `--env`（可选，默认 `prod`）：`test` 或 `prod`
- 用法：
  - `python scripts/get-key-features.py --yearMonth 2026-07`
  - `python scripts/get-key-features.py --env test --yearMonth 2026-07 --pageRow 50`

---

### `get-pending-demands.py`

- 作用：查询待投产需求点列表；输出原始分组、7 类归并与数据源分类汇总。
- 接口：`/report/productionSummary/pendingDemands`
- 参数：
  - `--yearMonth`（必填）：月份，格式 `YYYY-MM`
  - `--env`（可选，默认 `prod`）：`test` 或 `prod`
- 输出要点：
  - `grandTotal`：待投产需求总量
  - `groups`：接口原始产品线分组（`productLine` / `total` / `items`）
  - `canonicalGroups`：按固定 7 类（链数、云链证、云信、链信APP、信企直连、基础服务、其他）归并
  - `dataSourceSummary`：`DEMAND` / `NEED_DESIGNING` / `NEED_DESIGNED` / `PROJECT` 及其中文 `label`、`count`
  - `items` 字段：`code`、`name`、`productLine`、`description`、`planOnlineDate`、`reqDepartment`、`dataSource`
- 用法：
  - `python scripts/get-pending-demands.py --yearMonth 2026-07`
  - `python scripts/get-pending-demands.py --env test --yearMonth 2026-07`

---

后续新增脚本请保持"一个脚本一个接口"原则。
