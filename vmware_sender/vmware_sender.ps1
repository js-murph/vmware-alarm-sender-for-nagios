Param (
    [Switch]$help = $false,
    [Switch]$perf = $false,
    [String]$nrdpurl = $null,
    [String]$nrdptoken = $null,
    [String]$hostname = $null,
    [String]$service = $null,
    [String]$state = $null,
    [String]$output = $null,
    [Int]$activecheck = 0,
    [String]$map = $null
)

Set-StrictMode -Version 2.0

function send_alert_to_nagios([String]$xmlPost, [Hashtable]$hshNagVars) {
   # Generate web transaction 
   $webAgent = New-Object System.Net.WebClient
   $nvcWebData = New-Object System.Collections.Specialized.NameValueCollection
   $nvcWebData.Add('token', $hshNagVars['nrdptoken'])
   $nvcWebData.Add('cmd', 'submitcheck')
   $nvcWebData.Add('XMLDATA', $xmlPost)
   # Commit data to Nagios
   $strWebResponse = $webAgent.UploadValues($hshNagVars['nrdpurl'], 'POST', $nvcWebData)
   # Get response and return to user
   $strReturn = [System.Text.Encoding]::ASCII.GetString($strWebResponse)
   if ($strReturn.Contains("<message>OK</message>")) {
        $strLogContents += "SUCCESS - SCOM checks succesfully sent, NRDP returned: $strReturn`r`n"
        return $true
   } else {
        $strLogContents += "ERROR - SCOM checks failed to send, NRDP returned: $strReturn`r`n"
        return $false
   }
}

function generate_alert_xml([Hashtable]$hshNagVars) {
	# Convert retrieved values into valid XML.
    Add-Type -AssemblyName System.Web
    $hshNagVars['output'] = [System.Web.HttpUtility]::HtmlEncode($hshNagVars['output'])
    $xmlBuilder = "<?xml version='1.0'?>`n<checkresults>"
    $xmlBuilder += "`n`t<checkresult type='service' checktype='" + $hshNagVars['activecheck'] + "'>"
    $xmlBuilder += "`n`t`t<hostname>" + $hshNagVars['hostname'] + "</hostname>"
    $xmlBuilder += "`n`t`t<servicename>" + $hshNagVars['service'] + "</servicename>"
    $xmlBuilder += "`n`t`t<state>" + $hshNagVars['state'] + "</state>"
    $xmlBuilder += "`n`t`t<output>" + $hshNagVars['output'] + "</output>"
    $xmlBuilder += "`n`t</checkresult>"
    $xmlBuilder += "`n</checkresults>"
    return $xmlBuilder
}

function logger([String]$strMessage) {
	# Log information to console and if enabled the log file.
    $dtTime = Get-Date
    $strMessage = $dtTime.ToString() + " " + $strMessage
    Write-Host $strMessage
    if ($hshMainConf['logging']['log_enable'] -eq 1) {
        $strLogFile = $hshMainConf['logging']['log_full_path']
        $strMessage | Out-File $strLogFile -Encoding ascii -Append
    }
}

