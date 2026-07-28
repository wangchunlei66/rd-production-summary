import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import timezone, timedelta, datetime

ENVS = {
    "test": "http://103.234.22.57:8090/zqyl-pm-api",
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
    parser = argparse.ArgumentParser(description="查询投产概览数据")
    parser.add_argument("--env", choices=["test", "prod"], default="prod", help="环境（默认 prod）")
    parser.add_argument("--yearMonth", required=True, help="月份，格式 YYYY-MM")
    parser.add_argument(
        "--viewType",
        choices=["LAUNCHED", "PLANNED"],
        default="LAUNCHED",
        help="LAUNCHED=已上线 PLANNED=计划上线（默认 LAUNCHED）",
    )
    args = parser.parse_args()

    base_url = ENVS[args.env]
    params = urllib.parse.urlencode(
        {"yearMonth": args.yearMonth, "viewType": args.viewType}
    )
    url = f"{base_url}/report/productionSummary/overview?{params}"

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

    data = response.get("data") or {}

    result = {
        "yearMonth": args.yearMonth,
        "viewType": args.viewType,
        "projectCount": data.get("projectCount", 0),
        "featureCount": data.get("featureCount", 0),
        "titleSuffix": data.get("titleSuffix", ""),
        "topLineTypeStats": data.get("topLineTypeStats") or [],
        "dailyDistribution": data.get("dailyDistribution") or [],
        "productLineDistribution": data.get("productLineDistribution") or [],
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
