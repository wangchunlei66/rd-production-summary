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
    test = "http://172.16.32.110:8090/zqyl-pm-api"
    prod = "http://172.16.18.30:58184/zqyl-pm-api"
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

$rawData   = $response.data
$grandTotal = $rawData.grandTotal
$groups    = $rawData.groups

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

[PSCustomObject]@{
    yearMonth  = $YearMonth
    grandTotal = $grandTotal
    groups     = $resultGroups
} | ConvertTo-Json -Depth 8