function log_rotate([Datetime]$dtDate) {
    $strLogObject = Get-Item -LiteralPath $hshMainConf['logging']['log_full_path']
    $strLogDir = $hshMainConf['logging']['log_dir']
    $strLogName = $hshMainConf['logging']['log_name'] 
    $intBacklogs = $hshMainConf['logging']['log_backlogs'] - 1
    $strLogRotate = $hshMainConf['logging']['log_rotate']
    $bRotate = $false
	
	# Determine if we need to rotate the log file or not
    switch ($strLogRotate) {
        "daily" {
            $dtCompareTime = $dtDate.AddDays(-1)
            if ($dtCompareTime.Date -ge $strLogObject.CreationTime.Date) {
                $bRotate = $true
            }
        }
        "weekly" {
            $dtCompareTime = $dtDate.AddDays(-7)
            if ($dtCompareTime.Date -ge $strLogObject.CreationTime.Date) {
                $bRotate = $true
            }
        }
        "monthly" {
            $dtCompareTime = $dtDate.AddMonths(-1)
            if ($dtCompareTime.Date -ge $strLogObject.CreationTime.Date) {
                $bRotate = $true
            }
        }
        default {
            Write-Host "Invalid value: $strLogRotate for log_rotate in configuration file. Unable to continue."
            exit 2
        }
    }

	# If the log files need to be rotated get all of the current backlogs, order them and increment the number
    if ($bRotate) {
        $aryLogs = Get-ChildItem $strLogDir | Where-Object {$_.Name -match "^[0-9]*\-$strLogName"}
        $aryLogs = $aryLogs | sort -Property Name -Descending
        foreach ($strLog in $aryLogs) {
            if ($strLog -match "^[0-9]*\-$strLogName") {
                $strLog = $strLog.ToString()
                $strTempNameParts = $strLog.Split("-")
                $intNewNumber = [int]$strTempNameParts[0] + 1
                if ($intNewNumber -gt $intBacklogs) {
                    $strLogToRemove = $strLogDir + $strLog
                    Remove-Item $strLogToRemove.ToString()
                } else {
                    $strOldLogName = $strLogDir + $strLog
                    $strNewLogName = $strLogDir + $($strLog -replace "^[0-9]*", $intNewNumber)
                    Rename-Item $strOldLogName $strNewLogName
                }
            } else {
                continue 
            }
        }
        
		
        $strBaseLog = $(Get-ChildItem $strLogDir | Where-Object {$_.Name -match "^$strLogName"}).Name
        if (!([String]::IsNullOrEmpty($strBaseLog))) {
            $strNewLogName = $strLogDir + "0-" + $strBaseLog
            $strOldLogName = $strLogDir + $strBaseLog
            Rename-Item $strOldLogName $strNewLogName
        }
    }
}

function import_config([String]$strExecutingPath) {
	# Generate path string for the main configuration file
    $strConfigFile = $strExecutingPath + "vmware_sender.ini"
	
    if (Test-Path $strConfigFile) {
		# Read the contents of the INI file into a hashtable
        $hshIniContents = @{}
        switch -regex -file $strConfigFile {
            "^\[(.+)\]$" {
                $strHeading = $Matches[1]
                $hshIniContents[$strHeading] = @{}
            }
            "(.+?)\s*=\s*(.*)\s*$" {
                $strKey = $Matches[1]
                $strValue = $Matches[2]
                $hshIniContents[$strHeading][$strKey] = $strValue
            }
        }
    } else {
        Write-Host "Unable to find main config file at path: $strConfigFile"
        exit 2
    }

    return $hshIniContents
}

function help {
    $strVersion = "v2.0 b190713"
    $strNRDPVersion = "1.2"
    Write-Host "VMWare alarm sender version: $strVersion for NRDP version: $strNRDPVersion"
    Write-Host "By John Murphy <john.murphy@roshamboot.org>, GNU GPL License"
    Write-Host "Command line usage: ./vmware_sender.ps1 [-nrdpurl <Nagios NRDP Url> -nrdptoken <Nagios NRDP Token> -hostname <hostname> -service <service name> -state <nagios or vmware state> -output <Information> -activecheck <0/1> -map <name>] | [-help]"
    Write-Host @'
-nrdpurl
	The URL used to access the remote NRDP agent. i.e. http://nagiosip/nrdp/
-nrdptoken
	The authentication token used to access the remote NRDP agent.
-hostname
	The name of the host associated with the passive host/service check result. 
-service
	The name of the service associated with thischeck result.
-state
	The state of the service. Valid values are: OK, Green, WARNING, Yellow, CRITICAL, Red, UNKNOWN
-output
	Text output to be sent as the passive check result.
-activecheck
    Used to specify active or passive check, 0 = active, 1 = passive. Defaults to passive.
-map
    Name of the output map to use in the vmware_sender.ini file, for more information read the README
-help
	Display this help text.

'@
    exit 0
}

