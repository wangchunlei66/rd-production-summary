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
    parser = argparse.ArgumentParser(description="查询上线清单列表")
    parser.add_argument("--env", choices=["test", "prod"], default="prod", help="环境（默认 prod）")
    parser.add_argument("--yearMonth", required=True, help="月份，格式 YYYY-MM")
    parser.add_argument("--page", type=int, default=1, help="页码（默认 1）")
    parser.add_argument("--pageRow", type=int, default=20, help="每页条数（默认 20）")
    args = parser.parse_args()

    base_url = ENVS[args.env]
    params = urllib.parse.urlencode(
        {
            "yearMonth": args.yearMonth,
            "viewType": "LAUNCHED",
            "page": args.page,
            "pageRow": args.pageRow,
        }
    )
    url = f"{base_url}/report/productionSummary/launchList?{params}"

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
    items = raw_data if isinstance(raw_data, list) else raw_data.get("list") or []
    total = raw_data.get("total") if isinstance(raw_data, dict) else None

    result_items = []
    for item in items:
        result_items.append(
            {
                "jiraNo": item.get("jiraNo"),
                "projectName": item.get("projectName"),
                "productLine": item.get("productLine"),
                "keyValue": item.get("keyValue"),
                "description": item.get("description"),
                "windowType": item.get("windowType"),
                "onlineDate": item.get("onlineDate"),
                "onlineDateYmd": ts_to_date(item.get("onlineDate")),
            }
        )

    result = {
        "yearMonth": args.yearMonth,
        "page": args.page,
        "pageRow": args.pageRow,
        "total": total,
        "list": result_items,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
