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
    test = "http://172.16.32.110:8090/zqyl-pm-api"
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
$items   = if ($rawData -is [System.Array]) { $rawData } else { $rawData.groups }
$total   = if ($rawData.grandTotal) { $rawData.grandTotal } else { $null }

$result = @()
foreach ($group in $items) {
    foreach ($item in $group.items) {
        $result += [PSCustomObject]@{
            productLine   = $group.productLine
            jiraId        = $item.jiraId
            projectName   = $item.projectName
            keyValue      = $item.keyValue
            description   = $item.projectDescribe
            windowType    = $item.topLineTypeName
            onlineDate    = $item.onlineDate
        }
    }
}

[PSCustomObject]@{
    yearMonth = $YearMonth
    page      = $Page
    pageRow   = $PageRow
    total     = $total
    list      = $result
} | ConvertTo-Json -Depth 6
