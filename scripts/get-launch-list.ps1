param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("test", "prod")]
    [string]$Env = $(if ($env:RD_ENV) { $env:RD_ENV } else { "prod" }),

    [Parameter(Mandatory = $true)]
    [string]$YearMonth,

    [Parameter(Mandatory = $false)]
    [int]$Page = 1,

    [Parameter(Mandatory = $false)]
    [int]$PageRow = 20
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseUrls = @{
    test = "http://103.234.22.57:8090/zqyl-pm-api"
    prod = "http://172.16.18.30:58184/zqyl-pm-api"
}

$baseUrl = $baseUrls[$Env]
$encodedMonth = [uri]::EscapeDataString($YearMonth)
$uri = "$baseUrl/report/productionSummary/launchList?yearMonth=$encodedMonth&viewType=LAUNCHED&page=$Page&pageRow=$PageRow"

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
$groupsSrc = @()
$grandTotal = $null

if ($rawData -is [System.Array]) {
    $groupsSrc = $rawData
}
elseif ($null -ne $rawData) {
    $groupsSrc = @($rawData.groups)
    if ($null -eq $groupsSrc -or $groupsSrc.Count -eq 0) {
        $groupsSrc = @($rawData.list)
    }
    $grandTotal = $rawData.grandTotal
    if ($null -eq $grandTotal) { $grandTotal = $rawData.total }
}

$resultGroups = @()
$flatList = @()

foreach ($group in $groupsSrc) {
    if ($null -eq $group) { continue }

    # 兼容平铺 item
    if ($null -eq $group.items -and ($group.jiraId -or $group.jiraNo -or $group.projectName)) {
        $processed = [PSCustomObject]@{
            projectId   = $group.projectId
            jiraId      = if ($group.jiraId) { $group.jiraId } else { $group.jiraNo }
            projectName = $group.projectName
            productLine = if ($group.productLineName) { $group.productLineName } else { $group.productLine }
            keyValue    = $group.keyValue
            description = if ($group.projectDescribe) { $group.projectDescribe } else { $group.description }
            windowType  = if ($group.topLineTypeName) { $group.topLineTypeName } else { $group.windowType }
            topLineType = $group.topLineType
            onlineDate  = $group.onlineDate
        }
        $flatList += $processed
        continue
    }

    $processedItems = @()
    $productLine = $group.productLine
    foreach ($item in @($group.items)) {
        if ($null -eq $item) { continue }
        $processed = [PSCustomObject]@{
            projectId   = $item.projectId
            jiraId      = if ($item.jiraId) { $item.jiraId } else { $item.jiraNo }
            projectName = $item.projectName
            productLine = if ($item.productLineName) { $item.productLineName } else { $productLine }
            keyValue    = $item.keyValue
            description = if ($item.projectDescribe) { $item.projectDescribe } else { $item.description }
            windowType  = if ($item.topLineTypeName) { $item.topLineTypeName } else { $item.windowType }
            topLineType = $item.topLineType
            onlineDate  = $item.onlineDate
        }
        $processedItems += $processed
        $flatList += $processed
    }

    $total = $group.total
    if ($null -eq $total) { $total = $processedItems.Count }
    $resultGroups += [PSCustomObject]@{
        productLine = $productLine
        total       = $total
        items       = $processedItems
    }
}

if ($flatList.Count -gt 0 -and $resultGroups.Count -eq 0) {
    $byLine = @{}
    foreach ($item in $flatList) {
        $pl = if ($item.productLine) { $item.productLine } else { "其他" }
        if (-not $byLine.ContainsKey($pl)) { $byLine[$pl] = New-Object System.Collections.ArrayList }
        [void]$byLine[$pl].Add($item)
    }
    foreach ($pl in $byLine.Keys) {
        $items = @($byLine[$pl])
        $resultGroups += [PSCustomObject]@{
            productLine = $pl
            total       = $items.Count
            items       = $items
        }
    }
}

if ($null -eq $grandTotal) {
    $grandTotal = 0
    foreach ($g in $resultGroups) { $grandTotal += [int]$g.total }
}

[PSCustomObject]@{
    yearMonth  = $YearMonth
    page       = $Page
    pageRow    = $PageRow
    grandTotal = $grandTotal
    groups     = $resultGroups
    list       = $flatList
} | ConvertTo-Json -Depth 8
