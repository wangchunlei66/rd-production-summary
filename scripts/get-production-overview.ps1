param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("test", "prod")]
    [string]$Env = $(if ($env:RD_ENV) { $env:RD_ENV } else { "prod" }),

    [Parameter(Mandatory = $true)]
    [string]$YearMonth,

    [Parameter(Mandatory = $false)]
    [ValidateSet("LAUNCHED", "PLANNED")]
    [string]$ViewType = "LAUNCHED"
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$baseUrls = @{
    test = "http://172.16.32.110:8090/zqyl-pm-api"
    prod = "http://172.16.18.30:58184/zqyl-pm-api"
}

$baseUrl = $baseUrls[$Env]
$encodedMonth = [uri]::EscapeDataString($YearMonth)
$encodedView  = [uri]::EscapeDataString($ViewType)
$uri = "$baseUrl/report/productionSummary/overview?yearMonth=$encodedMonth&viewType=$encodedView"

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

$d = $response.data

[PSCustomObject]@{
    yearMonth               = $YearMonth
    viewType                = $ViewType
    projectCount            = $d.projectCount
    featureCount            = $d.featureCount
    titleSuffix             = $d.titleSuffix
    topLineTypeStats        = $d.topLineTypeStats
    dailyDistribution       = $d.dailyDistribution
    productLineDistribution = $d.productLineDistribution
} | ConvertTo-Json -Depth 6
