import argparse
import json
import sys
import urllib.parse
import urllib.request
from collections import OrderedDict

ENVS = {
    "test": "http://103.234.22.57:8090/zqyl-pm-api",
    "prod": "http://172.16.18.30:58184/zqyl-pm-api",
}

CANONICAL_PRODUCT_LINES = (
    "链数",
    "云链证",
    "云信",
    "链信APP",
    "信企直连",
    "基础服务",
    "其他",
)

DATA_SOURCE_LABELS = OrderedDict(
    [
        ("DEMAND", "待投产的需求点"),
        ("NEED_DESIGNING", "产品源设计中"),
        ("NEED_DESIGNED", "产品源设计完成"),
        ("PROJECT", "项目数据"),
    ]
)


def normalize_product_line(raw):
    if raw is None:
        return "其他"
    name = "".join(str(raw).split())
    if not name:
        return "其他"
    if "链信" in name and ("APP" in name.upper() or "客户端" in name):
        return "链信APP"
    for canonical in CANONICAL_PRODUCT_LINES[:-1]:
        if canonical in name or name in canonical:
            return canonical
    return "其他"


def process_item(item):
    return {
        "code": item.get("code") or item.get("jiraNo"),
        "name": item.get("name") or item.get("projectName"),
        "productLine": item.get("productLine"),
        "description": item.get("description"),
        "planOnlineDate": item.get("planOnlineDate") or None,
        "reqDepartment": item.get("reqDepartment") or item.get("sourceDept"),
        "dataSource": item.get("dataSource"),
    }


def extract_groups(raw_data):
    groups = []
    if isinstance(raw_data, list):
        for group in raw_data:
            if isinstance(group, dict) and "items" in group:
                items = [process_item(it) for it in (group.get("items") or [])]
                groups.append(
                    {
                        "productLine": group.get("productLine"),
                        "total": group.get("total", group.get("count", len(items))),
                        "items": items,
                    }
                )
            elif isinstance(group, dict):
                pl = group.get("productLine")
                if not groups or groups[-1].get("productLine") != pl:
                    groups.append({"productLine": pl, "total": 0, "items": []})
                groups[-1]["items"].append(process_item(group))
                groups[-1]["total"] = len(groups[-1]["items"])
    elif isinstance(raw_data, dict):
        source = raw_data.get("groups") or raw_data.get("list") or []
        for group in source:
            items = [process_item(it) for it in (group.get("items") or [])]
            groups.append(
                {
                    "productLine": group.get("productLine"),
                    "total": group.get("total", group.get("count", len(items))),
                    "items": items,
                }
            )
    return groups


def build_canonical_groups(groups):
    buckets = OrderedDict((name, []) for name in CANONICAL_PRODUCT_LINES)
    for group in groups:
        canonical = normalize_product_line(group.get("productLine"))
        for item in group.get("items") or []:
            enriched = dict(item)
            enriched["canonicalProductLine"] = canonical
            buckets[canonical].append(enriched)
    result = []
    for name, items in buckets.items():
        if not items:
            continue
        result.append(
            {
                "productLine": name,
                "total": len(items),
                "items": items,
            }
        )
    return result


def build_data_source_summary(groups):
    counts = {code: 0 for code in DATA_SOURCE_LABELS}
    for group in groups:
        for item in group.get("items") or []:
            code = item.get("dataSource")
            if code in counts:
                counts[code] += 1
            elif code:
                counts.setdefault(code, 0)
                counts[code] += 1
    summary = []
    for code, label in DATA_SOURCE_LABELS.items():
        summary.append({"code": code, "label": label, "count": counts.get(code, 0)})
    for code, count in counts.items():
        if code not in DATA_SOURCE_LABELS:
            summary.append({"code": code, "label": code, "count": count})
    return summary


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
    groups = extract_groups(raw_data)
    groups_sum = sum(g.get("total", 0) for g in groups)
    grand_total = (
        raw_data.get("grandTotal")
        if isinstance(raw_data, dict) and raw_data.get("grandTotal") is not None
        else groups_sum
    )
    canonical_groups = build_canonical_groups(groups)
    data_source_summary = build_data_source_summary(groups)

    result = {
        "yearMonth": args.yearMonth,
        "grandTotal": grand_total,
        "groups": groups,
        "canonicalGroups": canonical_groups,
        "dataSourceSummary": data_source_summary,
    }

    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
