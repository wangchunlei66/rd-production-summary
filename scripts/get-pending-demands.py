import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import timezone, timedelta, datetime

ENVS = {
    "test": "http://172.16.32.110:8090/zqyl-pm-api",
    "prod": "http://172.16.18.30:58184/zqyl-pm-api",
}

CST = timezone(timedelta(hours=8))


def ts_to_date(ts):
    if ts is None:
        return None
    try:
        return datetime.fromtimestamp(int(ts) / 1000, tz=CST).strftime("%Y-%m-%d")
    except Exception:
        return None


def main():
    parser = argparse.ArgumentParser(description="查询待投产需求点列表")
    parser.add_argument("--env", choices=["test", "prod"], default="prod", help="环境（默认 prod）")
    parser.add_argument("--yearMonth", required=True, help="月份，格式 YYYY-MM")
    args = parser.parse_args()

    base_url = ENVS[args.env]
    params = urllib.parse.urlencode({"yearMonth": args.yearMonth})
    url = f"{base_url}/report/productionSummary/pendingDemands?{params}"

    try:
        with urllib.request.urlopen(url, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
    except Exception as e:
        print(f"请求失败: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        response = json.loads(raw)
    except Exception:
        print(f"响应解析失败，原始内容: {raw[:500]}", file=sys.stderr)
        sys.exit(1)

    if response.get("status") != "M0200":
        msg = response.get("msg") or "API 返回非成功状态"
        print(f"API 调用失败: {msg} (status={response.get('status')})", file=sys.stderr)
        sys.exit(1)

    raw_data = response.get("data") or {}

    # 数据可能为分组列表（按产品线）或平铺列表，兼容两种格式
    groups = []
    if isinstance(raw_data, list):
        for group in raw_data:
            if isinstance(group, dict) and "items" in group:
                # 已分组格式
                processed_items = []
                for item in (group.get("items") or []):
                    processed_items.append(
                        {
                            "jiraNo": item.get("jiraNo"),
                            "projectName": item.get("projectName"),
                            "productLine": item.get("productLine"),
                            "description": item.get("description"),
                            "planOnlineTime": item.get("planOnlineTime"),
                            "planOnlineDate": ts_to_date(item.get("planOnlineTime")),
                            "sourceDept": item.get("sourceDept"),
                        }
                    )
                groups.append(
                    {
                        "productLine": group.get("productLine"),
                        "count": group.get("count", len(processed_items)),
                        "items": processed_items,
                    }
                )
            else:
                # 平铺列表，归入"未分组"
                if not groups or groups[-1].get("productLine") != group.get("productLine"):
                    groups.append(
                        {
                            "productLine": group.get("productLine"),
                            "count": 0,
                            "items": [],
                        }
                    )
                groups[-1]["items"].append(
                    {
                        "jiraNo": group.get("jiraNo"),
                        "projectName": group.get("projectName"),
                        "productLine": group.get("productLine"),
                        "description": group.get("description"),
                        "planOnlineTime": group.get("planOnlineTime"),
                        "planOnlineDate": ts_to_date(group.get("planOnlineTime")),
                        "sourceDept": group.get("sourceDept"),
                    }
                )
                groups[-1]["count"] = len(groups[-1]["items"])
    elif isinstance(raw_data, dict):
        # 可能是 { groups: [...] } 或 { list: [...] }
        source = raw_data.get("groups") or raw_data.get("list") or []
        for group in source:
            processed_items = []
            for item in (group.get("items") or []):
                processed_items.append(
                    {
                        "jiraNo": item.get("jiraNo"),
                        "projectName": item.get("projectName"),
                        "productLine": item.get("productLine"),
                        "description": item.get("description"),
                        "planOnlineTime": item.get("planOnlineTime"),
                        "planOnlineDate": ts_to_date(item.get("planOnlineTime")),
                        "sourceDept": item.get("sourceDept"),
                    }
                )
            groups.append(
                {
                    "productLine": group.get("productLine"),
                    "count": group.get("count", len(processed_items)),
                    "items": processed_items,
                }
            )

    total_count = sum(g.get("count", 0) for g in groups)

    result = {
        "yearMonth": args.yearMonth,
        "totalCount": total_count,
        "groups": groups,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
