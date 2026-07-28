import argparse
import json
import sys
import urllib.parse
import urllib.request

ENVS = {
    "test": "http://172.16.32.110:8090/zqyl-pm-api",
    "prod": "http://172.16.18.30:58184/zqyl-pm-api",
}


def main():
    parser = argparse.ArgumentParser(description="查询拟上线清单")
    parser.add_argument("--env", choices=["test", "prod"], default="prod", help="环境（默认 prod）")
    parser.add_argument("--yearMonth", required=True, help="月份，格式 YYYY-MM")
    parser.add_argument("--page", type=int, default=1, help="页码（默认 1）")
    parser.add_argument("--pageRow", type=int, default=20, help="每页条数（默认 20）")
    args = parser.parse_args()

    base_url = ENVS[args.env]
    params = urllib.parse.urlencode(
        {
            "yearMonth": args.yearMonth,
            "viewType": "PLANNED",
            "page": args.page,
            "pageRow": args.pageRow,
        }
    )
    url = f"{base_url}/report/productionSummary/keyFeatures?{params}"

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
    grand_total = raw_data.get("grandTotal")
    groups = raw_data.get("groups") or []

    result_groups = []
    for group in groups:
        processed_items = []
        for item in group.get("items") or []:
            processed_items.append(
                {
                    "projectId": item.get("projectId"),
                    "jiraId": item.get("jiraId"),
                    "projectName": item.get("projectName"),
                    "keyValue": item.get("keyValue"),
                    "description": item.get("projectDescribe"),
                    "topLineType": item.get("topLineTypeName"),
                    "onlineDate": item.get("onlineDate"),
                }
            )
        result_groups.append(
            {
                "productLine": group.get("productLine"),
                "total": group.get("total"),
                "items": processed_items,
            }
        )

    result = {
        "yearMonth": args.yearMonth,
        "grandTotal": grand_total,
        "groups": result_groups,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
