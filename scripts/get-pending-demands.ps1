param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("test", "prod")]
    [string]$Env = $(if ($env:RD_ENV) { $env:RD_ENV } else { "prod" }),

    [Parameter(Mandatory = $true)]
    [string]$YearMonth
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseUrls = @{
    test = "http://103.234.22.57:8090/zqyl-pm-api"
    prod = "http://172.16.18.30:58184/zqyl-pm-api"
}

$canonicalOrder = @("链数", "云链证", "云信", "链信APP", "信企直连", "基础服务", "其他")

$dataSourceLabels = [ordered]@{
    DEMAND         = "待投产的需求点"
    NEED_DESIGNING = "产品源设计中"
    NEED_DESIGNED  = "产品源设计完成"
    PROJECT        = "项目数据"
}

function Normalize-ProductLine {
    param([string]$Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return "其他" }
    $name = ($Raw -replace "\s", "")
    if ($name -match "链信" -and ($name -match "APP" -or $name -match "客户端")) {
        return "链信APP"
    }
    foreach ($canonical in @("链数", "云链证", "云信", "链信APP", "信企直连", "基础服务")) {
        if ($name.Contains($canonical) -or $canonical.Contains($name)) {
            return $canonical
        }
    }
    return "其他"
}

$baseUrl = $baseUrls[$Env]
$encodedMonth = [uri]::EscapeDataString($YearMonth)
$uri = "$baseUrl/report/productionSummary/pendingDemands?yearMonth=$encodedMonth"

$tempFile = [System.IO.Path]::GetTempFileName()
try {
    curl.exe --silent --show-error --location --max-time 30 --output "$tempFile" "$uri" | Out-Null
    $curlOutput = Get-Content -Path $tempFile -Raw -Encoding UTF8
}
finally {
    if (Test-Path $tempFile) { Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue }
}

if ([string]::IsNullOrWhiteSpace($curlOutput)) {
    throw "No response from API."
}

try {
    $response = $curlOutput | ConvertFrom-Json
}
catch {
    throw "Failed to parse API response as JSON. Raw response: $curlOutput"
}

if ($null -eq $response) { throw "No response from API." }

if ($response.status -ne "M0200") {
    $msg = if ($response.msg) { $response.msg } else { "API returned non-success status." }
    throw "API call failed: $msg (status=$($response.status))"
}

$rawData = $response.data
$grandTotal = $rawData.grandTotal
$groups = $rawData.groups

$resultGroups = @()
foreach ($group in $groups) {
    $processedItems = @()
    foreach ($item in $group.items) {
        $planOnlineDate = $null
        if ($item.planOnlineDate -and $item.planOnlineDate -ne "") {
            $planOnlineDate = $item.planOnlineDate
        }
        $processedItems += [PSCustomObject]@{
            code           = $item.code
            name           = $item.name
            productLine    = $item.productLine
            description    = $item.description
            planOnlineDate = $planOnlineDate
            reqDepartment  = $item.reqDepartment
            dataSource     = $item.dataSource
        }
    }
    $resultGroups += [PSCustomObject]@{
        productLine = $group.productLine
        total       = $group.total
        items       = $processedItems
    }
}

if ($null -eq $grandTotal) {
    $grandTotal = 0
    foreach ($g in $resultGroups) { $grandTotal += [int]$g.total }
}

$bucketMap = [ordered]@{}
foreach ($name in $canonicalOrder) { $bucketMap[$name] = New-Object System.Collections.ArrayList }

foreach ($group in $resultGroups) {
    $canonical = Normalize-ProductLine $group.productLine
    foreach ($item in $group.items) {
        $enriched = [PSCustomObject]@{
            code                   = $item.code
            name                   = $item.name
            productLine            = $item.productLine
            description            = $item.description
            planOnlineDate         = $item.planOnlineDate
            reqDepartment          = $item.reqDepartment
            dataSource             = $item.dataSource
            canonicalProductLine   = $canonical
        }
        [void]$bucketMap[$canonical].Add($enriched)
    }
}

$canonicalGroups = @()
foreach ($name in $canonicalOrder) {
    $items = @($bucketMap[$name])
    if ($items.Count -eq 0) { continue }
    $canonicalGroups += [PSCustomObject]@{
        productLine = $name
        total       = $items.Count
        items       = $items
    }
}

$dsCounts = @{}
foreach ($code in $dataSourceLabels.Keys) { $dsCounts[$code] = 0 }
foreach ($group in $resultGroups) {
    foreach ($item in $group.items) {
        $code = [string]$item.dataSource
        if ([string]::IsNullOrWhiteSpace($code)) { continue }
        if (-not $dsCounts.ContainsKey($code)) { $dsCounts[$code] = 0 }
        $dsCounts[$code]++
    }
}

$dataSourceSummary = @()
foreach ($code in $dataSourceLabels.Keys) {
    $dataSourceSummary += [PSCustomObject]@{
        code  = $code
        label = $dataSourceLabels[$code]
        count = $dsCounts[$code]
    }
}
foreach ($code in $dsCounts.Keys) {
    if (-not $dataSourceLabels.Contains($code)) {
        $dataSourceSummary += [PSCustomObject]@{
            code  = $code
            label = $code
            count = $dsCounts[$code]
        }
    }
}

[PSCustomObject]@{
    yearMonth          = $YearMonth
    grandTotal         = $grandTotal
    groups             = $resultGroups
    canonicalGroups    = $canonicalGroups
    dataSourceSummary  = $dataSourceSummary
} | ConvertTo-Json -Depth 8