##########################################
### BEGIN MAIN
##########################################
if ($help) {
    help
}

# Get the executing path of the script to use as the root for finding the main configuration and log directory.
$strExecutingPath = Split-Path $MyInvocation.MyCommand.Path -Parent

if (!("\" -eq $strExecutingPath.Substring($strExecutingPath.Length - 1, 1))) {
    $strExecutingPath = $strExecutingPath + "\"
}

# Import main configuration and ensure configuration is globally accessible
$hshMainConf = import_config($strExecutingPath)
Set-Variable -Name $hshMainConf -Scope Global

if ($hshMainConf['logging']['log_enable'] = 1) {
    if (!("\" -eq $hshMainConf['logging']['log_dir'].Substring($hshMainConf['logging']['log_dir'].Length - 1, 1))) {
        $hshMainConf['logging']['log_dir'] = $hshMainConf['logging']['log_dir'] + "\"
    }
	
	# Determine if full log path provided or relative log path and set accordingly
    $strFallBackLogPath = $strExecutingPath + $hshMainConf['logging']['log_dir']
    if (Test-Path $hshMainConf['logging']['log_dir']) {
        $hshMainConf['logging']['log_full_path'] = $hshMainConf['logging']['log_dir'] + $hshMainConf['logging']['log_name']
    } elseif (Test-Path $strFallBackLogPath) {
        $hshMainConf['logging']['log_dir'] = $strFallBackLogPath
        $hshMainConf['logging']['log_full_path'] = $hshMainConf['logging']['log_dir'] + $hshMainConf['logging']['log_name']
    } else {
        Write-Host "Can't find log directory. Unable to continue."
        exit 2
    }

    $dtStartTime = Get-Date

    $bLogExists = Test-Path $hshMainConf['logging']['log_full_path']
    
	# Rotate log files or create a new one if none exist.
    if($bLogExists) {
        log_rotate($dtStartTime)
    } else {
        Add-Content $hshMainConf['logging']['log_full_path'] ""
        $objNewFile = Get-Item -LiteralPath $hshMainConf['logging']['log_full_path']
        $objNewFile.CreationTime = $dtStartTime
    }
    
    $strLogContents = "`r`n############################################################`r`n"
    $strLogContents += "VMWare sender started at: $dtStartTime`r`n"
    Set-Variable -Name $strLogContents -Scope Global
}

# Initialize values set on the command line
$hshNagVars = @{"hostname" = $hostname; "service" = $service; "state" = $state; "output" = $output; "activecheck" = $activecheck; "nrdpurl" = $nrdpurl; "nrdptoken" = $nrdptoken}

# Determine which variables still need to be set
$aryUnsetNagVars = @()
$hshNagVars.GetEnumerator() | % {
    if ([String]::IsNullOrEmpty($_.Value)) {
        $aryUnsetNagVars += $_.Key
    } else {
        $strLogContents +=  $_.Key + " already set to: " + $_.Value + "`r`n"
    }
}

# Select the specified map otherwise use the default
if (!$map) {
    $strLogContents += "Using default map`r`n"
    $strSenderMap = "map_default"
} else {
    if ($map -Match '^map_') {
        $strSenderMap = $map
    } else {
        $strSenderMap = "map_" + $map
    }
    $strLogContents += "Using map $strSenderMap`r`n"
}

foreach ($strUnsetVar in $aryUnsetNagVars) {
	# Perform some sanity checking to determine if the map and key value pair can be located.
    if (!$hshMainConf.ContainsKey($strSenderMap)) {
        $strLogContents += "Unable to continue, cannot find config heading $strSenderMap`r`n"
        $strLogContents +=  "### END ###`r`n"
        logger($strLogContents)
        exit 2
    } else {
        if (!$hshMainConf[$strSenderMap].ContainsKey($strUnsetVar)) {
            $strLogContents += "Unable to continue, cannot find map for $strUnsetVar under heading $strSenderMap`r`n"
            $strLogContents += "### END ###`r`n"
            logger($strLogContents)
            exit 2
        }
    }
    
    $strNewValue = $hshMainConf[$strSenderMap][$strUnsetVar]
    
	# Resolve any potential environment vars encased in $$.
    if ($strNewValue -Match '\$(\S*)\$') {
        $regPattern = New-Object System.Text.RegularExpressions.Regex('\$\S*\$',[System.Text.RegularExpressions.RegexOptions]::Singleline)
        $aryMatches = $regPattern.Matches($strNewValue)
        
        foreach ($aryMatch in $aryMatches) {
            $aryMatch = $aryMatch -replace "\$",""
            Try {
                $strReplaceVal = (Get-Item env:$aryMatch).Value
            } Catch {
                $strLogContents += "Unable to find environment variable $aryMatch, unable to continue!`r`n"
                logger($strLogContents)
                exit 2
            }
            $strNewValue = $strNewValue.Replace("$" + $aryMatch + "$", $strReplaceVal)  
        }
    }
    
	# Set the final value for the input
    $hshNagVars[$strUnsetVar] = $strNewValue
    $strLogContents += "Setting $strUnsetVar to: $strNewValue`r`n"
}

# Determine if any required vars are still unset and gracefully fail if there are.
$hshNagVars.GetEnumerator() | % {
    if ([String]::IsNullOrEmpty($_.Value)) {
        $strLogContents += "No value set for: " + $_.Key + ". Unable to continue!`r`n"
        $strLogContents += "### END ###`r`n"
        logger($strLogContents)
        exit 2
    }
}

if ($hshMainConf['main']['strip_fqdn'] -eq 1) {
    $hshNagVars['hostname'] = $hshNagVars['hostname'] -replace "\..*$",""
}

# Conver the hostname case if necessary
switch -regex ($hshMainConf['main']['hostname_case']) {
    "lower" {
        $hshNagVars['hostname'] = $hshNagVars['hostname'].ToLower()
    }
    "upper" {
        $hshNagVars['hostname'] = $hshNagVars['hostname'].ToUpper()
    }
    "first-upper" {
        $hshNagVars['hostname'] = $hshNagVars['hostname'].substring(0,1).ToUpper() + $hshNagVars['hostname'].substring(1).ToLower()
    }
    "none" {
        # Do Nothing
    }
    default {
        $strLogContents += "Incorrect option set for hostname_case, doing nothing.`r`n"
    }
}

# Set the Nagios state
switch -regex ($hshNagVars['state']) {
    "Green|Ok|0" {
        $hshNagVars['state'] = 0
    }
    "Yellow|Warning|1" {
        $hshNagVars['state'] = 1
    }
    "Red|Critical|2" {
        $hshNagVars['state'] = 2
    }
    default {
        $hshNagVars['state'] = 3
    }
}

# If perfdata is enabled attempt to work out what (if any) the metric is for the provided input.
if (($perf) -or ($hshMainConf['main']['process_perfdata'] -eq 1)) {
    if ($hshNagVars['output'] -Match '\s([0-9]*)(\%|s|ms|B|[KMT]B|[mMkK]bps)\s?') {
        $strValueMatch = $Matches[1]
        $strUOMMatch = $Matches[2]
        if ($strUOMMatch -Match '[mMkK]bps') {
            $strUOM = "c"
            $strPerfData = " | 'vmw_perf_data'=" + $strValueMatch + $strUOM + ";0;0;0;0"
        } else {
            $strUOM = $strUOMMatch
            $strPerfData = " | 'vmw_perf_data'=" + $strValueMatch + $strUOM + ";0;0;0;0"
        }
        $hshNagVars['output'] += $strPerfData 
        $strLogContents += "Output with perfdata is now:" + $hshNagVars['output'] + "`r`n"
    }
}

# Generate the transaction information and send to Nagios.    
$xmlPost = generate_alert_xml $hshNagVars
send_alert_to_nagios $xmlPost $hshNagVars
$strLogContents += "### END ###`r`n"
logger($strLogContents)

exit 0