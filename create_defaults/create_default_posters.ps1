################################################################################
# create_default_poster.ps1
# Date: 2023-05-12
# Version: 3.1
# Author: bullmoose20
#
# DESCRIPTION: 
# This script contains ten functions that are used to create various types of posters. The functions are:
# CreateAudioLanguage, CreateAwards, CreateChart, CreateCountry, CreateDecade, CreateGenre, CreatePlaylist, CreateSubtitleLanguage, CreateUniverse, CreateYear, and CreateOverlays.
# The script can be called by providing the name of the functionor aliases you want to run as a command-line argument.
# AudioLanguage, Awards, Based, Charts, ContentRating, Country, Decades, Franchise, Genres, Network, Playlist, Resolution, Streaming,
# Studio, Seasonal, Separators, SubtitleLanguages, Universe, Years, All
#
# REQUIREMENTS:
# Imagemagick must be installed - https://imagemagick.org/script/download.php
# font must be installed on system and visible by Imagemagick. Make sure that you install the ttf font for ALL users as an admin so ImageMagick has access to the font when running (r-click on font Install for ALL Users in Windows)
# Powershell security settings: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-7.2
#
# multi-lingual font that supports arabic - Cairo-Regular
#
# EXAMPLES:
# You can run the script by providing the name of the function you want to run as a command-line argument:
# create_default_posters.ps1 AudioLanguage 
# This will run only the CreateAudioLanguage function.
# You can also provide multiple function names as command-line arguments:
# create_default_posters.ps1 AudioLanguage Playlist Chart
# This will run CreateAudioLanguage, CreatePlaylist, and CreateChart functions in that order.
# Finally just running the script with All will run all of the functions
# create_default_posters.ps1 All
################################################################################

#################################
# GLOBAL VARS
#################################
$global:font_flag = $null
$global:magick = $null
$global:ConfigObj = $null
$global:Config = $null

#################################
# collect paths
#################################
$script_path = $PSScriptRoot
Set-Location $script_path
$scriptName = $MyInvocation.MyCommand.Name
$scriptLogPath = Join-Path $script_path -ChildPath "logs"
$scriptLog = Join-Path $scriptLogPath -ChildPath "$scriptName.log"
$databasePath = Join-Path $script_path -ChildPath "OptimalPointSizeCache.db"

################################################################################
# Function: New-SQLCache
# Description: creates a sqlcache file
################################################################################
Function New-SQLCache {
    # Import the required .NET assemblies
    Add-Type -Path "System.Data.SQLite.dll"

    # Define the SQLite table name
    $tableName = "Cache"

    # Create a SQLite connection and command objects
    $connection = New-Object System.Data.SQLite.SQLiteConnection "Data Source=$databasePath"
    $command = New-Object System.Data.SQLite.SQLiteCommand($connection)

    # Create the Cache table if it does not already exist
    $command.CommandText = @"
    CREATE TABLE IF NOT EXISTS $tableName (
        CacheKey TEXT PRIMARY KEY,
        PointSize INTEGER NOT NULL
    );
"@
    $connection.Open()
    $command.ExecuteNonQuery()
    $connection.Close()
}

################################################################################
# Function: Import-YamlModule
# Description: installs module if its not there
################################################################################
Function Import-YamlModule {
    # Check if PowerShell-YAML module is installed
    if (!(Get-Module -Name PowerShell-YAML -ListAvailable)) {
        # If not installed, install the module
        Install-Module -Name PowerShell-YAML -Scope CurrentUser -Force
    }

    # Import the module
    Import-Module -Name PowerShell-YAML
}

################################################################################
# Function: Update-LogFile
# Description: Rotates logs up to 10
################################################################################
Function Update-LogFile {
    param (
        [string]$LogPath
    )

    if (Test-Path $LogPath) {
        # Check if the last log file exists and delete it if it does
        $lastLog = Join-Path $scriptLogPath -ChildPath "$scriptName.10.log"
        if (Test-Path $lastLog) {
            Remove-Item $lastLog -Force
        }

        # Rename existing log files
        for ($i = 9; $i -ge 1; $i--) {
            $prevLog = Join-Path $scriptLogPath -ChildPath "$scriptName.$('{0:d2}' -f $i).log"
            $newLog = Join-Path $scriptLogPath -ChildPath "$scriptName.$('{0:d2}' -f ($i+1)).log"
            if (Test-Path $prevLog) {
                Rename-Item $prevLog -NewName $newLog -Force
            }
        }

        # Rename current log file
        $newLog = Join-Path $scriptLogPath -ChildPath "$scriptName.01.log"
        Rename-Item $LogPath -NewName $newLog -Force
    }
}

################################################################################
# Function: InstallFontsIfNeeded
# Description: Determines if font is installed and if not, exits script
################################################################################
Function InstallFontsIfNeeded {
    $fontNames = @(
        "Comfortaa-Medium", 
        "Bebas-Regular",
        "Rye-Regular", 
        "Limelight-Regular", 
        "BoecklinsUniverse", 
        "UnifrakturCook", 
        "Trochut", 
        "Righteous", 
        "Yesteryear", 
        "Cherry-Cream-Soda-Regular", 
        "Boogaloo-Regular", 
        "Monoton", 
        "Press-Start-2P", 
        "Jura-Bold", 
        "Special-Elite-Regular", 
        "Barlow-Regular", 
        "Helvetica-Bold"
    )
    $missingFonts = $fontNames | Where-Object { !(magick identify -list font | Select-String "Font: $_$") }
    
    if ($missingFonts) {
        $fontList = magick identify -list font | Select-String "Font: " | ForEach-Object { $_.ToString().Trim().Substring(6) }
        $fontList | Out-File -Encoding utf8 -FilePath "magick_fonts.txt"
        WriteToLogFile "Fonts Check [ERROR]          : Fonts missing $($missingFonts -join ', ') are not installed/found. List of installed fonts that Imagemagick can use listed and exported here: magick_fonts.txt."
        WriteToLogFile "Fonts Check [ERROR]          : $($fontList.Count) fonts are visible to Imagemagick."
        WriteToLogFile "Fonts Check [ERROR]          : Please right-click 'Install for all users' on each font file in the $script_path\fonts folder before retrying."
        return $false
    }
    return $true
}

################################################################################
# Function: Remove-Folders
# Description: Removes folders to start fresh run
################################################################################
Function Remove-Folders {
    $folders = "audio_language", "award", "based", "chart", "content_rating", "country",
    "decade", "defaults-$LanguageCode", "franchise", "genre", "network", "playlist", "resolution",
    "seasonal", "separators", "streaming", "studio", "subtitle_language",
    "translations", "universe", "year"
    
    foreach ($folder in $folders) {
        $path = Join-Path $script_path $folder
        Remove-Item $path -Force -Recurse -ErrorAction SilentlyContinue
    }
}

################################################################################
# Function: Test-ImageMagick
# Description: Determines version of ImageMagick installed
################################################################################
Function Test-ImageMagick {
    $global:magick = $global:magick
    $global:magick = magick -version | select-string "Version:"
}

################################################################################
# Function: WriteToLogFile
# Description: Writes to a log file with timestamp
################################################################################
Function WriteToLogFile ($message) {
    Add-content $scriptLog -value ((Get-Date).ToString() + " ~ " + $message)
    Write-Host ((Get-Date).ToString() + " ~ " + $message)
}

################################################################################
# Function: Find-Path
# Description: Determines if path exists and if not, creates it
################################################################################
Function Find-Path ($sub) {
    if (!(Test-Path $sub -ErrorAction SilentlyContinue)) {
        WriteToLogFile "Creating path                : $sub"
        New-Item $sub -ItemType Directory | Out-Null
    }
}

################################################################################
# Function: Compare-FileChecksum
# Description: validates checksum of files
################################################################################
Function Compare-FileChecksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedChecksum,

        [Parameter(Mandatory = $true)]
        [ref]$failFlag
    )

    $actualChecksum = Get-FileHash $Path -Algorithm SHA256 | Select-Object -ExpandProperty Hash

    $output = [PSCustomObject]@{
        Path             = $Path
        ExpectedChecksum = $ExpectedChecksum
        ActualChecksum   = $actualChecksum
        Status           = $status
        failFlag         = $failFlag
    }

    $status = if ($actualChecksum -eq $ExpectedChecksum) {
        "Success"
        WriteToLogFile "Checksum verification        : Success for file $($output.Path). Expected checksum: $($output.ExpectedChecksum), actual checksum: $($output.ActualChecksum)."
    }
    else {
        $failFlag.Value = $true
        "Failed"
        WriteToLogFile "Checksum verification [ERROR]: Failed for file $($output.Path). Expected checksum: $($output.ExpectedChecksum), actual checksum: $($output.ActualChecksum)."
    }

    return $output
}

################################################################################
# Function: Get-TranslationFile
# Description: gets the language yml file from github
################################################################################
Function Get-TranslationFile {
    param(
        [string]$LanguageCode,
        [string]$BranchOption = "nightly"
    )

    $BranchOptions = @("master", "develop", "nightly")
    if ($BranchOptions -notcontains $BranchOption) {
        Write-Error "Error: Invalid branch option."
        return
    }

    # $GitHubRepository = "https://raw.githubusercontent.com/meisnate12/Plex-Meta-Manager/$BranchOption/defaults/translations"
    $GitHubRepository = "https://raw.githubusercontent.com/meisnate12/PMM-Translations/master/defaults"
    $TranslationFile = "$LanguageCode.yml"
    $TranslationFileUrl = "$GitHubRepository/$TranslationFile"
    $TranslationsPath = Join-Path $script_path "@translations"
    $TranslationFilePath = Join-Path $TranslationsPath $TranslationFile

    Find-Path $TranslationsPath

    try {
        $response = Invoke-WebRequest -Uri $TranslationFileUrl -Method Head
        if ($response.StatusCode -eq 404) {
            Write-Error "Error: Translation file not found."
            return
        }

        Invoke-WebRequest -Uri $TranslationFileUrl -OutFile $TranslationFilePath
        if ((Get-Content $TranslationFilePath).Length -eq 0) {
            throw "Error: Translation file is empty."
        }
    }
    catch {
        Write-Error $_
        return
    }
  
    Write-Output "Translation file downloaded to $TranslationFilePath"
}

################################################################################
# Function: Read-Yaml
# Description: read in yaml file for use
################################################################################
Function Read-Yaml {
    $global:Config = Get-Content $TranslationFilePath -Raw
    $global:ConfigObj = $global:Config | ConvertFrom-Yaml
}

################################################################################
# Function: Get-YamlPropertyValue
# Description: searches the yaml
################################################################################
Function Get-YamlPropertyValue {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PropertyPath,
        
        [Parameter(Mandatory = $true)]
        [object]$ConfigObject,
        
        [Parameter()]
        [ValidateSet("Exact", "Upper", "Lower")]
        [string]$CaseSensitivity = "Exact"
    )
    
    $value = $ConfigObject
    foreach ($path in $PropertyPath.Split(".")) {
        if ($value.ContainsKey($path)) {
            $value = $value.$path
        }
        else {
            Write-Output "TRANSLATION NOT FOUND"
            WriteToLogFile "TranslatedValue [ERROR]      : ${path}: TRANSLATION NOT FOUND in $TranslationFilePath"
            return
        }
    }
    
    switch ($CaseSensitivity) {
        "Exact" { break }
        "Upper" { $value = $value.ToUpper() }
        "Lower" { $value = $value.ToLower() }
    }
    WriteToLogFile "TranslatedValue              : ${path}: $value in $TranslationFilePath"
    return $value
}

################################################################################
# Function: Set-TextBetweenDelimiters
# Description: replaces <<something>> with a string
################################################################################
Function Set-TextBetweenDelimiters {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputString,

        [Parameter(Mandatory = $true)]
        [string]$ReplacementString
    )

    $outputString = $InputString -replace '<<.*?>>', $ReplacementString

    return $outputString
}


################################################################################
# Function: New-SqliteTable
# Description: Function to create a new SQLite table
################################################################################
Function New-SqliteTable {
    param(
        [string]$Database,
        [string]$Table,
        [string[]]$Columns,
        [string]$PrimaryKey
    )

    # Construct CREATE TABLE statement
    $sql = "CREATE TABLE IF NOT EXISTS $Table ("

    # Add column definitions
    foreach ($column in $Columns) {
        $sql += "$column, "
    }

    # Add primary key definition
    if ($PrimaryKey) {
        $sql += "PRIMARY KEY ($PrimaryKey)"
    }
    else {
        $sql = $sql.TrimEnd(", ")
    }

    $sql += ")"

    # Create table in database
    $connection = New-Object System.Data.SQLite.SQLiteConnection "Data Source=$Database"
    $connection.Open()

    $command = $connection.CreateCommand()
    $command.CommandText = $sql
    $command.ExecuteNonQuery()

    $connection.Close()
}

################################################################################
# Function: Get-SqliteData
# Description: Function to get data from a SQLite database
################################################################################
Function Get-SqliteData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = "Data Source=$Path"

    try {
        $connection.Open()
        $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
        $result = $command.ExecuteScalar()
        return $result
    }
    catch {
        throw $_
    }
    finally {
        $connection.Close()
    }
}

################################################################################
# Function: Set-SqliteData
# Description: Function to set data in a SQLite database
################################################################################
Function Set-SqliteData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = "Data Source=$Path"

    try {
        $connection.Open()
        $command = New-Object System.Data.SQLite.SQLiteCommand($Query, $connection)
        $command.ExecuteNonQuery()
    }
    catch {
        throw $_
    }
    finally {
        $connection.Close()
    }
}

################################################################################
# Function: Get-OptimalPointSize
# Description: Gets the optimal pointsize for a phrase
################################################################################
Function Get-OptimalPointSize {
    param(
        [string]$text,
        [string]$font,
        [int]$box_width,
        [int]$box_height,
        [int]$min_pointsize,
        [int]$max_pointsize
    )

    # Create SQLite cache table if it doesn't exist
    if (-not (Test-Path $databasePath)) {
        $null = New-SqliteTable -Path $databasePath -Table 'Cache' -Columns 'CacheKey', 'PointSize'
    }

    # Generate cache key
    $cache_key = "{0}-{1}-{2}-{3}-{4}-{5}" -f $text, $font, $box_width, $box_height, $min_pointsize, $max_pointsize

    if ($IsWindows) {
        # Windows-specific escape characters
        $escaped_cache_key = [System.Management.Automation.WildcardPattern]::Escape($cache_key)

        # Escape single quotes (')
        $escaped_cache_key = $escaped_cache_key -replace "'", "''"
    }
    else {
        # Unix-specific escape characters (No clue what to put here)
        $escaped_cache_key = $escaped_cache_key -replace "'", "''"
    }

    # Check if cache contains the key and return cached result if available
    $cached_pointsize = (Get-SqliteData -Path $databasePath -Query "SELECT PointSize FROM Cache WHERE CacheKey = '$escaped_cache_key'")
    if ($null -ne $cached_pointsize) {
        WriteToLogFile "Cache                        : Cache hit for key '$cache_key'"
        return $cached_pointsize
    }

    # Prepare command to get optimal point size
    # Escape special characters
    if ($IsWindows) {
        # Windows-specific escape characters
        $escaped_text = [System.Management.Automation.WildcardPattern]::Escape($text)
        $escaped_font = [System.Management.Automation.WildcardPattern]::Escape($font)

        # Escape single quotes (')
        $escaped_text = $escaped_text -replace "'", "''"
        $escaped_font = $escaped_font -replace "'", "''"
    }
    else {
        # Unix-specific escape characters (No clue what to put here)
        $escaped_text = $escaped_text -replace "'", "''"
        $escaped_font = $escaped_font -replace "'", "''"
    }

    $cmd = "magick -size ${box_width}x${box_height} -font `"$escaped_font`" -gravity center -fill black caption:`'$escaped_text`' -format `"%[caption:pointsize]`" info:"

    # Execute command and get point size
    $current_pointsize = [int](Invoke-Expression $cmd | Out-String).Trim()
    WriteToLogFile "Caption point size           : $current_pointsize"

    # Apply point size limits
    if ($current_pointsize -gt $max_pointsize) {
        WriteToLogFile "Optimal Point Size           : Font size limit reached"
        $current_pointsize = $max_pointsize
    }
    elseif ($current_pointsize -lt $min_pointsize) {
        WriteToLogFile "Optimal Point Size ERROR     : Text is too small and will be truncated"
        $current_pointsize = $min_pointsize
    }

    # Update cache with new result
    $null = Set-SqliteData -Path $databasePath -Query "INSERT OR REPLACE INTO Cache (CacheKey, PointSize) VALUES ('$escaped_cache_key', $current_pointsize)"
    WriteToLogFile "Optimal Point Size           : $current_pointsize"

    # Return optimal point size
    return $current_pointsize
}

################################################################################
# Function: EncodeIt
# Description:  base64 string encode
################################################################################
Function EncodeIt ($cmd) {
    $encodedCommand = $null
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($cmd)
    $encodedCommand = [Convert]::ToBase64String($bytes)
    return $encodedCommand
}

################################################################################
# Function: Wait-ForProcesses
# Description:  Tracks processses so you know what was launched
################################################################################
Function Wait-ForProcesses {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [int[]]$ProcessIds
    )

    foreach ($id in $ProcessIds) {
        $process = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($process) {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while ($process.Responding) {
                if ($stopwatch.Elapsed.TotalMinutes -gt 5) {
                    Write-Warning "Process $id has exceeded the maximum wait time of 5 minutes and will be terminated"
                    WriteToLogFile "Process Timeout              : Process $id has exceeded the maximum wait time of 5 minutes and will be terminated"
                    $process.Kill()
                    break
                }
                Start-Sleep -Seconds 1
                $process = Get-Process -Id $id -ErrorAction SilentlyContinue
            }
        }
    }
}

################################################################################
# Function: LaunchScripts
# Description:  Launches the scripts
################################################################################
Function LaunchScripts {
    param (
        [Parameter(Mandatory = $true)]
        [string[]]$ScriptPaths
    )

    $batchSize = 10
    $scriptCount = $ScriptPaths.Count

    for ($i = 0; $i -lt $scriptCount; $i += $batchSize) {
        $batch = $ScriptPaths[$i..($i + $batchSize - 1)]
        $processes = @()
        foreach ($scriptPath in $batch) {
            $encodedCommand = EncodeIt $scriptPath 
            WriteToLogFile "Unencoded                    : $scriptPath"
            WriteToLogFile "Encoded                      : $encodedCommand"
            # $process = Start-Process -NoNewWindow -FilePath "pwsh.exe" -ArgumentList "-noexit -encodedCommand $encodedCommand" -PassThru
            $process = Start-Process -NoNewWindow -FilePath "pwsh.exe" -ArgumentList "-encodedCommand $encodedCommand" -PassThru
            $processes += $process
        }
        Wait-ForProcesses -ProcessIds ( $processes | Select-Object -ExpandProperty Id)
    }
}

################################################################################
# Function: MoveFiles
# Description: Moves Folder and Files to final location
################################################################################
Function MoveFiles {
    # $defaultsPath = Join-Path $script_path -ChildPath "defaults"

    $foldersToMove = @(
        "audio_language"
        "award"
        "based"
        "chart"
        "content_rating"
        "country"
        "decade"
        "franchise"
        "genre"
        "network"
        "resolution"
        "playlist"
        "seasonal"
        "separators"
        "streaming"
        "studio"
        "subtitle_language"
        "universe"
        "year"
    )

    $filesToMove = @(
        "collectionless.jpg"
    )

    foreach ($folder in $foldersToMove) {
        Move-Item -Path (Join-Path $script_path -ChildPath $folder) -Destination $DefaultsPath -Force -ErrorAction SilentlyContinue
    }

    foreach ($file in $filesToMove) {
        Move-Item -Path (Join-Path $script_path -ChildPath $file) -Destination $DefaultsPath -Force -ErrorAction SilentlyContinue
    }
}

################################################################################
# Function: CreateAudioLanguage
# Description:  Creates audio language
################################################################################
Function CreateAudioLanguage {
    Write-Host "Creating Audio Language"
    Set-Location $script_path
    # Find-Path "$script_path\audio_language"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'audio_language_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $pre_value = Get-YamlPropertyValue -PropertyPath "collections.audio_language.name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'ABKHAZIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ab| #88F678| 1| 1| 0| 1',
        'AFAR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | aa| #612A1C| 1| 1| 0| 1',
        'AFRIKAANS| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | af| #60EC40| 1| 1| 0| 1',
        'AKAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ak| #021FBC| 1| 1| 0| 1',
        'ALBANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sq| #C5F277| 1| 1| 0| 1',
        'AMHARIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | am| #746BC8| 1| 1| 0| 1',
        'ARABIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ar| #37C768| 1| 1| 0| 1',
        'ARAGONESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | an| #4619FD| 1| 1| 0| 1',
        'ARMENIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hy| #5F26E3| 1| 1| 0| 1',
        'ASSAMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | as| #615C3B| 1| 1| 0| 1',
        'AVARIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | av| #2BCE4A| 1| 1| 0| 1',
        'AVESTAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ae| #CF6EEA| 1| 1| 0| 1',
        'AYMARA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ay| #3D5D3B| 1| 1| 0| 1',
        'AZERBAIJANI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | az| #A48C7A| 1| 1| 0| 1',
        'BAMBARA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bm| #C12E3D| 1| 1| 0| 1',
        'BASHKIR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ba| #ECD14A| 1| 1| 0| 1',
        'BASQUE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | eu| #89679F| 1| 1| 0| 1',
        'BELARUSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | be| #1050B0| 1| 1| 0| 1',
        'BENGALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bn| #EA4C42| 1| 1| 0| 1',
        'BISLAMA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bi| #C39A37| 1| 1| 0| 1',
        'BOSNIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bs| #7DE3FE| 1| 1| 0| 1',
        'BRETON| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | br| #7E1A72| 1| 1| 0| 1',
        'BULGARIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bg| #D5442A| 1| 1| 0| 1',
        'BURMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | my| #9E5CF0| 1| 1| 0| 1',
        'CATALAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ca| #99BC95| 1| 1| 0| 1',
        'CENTRAL_KHMER| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | km| #6ABDD6| 1| 1| 0| 1',
        'CHAMORRO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ch| #22302F| 1| 1| 0| 1',
        'CHECHEN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ce| #83E832| 1| 1| 0| 1',
        'CHICHEWA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ny| #03E31C| 1| 1| 0| 1',
        'CHINESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | zh| #40EA69| 1| 1| 0| 1',
        'CHURCH_SLAVIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cu| #C76DC2| 1| 1| 0| 1',
        'CHUVASH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cv| #920F92| 1| 1| 0| 1',
        'CORNISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kw| #55137D| 1| 1| 0| 1',
        'CORSICAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | co| #C605DC| 1| 1| 0| 1',
        'CREE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cr| #75D7F3| 1| 1| 0| 1',
        'CROATIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hr| #AB48D3| 1| 1| 0| 1',
        'CZECH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cs| #7804BB| 1| 1| 0| 1',
        'DANISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | da| #87A5BE| 1| 1| 0| 1',
        'DIVEHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | dv| #FA57EC| 1| 1| 0| 1',
        'DUTCH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nl| #74352E| 1| 1| 0| 1',
        'DZONGKHA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | dz| #F7C931| 1| 1| 0| 1',
        'ENGLISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | en| #DD4A2F| 1| 1| 0| 1',
        'ESPERANTO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | eo| #B65ADE| 1| 1| 0| 1',
        'ESTONIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | et| #AF1569| 1| 1| 0| 1',
        'EWE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ee| #2B7E43| 1| 1| 0| 1',
        'FAROESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fo| #507CCC| 1| 1| 0| 1',
        'FIJIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fj| #7083F9| 1| 1| 0| 1',
        'FILIPINO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fil| #8BEF80| 1| 1| 0| 1',
        'FINNISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fi| #9229A6| 1| 1| 0| 1',
        'FRENCH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fr| #4111A0| 1| 1| 0| 1',
        'FULAH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ff| #649BA7| 1| 1| 0| 1',
        'GAELIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gd| #FBFEC1| 1| 1| 0| 1',
        'GALICIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gl| #DB6769| 1| 1| 0| 1',
        'GANDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lg| #C71A50| 1| 1| 0| 1',
        'GEORGIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ka| #8517C8| 1| 1| 0| 1',
        'GERMAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | de| #4F5FDC| 1| 1| 0| 1',
        'GREEK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | el| #49B49A| 1| 1| 0| 1',
        'GUARANI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gn| #EDB51C| 1| 1| 0| 1',
        'GUJARATI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gu| #BDF7FF| 1| 1| 0| 1',
        'HAITIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ht| #466EB6| 1| 1| 0| 1',
        'HAUSA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ha| #A949D2| 1| 1| 0| 1',
        'HEBREW| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | he| #E9C58A| 1| 1| 0| 1',
        'HERERO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hz| #E9DF57| 1| 1| 0| 1',
        'HINDI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hi| #77775B| 1| 1| 0| 1',
        'HIRI_MOTU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ho| #3BB41B| 1| 1| 0| 1',
        'HUNGARIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hu| #111457| 1| 1| 0| 1',
        'ICELANDIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | is| #0ACE8F| 1| 1| 0| 1',
        'IDO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | io| #75CA6C| 1| 1| 0| 1',
        'IGBO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ig| #757EDE| 1| 1| 0| 1',
        'INDONESIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | id| #52E822| 1| 1| 0| 1',
        'INTERLINGUA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ia| #7F9248| 1| 1| 0| 1',
        'INTERLINGUE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ie| #8F802C| 1| 1| 0| 1',
        'INUKTITUT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | iu| #43C3B0| 1| 1| 0| 1',
        'INUPIAQ| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ik| #ECF371| 1| 1| 0| 1',
        'IRISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ga| #FB7078| 1| 1| 0| 1',
        'ITALIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | it| #95B5DF| 1| 1| 0| 1',
        'JAPANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ja| #5D776B| 1| 1| 0| 1',
        'JAVANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | jv| #5014C5| 1| 1| 0| 1',
        'KALAALLISUT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kl| #050CF3| 1| 1| 0| 1',
        'KANNADA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kn| #440B43| 1| 1| 0| 1',
        'KANURI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kr| #4F2AAC| 1| 1| 0| 1',
        'KASHMIRI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ks| #842C02| 1| 1| 0| 1',
        'KAZAKH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kk| #665F3D| 1| 1| 0| 1',
        'KIKUYU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ki| #315679| 1| 1| 0| 1',
        'KINYARWANDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rw| #CE1391| 1| 1| 0| 1',
        'KIRGHIZ| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ky| #5F0D23| 1| 1| 0| 1',
        'KOMI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kv| #9B06C3| 1| 1| 0| 1',
        'KONGO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kg| #74BC47| 1| 1| 0| 1',
        'KOREAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ko| #F5C630| 1| 1| 0| 1',
        'KUANYAMA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kj| #D8CB60| 1| 1| 0| 1',
        'KURDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ku| #467330| 1| 1| 0| 1',
        'LAO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lo| #DD3B78| 1| 1| 0| 1',
        'LATIN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | la| #A73376| 1| 1| 0| 1',
        'LATVIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lv| #A65EC1| 1| 1| 0| 1',
        'LIMBURGAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | li| #13C252| 1| 1| 0| 1',
        'LINGALA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ln| #BBEE5B| 1| 1| 0| 1',
        'LITHUANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lt| #E89C3E| 1| 1| 0| 1',
        'LUBA-KATANGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lu| #4E97F3| 1| 1| 0| 1',
        'LUXEMBOURGISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lb| #4738EE| 1| 1| 0| 1',
        'MACEDONIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mk| #B69974| 1| 1| 0| 1',
        'MALAGASY| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mg| #29D850| 1| 1| 0| 1',
        'MALAY| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ms| #A74139| 1| 1| 0| 1',
        'MALAYALAM| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ml| #FD4C87| 1| 1| 0| 1',
        'MALTESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mt| #D6EE0B| 1| 1| 0| 1',
        'MANX| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gv| #3F83E9| 1| 1| 0| 1',
        'MAORI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mi| #8339FD| 1| 1| 0| 1',
        'MARATHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mr| #93DEF1| 1| 1| 0| 1',
        'MARSHALLESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mh| #11DB75| 1| 1| 0| 1',
        'MONGOLIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mn| #A107D9| 1| 1| 0| 1',
        'NAURU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | na| #7A0925| 1| 1| 0| 1',
        'NAVAJO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nv| #48F865| 1| 1| 0| 1',
        'NDONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ng| #83538B| 1| 1| 0| 1',
        'NEPALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ne| #5A15FC| 1| 1| 0| 1',
        'NORTH_NDEBELE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nd| #A1533B| 1| 1| 0| 1',
        'NORTHERN_SAMI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | se| #AAD61B| 1| 1| 0| 1',
        'NORWEGIAN_BOKMÅL| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nb| #0AEB4A| 1| 1| 0| 1',
        'NORWEGIAN_NYNORSK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nn| #278B62| 1| 1| 0| 1',
        'NORWEGIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | no| #13FF63| 1| 1| 0| 1',
        'OCCITAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | oc| #B5B607| 1| 1| 0| 1',
        'OJIBWA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | oj| #100894| 1| 1| 0| 1',
        'ORIYA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | or| #0198FF| 1| 1| 0| 1',
        'OROMO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | om| #351BD8| 1| 1| 0| 1',
        'OSSETIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | os| #BF715E| 1| 1| 0| 1',
        'PALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pi| #BEB3FA| 1| 1| 0| 1',
        'PASHTO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ps| #A4236C| 1| 1| 0| 1',
        'PERSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fa| #68A38E| 1| 1| 0| 1',
        'POLISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pl| #D4F797| 1| 1| 0| 1',
        'PORTUGUESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pt| #71D659| 1| 1| 0| 1',
        'PUNJABI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pa| #14F788| 1| 1| 0| 1',
        'QUECHUA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | qu| #268110| 1| 1| 0| 1',
        'ROMANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ro| #06603F| 1| 1| 0| 1',
        'ROMANSH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rm| #3A73F3| 1| 1| 0| 1',
        'RUNDI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rn| #715E84| 1| 1| 0| 1',
        'RUSSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ru| #DB77DA| 1| 1| 0| 1',
        'SAMOAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sm| #A26738| 1| 1| 0| 1',
        'SANGO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sg| #CA1C7E| 1| 1| 0| 1',
        'SANSKRIT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sa| #CF9C76| 1| 1| 0| 1',
        'SARDINIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sc| #28AF67| 1| 1| 0| 1',
        'SERBIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sr| #FB3F2C| 1| 1| 0| 1',
        'SHONA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sn| #40F3EC| 1| 1| 0| 1',
        'SICHUAN_YI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ii| #FA3474| 1| 1| 0| 1',
        'SINDHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sd| #62D1BE| 1| 1| 0| 1',
        'SINHALA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | si| #24787A| 1| 1| 0| 1',
        'SLOVAK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sk| #66104F| 1| 1| 0| 1',
        'SLOVENIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sl| #6F79E6| 1| 1| 0| 1',
        'SOMALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | so| #A36185| 1| 1| 0| 1',
        'SOUTH_NDEBELE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nr| #8090E5| 1| 1| 0| 1',
        'SOUTHERN_SOTHO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | st| #4C3417| 1| 1| 0| 1',
        'SPANISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | es| #7842AE| 1| 1| 0| 1',
        'SUNDANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | su| #B2D05B| 1| 1| 0| 1',
        'SWAHILI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sw| #D32F20| 1| 1| 0| 1',
        'SWATI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ss| #AA196D| 1| 1| 0| 1',
        'SWEDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sv| #0EC5A2| 1| 1| 0| 1',
        'TAGALOG| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tl| #C9DDAC| 1| 1| 0| 1',
        'TAHITIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ty| #32009D| 1| 1| 0| 1',
        'TAJIK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tg| #100ECF| 1| 1| 0| 1',
        'TAMIL| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ta| #E71FAE| 1| 1| 0| 1',
        'TATAR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tt| #C17483| 1| 1| 0| 1',
        'TELUGU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | te| #E34ABD| 1| 1| 0| 1',
        'THAI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | th| #3FB501| 1| 1| 0| 1',
        'TIBETAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bo| #FF2496| 1| 1| 0| 1',
        'TIGRINYA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ti| #9074F0| 1| 1| 0| 1',
        'TONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | to| #B3259E| 1| 1| 0| 1',
        'TSONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ts| #12687C| 1| 1| 0| 1',
        'TSWANA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tn| #DA3E89| 1| 1| 0| 1',
        'TURKISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tr| #A08D29| 1| 1| 0| 1',
        'TURKMEN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tk| #E70267| 1| 1| 0| 1',
        'TWI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tw| #8A6C0F| 1| 1| 0| 1',
        'UIGHUR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ug| #79BC21| 1| 1| 0| 1',
        'UKRAINIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | uk| #EB60E9| 1| 1| 0| 1',
        'URDU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ur| #57E09D| 1| 1| 0| 1',
        'UZBEK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | uz| #4341F3| 1| 1| 0| 1',
        'VENDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ve| #4780ED| 1| 1| 0| 1',
        'VIETNAMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | vi| #90A301| 1| 1| 0| 1',
        'VOLAPÜK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | vo| #77D574| 1| 1| 0| 1',
        'WALLOON| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | wa| #BD440A| 1| 1| 0| 1',
        'WELSH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cy| #45E39C| 1| 1| 0| 1',
        'WESTERN_FRISIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fy| #01F471| 1| 1| 0| 1',
        'WOLOF| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | wo| #BDD498| 1| 1| 0| 1',
        'XHOSA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | xh| #0C6D9C| 1| 1| 0| 1',
        'YIDDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | yi| #111D14| 1| 1| 0| 1',
        'YORUBA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | yo| #E815FF| 1| 1| 0| 1',
        'ZHUANG| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | za| #C62A89| 1| 1| 0| 1',
        'ZULU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | zu| #0049F8| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = Set-TextBetweenDelimiters -InputString $pre_value -ReplacementString (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination audio_language
    Move-Item -Path output-orig -Destination output
    
}

################################################################################
# Function: CreateAwards
# Description:  Creates Awards
################################################################################
Function CreateAwards {
    Write-Host "Creating Awards"
    Set-Location $script_path
    Find-Path "$script_path\award"
    WriteToLogFile "ImageMagick Commands for     : Awards"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    ########################
    # BAFTA #9C7C26
    ########################
    WriteToLogFile "ImageMagick Commands for     : BAFTA"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #9C7C26| 1| 1| 0| 1',
        'NOMINATIONS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #9C7C26| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #9C7C26| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #9C7C26| 1| 1| 0| 1',
        '| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BAFTA| #9C7C26| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #9C7C26| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\bafta

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #9C7C26| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\bafta\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #9C7C26| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\bafta\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| BAFTA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #9C7C26| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\bafta\best

    # ########################
    # # Berlinale #BB0B34
    # ########################
    WriteToLogFile "ImageMagick Commands for     : Berlinale"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #BB0B34| 1| 1| 0| 1',
        'NOMINATIONS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #BB0B34| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #BB0B34| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #BB0B34| 1| 1| 0| 1',
        '| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Berlinale| #BB0B34| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #BB0B34| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1951; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\berlinale

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #BB0B34| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1951; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\berlinale\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #BB0B34| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1951; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\berlinale\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Berlinale.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #BB0B34| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1951; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\berlinale\best

    ########################
    # Cannes #AF8F51
    ########################
    WriteToLogFile "ImageMagick Commands for     : Cannes"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AF8F51| 1| 1| 0| 1',
        'NOMINATIONS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #AF8F51| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #AF8F51| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #AF8F51| 1| 1| 0| 1',
        '| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cannes| #AF8F51| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AF8F51| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1938; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cannes

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AF8F51| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1938; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cannes\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #AF8F51| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1938; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cannes\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Cannes.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AF8F51| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1938; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cannes\best

    ########################
    # Cesar #E2A845
    ########################
    WriteToLogFile "ImageMagick Commands for     : Cesar"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #E2A845| 1| 1| 0| 1',
        'NOMINATIONS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #E2A845| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #E2A845| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #E2A845| 1| 1| 0| 1',
        '| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cesar| #E2A845| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #E2A845| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1976; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cesar

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #E2A845| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1976; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cesar\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #E2A845| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1976; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cesar\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Cesar.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #E2A845| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1976; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\cesar\best

    ########################
    # Choice #AC7427
    ########################
    WriteToLogFile "ImageMagick Commands for     : Choice"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AC7427| 1| 1| 0| 1',
        'NOMINATIONS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #AC7427| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #AC7427| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #AC7427| 1| 1| 0| 1',
        '| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Choice| #AC7427| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AC7427| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1929; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\choice

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AC7427| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1929; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\choice\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #AC7427| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1929; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\choice\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Choice.png| -500| 600| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #AC7427| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1929; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\choice\best

    ########################
    # Emmys #D89C27
    ########################
    WriteToLogFile "ImageMagick Commands for     : Awards-Emmys-Winner"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D89C27| 1| 1| 0| 1',
        'NOMINATIONS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D89C27| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #D89C27| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #D89C27| 1| 1| 0| 1',
        '| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Emmys| #D89C27| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D89C27| 1| 1| 0| 1'
        # 'Logo| logo_resize| Name| out_name| base_color| ww',
        # 'Emmys.png| 1500| WINNERS| winner| #D89C27| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\emmys

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D89C27| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\emmys\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D89C27| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\emmys\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Emmys.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D89C27| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1947; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\emmys\best

    ########################
    # Golden #D0A047
    ########################
    WriteToLogFile "ImageMagick Commands for     : Golden"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D0A047| 1| 1| 0| 1',
        'NOMINATIONS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D0A047| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #D0A047| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #D0A047| 1| 1| 0| 1',
        '| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Golden| #D0A047| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr
    
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D0A047| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1943; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\golden

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D0A047| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1943; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\golden\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D0A047| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1943; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\golden\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Golden.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D0A047| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1943; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
            # $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.Logo)`" -logo_offset -500 -logo_resize $($item.logo_resize) -text `"$value`" -text_offset +850 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient 1 -avg_color 0 -clean 1 -white_wash $($item.ww)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\golden\best

    ########################
    # Oscars #A9842E
    ########################
    WriteToLogFile "ImageMagick Commands for     : Oscars"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #A9842E| 1| 1| 0| 1',
        'NOMINATIONS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #A9842E| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #A9842E| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #A9842E| 1| 1| 0| 1',
        '| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Oscars| #A9842E| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #A9842E| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1927; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\oscars

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #A9842E| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1927; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
            # $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.Logo)`" -logo_offset -500 -logo_resize $($item.logo_resize) -text `"$value`" -text_offset +850 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient 1 -avg_color 0 -clean 1 -white_wash $($item.ww)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\oscars\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #A9842E| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1927; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\oscars\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Oscars.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #A9842E| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1927; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\oscars\best

    ########################
    # Razzie #FF0C0C
    ########################
    WriteToLogFile "ImageMagick Commands for     : Razzie"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #FF0C0C| 1| 1| 0| 1',
        'NOMINATIONS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #FF0C0C| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #FF0C0C| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #FF0C0C| 1| 1| 0| 1',
        '| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Razzie| #FF0C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr
    
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #FF0C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1980; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\razzies

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #FF0C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1980; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\razzies\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #FF0C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1980; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\razzies\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Razzie.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #FF0C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1980; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\razzies\best

    ########################
    # Spirit #4662E7
    ########################
    WriteToLogFile "ImageMagick Commands for     : Spirit"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #4662E7| 1| 1| 0| 1',
        'NOMINATIONS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #4662E7| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #4662E7| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #4662E7| 1| 1| 0| 1',
        '| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Spirit| #4662E7| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr
    
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #4662E7| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1986; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\spirit

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #4662E7| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1986; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\spirit\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #4662E7| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1986; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\spirit\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Spirit.png| -500| 1000| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #4662E7| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1986; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\spirit\best

    ########################
    # Sundance #7EB2CF
    ########################
    WriteToLogFile "ImageMagick Commands for     : Sundance"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #7EB2CF| 1| 1| 0| 1',
        'NOMINATIONS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #7EB2CF| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #7EB2CF| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #7EB2CF| 1| 1| 0| 1',
        'GRAND_JURY_WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | grand_jury_winner| #7EB2CF| 1| 1| 0| 1',
        '| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sundance| #7EB2CF| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #7EB2CF| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1978; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\sundance

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #7EB2CF| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1978; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
            # $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.Logo)`" -logo_offset -500 -logo_resize $($item.logo_resize) -text `"$value`" -text_offset +850 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient 1 -avg_color 0 -clean 1 -white_wash $($item.ww)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\sundance\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #7EB2CF| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1978; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\sundance\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Sundance.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #7EB2CF| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1978; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\sundance\best

    ########################
    # Venice #D21635
    ########################
    WriteToLogFile "ImageMagick Commands for     : Venice"
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D21635| 1| 1| 0| 1',
        'NOMINATIONS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D21635| 1| 1| 0| 1',
        'BEST_DIRECTOR_WINNERS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_director_winner| #D21635| 1| 1| 0| 1',
        'BEST_PICTURE_WINNERS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | best_picture_winner| #D21635| 1| 1| 0| 1',
        '| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Venice| #D21635| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D21635| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1932; $i -lt 2030; $i++) {
            $value = $i
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\venice

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'WINNERS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D21635| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1932; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\venice\winner

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'NOMINATIONS| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nomination| #D21635| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1932; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
            # $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.Logo)`" -logo_offset -500 -logo_resize $($item.logo_resize) -text `"$value`" -text_offset +850 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient 1 -avg_color 0 -clean 1 -white_wash $($item.ww)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\venice\nomination
 
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BEST_PICTURE_WINNER| Venice.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | winner| #D21635| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        for ($i = 1932; $i -lt 2030; $i++) {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
            $value = "$value $i"
            $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
            $arr += ".\create_poster.ps1 -logo `"$script_path\logos_award\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$i`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination award\venice\best

    Copy-Item -Path logos_award -Destination award\logos -Recurse
    Move-Item -Path output-orig -Destination output

    Set-Location $script_path
}

################################################################################
# Function: CreateBased
# Description:  Creates Based Posters
################################################################################
Function CreateBased {
    Write-Host `"Creating Based Posters`"
    Set-Location $script_path
    # Find-Path `"$script_path\based`"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'BASED_ON_A_BOOK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Book| #131CA1| 1| 1| 0| 1',
        'BASED_ON_A_COMIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Comic| #7856EF| 1| 1| 0| 1',
        'BASED_ON_A_TRUE_STORY| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | True Story| #BC0638| 1| 1| 0| 1',
        'BASED_ON_A_VIDEO_GAME| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Video Game| #38CC66| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination based
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateChart
# Description:  Creates Chart
################################################################################
Function CreateChart {
    Write-Host "Creating Chart"
    Set-Location $script_path
    # Find-Path "$script_path\chart"
    $theMaxWidth = 1500
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'POPULAR| AniDB.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AniDB Popular| #FF7E17| 1| 1| 0| 1',
        'POPULAR| AniList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AniList Popular| #414A81| 1| 1| 0| 1',
        'SEASON| AniList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AniList Season| #414A81| 1| 1| 0| 1',
        'TOP_RATED| AniList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AniList Top Rated| #414A81| 1| 1| 0| 1',
        'TRENDING| AniList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AniList Trending| #414A81| 1| 1| 0| 1',
        'TOP_10| Apple TV+.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | apple_top| #494949| 1| 1| 0| 1',
        'TOP_10| Disney+.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | disney_top| #002CA1| 1| 1| 0| 1',
        'TOP_10| HBO Max.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hbo_top| #9015C5| 1| 1| 0| 1',
        'TOP_10| Max.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | max_top| #002BE7| 1| 1| 0| 1',
        'BOTTOM_RATED| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb Bottom Rated| #D7B00B| 1| 1| 0| 1',
        'BOX_OFFICE| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb Box Office| #D7B00B| 1| 1| 0| 1',
        'LOWEST_RATED| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb Lowest Rated| #D7B00B| 1| 1| 0| 1',
        'POPULAR| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb Popular| #D7B00B| 1| 1| 0| 1',
        'TOP_10| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | imdb_top| #D7B00B| 1| 1| 0| 1',
        'TOP_250| IMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb Top 250| #D7B00B| 1| 1| 0| 1',
        'FAVORITED| MyAnimeList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MyAnimeList Favorited| #304DA6| 1| 1| 0| 1',
        'POPULAR| MyAnimeList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MyAnimeList Popular| #304DA6| 1| 1| 0| 1',
        'SEASON| MyAnimeList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MyAnimeList Season| #304DA6| 1| 1| 0| 1',
        'TOP_AIRING| MyAnimeList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MyAnimeList Top Airing| #304DA6| 1| 1| 0| 1',
        'TOP_RATED| MyAnimeList.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MyAnimeList Top Rated| #304DA6| 1| 1| 0| 1',
        'TOP_10| Netflix.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | netflix_top| #B4121D| 1| 1| 0| 1',
        'TOP_10| Paramount+.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | paramount_top| #1641C3| 1| 1| 0| 1',
        'TOP_10_PIRATED| Pirated.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Top 10 Pirated Movies of the Week| #93561D| 1| 1| 0| 1',
        'NEW_EPISODES| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | New Episodes| #DC9924| 1| 1| 0| 1',
        'NEW_PREMIERES| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | New Premieres| #DC9924| 1| 1| 0| 1',
        'NEWLY_RELEASED_EPISODES| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Newly Released Episodes| #DC9924| 1| 1| 0| 1',
        'NEWLY_RELEASED| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Newly Released| #DC9924| 1| 1| 0| 1',
        'PILOTS| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Pilots| #DC9924| 1| 1| 0| 1',
        'PLEX_PEOPLE_WATCHING| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Plex People Watching| #DC9924| 1| 1| 0| 1',
        'PLEX_PILOTS| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Plex Pilots| #DC9924| 1| 1| 0| 1',
        'PLEX_POPULAR| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Plex Popular| #DC9924| 1| 1| 0| 1',
        'PLEX_WATCHED| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Plex Watched| #DC9924| 1| 1| 0| 1',
        'RECENTLY_ADDED| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Recently Added| #DC9924| 1| 1| 0| 1',
        'RECENTLY_AIRED| Plex.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Recently Aired| #DC9924| 1| 1| 0| 1',
        'TOP_10| Prime Video.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | prime_top| #43ABCE| 1| 1| 0| 1',
        'STEVENLU''S_POPULAR_MOVIES| StevenLu.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | StevenLu''s Popular Movies| #1D2D51| 1| 1| 0| 1',
        'AIRING_TODAY| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb Airing Today| #062AC8| 1| 1| 0| 1',
        'NOW_PLAYING| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb Now Playing| #062AC8| 1| 1| 0| 1',
        'ON_THE_AIR| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb On The Air| #062AC8| 1| 1| 0| 1',
        'POPULAR| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb Popular| #062AC8| 1| 1| 0| 1',
        'TOP_RATED| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb Top Rated| #062AC8| 1| 1| 0| 1',
        'TRENDING| TMDb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TMDb Trending| #062AC8| 1| 1| 0| 1',
        'POPULAR| Tautulli.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Tautulli Popular| #B9851F| 1| 1| 0| 1',
        'WATCHED| Tautulli.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Tautulli Watched| #B9851F| 1| 1| 0| 1',
        'COLLECTED| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Collected| #CD1A20| 1| 1| 0| 1',
        'NOW_PLAYING| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Now Playing| #CD1A20| 1| 1| 0| 1',
        'POPULAR| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Popular| #CD1A20| 1| 1| 0| 1',
        'RECOMMENDED| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Recommended| #CD1A20| 1| 1| 0| 1',
        'TRENDING| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Trending| #CD1A20| 1| 1| 0| 1',
        'WATCHED| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Watched| #CD1A20| 1| 1| 0| 1',
        'WATCHLIST| Trakt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Trakt Watchlist| #CD1A20| 1| 1| 0| 1',
        'FAMILIES| css.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Common Sense Selection| #1AA931| 1| 1| 0| 1',
        'TOP_10| google_play.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | google_top| #B81282| 1| 1| 0| 1',
        'TOP_10| hulu.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hulu_top| #1BB68A| 1| 1| 0| 1',
        'TOP_10| itunes.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | itunes_top| #D500CC| 1| 1| 0| 1',
        'TOP_10| star_plus.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | star_plus_top| #4A3159| 1| 1| 0| 1',
        'TOP_10| vudu.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | vudu_top| #3567AC| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_chart\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination chart
    Copy-Item -Path logos_chart -Destination chart\logos -Recurse
    Move-Item -Path output-orig -Destination output

}

################################################################################
# Function: CreateContentRating
# Description:  Creates ContentRating
################################################################################
Function CreateContentRating {
    Write-Host "Creating ContentRating"
    Set-Location $script_path
    # Find-Path "$script_path\content_rating"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    $logo_offset = -500
    $logo_resize = 1800
    $text_offset = +850
    $font = "ComfortAa-Medium"
    $font_color = "#FFFFFF"
    $border = 0
    $border_width = 15
    $border_color = "#FFFFFF"
    $avg_color_image = ""
    $base_color = ""
    $gradient = 1
    $clean = 1
    $avg_color = 0
    $white_wash = 1

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'content_ratings_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination content_rating

    $base_color = "#1AA931"
    $arr = @()
    for ($i = 1; $i -lt 19; $i++) {
        $value = (Get-YamlPropertyValue -PropertyPath "key_names.age" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        $value = "$value $i+"
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\cs.png`" -logo_offset $logo_offset -logo_resize $logo_resize -text `"$value`" -text_offset $text_offset -font `"$font`" -font_size $optimalFontSize -font_color `"$font_color`" -border $border -border_width $border_width -border_color `"$border_color`" -avg_color_image `"$avg_color_image`" -out_name `"$i`" -base_color `"$base_color`" -gradient $gradient -avg_color $avg_color -clean $clean -white_wash $white_wash"
    }
    $value = (Get-YamlPropertyValue -PropertyPath "key_names.NOT_RATED" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
    $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
    $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\cs.png`" -logo_offset $logo_offset -logo_resize $logo_resize -text `"$value`" -text_offset $text_offset -font `"$font`" -font_size $optimalFontSize -font_color `"$font_color`" -border $border -border_width $border_width -border_color `"$border_color`" -avg_color_image `"$avg_color_image`" -out_name `"$i`" -base_color `"$base_color`" -gradient $gradient -avg_color $avg_color -clean $clean -white_wash $white_wash"
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination content_rating\cs
    
    $content_rating = "G", "PG", "PG-13", "R", "R+", "Rx"
    $base_color = "#2444D1"
    $arr = @()
    foreach ( $cr in $content_rating ) { 
        $value = (Get-YamlPropertyValue -PropertyPath "key_names.RATED" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        $value = "$value $cr"
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\mal.png`" -logo_offset $logo_offset -logo_resize $logo_resize -text `"$value`" -text_offset $text_offset -font `"$font`" -font_size $optimalFontSize -font_color `"$font_color`" -border $border -border_width $border_width -border_color `"$border_color`" -avg_color_image `"$avg_color_image`" -out_name `"$cr`" -base_color `"$base_color`" -gradient $gradient -avg_color $avg_color -clean $clean -white_wash $white_wash"
    }
    $value = (Get-YamlPropertyValue -PropertyPath "key_names.NOT_RATED" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
    $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
    $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\mal.png`" -logo_offset $logo_offset -logo_resize $logo_resize -text `"$value`" -text_offset $text_offset -font `"$font`" -font_size $optimalFontSize -font_color `"$font_color`" -border $border -border_width $border_width -border_color `"$border_color`" -avg_color_image `"$avg_color_image`" -out_name `"$cr`" -base_color `"$base_color`" -gradient $gradient -avg_color $avg_color -clean $clean -white_wash $white_wash"
    LaunchScripts -ScriptPaths $arr
    
    Move-Item -Path output -Destination content_rating\mal
    
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| uk12.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | 12| #FF7D13| 1| 1| 0| 1',
        '| uk12A.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | 12A| #FF7D13| 1| 1| 0| 1',
        '| uk15.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | 15| #FC4E93| 1| 1| 0| 1',
        '| uk18.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | 18| #DC0A0B| 1| 1| 0| 1',
        '| uknr.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | NR| #0E84A3| 1| 1| 0| 1',
        '| ukpg.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | PG| #FBAE00| 1| 1| 0| 1',
        '| ukr18.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | R18| #016ED3| 1| 1| 0| 1',
        '| uku.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | U| #0BC700| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination content_rating\uk

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| usg.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | G| #79EF06| 1| 1| 0| 1',
        '| usnc17.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | NC-17| #EE45A4| 1| 1| 0| 1',
        '| usnr.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | NR| #0E84A3| 1| 1| 0| 1',
        '| uspg.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | PG| #918CE2| 1| 1| 0| 1',
        '| uspg13.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | PG-13| #A124CC| 1| 1| 0| 1',
        '| usr.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | R| #FB5226| 1| 1| 0| 1',
        '| ustv14.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV-14| #C29CC1| 1| 1| 0| 1',
        '| ustvg.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV-G| #98A5BB| 1| 1| 0| 1',
        '| ustvma.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV-MA| #DB8689| 1| 1| 0| 1',
        '| ustvpg.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV-PG| #5B0EFD| 1| 1| 0| 1',
        '| ustvy.png| +0| 1500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV-Y| #3EB3C1| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_content_rating\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination content_rating\us
    Copy-Item -Path logos_content_rating -Destination content_rating\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateCountry
# Description:  Creates Country
################################################################################
Function CreateCountry {
    Write-Host "Creating Country"
    Set-Location $script_path
    Find-Path "$script_path\country"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'country_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Other Countries| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'UNITED_ARAB_EMIRATES| ae.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United Arab Emirates| #BC9C16| 1| 1| 0| 0',
        'ARGENTINA| ar.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Argentina| #F05610| 1| 1| 0| 0',
        'AUSTRIA| at.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Austria| #F5E6AE| 1| 1| 0| 0',
        'AUSTRALIA| au.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Australia| #D5237B| 1| 1| 0| 0',
        'BELGIUM| be.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Belgium| #AC98DB| 1| 1| 0| 0',
        'BULGARIA| bg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Bulgaria| #79AB96| 1| 1| 0| 0',
        'BRAZIL| br.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Brazil| #EE9DA9| 1| 1| 0| 0',
        'BAHAMAS| bs.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Bahamas| #F6CDF0| 1| 1| 0| 0',
        'CANADA| ca.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Canada| #32DE58| 1| 1| 0| 0',
        'SWITZERLAND| ch.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Switzerland| #5803F1| 1| 1| 0| 0',
        'CHILE| cl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Chile| #AAC41F| 1| 1| 0| 0',
        'CHINA| cn.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | China| #902A62| 1| 1| 0| 0',
        'COSTA_RICA| cr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Costa Rica| #41F306| 1| 1| 0| 0',
        'CZECH_REPUBLIC| cz.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Czech Republic| #9ECE8F| 1| 1| 0| 0',
        'GERMANY| de.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Germany| #97FDAE| 1| 1| 0| 0',
        'DENMARK| dk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Denmark| #685ECB| 1| 1| 0| 0',
        'DOMINICAN_REPUBLIC| do.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Dominican Republic| #83F0A2| 1| 1| 0| 0',
        'ESTONIA| ee.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Estonia| #5145DA| 1| 1| 0| 0',
        'EGYPT| eg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Egypt| #86B137| 1| 1| 0| 0',
        'SPAIN| es.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Spain| #99DA4B| 1| 1| 0| 0',
        'FINLAND| fi.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Finland| #856518| 1| 1| 0| 0',
        'FRANCE| fr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | France| #D0404D| 1| 1| 0| 0',
        'UNITED_KINGDOM| gb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United Kingdom| #C7B89D| 1| 1| 0| 0',
        'GREECE| gr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Greece| #431832| 1| 1| 0| 0',
        'HONG_KONG| hk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hong Kong| #F6B541| 1| 1| 0| 0',
        'CROATIA| hr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Croatia| #62BF53| 1| 1| 0| 0',
        'HUNGARY| hu.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hungary| #E5983C| 1| 1| 0| 0',
        'INDONESIA| id.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Indonesia| #3E33E4| 1| 1| 0| 0',
        'IRELAND| ie.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ireland| #C6377E| 1| 1| 0| 0',
        'ISRAEL| il.png| -500| 650| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Israel| #41E0A9| 1| 1| 0| 0',
        'INDIA| in.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | India| #A6404A| 1| 1| 0| 0',
        'ICELAND| is.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Iceland| #CE31A0| 1| 1| 0| 0',
        'ITALY| it.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Italy| #57B9BF| 1| 1| 0| 0',
        'IRAN| ir.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Iran| #2AAC15| 1| 1| 0| 0',
        'JAPAN| jp.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Japan| #4FCF54| 1| 1| 0| 0',
        'KOREA| kr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Korea| #127FFE| 1| 1| 0| 0',
        'LATIN_AMERICA| latin america.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Latin America| #3785B6| 1| 1| 0| 0',
        'SRI_LANKA| lk.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sri Lanka| #6415FD| 1| 1| 0| 0',
        'LUXEMBOURG| lu.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Luxembourg| #C90586| 1| 1| 0| 0',
        'LATVIA| lv.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Latvia| #5326A3| 1| 1| 0| 0',
        'MOROCCO| ma.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Morocco| #B28BDC| 1| 1| 0| 0',
        'MEXICO| mx.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mexico| #964F76| 1| 1| 0| 0',
        'MALAYSIA| my.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Malaysia| #9630B4| 1| 1| 0| 0',
        'NETHERLANDS| nl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Netherlands| #B14FAA| 1| 1| 0| 0',
        'NORWAY| no.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Norway| #AC320E| 1| 1| 0| 0',
        'NORDIC| nordic.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nordic| #A12398| 1| 1| 0| 0',
        'NEPAL| np.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nepal| #3F847B| 1| 1| 0| 0',
        'NEW_ZEALAND| nz.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | New Zealand| #E0A486| 1| 1| 0| 0',
        'PANAMA| pa.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Panama| #417818| 1| 1| 0| 0',
        'PERU| pe.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Peru| #803704| 1| 1| 0| 0',
        'PHILIPPINES| ph.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Philippines| #2DF423| 1| 1| 0| 0',
        'PAKISTAN| pk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Pakistan| #6FF34E| 1| 1| 0| 0',
        'POLAND| pl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Poland| #BAF6C2| 1| 1| 0| 0',
        'PORTUGAL| pt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Portugal| #A1DE3F| 1| 1| 0| 0',
        'QATAR| qa.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Qatar| #4C1FCC| 1| 1| 0| 0',
        'ROMANIA| ro.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Romania| #ABD0CF| 1| 1| 0| 0',
        'SERBIA| rs.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Serbia| #7E0D8E| 1| 1| 0| 0',
        'RUSSIA| ru.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Russia| #97D820| 1| 1| 0| 0',
        'SAUDI_ARABIA| sa.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Saudi Arabia| #D34B83| 1| 1| 0| 0',
        'SWEDEN| se.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sweden| #E3C61A| 1| 1| 0| 0',
        'SINGAPORE| sg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Singapore| #0328DB| 1| 1| 0| 0',
        'THAILAND| th.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Thailand| #32DBD9| 1| 1| 0| 0',
        'TURKEY| tr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Turkey| #CD90D1| 1| 1| 0| 0',
        'TAIWAN| tw.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Taiwan| #ABE3E0| 1| 1| 0| 0',
        'UKRAINE| ua.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ukraine| #1640B6| 1| 1| 0| 0',
        'UNITED_STATES_OF_AMERICA| us.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United States of America| #D2A345| 1| 1| 0| 0',
        'VIETNAM| vn.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Vietnam| #19156E| 1| 1| 0| 0',
        'SOUTH_AFRICA| za.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | South Africa| #E7BB4A| 1| 1| 0| 0'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_country\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination country\color

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'UNITED_ARAB_EMIRATES| ae.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United Arab Emirates| #BC9C16| 1| 1| 0| 1',
        'ARGENTINA| ar.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Argentina| #F05610| 1| 1| 0| 1',
        'AUSTRIA| at.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Austria| #F5E6AE| 1| 1| 0| 1',
        'AUSTRALIA| au.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Australia| #D5237B| 1| 1| 0| 1',
        'BELGIUM| be.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Belgium| #AC98DB| 1| 1| 0| 1',
        'BULGARIA| bg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Bulgaria| #79AB96| 1| 1| 0| 1',
        'BRAZIL| br.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Brazil| #EE9DA9| 1| 1| 0| 1',
        'BAHAMAS| bs.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Bahamas| #F6CDF0| 1| 1| 0| 1',
        'CANADA| ca.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Canada| #32DE58| 1| 1| 0| 1',
        'SWITZERLAND| ch.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Switzerland| #5803F1| 1| 1| 0| 1',
        'CHILE| cl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Chile| #AAC41F| 1| 1| 0| 1',
        'CHINA| cn.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | China| #902A62| 1| 1| 0| 1',
        'COSTA_RICA| cr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Costa Rica| #41F306| 1| 1| 0| 1',
        'CZECH_REPUBLIC| cz.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Czech Republic| #9ECE8F| 1| 1| 0| 1',
        'GERMANY| de.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Germany| #97FDAE| 1| 1| 0| 1',
        'DENMARK| dk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Denmark| #685ECB| 1| 1| 0| 1',
        'DOMINICAN_REPUBLIC| do.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Dominican Republic| #83F0A2| 1| 1| 0| 1',
        'ESTONIA| ee.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Estonia| #5145DA| 1| 1| 0| 1',
        'EGYPT| eg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Egypt| #86B137| 1| 1| 0| 1',
        'SPAIN| es.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Spain| #99DA4B| 1| 1| 0| 1',
        'FINLAND| fi.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Finland| #856518| 1| 1| 0| 1',
        'FRANCE| fr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | France| #D0404D| 1| 1| 0| 1',
        'UNITED_KINGDOM| gb.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United Kingdom| #C7B89D| 1| 1| 0| 1',
        'GREECE| gr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Greece| #431832| 1| 1| 0| 1',
        'HONG_KONG| hk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hong Kong| #F6B541| 1| 1| 0| 1',
        'CROATIA| hr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Croatia| #62BF53| 1| 1| 0| 1',
        'HUNGARY| hu.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hungary| #E5983C| 1| 1| 0| 1',
        'INDONESIA| id.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Indonesia| #3E33E4| 1| 1| 0| 1',
        'IRELAND| ie.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ireland| #C6377E| 1| 1| 0| 1',
        'ISRAEL| il.png| -500| 650| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Israel| #41E0A9| 1| 1| 0| 1',
        'INDIA| in.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | India| #A6404A| 1| 1| 0| 1',
        'ICELAND| is.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Iceland| #CE31A0| 1| 1| 0| 1',
        'ITALY| it.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Italy| #57B9BF| 1| 1| 0| 1',
        'IRAN| ir.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Iran| #2AAC15| 1| 1| 0| 1',
        'JAPAN| jp.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Japan| #4FCF54| 1| 1| 0| 1',
        'KOREA| kr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Korea| #127FFE| 1| 1| 0| 1',
        'LATIN_AMERICA| latin america.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Latin America| #3785B6| 1| 1| 0| 1',
        'SRI_LANKA| lk.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sri Lanka| #6415FD| 1| 1| 0| 1',
        'LUXEMBOURG| lu.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Luxembourg| #C90586| 1| 1| 0| 1',
        'LATVIA| lv.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Latvia| #5326A3| 1| 1| 0| 1',
        'MOROCCO| ma.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Morocco| #B28BDC| 1| 1| 0| 1',
        'MEXICO| mx.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mexico| #964F76| 1| 1| 0| 1',
        'MALAYSIA| my.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Malaysia| #9630B4| 1| 1| 0| 1',
        'NETHERLANDS| nl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Netherlands| #B14FAA| 1| 1| 0| 1',
        'NORWAY| no.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Norway| #AC320E| 1| 1| 0| 1',
        'NORDIC| nordic.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nordic| #A12398| 1| 1| 0| 1',
        'NEPAL| np.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nepal| #3F847B| 1| 1| 0| 1',
        'NEW_ZEALAND| nz.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | New Zealand| #E0A486| 1| 1| 0| 1',
        'PANAMA| pa.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Panama| #417818| 1| 1| 0| 1',
        'PERU| pe.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Peru| #803704| 1| 1| 0| 1',
        'PHILIPPINES| ph.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Philippines| #2DF423| 1| 1| 0| 1',
        'PAKISTAN| pk.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Pakistan| #6FF34E| 1| 1| 0| 1',
        'POLAND| pl.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Poland| #BAF6C2| 1| 1| 0| 1',
        'PORTUGAL| pt.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Portugal| #A1DE3F| 1| 1| 0| 1',
        'QATAR| qa.png| -500| 750| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Qatar| #4C1FCC| 1| 1| 0| 1',
        'ROMANIA| ro.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Romania| #ABD0CF| 1| 1| 0| 1',
        'SERBIA| rs.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Serbia| #7E0D8E| 1| 1| 0| 1',
        'RUSSIA| ru.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Russia| #97D820| 1| 1| 0| 1',
        'SAUDI_ARABIA| sa.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Saudi Arabia| #D34B83| 1| 1| 0| 1',
        'SWEDEN| se.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sweden| #E3C61A| 1| 1| 0| 1',
        'SINGAPORE| sg.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Singapore| #0328DB| 1| 1| 0| 1',
        'THAILAND| th.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Thailand| #32DBD9| 1| 1| 0| 1',
        'TURKEY| tr.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Turkey| #CD90D1| 1| 1| 0| 1',
        'TAIWAN| tw.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Taiwan| #ABE3E0| 1| 1| 0| 1',
        'UKRAINE| ua.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ukraine| #1640B6| 1| 1| 0| 1',
        'UNITED_STATES_OF_AMERICA| us.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | United States of America| #D2A345| 1| 1| 0| 1',
        'VIETNAM| vn.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Vietnam| #19156E| 1| 1| 0| 1',
        'SOUTH_AFRICA| za.png| -500| 1500| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | South Africa| #E7BB4A| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_country\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'country_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Other Countries| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination country\white
    Copy-Item -Path logos_country -Destination country\logos -Recurse
    Move-Item -Path output-orig -Destination output
    
}

################################################################################
# Function: CreateDecade
# Description:  Creates Decade
################################################################################
Function CreateDecade {
    Write-Host "Creating Decade"
    Set-Location $script_path
    WriteToLogFile "ImageMagick Commands for     : Decades"

    Move-Item -Path output -Destination output-orig

    $theFont = "ComfortAa-Medium"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'decade_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $theMaxWidth = 1900
    $theMaxHeight = 550
    $minPointSize = 250
    $maxPointSize = 1000

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '1880s| transparent.png| +0| 0| +0| Rye-Regular| 453| #FFFFFF| 0| 15| #FFFFFF| | 1880| #44EF10| 1| 1| 0| 1',
        '1890s| transparent.png| +0| 0| +0| Limelight-Regular| 453| #FFFFFF| 0| 15| #FFFFFF| | 1890| #44EF10| 1| 1| 0| 1',
        '1900s| transparent.png| +0| 0| +0| BoecklinsUniverse| 453| #FFFFFF| 0| 15| #FFFFFF| | 1900| #44EF10| 1| 1| 0| 1',
        '1910s| transparent.png| +0| 0| +0| UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1910| #44EF10| 1| 1| 0| 1',
        '1920s| transparent.png| +0| 0| +0| Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1920| #44EF10| 1| 1| 0| 1',
        '1930s| transparent.png| +0| 0| +0| Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1930| #44EF10| 1| 1| 0| 1',
        '1940s| transparent.png| +0| 0| +0| Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1940| #44EF10| 1| 1| 0| 1',
        '1950s| transparent.png| +0| 0| +0| Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1950| #44EF10| 1| 1| 0| 1',
        '1960s| transparent.png| +0| 0| +0| Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1960| #44EF10| 1| 1| 0| 1',
        '1970s| transparent.png| +0| 0| +0| Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1970| #44EF10| 1| 1| 0| 1',
        '1980s| transparent.png| +0| 0| +0| Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1980| #44EF10| 1| 1| 0| 1',
        '1990s| transparent.png| +0| 0| +0| Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1990| #44EF10| 1| 1| 0| 1',
        '2000s| transparent.png| +0| 0| +0| Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2000| #44EF10| 1| 1| 0| 1',
        '2010s| transparent.png| +0| 0| +0| Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2010| #44EF10| 1| 1| 0| 1',
        '2020s| transparent.png| +0| 0| +0| Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2020| #44EF10| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'
    
    $arr = @()
    foreach ($item in $myArray) {
        $value = $($item.key_name)
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $($item.font_size)
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    WriteToLogFile "MonitorProcess               : Waiting for all processes to end before continuing..."
    Start-Sleep -Seconds 3
    MonitorProcess -ProcessName "magick.exe"
    
    Move-Item -Path output -Destination decade

    $pre_value = Get-YamlPropertyValue -PropertyPath "key_names.BEST_OF" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    $theFont = "ComfortAa-Medium"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 200

    $arr = @()
    for ($i = 1880; $i -lt 2030; $i += 10) {
        $value = $pre_value
        $optimalFontSize = Get-OptimalPointSize -text $value -font $theFont -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\decade\$i.jpg`" -logo_offset +0 -logo_resize 2000 -text `"$value`" -text_offset -400 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"#FFFFFF`" -gradient 1 -avg_color 0 -clean 1 -white_wash 0"
    }
    LaunchScripts -ScriptPaths $arr
    Start-Sleep -Seconds 3
    MonitorProcess -ProcessName "magick.exe"
    Move-Item -Path output -Destination "$script_path\decade\best"
    Move-Item -Path output-orig -Destination output

}

################################################################################
# Function: CreateFranchise
# Description:  Creates Franchise
################################################################################
Function CreateFranchise {
    Write-Host "Creating Franchise"
    Set-Location $script_path
    # Find-Path "$script_path\franchise"
    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| 28 Days Weeks Later.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 28 Days Weeks Later| #B93033| 1| 1| 0| 0',
        '| 9-1-1.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 9-1-1| #C62B2B| 1| 1| 0| 1',
        '| A Nightmare on Elm Street.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | A Nightmare on Elm Street| #BE3C3E| 1| 1| 0| 1',
        '| Alien Predator.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Alien Predator| #1EAC1B| 1| 1| 0| 1',
        '| Alien.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Alien| #18BC56| 1| 1| 0| 1',
        '| American Pie.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | American Pie| #C24940| 1| 1| 0| 1',
        '| Anaconda.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Anaconda| #A42E2D| 1| 1| 0| 1',
        '| Angels In The.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Angels In The| #4869BD| 1| 1| 0| 1',
        '| Appleseed.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Appleseed| #986E22| 1| 1| 0| 1',
        '| Archie Comics.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Archie Comics| #DFB920| 1| 1| 0| 1',
        '| Arrowverse.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Arrowverse| #2B8F40| 1| 1| 0| 1',
        '| Barbershop.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Barbershop| #2399AF| 1| 1| 0| 1',
        '| Batman.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Batman| #525252| 1| 1| 0| 1',
        '| Bourne.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Bourne| #383838| 1| 1| 0| 0',
        '| Charlie Brown.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Charlie Brown| #C8BF2B| 1| 1| 0| 1',
        '| Cloverfield.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Cloverfield| #0E1672| 1| 1| 0| 1',
        '| Cornetto Trilogy.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Cornetto Trilogy| #6C9134| 1| 1| 0| 1',
        '| CSI.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | CSI| #969322| 1| 1| 0| 1',
        '| DC Super Hero Girls.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | DC Super Hero Girls| #299CB1| 1| 1| 0| 1',
        '| DC Universe.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | DC Universe| #213DB6| 1| 1| 0| 1',
        '| Deadpool.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Deadpool| #BD393C| 1| 1| 0| 1',
        '| Despicable Me.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Despicable Me| #C77344| 1| 1| 0| 1',
        '| Doctor Who.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Doctor Who| #1C38B4| 1| 1| 0| 1',
        '| Escape From.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Escape From| #B82026| 1| 1| 0| 1',
        '| Fantastic Beasts.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Fantastic Beasts| #9E972B| 1| 1| 0| 1',
        '| Fast & Furious.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Fast & Furious| #8432C4| 1| 1| 0| 1',
        '| FBI.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | FBI| #FFD32C| 1| 1| 0| 1',
        '| Final Fantasy.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Final Fantasy| #86969F| 1| 1| 0| 1',
        '| Friday the 13th.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Friday the 13th| #B9242A| 1| 1| 0| 1',
        '| Frozen.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Frozen| #2A5994| 1| 1| 0| 1',
        '| Garfield.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Garfield| #C28117| 1| 1| 0| 1',
        '| Ghostbusters.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Ghostbusters| #414141| 1| 1| 0| 1',
        '| Godzilla (Heisei).png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Godzilla (Heisei)| #BFB330| 1| 1| 0| 1',
        '| Godzilla (Showa).png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Godzilla (Showa)| #BDB12A| 1| 1| 0| 1',
        '| Godzilla.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Godzilla| #B82737| 1| 1| 0| 1',
        '| Halloween.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Halloween| #BB2D22| 1| 1| 0| 1',
        '| Halo.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Halo| #556A92| 1| 1| 0| 1',
        '| Hannibal Lecter.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Hannibal Lecter| #383838| 1| 1| 0| 1',
        '| Harry Potter.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Harry Potter| #9D9628| 1| 1| 0| 1',
        '| Has Fallen.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Has Fallen| #3B3B3B| 1| 1| 0| 1',
        '| Ice Age.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Ice Age| #5EA0BB| 1| 1| 0| 1',
        '| In Association with Marvel.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | In Association with Marvel| #C42424| 1| 1| 0| 1',
        '| Indiana Jones.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Indiana Jones| #D97724| 1| 1| 0| 1',
        '| IP Man.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | IP Man| #8D7E63| 1| 1| 0| 0',
        '| James Bond 007.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | James Bond 007| #414141| 1| 1| 0| 1',
        '| Jurassic Park.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Jurassic Park| #902E32| 1| 1| 0| 1',
        '| Karate Kid.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Karate Kid| #AC6822| 1| 1| 0| 1',
        '| Law & Order.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Law & Order| #5B87AB| 1| 1| 0| 1',
        '| Lord of the Rings.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Lord of the Rings| #C38B27| 1| 1| 0| 1',
        '| Madagascar.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Madagascar| #AD8F27| 1| 1| 0| 1',
        '| Marvel Cinematic Universe.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Marvel Cinematic Universe| #AD2B2B| 1| 1| 0| 1',
        '| Marx Brothers.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Marx Brothers| #347294| 1| 1| 0| 1',
        '| Middle Earth.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Middle Earth| #C28A25| 1| 1| 0| 1',
        '| Mission Impossible.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Mission Impossible| #BF1616| 1| 1| 0| 1',
        '| Monty Python.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Monty Python| #B61C22| 1| 1| 0| 1',
        '| Mortal Kombat.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Mortal Kombat| #BA4D29| 1| 1| 0| 1',
        '| Mothra.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Mothra| #9C742A| 1| 1| 0| 1',
        '| NCIS.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | NCIS| #AC605F| 1| 1| 0| 1',
        '| One Chicago.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | One Chicago| #BE7C30| 1| 1| 0| 1',
        '| Oz.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Oz| #AD8F27| 1| 1| 0| 1',
        '| Pet Sematary.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Pet Sematary| #B71F25| 1| 1| 0| 1',
        '| Pirates of the Caribbean.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Pirates of the Caribbean| #7F6936| 1| 1| 0| 1',
        '| Planet of the Apes.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Planet of the Apes| #4E4E4E| 1| 1| 0| 1',
        '| Pokémon.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Pokémon| #FECA06| 1| 1| 0| 1',
        '| Power Rangers.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Power Rangers| #24AA60| 1| 1| 0| 1',
        '| Pretty Little Liars.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Pretty Little Liars| #BD0F0F| 1| 1| 0| 1',
        '| Resident Evil Biohazard.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Resident Evil Biohazard| #930B0B| 1| 1| 0| 1',
        '| Resident Evil.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Resident Evil| #940E0F| 1| 1| 0| 1',
        '| Rocky Creed.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Rocky Creed| #C52A2A| 1| 1| 0| 1',
        '| Rocky.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Rocky| #C22121| 1| 1| 0| 1',
        '| RuPaul''s Drag Race.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | RuPaul''s Drag Race| #FF5757| 1| 1| 0| 1',
        '| Scooby-Doo!.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Scooby-Doo!| #5F3879| 1| 1| 0| 1',
        '| Shaft.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Shaft| #382637| 1| 1| 0| 1',
        '| Shrek.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Shrek| #3DB233| 1| 1| 0| 1',
        '| Spider-Man.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Spider-Man| #C11B1B| 1| 1| 0| 1',
        '| Star Trek Alternate Reality.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Trek Alternate Reality| #C78639| 1| 1| 0| 1',
        '| Star Trek The Next Generation.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Trek The Next Generation| #B7AE4C| 1| 1| 0| 1',
        '| Star Trek The Original Series.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Trek The Original Series| #BB5353| 1| 1| 0| 1',
        '| Star Trek.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Trek| #C2A533| 1| 1| 0| 1',
        '| Star Wars Legends.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Wars Legends| #BAA416| 1| 1| 0| 1',
        '| Star Wars Skywalker Saga.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Wars Skywalker Saga| #5C5C5C| 1| 1| 0| 1',
        '| Star Wars.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Star Wars| #C2A21B| 1| 1| 0| 1',
        '| Stargate.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Stargate| #6C73A1| 1| 1| 0| 1',
        '| Street Fighter.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Street Fighter| #C5873F| 1| 1| 0| 1',
        '| Superman.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Superman| #C34544| 1| 1| 0| 1',
        '| Teenage Mutant Ninja Turtles.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Teenage Mutant Ninja Turtles| #78A82E| 1| 1| 0| 1',
        '| The Hunger Games.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Hunger Games| #619AB5| 1| 1| 0| 1',
        '| The Man With No Name.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Man With No Name| #9A7B40| 1| 1| 0| 1',
        '| The Mummy.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Mummy| #C28A25| 1| 1| 0| 1',
        '| The Real Housewives.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Real Housewives| #400EA4| 1| 1| 0| 1',
        '| The Rookie.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Rookie| #DC5A2B| 1| 1| 0| 1',
        '| The Texas Chainsaw Massacre.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Texas Chainsaw Massacre| #B15253| 1| 1| 0| 1',
        '| The Three Stooges.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Three Stooges| #B9532A| 1| 1| 0| 1',
        '| The Twilight Zone.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Twilight Zone| #16245F| 1| 1| 0| 1',
        '| The Walking Dead.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | The Walking Dead| #797F48| 1| 1| 0| 1',
        '| Tom and Jerry.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Tom and Jerry| #B9252B| 1| 1| 0| 1',
        '| Tomb Raider.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Tomb Raider| #620D0E| 1| 1| 0| 1',
        '| Toy Story.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Toy Story| #CEB423| 1| 1| 0| 1',
        '| Transformers.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Transformers| #B02B2B| 1| 1| 0| 1',
        '| Tron.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Tron| #5798B2| 1| 1| 0| 1',
        '| Twilight.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Twilight| #3B3B3B| 1| 1| 0| 1',
        '| Unbreakable.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Unbreakable| #445DBB| 1| 1| 0| 1',
        '| Wallace & Gromit.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Wallace & Gromit| #BA2A20| 1| 1| 0| 1',
        '| Wizarding World.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Wizarding World| #7B7A33| 1| 1| 0| 1',
        '| X-Men.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | X-Men| #636363| 1| 1| 0| 1',
        '| Yellowstone.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Yellowstone| #441515| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_franchise\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination franchise
    Copy-Item -Path logos_franchise -Destination franchise\logos -Recurse
    Move-Item -Path output-orig -Destination output
    
}

################################################################################
# Function: CreateGenre
# Description:  Creates Genre
################################################################################
Function CreateGenre {
    Write-Host "Creating Genre"
    Set-Location $script_path
    # Find-Path "$script_path\genre"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'genre_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'ACTION_ADVENTURE| Action & adventure.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Action & adventure| #65AEA5| 1| 1| 0| 1',
        'ACTION| Action.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Action| #387DBF| 1| 1| 0| 1',
        'ADULT| Adult.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Adult| #D02D2D| 1| 1| 0| 1',
        'ADVENTURE| Adventure.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Adventure| #40B997| 1| 1| 0| 1',
        'ANIMATION| Animation.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Animation| #9035BE| 1| 1| 0| 1',
        'ANIME| Anime.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Anime| #41A4BE| 1| 1| 0| 1',
        'ASIAN_AMERICAN_PACIFIC_ISLANDER_HERITAGE_MONTH| APAC month.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | APAC month| #0EC26B| 1| 1| 0| 1',
        'ASSASSIN| Assassin.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Assasin| #C52124| 1| 1| 0| 1',
        'BIOGRAPHY| Biography.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Biography| #C1A13E| 1| 1| 0| 1',
        'BIOPIC| Biopic.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Biopic| #C1A13E| 1| 1| 0| 1',
        'BLACK_HISTORY_MONTH| Black History.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Black History| #D86820| 1| 1| 0| 0',
        'BLACK_HISTORY_MONTH| Black History2.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Black History2| #D86820| 1| 1| 0| 1',
        'BOYS_LOVE| Boys Love.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Boys Love| #85ADAC| 1| 1| 0| 1',
        'CARS| Cars.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cars| #7B36D2| 1| 1| 0| 1',
        'CHILDREN| Children.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Children| #9C42C2| 1| 1| 0| 1',
        'COMEDY| Comedy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Comedy| #B7363E| 1| 1| 0| 1',
        'COMPETITION| Competition.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Competition| #55BF48| 1| 1| 0| 1',
        'CON_ARTIST| Con Artist.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Con Artist| #C7A5A1| 1| 1| 0| 1',
        'CREATURE_HORROR| Creature Horror.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Creature Horror| #AD8603| 1| 1| 0| 1',
        'CRIME| Crime.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Crime| #888888| 1| 1| 0| 1',
        'DEMONS| Demons.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Demons| #9A2A2A| 1| 1| 0| 1',
        'DAY_OF_PERSONS_WITH_DISABILITIES| Disabilities.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Disabilities| #40B9FE| 1| 1| 0| 1',
        'DOCUMENTARY| Documentary.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Documentary| #2C4FA8| 1| 1| 0| 1',
        'DRAMA| Drama.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Drama| #A22C2C| 1| 1| 0| 1',
        'ECCHI| Ecchi.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ecchi| #C592C0| 1| 1| 0| 1',
        'EROTICA| Erotica.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Erotica| #CA9FC9| 1| 1| 0| 1',
        'FAMILY| Family.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Family| #BABA6C| 1| 1| 0| 1',
        'FANTASY| Fantasy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Fantasy| #CC2BC6| 1| 1| 0| 1',
        'FILM_NOIR| Film Noir.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Film Noir| #5B5B5B| 1| 1| 0| 1',
        'FOOD| Food.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Food| #A145C1| 1| 1| 0| 1',
        'FOUND_FOOTAGE_HORROR| Found Footage Horror.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Found Footage Horror| #2C3B08| 1| 1| 0| 1',
        'GAME_SHOW| Game Show.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Game Show| #32D184| 1| 1| 0| 1',
        'GAME| Game.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Game| #70BD98| 1| 1| 0| 1',
        'GANGSTER| Gangster.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Gangster| #77ACBD| 1| 1| 0| 1',
        'GIRLS_LOVE| Girls Love.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Girls Love| #AC86AD| 1| 1| 0| 1',
        'GOURMET| Gourmet.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Gourmet| #83AC8F| 1| 1| 0| 1',
        'HAREM| Harem.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Harem| #7DB0C5| 1| 1| 0| 1',
        'HEIST| Heist.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Heist| #4281C9| 1| 1| 0| 1',
        'HENTAI| Hentai.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hentai| #B274BF| 1| 1| 0| 1',
        'HISTORY| History.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | History| #B7A95D| 1| 1| 0| 1',
        'HOME_AND_GARDEN| Home and Garden.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Home and Garden| #8CC685| 1| 1| 0| 1',
        'HORROR| Horror.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Horror| #B94948| 1| 1| 0| 1',
        'INDIE| Indie.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Indie| #BB7493| 1| 1| 0| 1',
        'KIDS| Kids.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Kids| #9F40C6| 1| 1| 0| 1',
        'LATINX_HERITAGE_MONTH| LatinX Month.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | LatinX| #FF5F5F| 1| 1| 0| 1',
        'LGBTQ| LGBTQ+.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | LGBTQ+| #BD86C4| 1| 1| 0| 1',
        'LGBTQ_PRIDE_MONTH| LGBTQ+ Month.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | LGBTQ+ Month| #FF3B3C| 1| 1| 0| 1',
        'MARTIAL_ARTS| Martial Arts.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Martial Arts| #777777| 1| 1| 0| 1',
        'MECHA| Mecha.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mecha| #8B8B8B| 1| 1| 0| 1',
        'MILITARY| Military.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Military| #87552F| 1| 1| 0| 1',
        'MIND_BEND| Mind-Bend.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mind-Bend| #619DA2| 1| 1| 0| 1',
        'MIND_FUCK| Mind-Fuck.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mind-Fuck| #619DA2| 1| 1| 0| 1',
        'MIND_F**K| Mind-Fuck2.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mind-Fuck2| #619DA2| 1| 1| 0| 1',
        'MINI_SERIES| Mini-Series.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mini-Series| #66B7BE| 1| 1| 0| 1',
        'MMA| MMA.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MMA| #69E39F| 1| 1| 0| 1',
        'MUSIC| Music.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Music| #3CC79C| 1| 1| 0| 1',
        'MUSICAL| Musical.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Musical| #C38CB7| 1| 1| 0| 1',
        'MYSTERY| Mystery.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Mystery| #867CB5| 1| 1| 0| 1',
        'NEWS_POLITICS| News & Politics.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | News & Politics| #C83131| 1| 1| 0| 1',
        'NEWS| News.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | News| #C83131| 1| 1| 0| 1',
        'OUTDOOR_ADVENTURE| Outdoor Adventure.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Outdoor Adventure| #56C89C| 1| 1| 0| 1',
        'PARODY| Parody.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Parody| #83A9A2| 1| 1| 0| 1',
        'POLICE| Police.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Police| #262398| 1| 1| 0| 1',
        'POLITICS| Politics.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Politics| #3F5FC0| 1| 1| 0| 1',
        'PSYCHEDELIC| Psychedelic.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Psychedelic| #E973F6| 1| 1| 0| 0',
        'PSYCHOLOGICAL_HORROR| Psychological Horror.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Psychological Horror| #AC5969| 1| 1| 0| 1',
        'PSYCHOLOGICAL| Psychological.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Psychological| #C79367| 1| 1| 0| 1',
        'REALITY| Reality.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Reality| #7CB6AE| 1| 1| 0| 1',
        'ROMANCE| Romance.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Romance| #B6398E| 1| 1| 0| 1',
        'ROMANTIC_COMEDY| Romantic Comedy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Romantic Comedy| #B2445D| 1| 1| 0| 1',
        'ROMANTIC_DRAMA| Romantic Drama.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Romantic Drama| #AB89C0| 1| 1| 0| 1',
        'SAMURAI| Samurai.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Samurai| #C0C282| 1| 1| 0| 1',
        'SCHOOL| School.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | School| #4DC369| 1| 1| 0| 1',
        'SCI-FI_&_FANTASY| Sci-Fi & Fantasy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sci-Fi & Fantasy| #9254BA| 1| 1| 0| 1',
        'SCIENCE_FICTION| Science Fiction.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Science Fiction| #545FBA| 1| 1| 0| 1',
        'SERIAL_KILLER| Serial Killer.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Serial Killer| #163F56| 1| 1| 0| 1',
        'SHORT| Short.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Short| #BCBB7B| 1| 1| 0| 1',
        'SHOUJO| Shoujo.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Shoujo| #89529D| 1| 1| 0| 1',
        'SHOUNEN| Shounen.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Shounen| #505E99| 1| 1| 0| 1',
        'SLASHER| Slasher.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Slasher| #B75157| 1| 1| 0| 1',
        'SLICE_OF_LIFE| Slice of Life.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Slice of Life| #C696C4| 1| 1| 0| 1',
        'SOAP| Soap.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Soap| #AF7CC0| 1| 1| 0| 1',
        'SPACE| Space.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Space| #A793C1| 1| 1| 0| 1',
        'SPORT| Sport.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sport| #587EB1| 1| 1| 0| 1',
        'SPY| Spy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Spy| #B7D99F| 1| 1| 0| 1',
        'STAND-UP_COMEDY| Stand-Up Comedy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Stand-Up Comedy| #CF8A49| 1| 1| 0| 1',
        'STONER_COMEDY| Stoner Comedy.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Stoner Comedy| #79D14D| 1| 1| 0| 1',
        'SUPER_POWER| Super Power.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Super Power| #279552| 1| 1| 0| 1',
        'SUPERHERO| Superhero.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Superhero| #DA8536| 1| 1| 0| 1',
        'SUPERNATURAL| Supernatural.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Supernatural| #262693| 1| 1| 0| 1',
        'SURVIVAL| Survival.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Survival| #434447| 1| 1| 0| 1',
        'SUSPENSE| Suspense.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Suspense| #AE5E37| 1| 1| 0| 1',
        'SWORD_SORCERY| Sword & Sorcery.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sword & Sorcery| #B44FBA| 1| 1| 0| 1',
        'TV_MOVIE| TV Movie.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV Movie| #85A5B4| 1| 1| 0| 1',
        'TALK_SHOW| Talk Show.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Talk Show| #82A2B5| 1| 1| 0| 1',
        'THRILLER| Thriller.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Thriller| #C3602B| 1| 1| 0| 1',
        'TRAVEL| Travel.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Travel| #B6BA6D| 1| 1| 0| 1',
        'VAMPIRE| Vampire.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Vampire| #7D2627| 1| 1| 0| 1',
        'UFO| Ufo.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Ufo| #529D82| 1| 1| 0| 1',
        'WAR_POLITICS| War & Politics.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | War & Politics| #4ABF6E| 1| 1| 0| 1',
        'WAR| War.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | War| #63AB62| 1| 1| 0| 1',
        'WESTERN| Western.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Western| #AD9B6D| 1| 1| 0| 1',
        'WOMENS_HISTORY_MONTH| Womens History.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Womens Month| #874E83| 1| 1| 0| 1',
        'ZOMBIE_HORROR| Zombie Horror.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Zombie Horror| #909513| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_genre\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination genre
    Copy-Item -Path logos_genre -Destination genre\logos -Recurse
    Move-Item -Path output-orig -Destination output

}

################################################################################
# Function: CreateNetwork
# Description:  Creates Network
################################################################################
Function CreateNetwork {
    Write-Host "Creating Network"
    Set-Location $script_path
    # Find-Path "$script_path\network"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'network_kids_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Other Kids Networks| #FF2000| 1| 1| 0| 1',
        'network_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Other Networks| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        ' | A&E.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | A&E| #676767| 1| 1| 0| 1',
        ' | ABC (AU).png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABC (AU)| #CEC281| 1| 1| 0| 1',
        ' | ABC (AU).png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABC TV| #CEC281| 1| 1| 0| 1',
        ' | ABC Family.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABC Family| #73D444| 1| 1| 0| 1',
        ' | ABC Kids.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABC Kids| #6172B9| 1| 1| 0| 1',
        ' | ABC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABC| #403993| 1| 1| 0| 1',
        ' | ABS-CBN.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ABS-CBN| #16F67B| 1| 1| 0| 1',
        ' | Acorn TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Acorn TV| #182034| 1| 1| 0| 1',
        ' | Adult Swim.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Adult Swim| #C0A015| 1| 1| 0| 1',
        ' | AltBalaji.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AltBalaji| #00CC30| 1| 1| 0| 1',
        ' | Amazon Kids+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Amazon Kids+| #8E2AAF| 1| 1| 0| 1',
        ' | Amazon.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Amazon| #9B8832| 1| 1| 0| 1',
        ' | AMC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AMC| #4A9472| 1| 1| 0| 1',
        ' | Animal Planet.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Animal Planet| #4389BA| 1| 1| 0| 1',
        ' | Antena 3.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Antena 3| #306A94| 1| 1| 0| 1',
        ' | Apple TV+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Apple TV+| #313131| 1| 1| 0| 1',
        ' | ARD.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ARD| #3F76D7| 1| 1| 0| 1',
        ' | Arte.png| +0| 400| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Arte| #378BC4| 1| 1| 0| 1',
        ' | AT-X.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | AT-X| #BEDA86| 1| 1| 0| 1',
        ' | BBC America.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BBC America| #C83535| 1| 1| 0| 1',
        ' | BBC Four.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BBC Four| #02A0D2| 1| 1| 0| 1',
        ' | BBC One.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BBC One| #3A38C6| 1| 1| 0| 1',
        ' | BBC Two.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BBC Two| #9130B1| 1| 1| 0| 1',
        ' | BBC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BBC| #A24649| 1| 1| 0| 1',
        ' | BET+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BET+| #B3359C| 1| 1| 0| 1',
        ' | BET.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BET| #942C2C| 1| 1| 0| 1',
        ' | bilibili.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bilibili| #677626| 1| 1| 0| 1',
        ' | BluTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BluTV| #1E6DA3| 1| 1| 0| 1',
        ' | Boomerang.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Boomerang| #6190B3| 1| 1| 0| 1',
        ' | Bravo.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Bravo| #6D6D6D| 1| 1| 0| 1',
        ' | BritBox.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | BritBox| #198CA8| 1| 1| 0| 1',
        ' | Canal+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Canal+| #FB78AE| 1| 1| 0| 1',
        ' | Cartoon Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cartoon Network| #6084A0| 1| 1| 0| 1',
        ' | Cartoonito.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cartoonito| #2D9EB2| 1| 1| 0| 1',
        ' | CBC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | CBC Television| #9D3B3F| 1| 1| 0| 1',
        ' | CBC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | CBC| #9D3B3F| 1| 1| 0| 1',
        ' | Cbeebies.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cbeebies| #AFA619| 1| 1| 0| 1',
        ' | CBS.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | CBS| #2926C0| 1| 1| 0| 1',
        ' | Channel 3.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Channel 3| #FF85AF| 1| 1| 0| 1',
        ' | Channel 4.png| +0| 1000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Channel 4| #2B297D| 1| 1| 0| 1',
        ' | Channel 5.png| +0| 1000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Channel 5| #8C28AD| 1| 1| 0| 1',
        ' | Cinemax.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cinemax| #B4AB22| 1| 1| 0| 1',
        ' | Citytv.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Citytv| #C23B40| 1| 1| 0| 1',
        ' | CNN.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | CNN| #AE605C| 1| 1| 0| 1',
        ' | Comedy Central.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Comedy Central| #BFB516| 1| 1| 0| 1',
        ' | Cooking Channel.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Cooking Channel| #C29B16| 1| 1| 0| 1',
        ' | Criterion Channel.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Criterion Channel| #810BA7| 1| 1| 0| 1',
        ' | Crunchyroll.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Crunchyroll| #C9761D| 1| 1| 0| 1',
        ' | CTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | CTV| #1FAA3C| 1| 1| 0| 1',
        ' | Curiosity Stream.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Curiosity Stream| #BF983F| 1| 1| 0| 1',
        ' | Dave.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Dave| #32336C| 1| 1| 0| 1',
        ' | Discovery Kids.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Discovery Kids| #1C7A1E| 1| 1| 0| 1',
        ' | discovery+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | discovery+| #2175D9| 1| 1| 0| 1',
        ' | Discovery.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Discovery| #1E1CBD| 1| 1| 0| 1',
        ' | Disney Channel.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Disney Channel| #3679C4| 1| 1| 0| 1',
        ' | Disney Junior.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Disney Junior| #C33B40| 1| 1| 0| 1',
        ' | Disney XD.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Disney XD| #6BAB6D| 1| 1| 0| 1',
        ' | Disney+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Disney+| #0F2FA4| 1| 1| 0| 1',
        ' | E!.png| +0| 500| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | E!| #BF3137| 1| 1| 0| 1',
        ' | Epix.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Epix| #8E782B| 1| 1| 0| 1',
        ' | ESPN.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ESPN| #B82B30| 1| 1| 0| 1',
        ' | Family Channel.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Family Channel| #3841B6| 1| 1| 0| 1',
        ' | Food Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Food Network| #B97A7C| 1| 1| 0| 1',
        ' | Fox Kids.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Fox Kids| #B7282D| 1| 1| 0| 1',
        ' | FOX.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | FOX| #474EAB| 1| 1| 0| 1',
        ' | Freeform.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Freeform| #3C9C3E| 1| 1| 0| 1',
        ' | Freevee.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Freevee| #B5CF1B| 1| 1| 0| 1',
        ' | Fuji TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Fuji TV| #29319C| 1| 1| 0| 1',
        ' | FX.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | FX| #4A51A9| 1| 1| 0| 1',
        ' | FXX.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | FXX| #5070A7| 1| 1| 0| 1',
        ' | Game Show Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Game Show Network| #BA27BF| 1| 1| 0| 1',
        ' | Global TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Global TV| #409E42| 1| 1| 0| 1',
        ' | Globoplay.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Globoplay| #775E92| 1| 1| 0| 1',
        ' | GMA Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | GMA Network| #A755A4| 1| 1| 0| 1',
        ' | Hallmark.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hallmark| #601CB4| 1| 1| 0| 1',
        ' | HBO Max.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | HBO Max| #7870B9| 1| 1| 0| 1',
        ' | HBO.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | HBO| #458EAD| 1| 1| 0| 1',
        ' | HGTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | HGTV| #3CA38F| 1| 1| 0| 1',
        ' | History.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | History| #A57E2E| 1| 1| 0| 1',
        ' | Hulu.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Hulu| #1BC073| 1| 1| 0| 1',
        ' | IFC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IFC| #296FB4| 1| 1| 0| 1',
        ' | IMDb TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | IMDb TV| #C1CD2F| 1| 1| 0| 1',
        ' | Investigation Discovery.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Investigation Discovery| #BD5054| 1| 1| 0| 1',
        ' | ION Television.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ION Television| #850ECC| 1| 1| 0| 1',
        ' | iQiyi.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | iQiyi| #F26F4C| 1| 1| 0| 1',
        ' | ITV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ITV| #B024B5| 1| 1| 0| 1',
        ' | KBS2.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | KBS2| #0D197B| 1| 1| 0| 1',
        ' | Kids WB.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Kids WB| #B52429| 1| 1| 0| 1',
        ' | Las Estrellas.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Las Estrellas| #DD983B| 1| 1| 0| 1',
        ' | Lifetime.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Lifetime| #B61F64| 1| 1| 0| 1',
        ' | MasterClass.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MasterClass| #4D4D4D| 1| 1| 0| 1',
        ' | Max.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Max| #002BE7| 1| 1| 0| 1',
        ' | MBC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MBC| #AF1287| 1| 1| 0| 1',
        ' | MTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | MTV| #76A3AF| 1| 1| 0| 1',
        ' | National Geographic.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | National Geographic| #C6B31B| 1| 1| 0| 1',
        ' | NBC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | NBC| #703AAC| 1| 1| 0| 1',
        ' | Netflix.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Netflix| #B42A33| 1| 1| 0| 1',
        ' | Nick Jr.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nick Jr| #4290A4| 1| 1| 0| 1',
        ' | Nick.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nick| #B68021| 1| 1| 0| 1',
        ' | Nickelodeon.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nickelodeon| #C56A16| 1| 1| 0| 1',
        ' | Nicktoons.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nicktoons| #C56B17| 1| 1| 0| 1',
        ' | Nippon TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Nippon TV| #7E180F| 1| 1| 0| 1',
        ' | Oxygen.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Oxygen| #CBB23E| 1| 1| 0| 1',
        ' | Paramount Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Paramount Network| #9DE60E| 1| 1| 0| 1',
        ' | Paramount+.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Paramount+| #2A67CC| 1| 1| 0| 1',
        ' | PBS Kids.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | PBS Kids| #47A149| 1| 1| 0| 1',
        ' | PBS.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | PBS| #3A4894| 1| 1| 0| 1',
        ' | Peacock.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Peacock| #DA4428| 1| 1| 0| 1',
        ' | Prime Video.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Prime Video| #11607E| 1| 1| 0| 1',
        ' | RTL.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | RTL| #21354A| 1| 1| 0| 1',
        ' | SBS.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | SBS| #BEBC19| 1| 1| 0| 1',
        ' | Shahid.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Shahid| #7FEB9A| 1| 1| 0| 1',
        ' | Showcase.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Showcase| #4D4D4D| 1| 1| 0| 1',
        ' | Showtime.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Showtime| #C2201F| 1| 1| 0| 1',
        ' | Shudder.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Shudder| #0D0C89| 1| 1| 0| 1',
        ' | Sky.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sky| #BC3272| 1| 1| 0| 1',
        ' | Smithsonian.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Smithsonian| #303F8F| 1| 1| 0| 1',
        ' | Spike.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Spike| #ADAE74| 1| 1| 0| 1',
        ' | Stan.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Stan| #227CC0| 1| 1| 0| 1',
        ' | Starz.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Starz| #464646| 1| 1| 0| 1',
        ' | Sundance TV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Sundance TV| #424242| 1| 1| 0| 1',
        ' | SVT1.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | SVT1| #94BE7C| 1| 1| 0| 1',
        ' | Syfy.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Syfy| #BEB42D| 1| 1| 0| 1',
        ' | TBS.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TBS| #A139BF| 1| 1| 0| 1',
        ' | Telemundo.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Telemundo| #407160| 1| 1| 0| 1',
        ' | Tencent Video.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Tencent Video| #DE90F0| 1| 1| 0| 1',
        ' | TF1.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TF1| #43D582| 1| 1| 0| 1',
        ' | The CW.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | The CW| #397F96| 1| 1| 0| 1',
        ' | TLC.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TLC| #BA6C70| 1| 1| 0| 1',
        ' | TNT.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TNT| #C1B83A| 1| 1| 0| 1',
        ' | tokyo mx.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tokyo mx| #8662EA| 1| 1| 0| 1',
        ' | Travel Channel.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Travel Channel| #D4FFD9| 1| 1| 0| 1',
        ' | truTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | truTV| #C79F26| 1| 1| 0| 1',
        ' | Turner Classic Movies.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Turner Classic Movies| #616161| 1| 1| 0| 1',
        ' | TV 2.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV 2| #8040C7| 1| 1| 0| 1',
        ' | tv asahi.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tv asahi| #DD1A67| 1| 1| 0| 1',
        ' | TV Globo.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV Globo| #C8A69F| 1| 1| 0| 1',
        ' | TV Land.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV Land| #78AFB4| 1| 1| 0| 1',
        ' | TV Tokyo.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV Tokyo| #EC00E2| 1| 1| 0| 1',
        ' | TV3.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TV3| #FACED0| 1| 1| 0| 1',
        ' | TVB Jade.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | TVB Jade| #C6582F| 1| 1| 0| 1',
        ' | tving.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tving| #B2970D| 1| 1| 0| 1',
        ' | tvN.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tvN| #510F23| 1| 1| 0| 1',
        ' | UKTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | UKTV| #2EADB1| 1| 1| 0| 1',
        ' | UniMás.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | UniMás| #3A4669| 1| 1| 0| 1',
        ' | Universal Kids.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Universal Kids| #2985A1| 1| 1| 0| 1',
        ' | Univision.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Univision| #28BE59| 1| 1| 0| 1',
        ' | UPN.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | UPN| #C6864E| 1| 1| 0| 1',
        ' | USA Network.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | USA Network| #F7EB20| 1| 1| 0| 1',
        ' | USA.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | USA| #C0565B| 1| 1| 0| 1',
        ' | VH1.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | VH1| #8E3BB1| 1| 1| 0| 1',
        ' | Viaplay.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Viaplay| #30F7FB| 1| 1| 0| 1',
        ' | Vice.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Vice| #D3D3D3| 1| 1| 0| 1',
        ' | ViuTV.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ViuTV| #D3ADE3| 1| 1| 0| 1',
        ' | Warner Bros..png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Warner Bros.| #39538F| 1| 1| 0| 1',
        ' | WE tv.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | WE tv| #15DD51| 1| 1| 0| 1',
        ' | Youku.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | Youku| #42809E| 1| 1| 0| 1',
        ' | YouTube.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | YouTube| #C51414| 1| 1| 0| 1',
        ' | ZDF.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ZDF| #C58654| 1| 1| 0| 1',
        ' | ZEE5.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ZEE5| #8704C1| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_network\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination network
    Copy-Item -Path logos_network -Destination network\logos -Recurse
    Move-Item -Path output-orig -Destination output
    
}

################################################################################
# Function: CreatePlaylist
# Description:  Creates Playlist
################################################################################
Function CreatePlaylist {
    Write-Host "Creating Playlist"
    Set-Location $script_path
    # Find-Path "$script_path\playlist"
    $theMaxWidth = 1600
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 140

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'TIMELINE_ORDER| Arrowverse.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Arrowverse (Timeline Order)| #2B8F40| 1| 1| 0| 1',
        'TIMELINE_ORDER| DragonBall.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Dragon Ball (Timeline Order)| #E39D30| 1| 1| 0| 1',
        'TIMELINE_ORDER| Marvel Cinematic Universe.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Marvel Cinematic Universe (Timeline Order)| #AD2B2B| 1| 1| 0| 1',
        'TIMELINE_ORDER| Star Trek.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Star Trek (Timeline Order)| #0193DD| 1| 1| 0| 1',
        'TIMELINE_ORDER| Pokémon.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Pokémon (Timeline Order)| #FECA06| 1| 1| 0| 1',
        'TIMELINE_ORDER| dca.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | DC Animated Universe (Timeline Order)| #2832C4| 1| 1| 0| 1',
        'TIMELINE_ORDER| X-men.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | X-Men (Timeline Order)| #636363| 1| 1| 0| 1',
        'TIMELINE_ORDER| Star Wars The Clone Wars.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Star Wars The Clone Wars (Timeline Order)| #ED1C24| 1| 1| 0| 1',
        'TIMELINE_ORDER| Star Wars.png| -200| 1600| +450| Bebas-Regular| | #FFFFFF| 0| 15| #FFFFFF| | Star Wars (Timeline Order)| #F8C60A| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_playlist\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination playlist
    Copy-Item -Path logos_playlist -Destination playlist\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateResolution
# Description:  Creates Resolution
################################################################################
Function CreateResolution {
    Write-Host "Creating Resolution"
    Set-Location $script_path
    # Find-Path "$script_path\resolution"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250
    
    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'resolutions_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| 4K.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 4k| #8A46CF| 1| 1| 0| 1',
        '| 8K.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 8k| #95BCDC| 1| 1| 0| 1',
        '| 144p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 144| #F0C5E5| 1| 1| 0| 1',
        '| 240p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 240| #DFA172| 1| 1| 0| 1',
        '| 360p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 360| #6D3FDC| 1| 1| 0| 1',
        '| 480p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 480| #3996D3| 1| 1| 0| 1',
        '| 576p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 576| #DED1B2| 1| 1| 0| 1',
        '| 720p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 720| #30DC76| 1| 1| 0| 1',
        '| 1080p.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 1080| #D60C0C| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'


    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_resolution\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination resolution
    
    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'resolutions_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| ultrahd.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 4k| #8A46CF| 1| 1| 0| 1',
        '| sd.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 480| #95BCDC| 1| 1| 0| 1',
        '| hdready.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 720| #F0C5E5| 1| 1| 0| 1',
        '| fullhd.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | 1080| #DFA172| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_resolution\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination resolution\standards
    Copy-Item -Path logos_resolution -Destination resolution\logos -Recurse
    Move-Item -Path output-orig -Destination output
    
}

################################################################################
# Function: CreateSeasonal
# Description:  Creates Seasonal
################################################################################
Function CreateSeasonal {
    Write-Host "Creating Seasonal"
    Set-Location $script_path
    # Find-Path "$script_path\seasonal"
    Move-Item -Path output -Destination output-orig
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '4/20| 420.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | 420| #43C32F| 1| 1| 0| 1',
        'CHRISTMAS| christmas.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | christmas| #D52414| 1| 1| 0| 1',
        'EASTER| easter.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | easter| #46D69D| 1| 1| 0| 1',
        'FATHERS_DAY| father.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | father| #7CDA83| 1| 1| 0| 1',
        'HALLOWEEN| halloween.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | halloween| #DA8B25| 1| 1| 0| 1',
        'INDEPENDENCE_DAY| independence.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | independence| #2931CB| 1| 1| 0| 1',
        'LABOR_DAY| labor.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | labor| #DA5C5E| 1| 1| 0| 1',
        'MEMORIAL_DAY| memorial.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | memorial| #917C5C| 1| 1| 0| 1',
        'MOTHERS_DAY| mother.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mother| #DB81D6| 1| 1| 0| 1',
        'ST_PATRICKS_DAY| patrick.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | patrick| #26A53E| 1| 1| 0| 1',
        'THANKSGIVING| thanksgiving.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | thanksgiving| #A1841E| 1| 1| 0| 1',
        'VALENTINES_DAY| valentine.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | valentine| #D12AAE| 1| 1| 0| 1',
        'VETERANS_DAY| veteran.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | veteran| #B6AD93| 1| 1| 0| 1',
        'NEW_YEAR| years.png| -500| 1800| +850| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | years| #444444| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_seasonal\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr

    Move-Item -Path output -Destination seasonal
    Copy-Item -Path logos_seasonal -Destination seasonal\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateSeparators
# Description:  Creates Separators
################################################################################
Function CreateSeparators {
    Write-Host "Creating Separators"
    WriteToLogFile "ImageMagick Commands for     : Separators"
    Set-Location $script_path
    Move-Item -Path output -Destination output-orig
    Find-Path "$script_path\output"
    $colors = @('amethyst', 'aqua', 'blue', 'forest', 'fuchsia', 'gold', 'gray', 'green', 'navy', 'ocean', 'olive', 'orchid', 'orig', 'pink', 'plum', 'purple', 'red', 'rust', 'salmon', 'sand', 'stb', 'tan')
    foreach ($color in $colors) {
        Find-Path "$script_path\output\$color"
    }

    $value = Get-YamlPropertyValue -PropertyPath "collections.COLLECTIONLESS.name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    .\create_poster.ps1 -logo "$script_path\logos_chart\Plex.png" -logo_offset -500 -logo_resize 1500 -text "$value" -text_offset +850 -font "ComfortAa-Medium" -font_size 195 -font_color "#FFFFFF" -border 0 -border_width 15 -border_color "#FFFFFF" -avg_color_image "" -out_name "collectionless" -base_color "#DC9924" -gradient 1 -avg_color 0 -clean 1 -white_wash 1
    Move-Item -Path $script_path\output\collectionless.jpg -Destination $script_path\collectionless.jpg

    $theMaxWidth = 1900
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 203

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'COLLECTIONLESS| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | collectionless| | 0| 1| 0| 0',
        'ACTOR| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | actor| | 0| 1| 0| 0',
        'AUDIO_LANGUAGE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | audio_language| | 0| 1| 0| 0',
        'AWARD| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | award| | 0| 1| 0| 0',
        'CHART| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | chart| | 0| 1| 0| 0',
        'CONTENT_RATINGS| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | content_rating| | 0| 1| 0| 0',
        'COUNTRY| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | country| | 0| 1| 0| 0',
        'DECADE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | decade| | 0| 1| 0| 0',
        'DIRECTOR| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | director| | 0| 1| 0| 0',
        'FRANCHISE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | franchise| | 0| 1| 0| 0',
        'GENRE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | genre| | 0| 1| 0| 0',
        'KIDS_NETWORK| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | network_kids| | 0| 1| 0| 0',
        'MOVIE_CHART| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | movie_chart| | 0| 1| 0| 0',
        'NETWORK| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | network| | 0| 1| 0| 0',
        'PERSONAL| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | personal| | 0| 1| 0| 0',
        'PRODUCER| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | producer| | 0| 1| 0| 0',
        'RESOLUTION| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | resolution| | 0| 1| 0| 0',
        'SEASONAL| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | seasonal| | 0| 1| 0| 0',
        'STREAMING| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | streaming| | 0| 1| 0| 0',
        'STUDIO_ANIMATION| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | studio_animation| | 0| 1| 0| 0',
        'STUDIO| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | studio| | 0| 1| 0| 0',
        'SUBTITLE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | subtitle_language| | 0| 1| 0| 0',
        'TV_CHART| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tv_chart| | 0| 1| 0| 0',
        'UK_NETWORK| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | network_uk| | 0| 1| 0| 0',
        'UK_STREAMING| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | streaming_uk| | 0| 1| 0| 0',
        'UNIVERSE| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | universe| | 0| 1| 0| 0',
        'US_NETWORK| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | network_us| | 0| 1| 0| 0',
        'US_STREAMING| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | streaming_us| | 0| 1| 0| 0',
        'WRITER| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | writer| | 0| 1| 0| 0',
        'YEAR| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | year| | 0| 1| 0| 0',
        'BASED_ON| | +0| 2000| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | based| | 0| 1| 0| 0'
    ) | ConvertFrom-Csv -Delimiter '|'

    $pre_value = Get-YamlPropertyValue -PropertyPath "collections.separator.name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    $arr = @()
    foreach ($item in $myArray) {
        $value = Set-TextBetweenDelimiters -InputString $pre_value -ReplacementString (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        foreach ($color in $colors) {
            $arr += ".\create_poster.ps1 -logo `"$script_path\@base\$color.png`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"\$color\$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
        }
    }
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination separators
    Copy-Item -Path "@base" -Destination "separators\@base" -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateStreaming
# Description:  Creates Streaming
################################################################################
Function CreateStreaming {
    Write-Host "Creating Streaming"
    Set-Location $script_path
    # Find-Path "$script_path\streaming"
    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| All 4.png| +0| 1000| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | All 4| #14AE9A| 1| 1| 0| 1',
        '| Apple TV+.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Apple TV+| #494949| 1| 1| 0| 1',
        '| BET+.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | BET+| #B3359C| 1| 1| 0| 1',
        '| BritBox.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | BritBox| #198CA8| 1| 1| 0| 1',
        '| crave.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | crave| #29C2F1| 1| 1| 0| 1',
        '| Crunchyroll.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Crunchyroll| #C9761D| 1| 1| 0| 1',
        '| discovery+.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | discovery+| #2175D9| 1| 1| 0| 1',
        '| Disney+.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Disney+| #0F2FA4| 1| 1| 0| 1',
        '| Funimation.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Funimation| #513790| 1| 1| 0| 1',
        '| hayu.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | hayu| #C9516D| 1| 1| 0| 1',
        '| HBO Max.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | HBO Max| #7870B9| 1| 1| 0| 1',
        '| Hulu.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Hulu| #1BC073| 1| 1| 0| 1',
        '| Max.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Max| #002BE7| 1| 1| 0| 1',
        '| My 5.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | My 5| #426282| 1| 1| 0| 1',
        '| Netflix.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Netflix| #B42A33| 1| 1| 0| 1',
        '| NOW.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | NOW| #215659| 1| 1| 0| 1',
        '| Paramount+.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Paramount+| #2A67CC| 1| 1| 0| 1',
        '| Peacock.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Peacock| #DA4428| 1| 1| 0| 1',
        '| Prime Video.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Prime Video| #11607E| 1| 1| 0| 1',
        '| Quibi.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Quibi| #AB5E73| 1| 1| 0| 1',
        '| Showtime.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Showtime| #BC1818| 1| 1| 0| 1',
        '| Stan.png| +0| 1600| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | Stan| #227CC0| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_streaming\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }

    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination streaming
    Copy-Item -Path logos_streaming -Destination streaming\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateStudio
# Description:  Creates Studio
################################################################################
Function CreateStudio {
    Write-Host "Creating Studio"
    Set-Location $script_path
    # Find-Path "$script_path\studio"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'studio_animation_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other_animation| #FF2000| 1| 1| 0| 1',
        'studio_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| 101 Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 101 Studios| #B69367| 1| 1| 0| 0',
        '| 20th Century Animation.png| 0| 1500| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 20th Century Animation| #9F3137| 1| 1| 0| 0',
        '| 20th Century Fox Television.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 20th Century Fox Television| #EF3F42| 1| 1| 0| 0',
        '| 20th Century Studios.png| 0| 1500| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 20th Century Studios| #3387C6| 1| 1| 0| 0',
        '| 21 Laps Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 21 Laps Entertainment| #FEC130| 1| 1| 0| 0',
        '| 3 Arts Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 251| #FFFFFF| 0| 15| #FFFFFF|  | 3 Arts Entertainment| #245674| 1| 1| 0| 0',
        '| 6th & Idaho.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 6th & Idaho| #9539BB| 1| 1| 0| 0',
        '| 87North Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 87North Productions| #3C13A1| 1| 1| 0| 0',
        '| 8bit.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | 8bit| #365F71| 1| 1| 0| 0',
        '| A+E Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | A+E Studios| #35359B| 1| 1| 0| 0',
        '| A-1 Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | A-1 Pictures| #5776A8| 1| 1| 0| 0',
        '| A.C.G.T..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | A.C.G.T.| #9C46DE| 1| 1| 0| 0',
        '| A24.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | A24| #B13098| 1| 1| 0| 0',
        '| ABC Signature.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | ABC Signature| #C127DA| 1| 1| 0| 0',
        '| ABC Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | ABC Studios| #62D6AC| 1| 1| 0| 0',
        '| Acca effe.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Acca effe| #1485D0| 1| 1| 0| 0',
        '| Actas.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Actas| #C9C4FF| 1| 1| 0| 0',
        '| AGBO.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | AGBO| #3D976E| 1| 1| 0| 0',
        '| AIC.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | AIC| #6DF7FB| 1| 1| 0| 0',
        '| Ajia-Do.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ajia-Do| #665AC4| 1| 1| 0| 0',
        '| Akatsuki.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Akatsuki| #8CC0AE| 1| 1| 0| 0',
        '| Amazon Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Amazon Studios| #D28109| 1| 1| 0| 0',
        '| Amblin Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Amblin Entertainment| #394E76| 1| 1| 0| 0',
        '| AMC Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | AMC Studios| #AE8434| 1| 1| 0| 0',
        '| Animation Do.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Animation Do| #408FE3| 1| 1| 0| 0',
        '| Ankama.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ankama| #CD717E| 1| 1| 0| 0',
        '| APPP.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | APPP| #4D4AAD| 1| 1| 0| 0',
        '| Ardustry Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ardustry Entertainment| #DDC8F4| 1| 1| 0| 0',
        '| Arms.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Arms| #50A8C3| 1| 1| 0| 0',
        '| Artland.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Artland| #6157CB| 1| 1| 0| 0',
        '| Artmic.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Artmic| #7381BE| 1| 1| 0| 0',
        '| Arvo Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Arvo Animation| #6117D1| 1| 1| 0| 0',
        '| Asahi Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Asahi Production| #BC9A43| 1| 1| 0| 0',
        '| Ashi Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ashi Productions| #6AB420| 1| 1| 0| 0',
        '| asread..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | asread.| #6CCDB4| 1| 1| 0| 0',
        '| AtelierPontdarc.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | AtelierPontdarc| #CD0433| 1| 1| 0| 0',
        '| B.CMAY PICTURES.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | B.CMAY PICTURES| #873E7F| 1| 1| 0| 0',
        '| Bad Hat Harry Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bad Hat Harry Productions| #FFFF00| 1| 1| 0| 0',
        '| Bad Robot.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bad Robot| #DCCCF6| 1| 1| 0| 0',
        '| Bad Wolf.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bad Wolf| #54F762| 1| 1| 0| 0',
        '| Bakken Record.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bakken Record| #4B3EDE| 1| 1| 0| 0',
        '| Bandai Namco Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bandai Namco Pictures| #4FC739| 1| 1| 0| 0',
        '| Bardel Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bardel Entertainment| #5009A5| 1| 1| 0| 0',
        '| BBC Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | BBC Studios| #8E9BF1| 1| 1| 0| 0',
        '| Bee Train.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bee Train| #804F23| 1| 1| 0| 0',
        '| Berlanti Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Berlanti Productions| #03F5AB| 1| 1| 0| 0',
        '| Bibury Animation Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bibury Animation Studios| #A7FAAA| 1| 1| 0| 0',
        '| bilibili.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | bilibili| #E85486| 1| 1| 0| 0',
        '| Blade.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Blade| #17D53B| 1| 1| 0| 0',
        '| Blown Deadline Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Blown Deadline Productions| #134419| 1| 1| 0| 0',
        '| Blue Sky Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Blue Sky Studios| #1E4678| 1| 1| 0| 0',
        '| Blumhouse Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Blumhouse Productions| #353535| 1| 1| 0| 0',
        '| Blur Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Blur Studio| #88623F| 1| 1| 0| 0',
        '| Bones.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bones| #C4AE14| 1| 1| 0| 0',
        '| Bosque Ranch Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bosque Ranch Productions| #604BA1| 1| 1| 0| 0',
        '| Box to Box Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Box to Box Films| #D87A5A| 1| 1| 0| 0',
        '| Brain''s Base.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Brain''s Base| #8A530E| 1| 1| 0| 0',
        '| Brandywine Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Brandywine Productions| #C47FF8| 1| 1| 0| 0',
        '| Bridge.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Bridge| #F0FF7F| 1| 1| 0| 0',
        '| C-Station.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | C-Station| #B40C76| 1| 1| 0| 0',
        '| C2C.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | C2C| #320AE4| 1| 1| 0| 0',
        '| Calt Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Calt Production| #F4572C| 1| 1| 0| 0',
        '| Canal+.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Canal+| #488681| 1| 1| 0| 0',
        '| Carnival Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Carnival Films| #ABD477| 1| 1| 0| 0',
        '| Castle Rock Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Castle Rock Entertainment| #7C2843| 1| 1| 0| 0',
        '| CBS Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | CBS Productions| #8E6C3C| 1| 1| 0| 0',
        '| CBS Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | CBS Studios| #E6DE92| 1| 1| 0| 0',
        '| Centropolis Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Centropolis Entertainment| #AE1939| 1| 1| 0| 0',
        '| Chernin Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Chernin Entertainment| #3D4A64| 1| 1| 0| 0',
        '| Children''s Playground Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Children''s Playground Entertainment| #151126| 1| 1| 0| 0',
        '| Chimp Television.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Chimp Television| #1221EB| 1| 1| 0| 0',
        '| Cinergi Pictures Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 282| #FFFFFF| 0| 15| #FFFFFF|  | Cinergi Pictures Entertainment| #A9B9D2| 1| 1| 0| 0',
        '| Cloud Hearts.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Cloud Hearts| #47EBDC| 1| 1| 0| 0',
        '| CloverWorks.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | CloverWorks| #6D578F| 1| 1| 0| 0',
        '| Colored Pencil Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Colored Pencil Animation| #FB6DFD| 1| 1| 0| 0',
        '| Columbia Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Columbia Pictures| #329763| 1| 1| 0| 0',
        '| CoMix Wave Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | CoMix Wave Films| #715AD3| 1| 1| 0| 0',
        '| Connect.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Connect| #2B3FA4| 1| 1| 0| 0',
        '| Constantin Film.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Constantin Film| #343B44| 1| 1| 0| 0',
        '| Cowboy Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Cowboy Films| #93F80E| 1| 1| 0| 0',
        '| Craftar Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Craftar Studios| #362BFF| 1| 1| 0| 0',
        '| Creators in Pack.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Creators in Pack| #6057C4| 1| 1| 0| 0',
        '| CygamesPictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | CygamesPictures| #8C5677| 1| 1| 0| 0',
        '| Dark Horse Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Dark Horse Entertainment| #11F499| 1| 1| 0| 0',
        '| David Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | David Production| #AB104E| 1| 1| 0| 0',
        '| DC Comics.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | DC Comics| #4277D7| 1| 1| 0| 0',
        '| Dino De Laurentiis Company.png| 0| 1600| 0| ComfortAa-Medium| 285| #FFFFFF| 0| 15| #FFFFFF|  | Dino De Laurentiis Company| #FDA8EB| 1| 1| 0| 0',
        '| Diomedéa.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Diomedéa| #E6A604| 1| 1| 0| 0',
        '| DLE.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | DLE| #65450D| 1| 1| 0| 0',
        '| Doga Kobo.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Doga Kobo| #BD0F0F| 1| 1| 0| 0',
        '| domerica.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | domerica| #4CC65F| 1| 1| 0| 0',
        '| Doozer.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Doozer| #38A897| 1| 1| 0| 0',
        '| Dreams Salon Entertainment Culture.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Dreams Salon Entertainment Culture| #138F97| 1| 1| 0| 0',
        '| DreamWorks Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | DreamWorks Pictures| #7F8EE7| 1| 1| 0| 0',
        '| DreamWorks Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | DreamWorks Studios| #F1A7BC| 1| 1| 0| 0',
        '| Drive.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Drive| #C80A46| 1| 1| 0| 0',
        '| Eleventh Hour Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Eleventh Hour Films| #301637| 1| 1| 0| 0',
        '| EMT Squared.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | EMT Squared| #62F7A1| 1| 1| 0| 0',
        '| Encourage Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Encourage Films| #357C76| 1| 1| 0| 0',
        '| Endeavor Content.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Endeavor Content| #24682A| 1| 1| 0| 0',
        '| ENGI.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | ENGI| #B5D798| 1| 1| 0| 0',
        '| Entertainment One.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Entertainment One| #F3A9F9| 1| 1| 0| 0',
        '| Eon Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Eon Productions| #DA52FB| 1| 1| 0| 0',
        '| Expectation Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Expectation Entertainment| #AE9483| 1| 1| 0| 0',
        '| Fandango.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Fandango| #BEC0B6| 1| 1| 0| 0',
        '| feel..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | feel.| #9268C7| 1| 1| 0| 0',
        '| Felix Film.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Felix Film| #7B2557| 1| 1| 0| 0',
        '| Fenz.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Fenz| #A6AD7F| 1| 1| 0| 0',
        '| FilmDistrict.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | FilmDistrict| #E5FC8C| 1| 1| 0| 0',
        '| FilmNation Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | FilmNation Entertainment| #98D9EE| 1| 1| 0| 0',
        '| Fortiche Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Fortiche Production| #63505B| 1| 1| 0| 0',
        '| Frederator Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Frederator Studios| #10DF97| 1| 1| 0| 0',
        '| Fuqua Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Fuqua Films| #329026| 1| 1| 0| 0',
        '| GAINAX.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | GAINAX| #A73034| 1| 1| 0| 0',
        '| Gallagher Films Ltd.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gallagher Films Ltd| #71ADBB| 1| 1| 0| 0',
        '| Gallop.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gallop| #5EC0A0| 1| 1| 0| 0',
        '| Gary Sanchez Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gary Sanchez Productions| #FED36B| 1| 1| 0| 0',
        '| Gaumont.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gaumont| #8F2734| 1| 1| 0| 0',
        '| Geek Toys.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Geek Toys| #5B5757| 1| 1| 0| 0',
        '| Gekkou.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gekkou| #02AB76| 1| 1| 0| 0',
        '| Gemba.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gemba| #BEE8C2| 1| 1| 0| 0',
        '| GENCO.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | GENCO| #705D63| 1| 1| 0| 0',
        '| Generator Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Generator Entertainment| #5C356A| 1| 1| 0| 0',
        '| Geno Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Geno Studio| #D504AB| 1| 1| 0| 0',
        '| GoHands.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | GoHands| #A683DD| 1| 1| 0| 0',
        '| Gonzo.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Gonzo| #C92A69| 1| 1| 0| 0',
        '| Graphinica.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Graphinica| #935FBB| 1| 1| 0| 0',
        '| Grindstone Entertainment Group.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Grindstone Entertainment Group| #B66736| 1| 1| 0| 0',
        '| Group Tac.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Group Tac| #157DB4| 1| 1| 0| 0',
        '| Hal Film Maker.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Hal Film Maker| #E085A4| 1| 1| 0| 0',
        '| Haoliners Animation League.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Haoliners Animation League| #A616E8| 1| 1| 0| 0',
        '| Happy Madison Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Happy Madison Productions| #278761| 1| 1| 0| 0',
        '| Hartswood Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Hartswood Films| #904D79| 1| 1| 0| 0',
        '| HBO.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | HBO| #4B35CD| 1| 1| 0| 0',
        '| Hoods Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Hoods Entertainment| #F5F5D1| 1| 1| 0| 0',
        '| Hotline.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Hotline| #45AB9A| 1| 1| 0| 0',
        '| Illumination Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Illumination Entertainment| #C7C849| 1| 1| 0| 0',
        '| Imagin.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Imagin| #241EFD| 1| 1| 0| 0',
        '| Imperative Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Imperative Entertainment| #39136F| 1| 1| 0| 0',
        '| Ingenious Media.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ingenious Media| #729A3B| 1| 1| 0| 0',
        '| J.C.Staff.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | J.C.Staff| #986BF3| 1| 1| 0| 0',
        '| Jerry Bruckheimer Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Jerry Bruckheimer Films| #70C954| 1| 1| 0| 0',
        '| Jumondou.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Jumondou| #AA58AA| 1| 1| 0| 0',
        '| Kadokawa.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kadokawa| #648E1A| 1| 1| 0| 0',
        '| Kazak Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kazak Productions| #BE6070| 1| 1| 0| 0',
        '| Kennedy Miller Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kennedy Miller Productions| #336937| 1| 1| 0| 0',
        '| Khara.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Khara| #538150| 1| 1| 0| 0',
        '| Kilter Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kilter Films| #CA1893| 1| 1| 0| 0',
        '| Kinema Citrus.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kinema Citrus| #87A92B| 1| 1| 0| 0',
        '| Kjam Media.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kjam Media| #CC0604| 1| 1| 0| 0',
        '| Kudos.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kudos| #4D11E8| 1| 1| 0| 0',
        '| Kyoto Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Kyoto Animation| #1C4744| 1| 1| 0| 0',
        '| Lan Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lan Studio| #989DED| 1| 1| 0| 0',
        '| LandQ Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | LandQ Studio| #4667C3| 1| 1| 0| 0',
        '| Landscape Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Landscape Entertainment| #3CBE98| 1| 1| 0| 0',
        '| Laura Ziskin Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Laura Ziskin Productions| #82883F| 1| 1| 0| 0',
        '| Lay-duce.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lay-duce| #0A1988| 1| 1| 0| 0',
        '| Legendary Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Legendary Pictures| #303841| 1| 1| 0| 0',
        '| Lerche.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lerche| #D42DAE| 1| 1| 0| 0',
        '| Let''s Not Turn This Into a Whole Big Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Let''s Not Turn This Into a Whole Big Production| #7597E6| 1| 1| 0| 0',
        '| LIDENFILMS.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | LIDENFILMS| #EF8907| 1| 1| 0| 0',
        '| Lionsgate.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lionsgate| #7D22A3| 1| 1| 0| 0',
        '| Lord Miller Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lord Miller Productions| #0F543F| 1| 1| 0| 0',
        '| Lucasfilm Ltd.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Lucasfilm Ltd| #22669B| 1| 1| 0| 0',
        '| M.S.C.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | M.S.C| #44FD9A| 1| 1| 0| 0',
        '| Madhouse.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Madhouse| #C58E2C| 1| 1| 0| 0',
        '| Magic Bus.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Magic Bus| #732AF6| 1| 1| 0| 0',
        '| Maho Film.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Maho Film| #B95BEB| 1| 1| 0| 0',
        '| Malevolent Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Malevolent Films| #5A6B7B| 1| 1| 0| 0',
        '| Mandarin Motion Pictures Limited.png| 0| 1600| 0| ComfortAa-Medium| 316| #FFFFFF| 0| 15| #FFFFFF|  | Mandarin Motion Pictures Limited| #509445| 1| 1| 0| 0',
        '| Mandarin.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Mandarin| #827715| 1| 1| 0| 0',
        '| Manglobe.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Manglobe| #085B61| 1| 1| 0| 0',
        '| MAPPA.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | MAPPA| #376430| 1| 1| 0| 0',
        '| Marvel Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Marvel Animation| #ED171F| 1| 1| 0| 0',
        '| Marvel Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Marvel Studios| #1ED8E3| 1| 1| 0| 0',
        '| Maximum Effort.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Maximum Effort| #CE4D0E| 1| 1| 0| 0',
        '| Media Res.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Media Res| #51251D| 1| 1| 0| 0',
        '| Metro-Goldwyn-Mayer.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Metro-Goldwyn-Mayer| #A48221| 1| 1| 0| 0',
        '| Millennium Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Millennium Films| #911213| 1| 1| 0| 0',
        '| Millepensee.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Millepensee| #7D9EAC| 1| 1| 0| 0',
        '| Miramax.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Miramax| #344B75| 1| 1| 0| 0',
        '| Namu Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Namu Animation| #FDD8D9| 1| 1| 0| 0',
        '| NAZ.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | NAZ| #476C7A| 1| 1| 0| 0',
        '| New Line Cinema.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | New Line Cinema| #67857E| 1| 1| 0| 0',
        '| Nexus.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Nexus| #F8D946| 1| 1| 0| 0',
        '| Nickelodeon Animation Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Nickelodeon Animation Studio| #5E9BFB| 1| 1| 0| 0',
        '| Nippon Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Nippon Animation| #4A688B| 1| 1| 0| 0',
        '| Nomad.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Nomad| #9FE1BF| 1| 1| 0| 0',
        '| Nut.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Nut| #0DAB93| 1| 1| 0| 0',
        '| Okuruto Noboru.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Okuruto Noboru| #88B27E| 1| 1| 0| 0',
        '| OLM.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | OLM| #98FA51| 1| 1| 0| 0',
        '| Orange.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Orange| #C4BEF5| 1| 1| 0| 0',
        '| Ordet.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Ordet| #0EEEF6| 1| 1| 0| 0',
        '| Original Film.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Original Film| #364B61| 1| 1| 0| 0',
        '| Orion Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Orion Pictures| #6E6E6E| 1| 1| 0| 0',
        '| OZ.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | OZ| #2EF68F| 1| 1| 0| 0',
        '| P.A. Works.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | P.A. Works| #A21B4B| 1| 1| 0| 0',
        '| P.I.C.S..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | P.I.C.S.| #A63FA8| 1| 1| 0| 0',
        '| Paramount Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Paramount Animation6| #3C3C3C| 1| 1| 0| 0',
        '| Paramount Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Paramount Pictures| #5D94B4| 1| 1| 0| 0',
        '| Paramount Television Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Paramount Television Studios| #E2D6BE| 1| 1| 0| 0',
        '| Passione.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Passione| #970A59| 1| 1| 0| 0',
        '| Pb Animation Co. Ltd.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pb Animation Co. Ltd| #003EB9| 1| 1| 0| 0',
        '| Pierrot.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pierrot| #C1CFBC| 1| 1| 0| 0',
        '| Piki Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Piki Films| #52CB78| 1| 1| 0| 0',
        '| Pine Jam.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pine Jam| #4C9C3F| 1| 1| 0| 0',
        '| Pixar.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pixar| #1668B0| 1| 1| 0| 0',
        '| Plan B Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Plan B Entertainment| #9084B5| 1| 1| 0| 0',
        '| Platinum Vision.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Platinum Vision| #70A8B4| 1| 1| 0| 0',
        '| PlayStation Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | PlayStation Productions| #478D03| 1| 1| 0| 0',
        '| Plum Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Plum Pictures| #ACCB76| 1| 1| 0| 0',
        '| Polygon Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Polygon Pictures| #741E67| 1| 1| 0| 0',
        '| Pony Canyon.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pony Canyon| #EECA46| 1| 1| 0| 0',
        '| Powerhouse Animation Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Powerhouse Animation Studios| #42A545| 1| 1| 0| 0',
        '| PRA.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | PRA| #DFA26E| 1| 1| 0| 0',
        '| Production +h..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Production +h.| #FC07C6| 1| 1| 0| 0',
        '| Production I.G.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Production I.G| #8843C2| 1| 1| 0| 0',
        '| Production IMS.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Production IMS| #169AB7| 1| 1| 0| 0',
        '| Production Reed.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Production Reed| #92F588| 1| 1| 0| 0',
        '| Project No.9.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Project No.9| #FDC471| 1| 1| 0| 0',
        '| Prospect Park.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Prospect Park| #F28C17| 1| 1| 0| 0',
        '| Pulse Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Pulse Films| #8EEB80| 1| 1| 0| 0',
        '| Quad.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Quad| #0CA0BE| 1| 1| 0| 0',
        '| Radix.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Radix| #1F2D33| 1| 1| 0| 0',
        '| RatPac Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | RatPac Entertainment| #91E130| 1| 1| 0| 0',
        '| Red Dog Culture House.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Red Dog Culture House| #46FDF5| 1| 1| 0| 0',
        '| Regency Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Regency Pictures| #1DD664| 1| 1| 0| 0',
        '| Reveille Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Reveille Productions| #1A527C| 1| 1| 0| 0',
        '| Revoroot.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Revoroot| #E8DEB3| 1| 1| 0| 0',
        '| RocketScience.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | RocketScience| #5767E4| 1| 1| 0| 0',
        '| Saetta.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Saetta| #46476A| 1| 1| 0| 0',
        '| SANZIGEN.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | SANZIGEN| #068509| 1| 1| 0| 0',
        '| Satelight.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Satelight| #D1B2CD| 1| 1| 0| 0',
        '| Science SARU.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Science SARU| #6948C1| 1| 1| 0| 0',
        '| Scott Free Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Scott Free Productions| #A425E7| 1| 1| 0| 0',
        '| Sean Daniel Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sean Daniel Company| #16EC29| 1| 1| 0| 0',
        '| Secret Hideout.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Secret Hideout| #3B18AD| 1| 1| 0| 0',
        '| See-Saw Films.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | See-Saw Films| #2D7D0F| 1| 1| 0| 0',
        '| Sentai Filmworks.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sentai Filmworks| #E00604| 1| 1| 0| 0',
        '| Seven Arcs.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Seven Arcs| #7B82BA| 1| 1| 0| 0',
        '| Shaft.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Shaft| #2BA8A4| 1| 1| 0| 0',
        '| Shin-Ei Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Shin-Ei Animation| #2798DA| 1| 1| 0| 0',
        '| Shogakukan.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Shogakukan| #739D5A| 1| 1| 0| 0',
        '| Showtime Networks.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Showtime Networks| #3EA9E8| 1| 1| 0| 0',
        '| Shuka.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Shuka| #925BD1| 1| 1| 0| 0',
        '| Signal.MD.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Signal.MD| #29113A| 1| 1| 0| 0',
        '| Sil-Metropole Organisation.png| 0| 1600| 0| ComfortAa-Medium| 335| #FFFFFF| 0| 15| #FFFFFF|  | Sil-Metropole Organisation| #48D4F2| 1| 1| 0| 0',
        '| SILVER LINK..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | SILVER LINK.| #06FF01| 1| 1| 0| 0',
        '| SISTER.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | SISTER| #BD6B5C| 1| 1| 0| 0',
        '| Sixteen String Jack Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sixteen String Jack Productions| #6D7D9E| 1| 1| 0| 0',
        '| Sky studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sky studios| #5F1D61| 1| 1| 0| 0',
        '| Skydance.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Skydance| #B443B5| 1| 1| 0| 0',
        '| Sony Pictures Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sony Pictures Animation| #498BA9| 1| 1| 0| 0',
        '| Sony Pictures.png| 0| 1200| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sony Pictures| #943EBD| 1| 1| 0| 0',
        '| Spyglass Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Spyglass Entertainment| #472659| 1| 1| 0| 0',
        '| Staple Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Staple Entertainment| #E1EB06| 1| 1| 0| 0',
        '| Studio 3Hz.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio 3Hz| #F7F5BC| 1| 1| 0| 0',
        '| Studio A-CAT.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio A-CAT| #049ABA| 1| 1| 0| 0',
        '| Studio Babelsberg.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Babelsberg| #7CAE06| 1| 1| 0| 0',
        '| Studio Bind.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Bind| #E20944| 1| 1| 0| 0',
        '| Studio Blanc..png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Blanc.| #6308CC| 1| 1| 0| 0',
        '| Studio Chizu.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Chizu| #68ACAA| 1| 1| 0| 0',
        '| Studio Comet.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Comet| #2D1337| 1| 1| 0| 0',
        '| Studio Deen.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Deen| #3A6EA8| 1| 1| 0| 0',
        '| Studio Dragon.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Dragon| #3ECAF1| 1| 1| 0| 0',
        '| Studio Elle.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Elle| #511DD7| 1| 1| 0| 0',
        '| Studio Flad.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Flad| #996396| 1| 1| 0| 0',
        '| Studio Ghibli.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Ghibli| #AB2F46| 1| 1| 0| 0',
        '| Studio Gokumi.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Gokumi| #D9C7A0| 1| 1| 0| 0',
        '| Studio Guts.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Guts| #832A64| 1| 1| 0| 0',
        '| Studio Hibari.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Hibari| #4F9E24| 1| 1| 0| 0',
        '| Studio Kafka.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Kafka| #7A2917| 1| 1| 0| 0',
        '| Studio Kai.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Kai| #CA3EC8| 1| 1| 0| 0',
        '| Studio Mir.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Mir| #723564| 1| 1| 0| 0',
        '| studio MOTHER.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | studio MOTHER| #203953| 1| 1| 0| 0',
        '| Studio Palette.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Palette| #5A17AC| 1| 1| 0| 0',
        '| Studio Rikka.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Rikka| #DB5318| 1| 1| 0| 0',
        '| Studio Signpost.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio Signpost| #597F70| 1| 1| 0| 0',
        '| Studio VOLN.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Studio VOLN| #6FDDE8| 1| 1| 0| 0',
        '| STUDIO4°C.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | STUDIO4°C| #33352C| 1| 1| 0| 0',
        '| Summit Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Summit Entertainment| #3898B6| 1| 1| 0| 0',
        '| Sunrise Beyond.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sunrise Beyond| #F6E84F| 1| 1| 0| 0',
        '| Sunrise.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Sunrise| #864B89| 1| 1| 0| 0',
        '| Syfy.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Syfy| #535FA5| 1| 1| 0| 0',
        '| Syncopy.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Syncopy| #1E940B| 1| 1| 0| 0',
        '| SynergySP.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | SynergySP| #0E82C8| 1| 1| 0| 0',
        '| Tall Ship Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Tall Ship Productions| #BD95BF| 1| 1| 0| 0',
        '| Tatsunoko Production.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Tatsunoko Production| #5A76B8| 1| 1| 0| 0',
        '| Team Downey.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Team Downey| #2EE0DD| 1| 1| 0| 0',
        '| Telecom Animation Film.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Telecom Animation Film| #2F562B| 1| 1| 0| 0',
        '| Tezuka Productions.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Tezuka Productions| #10259A| 1| 1| 0| 0',
        '| The Donners'' Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | The Donners'' Company| #625B26| 1| 1| 0| 0',
        '| The Kennedy-Marshall Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | The Kennedy-Marshall Company| #78A91F| 1| 1| 0| 0',
        '| The Linson Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | The Linson Company| #773D61| 1| 1| 0| 0',
        '| The Littlefield Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | The Littlefield Company| #9FE1C5| 1| 1| 0| 0',
        '| The Mark Gordon Company.png| 0| 1600| 0| ComfortAa-Medium| 350| #FFFFFF| 0| 15| #FFFFFF|  | The Mark Gordon Company| #9FD3D8| 1| 1| 0| 0',
        '| The Weinstein Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | The Weinstein Company| #927358| 1| 1| 0| 0',
        '| Titmouse.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Titmouse| #E5DCBD| 1| 1| 0| 0',
        '| TMS Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | TMS Entertainment| #68B823| 1| 1| 0| 0',
        '| TNK.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | TNK| #B7D0AF| 1| 1| 0| 0',
        '| Toei Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Toei Animation| #63A2B1| 1| 1| 0| 0',
        '| Tomorrow Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Tomorrow Studios| #397DC4| 1| 1| 0| 0',
        '| Topcraft.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Topcraft| #285732| 1| 1| 0| 0',
        '| Touchstone Pictures.png| 0| 1600| 0| ComfortAa-Medium| 353| #FFFFFF| 0| 15| #FFFFFF|  | Touchstone Pictures| #0C8F4D| 1| 1| 0| 0',
        '| Touchstone Television.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Touchstone Television| #1C493D| 1| 1| 0| 0',
        '| Triangle Staff.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Triangle Staff| #F01AFA| 1| 1| 0| 0',
        '| Trigger.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Trigger| #5C5C5C| 1| 1| 0| 0',
        '| TriStar Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | TriStar Pictures| #F24467| 1| 1| 0| 0',
        '| TROYCA.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | TROYCA| #2F562B| 1| 1| 0| 0',
        '| TYO Animations.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | TYO Animations| #83CC1D| 1| 1| 0| 0',
        '| Typhoon Graphics.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Typhoon Graphics| #C84B2E| 1| 1| 0| 0',
        '| UCP.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | UCP| #2221DA| 1| 1| 0| 0',
        '| ufotable.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | ufotable| #F39942| 1| 1| 0| 0',
        '| Universal Animation Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Universal Animation Studios| #1C508F| 1| 1| 0| 0',
        '| Universal Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Universal Pictures| #207AAB| 1| 1| 0| 0',
        '| Universal Television.png| 0| 1600| 0| ComfortAa-Medium| 357| #FFFFFF| 0| 15| #FFFFFF|  | Universal Television| #AADDF6| 1| 1| 0| 0',
        '| V1 Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | V1 Studio| #961982| 1| 1| 0| 0',
        '| Village Roadshow Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Village Roadshow Pictures| #A76B29| 1| 1| 0| 0',
        '| W-Toon Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | W-Toon Studio| #9EAFE3| 1| 1| 0| 0',
        '| W. Chump and Sons.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | W. Chump and Sons| #0125F4| 1| 1| 0| 0',
        '| Walt Disney Animation Studios.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Walt Disney Animation Studios| #1290C0| 1| 1| 0| 0',
        '| Walt Disney Pictures.png| 0| 1300| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Walt Disney Pictures| #2944AA| 1| 1| 0| 0',
        '| Warner Animation Group.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Warner Animation Group| #2C80EE| 1| 1| 0| 0'
        '| Warner Bros. Pictures.png| 0| 1200| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Warner Bros. Pictures| #39538F| 1| 1| 0| 0',
        '| Warner Bros. Television.png| 0| 1600| 0| ComfortAa-Medium| 359| #FFFFFF| 0| 15| #FFFFFF|  | Warner Bros. Television| #B65CF3| 1| 1| 0| 0',
        '| Wawayu Animation.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Wawayu Animation| #EB7786| 1| 1| 0| 0',
        '| Wayfare Entertainment.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Wayfare Entertainment| #4FD631| 1| 1| 0| 0',
        '| White Fox.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | White Fox| #A86633| 1| 1| 0| 0',
        '| Wiedemann & Berg Television.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Wiedemann & Berg Television| #9A2F9F| 1| 1| 0| 0',
        '| Wit Studio.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Wit Studio| #1F3BB6| 1| 1| 0| 0',
        '| Wolfsbane.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Wolfsbane| #8E7689| 1| 1| 0| 0',
        '| Xebec.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Xebec| #051D31| 1| 1| 0| 0'
        '| Yokohama Animation Lab.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Yokohama Animation Lab| #2C3961| 1| 1| 0| 0',
        '| Yostar Pictures.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Yostar Pictures| #9A3DC1| 1| 1| 0| 0',
        '| Yumeta Company.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Yumeta Company| #945E75| 1| 1| 0| 0',
        '| Zero-G.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Zero-G| #460961| 1| 1| 0| 0',
        '| Zexcs.png| 0| 1600| 0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF|  | Zexcs| #E60CB2| 1| 1| 0| 0'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_studio\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    
    LaunchScripts -ScriptPaths $arr
    Move-Item -Path output -Destination studio
    Copy-Item -Path logos_studio -Destination studio\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateSubtitleLanguage
# Description:  Creates Subtitle Language
################################################################################
Function CreateSubtitleLanguage {
    Write-Host `"Creating Subtitle Language`"
    Set-Location $script_path
    # Find-Path `"$script_path\subtitle_language`"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    Move-Item -Path output -Destination output-orig

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'subtitle_language_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    $pre_value = Get-YamlPropertyValue -PropertyPath "collections.subtitle_language.name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'ABKHAZIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ab| #88F678| 1| 1| 0| 1',
        'AFAR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | aa| #612A1C| 1| 1| 0| 1',
        'AFRIKAANS| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | af| #60EC40| 1| 1| 0| 1',
        'AKAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ak| #021FBC| 1| 1| 0| 1',
        'ALBANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sq| #C5F277| 1| 1| 0| 1',
        'AMHARIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | am| #746BC8| 1| 1| 0| 1',
        'ARABIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ar| #37C768| 1| 1| 0| 1',
        'ARAGONESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | an| #4619FD| 1| 1| 0| 1',
        'ARMENIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hy| #5F26E3| 1| 1| 0| 1',
        'ASSAMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | as| #615C3B| 1| 1| 0| 1',
        'AVARIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | av| #2BCE4A| 1| 1| 0| 1',
        'AVESTAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ae| #CF6EEA| 1| 1| 0| 1',
        'AYMARA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ay| #3D5D3B| 1| 1| 0| 1',
        'AZERBAIJANI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | az| #A48C7A| 1| 1| 0| 1',
        'BAMBARA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bm| #C12E3D| 1| 1| 0| 1',
        'BASHKIR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ba| #ECD14A| 1| 1| 0| 1',
        'BASQUE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | eu| #89679F| 1| 1| 0| 1',
        'BELARUSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | be| #1050B0| 1| 1| 0| 1',
        'BENGALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bn| #EA4C42| 1| 1| 0| 1',
        'BISLAMA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bi| #C39A37| 1| 1| 0| 1',
        'BOSNIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bs| #7DE3FE| 1| 1| 0| 1',
        'BRETON| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | br| #7E1A72| 1| 1| 0| 1',
        'BULGARIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bg| #D5442A| 1| 1| 0| 1',
        'BURMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | my| #9E5CF0| 1| 1| 0| 1',
        'CATALAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ca| #99BC95| 1| 1| 0| 1',
        'CENTRAL_KHMER| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | km| #6ABDD6| 1| 1| 0| 1',
        'CHAMORRO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ch| #22302F| 1| 1| 0| 1',
        'CHECHEN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ce| #83E832| 1| 1| 0| 1',
        'CHICHEWA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ny| #03E31C| 1| 1| 0| 1',
        'CHINESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | zh| #40EA69| 1| 1| 0| 1',
        'CHURCH_SLAVIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cu| #C76DC2| 1| 1| 0| 1',
        'CHUVASH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cv| #920F92| 1| 1| 0| 1',
        'CORNISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kw| #55137D| 1| 1| 0| 1',
        'CORSICAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | co| #C605DC| 1| 1| 0| 1',
        'CREE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cr| #75D7F3| 1| 1| 0| 1',
        'CROATIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hr| #AB48D3| 1| 1| 0| 1',
        'CZECH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cs| #7804BB| 1| 1| 0| 1',
        'DANISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | da| #87A5BE| 1| 1| 0| 1',
        'DIVEHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | dv| #FA57EC| 1| 1| 0| 1',
        'DUTCH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nl| #74352E| 1| 1| 0| 1',
        'DZONGKHA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | dz| #F7C931| 1| 1| 0| 1',
        'ENGLISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | en| #DD4A2F| 1| 1| 0| 1',
        'ESPERANTO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | eo| #B65ADE| 1| 1| 0| 1',
        'ESTONIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | et| #AF1569| 1| 1| 0| 1',
        'EWE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ee| #2B7E43| 1| 1| 0| 1',
        'FAROESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fo| #507CCC| 1| 1| 0| 1',
        'FIJIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fj| #7083F9| 1| 1| 0| 1',
        'FILIPINO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fil| #8BEF80| 1| 1| 0| 1',
        'FINNISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fi| #9229A6| 1| 1| 0| 1',
        'FRENCH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fr| #4111A0| 1| 1| 0| 1',
        'FULAH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ff| #649BA7| 1| 1| 0| 1',
        'GAELIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gd| #FBFEC1| 1| 1| 0| 1',
        'GALICIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gl| #DB6769| 1| 1| 0| 1',
        'GANDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lg| #C71A50| 1| 1| 0| 1',
        'GEORGIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ka| #8517C8| 1| 1| 0| 1',
        'GERMAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | de| #4F5FDC| 1| 1| 0| 1',
        'GREEK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | el| #49B49A| 1| 1| 0| 1',
        'GUARANI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gn| #EDB51C| 1| 1| 0| 1',
        'GUJARATI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gu| #BDF7FF| 1| 1| 0| 1',
        'HAITIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ht| #466EB6| 1| 1| 0| 1',
        'HAUSA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ha| #A949D2| 1| 1| 0| 1',
        'HEBREW| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | he| #E9C58A| 1| 1| 0| 1',
        'HERERO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hz| #E9DF57| 1| 1| 0| 1',
        'HINDI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hi| #77775B| 1| 1| 0| 1',
        'HIRI_MOTU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ho| #3BB41B| 1| 1| 0| 1',
        'HUNGARIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | hu| #111457| 1| 1| 0| 1',
        'ICELANDIC| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | is| #0ACE8F| 1| 1| 0| 1',
        'IDO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | io| #75CA6C| 1| 1| 0| 1',
        'IGBO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ig| #757EDE| 1| 1| 0| 1',
        'INDONESIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | id| #52E822| 1| 1| 0| 1',
        'INTERLINGUA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ia| #7F9248| 1| 1| 0| 1',
        'INTERLINGUE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ie| #8F802C| 1| 1| 0| 1',
        'INUKTITUT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | iu| #43C3B0| 1| 1| 0| 1',
        'INUPIAQ| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ik| #ECF371| 1| 1| 0| 1',
        'IRISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ga| #FB7078| 1| 1| 0| 1',
        'ITALIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | it| #95B5DF| 1| 1| 0| 1',
        'JAPANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ja| #5D776B| 1| 1| 0| 1',
        'JAVANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | jv| #5014C5| 1| 1| 0| 1',
        'KALAALLISUT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kl| #050CF3| 1| 1| 0| 1',
        'KANNADA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kn| #440B43| 1| 1| 0| 1',
        'KANURI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kr| #4F2AAC| 1| 1| 0| 1',
        'KASHMIRI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ks| #842C02| 1| 1| 0| 1',
        'KAZAKH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kk| #665F3D| 1| 1| 0| 1',
        'KIKUYU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ki| #315679| 1| 1| 0| 1',
        'KINYARWANDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rw| #CE1391| 1| 1| 0| 1',
        'KIRGHIZ| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ky| #5F0D23| 1| 1| 0| 1',
        'KOMI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kv| #9B06C3| 1| 1| 0| 1',
        'KONGO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kg| #74BC47| 1| 1| 0| 1',
        'KOREAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ko| #F5C630| 1| 1| 0| 1',
        'KUANYAMA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | kj| #D8CB60| 1| 1| 0| 1',
        'KURDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ku| #467330| 1| 1| 0| 1',
        'LAO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lo| #DD3B78| 1| 1| 0| 1',
        'LATIN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | la| #A73376| 1| 1| 0| 1',
        'LATVIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lv| #A65EC1| 1| 1| 0| 1',
        'LIMBURGAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | li| #13C252| 1| 1| 0| 1',
        'LINGALA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ln| #BBEE5B| 1| 1| 0| 1',
        'LITHUANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lt| #E89C3E| 1| 1| 0| 1',
        'LUBA-KATANGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lu| #4E97F3| 1| 1| 0| 1',
        'LUXEMBOURGISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | lb| #4738EE| 1| 1| 0| 1',
        'MACEDONIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mk| #B69974| 1| 1| 0| 1',
        'MALAGASY| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mg| #29D850| 1| 1| 0| 1',
        'MALAY| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ms| #A74139| 1| 1| 0| 1',
        'MALAYALAM| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ml| #FD4C87| 1| 1| 0| 1',
        'MALTESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mt| #D6EE0B| 1| 1| 0| 1',
        'MANX| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | gv| #3F83E9| 1| 1| 0| 1',
        'MAORI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mi| #8339FD| 1| 1| 0| 1',
        'MARATHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mr| #93DEF1| 1| 1| 0| 1',
        'MARSHALLESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mh| #11DB75| 1| 1| 0| 1',
        'MONGOLIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | mn| #A107D9| 1| 1| 0| 1',
        'NAURU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | na| #7A0925| 1| 1| 0| 1',
        'NAVAJO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nv| #48F865| 1| 1| 0| 1',
        'NDONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ng| #83538B| 1| 1| 0| 1',
        'NEPALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ne| #5A15FC| 1| 1| 0| 1',
        'NORTH_NDEBELE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nd| #A1533B| 1| 1| 0| 1',
        'NORTHERN_SAMI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | se| #AAD61B| 1| 1| 0| 1',
        'NORWEGIAN_BOKMÅL| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nb| #0AEB4A| 1| 1| 0| 1',
        'NORWEGIAN_NYNORSK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nn| #278B62| 1| 1| 0| 1',
        'NORWEGIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | no| #13FF63| 1| 1| 0| 1',
        'OCCITAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | oc| #B5B607| 1| 1| 0| 1',
        'OJIBWA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | oj| #100894| 1| 1| 0| 1',
        'ORIYA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | or| #0198FF| 1| 1| 0| 1',
        'OROMO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | om| #351BD8| 1| 1| 0| 1',
        'OSSETIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | os| #BF715E| 1| 1| 0| 1',
        'PALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pi| #BEB3FA| 1| 1| 0| 1',
        'PASHTO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ps| #A4236C| 1| 1| 0| 1',
        'PERSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fa| #68A38E| 1| 1| 0| 1',
        'POLISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pl| #D4F797| 1| 1| 0| 1',
        'PORTUGUESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pt| #71D659| 1| 1| 0| 1',
        'PUNJABI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | pa| #14F788| 1| 1| 0| 1',
        'QUECHUA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | qu| #268110| 1| 1| 0| 1',
        'ROMANIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ro| #06603F| 1| 1| 0| 1',
        'ROMANSH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rm| #3A73F3| 1| 1| 0| 1',
        'RUNDI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | rn| #715E84| 1| 1| 0| 1',
        'RUSSIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ru| #DB77DA| 1| 1| 0| 1',
        'SAMOAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sm| #A26738| 1| 1| 0| 1',
        'SANGO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sg| #CA1C7E| 1| 1| 0| 1',
        'SANSKRIT| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sa| #CF9C76| 1| 1| 0| 1',
        'SARDINIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sc| #28AF67| 1| 1| 0| 1',
        'SERBIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sr| #FB3F2C| 1| 1| 0| 1',
        'SHONA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sn| #40F3EC| 1| 1| 0| 1',
        'SICHUAN_YI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ii| #FA3474| 1| 1| 0| 1',
        'SINDHI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sd| #62D1BE| 1| 1| 0| 1',
        'SINHALA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | si| #24787A| 1| 1| 0| 1',
        'SLOVAK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sk| #66104F| 1| 1| 0| 1',
        'SLOVENIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sl| #6F79E6| 1| 1| 0| 1',
        'SOMALI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | so| #A36185| 1| 1| 0| 1',
        'SOUTH_NDEBELE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | nr| #8090E5| 1| 1| 0| 1',
        'SOUTHERN_SOTHO| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | st| #4C3417| 1| 1| 0| 1',
        'SPANISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | es| #7842AE| 1| 1| 0| 1',
        'SUNDANESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | su| #B2D05B| 1| 1| 0| 1',
        'SWAHILI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sw| #D32F20| 1| 1| 0| 1',
        'SWATI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ss| #AA196D| 1| 1| 0| 1',
        'SWEDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | sv| #0EC5A2| 1| 1| 0| 1',
        'TAGALOG| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tl| #C9DDAC| 1| 1| 0| 1',
        'TAHITIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ty| #32009D| 1| 1| 0| 1',
        'TAJIK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tg| #100ECF| 1| 1| 0| 1',
        'TAMIL| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ta| #E71FAE| 1| 1| 0| 1',
        'TATAR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tt| #C17483| 1| 1| 0| 1',
        'TELUGU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | te| #E34ABD| 1| 1| 0| 1',
        'THAI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | th| #3FB501| 1| 1| 0| 1',
        'TIBETAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | bo| #FF2496| 1| 1| 0| 1',
        'TIGRINYA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ti| #9074F0| 1| 1| 0| 1',
        'TONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | to| #B3259E| 1| 1| 0| 1',
        'TSONGA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ts| #12687C| 1| 1| 0| 1',
        'TSWANA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tn| #DA3E89| 1| 1| 0| 1',
        'TURKISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tr| #A08D29| 1| 1| 0| 1',
        'TURKMEN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tk| #E70267| 1| 1| 0| 1',
        'TWI| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | tw| #8A6C0F| 1| 1| 0| 1',
        'UIGHUR| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ug| #79BC21| 1| 1| 0| 1',
        'UKRAINIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | uk| #EB60E9| 1| 1| 0| 1',
        'URDU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ur| #57E09D| 1| 1| 0| 1',
        'UZBEK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | uz| #4341F3| 1| 1| 0| 1',
        'VENDA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | ve| #4780ED| 1| 1| 0| 1',
        'VIETNAMESE| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | vi| #90A301| 1| 1| 0| 1',
        'VOLAPÜK| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | vo| #77D574| 1| 1| 0| 1',
        'WALLOON| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | wa| #BD440A| 1| 1| 0| 1',
        'WELSH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | cy| #45E39C| 1| 1| 0| 1',
        'WESTERN_FRISIAN| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | fy| #01F471| 1| 1| 0| 1',
        'WOLOF| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | wo| #BDD498| 1| 1| 0| 1',
        'XHOSA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | xh| #0C6D9C| 1| 1| 0| 1',
        'YIDDISH| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | yi| #111D14| 1| 1| 0| 1',
        'YORUBA| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | yo| #E815FF| 1| 1| 0| 1',
        'ZHUANG| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | za| #C62A89| 1| 1| 0| 1',
        'ZULU| transparent.png| +0| 0| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | zu| #0049F8| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = Set-TextBetweenDelimiters -InputString $pre_value -ReplacementString (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr
    
    Move-Item -Path output -Destination subtitle_language
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateUniverse
# Description:  Creates Universe
################################################################################
Function CreateUniverse {
    Write-Host "Creating Universe"
    Set-Location $script_path
    # Find-Path "$script_path\universe"
    Move-Item -Path output -Destination output-orig    

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '| askew.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | askew| #0F66AD| 1| 1| 0| 1',
        '| avp.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | avp| #2FC926| 1| 1| 0| 1',
        '| arrow.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | arrow| #03451A| 1| 1| 0| 1',
        '| dca.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | dca| #2832C5| 1| 1| 0| 1',
        '| dcu.png| +0| 1500| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | dcu| #2832C4| 1| 1| 0| 1',
        '| fast.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | fast| #7F1FC8| 1| 1| 0| 1',
        '| marvel.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | marvel| #ED171F| 1| 1| 0| 1',
        '| mcu.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | mcu| #C62D21| 1| 1| 0| 1',
        '| middle.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | middle| #D79C2B| 1| 1| 0| 1',
        '| mummy.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | mummy| #DBA02F| 1| 1| 0| 1',
        '| rocky.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | rocky| #CC1F10| 1| 1| 0| 1',
        '| star.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | star| #FFD64F| 1| 1| 0| 1',
        '| star (1).png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | star (1)| #F2DC1D| 1| 1| 0| 1',
        '| starsky.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | starsky| #0595FB| 1| 1| 0| 1',
        '| trek.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | trek| #ffe15f| 1| 1| 0| 1',
        '| wizard.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | wizard| #878536| 1| 1| 0| 1',
        '| xmen.png| +0| 1800| +0| ComfortAa-Medium| 250| #FFFFFF| 0| 15| #FFFFFF| | xmen| #636363| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "key_names.$($item.key_name)" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\logos_universe\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr
    
    Move-Item -Path output -Destination universe
    Copy-Item -Path logos_universe -Destination universe\logos -Recurse
    Move-Item -Path output-orig -Destination output
}

################################################################################
# Function: CreateYear
# Description:  Creates Year
################################################################################
Function CreateYear {
    Write-Host "Creating Year"
    Set-Location $script_path
    # Find-Path "$script_path\year"
    # Find-Path "$script_path\year\best"
    WriteToLogFile "ImageMagick Commands for     : Years"

    Move-Item -Path output -Destination output-orig

    $theFont = "ComfortAa-Medium"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 250

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        'year_other| transparent.png| +0| 1600| +0| ComfortAa-Medium| | #FFFFFF| 0| 15| #FFFFFF| | other| #FF2000| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        if ($($item.key_name).ToString() -eq "") {
            $value = $null
        }
        else {
            $value = (Get-YamlPropertyValue -PropertyPath "collections.$($item.key_name).name" -ConfigObject $global:ConfigObj -CaseSensitivity Upper)
        }
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    # $theFont = "ComfortAa-Medium"
    $theMaxWidth = 1900
    $theMaxHeight = 550
    $minPointSize = 250
    $maxPointSize = 1000

    $myArray = @(
        'key_name| logo| logo_offset| logo_resize| text_offset| font| font_size| font_color| border| border_width| border_color| avg_color_image| out_name| base_color| gradient| clean| avg_color| white_wash',
        '1880| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1880|  #EF10D3| 1| 1| 0| 1',
        '1881| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1881|  #EF102A| 1| 1| 0| 1',
        '1882| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1882|  #EF6210| 1| 1| 0| 1',
        '1883| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1883|  #EFC910| 1| 1| 0| 1',
        '1884| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1884|  #10EFA3| 1| 1| 0| 1',
        '1885| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1885|  #108FEF| 1| 1| 0| 1',
        '1886| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1886|  #A900EF| 1| 1| 0| 1',
        '1887| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1887|  #8D848E| 1| 1| 0| 1',
        '1888| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1888|  #992C2E| 1| 1| 0| 1',
        '1889| transparent.png| +0| 1800| +0|  Rye-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1889|  #131CA1| 1| 1| 0| 1',
        '1890| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1890|  #EF10D3| 1| 1| 0| 1',
        '1891| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1891|  #EF102A| 1| 1| 0| 1',
        '1892| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1892|  #EF6210| 1| 1| 0| 1',
        '1893| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1893|  #EFC910| 1| 1| 0| 1',
        '1894| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1894|  #10EFA3| 1| 1| 0| 1',
        '1895| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1895|  #108FEF| 1| 1| 0| 1',
        '1896| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1896|  #A900EF| 1| 1| 0| 1',
        '1897| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1897|  #8D848E| 1| 1| 0| 1',
        '1898| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1898|  #992C2E| 1| 1| 0| 1',
        '1899| transparent.png| +0| 1800| +0|  Limelight-Regular|  453| #FFFFFF| 0| 15| #FFFFFF| | 1899|  #131CA1| 1| 1| 0| 1',
        '1900| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1900|  #EF10D3| 1| 1| 0| 1',
        '1901| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1901|  #EF102A| 1| 1| 0| 1',
        '1902| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1902|  #EF6210| 1| 1| 0| 1',
        '1903| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1903|  #EFC910| 1| 1| 0| 1',
        '1904| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1904|  #10EFA3| 1| 1| 0| 1',
        '1905| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1905|  #108FEF| 1| 1| 0| 1',
        '1906| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1906|  #A900EF| 1| 1| 0| 1',
        '1907| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1907|  #8D848E| 1| 1| 0| 1',
        '1908| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1908|  #992C2E| 1| 1| 0| 1',
        '1909| transparent.png| +0| 1800| +0|  BoecklinsUniverse|  453| #FFFFFF| 0| 15| #FFFFFF| | 1909|  #131CA1| 1| 1| 0| 1',
        '1910| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1910|  #EF10D3| 1| 1| 0| 1',
        '1911| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1911|  #EF102A| 1| 1| 0| 1',
        '1912| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1912|  #EF6210| 1| 1| 0| 1',
        '1913| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1913|  #EFC910| 1| 1| 0| 1',
        '1914| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1914|  #10EFA3| 1| 1| 0| 1',
        '1915| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1915|  #108FEF| 1| 1| 0| 1',
        '1916| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1916|  #A900EF| 1| 1| 0| 1',
        '1917| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1917|  #8D848E| 1| 1| 0| 1',
        '1918| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1918|  #992C2E| 1| 1| 0| 1',
        '1919| transparent.png| +0| 1800| +0|  UnifrakturCook| 700| #FFFFFF| 0| 15| #FFFFFF| | 1919|  #131CA1| 1| 1| 0| 1',
        '1920| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1920|  #EF10D3| 1| 1| 0| 1',
        '1921| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1921|  #EF102A| 1| 1| 0| 1',
        '1922| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1922|  #EF6210| 1| 1| 0| 1',
        '1923| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1923|  #EFC910| 1| 1| 0| 1',
        '1924| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1924|  #10EFA3| 1| 1| 0| 1',
        '1925| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1925|  #108FEF| 1| 1| 0| 1',
        '1926| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1926|  #A900EF| 1| 1| 0| 1',
        '1927| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1927|  #8D848E| 1| 1| 0| 1',
        '1928| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1928|  #992C2E| 1| 1| 0| 1',
        '1929| transparent.png| +0| 1800| +0|  Trochut| 500| #FFFFFF| 0| 15| #FFFFFF| | 1929|  #131CA1| 1| 1| 0| 1',
        '1930| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1930|  #EF10D3| 1| 1| 0| 1',
        '1931| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1931|  #EF102A| 1| 1| 0| 1',
        '1932| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1932|  #EF6210| 1| 1| 0| 1',
        '1933| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1933|  #EFC910| 1| 1| 0| 1',
        '1934| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1934|  #10EFA3| 1| 1| 0| 1',
        '1935| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1935|  #108FEF| 1| 1| 0| 1',
        '1936| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1936|  #A900EF| 1| 1| 0| 1',
        '1937| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1937|  #8D848E| 1| 1| 0| 1',
        '1938| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1938|  #992C2E| 1| 1| 0| 1',
        '1939| transparent.png| +0| 1800| +0|  Righteous| 500| #FFFFFF| 0| 15| #FFFFFF| | 1939|  #131CA1| 1| 1| 0| 1',
        '1940| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1940|  #EF10D3| 1| 1| 0| 1',
        '1941| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1941|  #EF102A| 1| 1| 0| 1',
        '1942| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1942|  #EF6210| 1| 1| 0| 1',
        '1943| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1943|  #EFC910| 1| 1| 0| 1',
        '1944| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1944|  #10EFA3| 1| 1| 0| 1',
        '1945| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1945|  #108FEF| 1| 1| 0| 1',
        '1946| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1946|  #A900EF| 1| 1| 0| 1',
        '1947| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1947|  #8D848E| 1| 1| 0| 1',
        '1948| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1948|  #992C2E| 1| 1| 0| 1',
        '1949| transparent.png| +0| 1800| +0|  Yesteryear| 700| #FFFFFF| 0| 15| #FFFFFF| | 1949|  #131CA1| 1| 1| 0| 1',
        '1950| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1950|  #EF10D3| 1| 1| 0| 1',
        '1951| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1951|  #EF102A| 1| 1| 0| 1',
        '1952| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1952|  #EF6210| 1| 1| 0| 1',
        '1953| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1953|  #EFC910| 1| 1| 0| 1',
        '1954| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1954|  #10EFA3| 1| 1| 0| 1',
        '1955| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1955|  #108FEF| 1| 1| 0| 1',
        '1956| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1956|  #A900EF| 1| 1| 0| 1',
        '1957| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1957|  #8D848E| 1| 1| 0| 1',
        '1958| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1958|  #992C2E| 1| 1| 0| 1',
        '1959| transparent.png| +0| 1800| +0|  Cherry-Cream-Soda-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1959|  #131CA1| 1| 1| 0| 1',
        '1960| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1960|  #EF10D3| 1| 1| 0| 1',
        '1961| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1961|  #EF102A| 1| 1| 0| 1',
        '1962| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1962|  #EF6210| 1| 1| 0| 1',
        '1963| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1963|  #EFC910| 1| 1| 0| 1',
        '1964| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1964|  #10EFA3| 1| 1| 0| 1',
        '1965| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1965|  #108FEF| 1| 1| 0| 1',
        '1966| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1966|  #A900EF| 1| 1| 0| 1',
        '1967| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1967|  #8D848E| 1| 1| 0| 1',
        '1968| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1968|  #992C2E| 1| 1| 0| 1',
        '1969| transparent.png| +0| 1800| +0|  Boogaloo-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 1969|  #131CA1| 1| 1| 0| 1',
        '1970| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1970|  #EF10D3| 1| 1| 0| 1',
        '1971| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1971|  #EF102A| 1| 1| 0| 1',
        '1972| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1972|  #EF6210| 1| 1| 0| 1',
        '1973| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1973|  #EFC910| 1| 1| 0| 1',
        '1974| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1974|  #10EFA3| 1| 1| 0| 1',
        '1975| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1975|  #108FEF| 1| 1| 0| 1',
        '1976| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1976|  #A900EF| 1| 1| 0| 1',
        '1977| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1977|  #8D848E| 1| 1| 0| 1',
        '1978| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1978|  #992C2E| 1| 1| 0| 1',
        '1979| transparent.png| +0| 1800| +0|  Monoton| 500| #FFFFFF| 0| 15| #FFFFFF| | 1979|  #131CA1| 1| 1| 0| 1',
        '1980| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1980|  #EF10D3| 1| 1| 0| 1',
        '1981| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1981|  #EF102A| 1| 1| 0| 1',
        '1982| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1982|  #EF6210| 1| 1| 0| 1',
        '1983| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1983|  #EFC910| 1| 1| 0| 1',
        '1984| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1984|  #10EFA3| 1| 1| 0| 1',
        '1985| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1985|  #108FEF| 1| 1| 0| 1',
        '1986| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1986|  #A900EF| 1| 1| 0| 1',
        '1987| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1987|  #8D848E| 1| 1| 0| 1',
        '1988| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1988|  #992C2E| 1| 1| 0| 1',
        '1989| transparent.png| +0| 1800| +0|  Press-Start-2P| 300| #FFFFFF| 0| 15| #FFFFFF| | 1989|  #131CA1| 1| 1| 0| 1',
        '1990| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1990|  #EF10D3| 1| 1| 0| 1',
        '1991| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1991|  #EF102A| 1| 1| 0| 1',
        '1992| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1992|  #EF6210| 1| 1| 0| 1',
        '1993| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1993|  #EFC910| 1| 1| 0| 1',
        '1994| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1994|  #10EFA3| 1| 1| 0| 1',
        '1995| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1995|  #108FEF| 1| 1| 0| 1',
        '1996| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1996|  #A900EF| 1| 1| 0| 1',
        '1997| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1997|  #8D848E| 1| 1| 0| 1',
        '1998| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1998|  #992C2E| 1| 1| 0| 1',
        '1999| transparent.png| +0| 1800| +0|  Jura-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 1999|  #131CA1| 1| 1| 0| 1',
        '2000| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2000|  #EF10D3| 1| 1| 0| 1',
        '2001| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2001|  #EF102A| 1| 1| 0| 1',
        '2002| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2002|  #EF6210| 1| 1| 0| 1',
        '2003| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2003|  #EFC910| 1| 1| 0| 1',
        '2004| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2004|  #10EFA3| 1| 1| 0| 1',
        '2005| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2005|  #108FEF| 1| 1| 0| 1',
        '2006| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2006|  #A900EF| 1| 1| 0| 1',
        '2007| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2007|  #8D848E| 1| 1| 0| 1',
        '2008| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2008|  #992C2E| 1| 1| 0| 1',
        '2009| transparent.png| +0| 1800| +0|  Special-Elite-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2009|  #131CA1| 1| 1| 0| 1',
        '2010| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2010|  #EF10D3| 1| 1| 0| 1',
        '2011| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2011|  #EF102A| 1| 1| 0| 1',
        '2012| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2012|  #EF6210| 1| 1| 0| 1',
        '2013| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2013|  #EFC910| 1| 1| 0| 1',
        '2014| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2014|  #10EFA3| 1| 1| 0| 1',
        '2015| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2015|  #108FEF| 1| 1| 0| 1',
        '2016| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2016|  #A900EF| 1| 1| 0| 1',
        '2017| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2017|  #8D848E| 1| 1| 0| 1',
        '2018| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2018|  #992C2E| 1| 1| 0| 1',
        '2019| transparent.png| +0| 1800| +0|  Barlow-Regular| 500| #FFFFFF| 0| 15| #FFFFFF| | 2019|  #131CA1| 1| 1| 0| 1',
        '2020| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2020|  #EF10D3| 1| 1| 0| 1',
        '2021| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2021|  #EF102A| 1| 1| 0| 1',
        '2022| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2022|  #EF6210| 1| 1| 0| 1',
        '2023| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2023|  #EFC910| 1| 1| 0| 1',
        '2024| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2024|  #10EFA3| 1| 1| 0| 1',
        '2025| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2025|  #108FEF| 1| 1| 0| 1',
        '2026| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2026|  #A900EF| 1| 1| 0| 1',
        '2027| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2027|  #8D848E| 1| 1| 0| 1',
        '2028| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2028|  #992C2E| 1| 1| 0| 1',
        '2029| transparent.png| +0| 1800| +0|  Helvetica-Bold| 500| #FFFFFF| 0| 15| #FFFFFF| | 2029|  #131CA1| 1| 1| 0| 1'
    ) | ConvertFrom-Csv -Delimiter '|'

    $arr = @()
    foreach ($item in $myArray) {
        $value = $($item.key_name)
        $optimalFontSize = Get-OptimalPointSize -text $value -font $($item.font) -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $($item.font_size)
        $arr += ".\create_poster.ps1 -logo `"$script_path\$($item.logo)`" -logo_offset $($item.logo_offset) -logo_resize $($item.logo_resize) -text `"$value`" -text_offset $($item.text_offset) -font `"$($item.font)`" -font_size $optimalFontSize -font_color `"$($item.font_color)`" -border $($item.border) -border_width $($item.border_width) -border_color `"$($item.border_color)`" -avg_color_image `"$($item.avg_color_image)`" -out_name `"$($item.out_name)`" -base_color `"$($item.base_color)`" -gradient $($item.gradient) -avg_color $($item.avg_color) -clean $($item.clean) -white_wash $($item.white_wash)"
    }
    LaunchScripts -ScriptPaths $arr

    WriteToLogFile "MonitorProcess               : Waiting for all processes to end before continuing..."
    Start-Sleep -Seconds 3
    MonitorProcess -ProcessName "magick.exe"
    
    Move-Item -Path output -Destination year

    $pre_value = Get-YamlPropertyValue -PropertyPath "key_names.BEST_OF" -ConfigObject $global:ConfigObj -CaseSensitivity Upper

    $theFont = "ComfortAa-Medium"
    $theMaxWidth = 1800
    $theMaxHeight = 1000
    $minPointSize = 100
    $maxPointSize = 200

    $arr = @()
    for ($i = 1880; $i -lt 2030; $i++) {
        $value = $pre_value
        $optimalFontSize = Get-OptimalPointSize -text $value -font $theFont -box_width $theMaxWidth -box_height $theMaxHeight -min_pointsize $minPointSize -max_pointsize $maxPointSize
        $arr += ".\create_poster.ps1 -logo `"$script_path\year\$i.jpg`" -logo_offset +0 -logo_resize 2000 -text `"$value`" -text_offset -400 -font `"$theFont`" -font_size $optimalFontSize -font_color `"#FFFFFF`" -border 0 -border_width 15 -border_color `"#FFFFFF`" -avg_color_image `"`" -out_name `"$i`" -base_color `"#FFFFFF`" -gradient 1 -avg_color 0 -clean 1 -white_wash 0"
    }
    LaunchScripts -ScriptPaths $arr
    Start-Sleep -Seconds 3
    MonitorProcess -ProcessName "magick.exe"
    Move-Item -Path output -Destination "$script_path\year\best"
    Move-Item -Path output-orig -Destination output

}

################################################################################
# Function: CreateOverlays
# Description:  Creates Overlay Icons
################################################################################
Function CreateOverlays {
    Write-Host "Creating Overlays"
    Set-Location $script_path
    
    $directories = @("award", "chart", "content_rating", "country", "franchise", "network", "playlist", "resolution", "streaming", "studio", "universe")
    $directories_no_trim = @("genre", "seasonal")
    $sizes = "285x85>"
    
    Foreach ($dir in $directories_no_trim) {
        $path = Join-Path $script_path $dir
        $outputPath = Join-Path $path "logos_overlays"
        $inputPath = Join-Path $script_path "logos_$dir"
        Find-Path $path
        Find-Path $outputPath
        $joinpath = (Join-Path $inputPath "*.png")
        WriteToLogFile "Resizing overlays            : magick mogrify -colorspace sRGB -strip -path $outputPath -resize $sizes $joinpath"
        magick mogrify -colorspace sRGB -strip -path $outputPath -resize $sizes $joinpath
    }

    Foreach ($dir in $directories) {
        $path = Join-Path $script_path $dir
        $outputPath = Join-Path $path "logos_overlays"
        $inputPath = Join-Path $script_path "logos_$dir"
        Find-Path $path
        Find-Path $outputPath
        $joinpath = (Join-Path $inputPath "*.png")
        WriteToLogFile "Resizing overlays            : magick mogrify -colorspace sRGB -strip -trim -path $outputPath -resize $sizes $joinpath"
        magick mogrify -colorspace sRGB -strip -trim -path $outputPath -resize $sizes $joinpath
    }
}

################################################################################
# Function: MonitorProcess
# Description: Checks to see if process is running in memory and only exits
################################################################################
Function MonitorProcess {
    param(
        [string]$ProcessName
    )
    # Start-Sleep -Seconds 10
    $startTime = Get-Date
    while ((Get-Process $ProcessName -ErrorAction SilentlyContinue) -and ((New-TimeSpan -Start $startTime).TotalMinutes -lt 10)) {
        Start-Sleep -Seconds 10
    }
    if ((Get-Process $ProcessName -ErrorAction SilentlyContinue)) {
        WriteToLogFile "MonitorProcess               : Process $ProcessName is still running after 10 minutes, exiting the function"
    }
    else {
        WriteToLogFile "MonitorProcess               : Process $ProcessName is no longer running"

    }
}

################################################################################
# Function: CheckSum-Files
# Description: Prints the list of possible parameters
################################################################################
Function Get-Checksum-Files {
    param(
        [string]$script_path
    )

    Set-Location $script_path
    WriteToLogFile "CheckSum Files               : Checking dependency files."

    $sep1 = "amethyst.png"
    $sep2 = "aqua.png"
    $sep3 = "blue.png"
    $sep4 = "forest.png"
    $sep5 = "fuchsia.png"
    $sep6 = "gold.png"
    $sep7 = "gray.png"
    $sep8 = "green.png"
    $sep9 = "navy.png"
    $sep10 = "ocean.png"
    $sep11 = "olive.png"
    $sep12 = "orchid.png"
    $sep13 = "orig.png"
    $sep14 = "pink.png"
    $sep15 = "plum.png"
    $sep16 = "purple.png"
    $sep17 = "red.png"
    $sep18 = "rust.png"
    $sep19 = "salmon.png"
    $sep20 = "sand.png"
    $sep21 = "stb.png"
    $sep22 = "tan.png"

    $ttf1 = "Boogaloo-Regular.ttf"
    $ttf2 = "Righteous-Regular.ttf"
    $ttf3 = "Bebas-Regular.ttf"
    $ttf4 = "BoecklinsUniverse.ttf"
    $ttf5 = "Comfortaa-Medium.ttf"
    $ttf6 = "UnifrakturCook-Bold.ttf"
    $ttf7 = "Helvetica-Bold.ttf"
    $ttf8 = "Limelight-Regular.ttf"
    $ttf9 = "Monoton-Regular.ttf"
    $ttf10 = "Jura-Bold.ttf"
    $ttf11 = "Press-Start-2P.ttf"
    $ttf12 = "Yesteryear-Regular.ttf"
    $ttf13 = "Rye-Regular.ttf"
    $ttf14 = "CherryCreamSoda-Regular.ttf"
    $ttf15 = "Barlow-Regular.ttf"
    $ttf16 = "SpecialElite-Regular.ttf"
    $ttf17 = "Trochut-Regular.ttf"
    
    $fade1 = "@bottom-top-fade.png"
    $fade2 = "@bottom-up-fade.png"
    $fade3 = "@center-out-fade.png"
    $fade4 = "@none.png"
    $fade5 = "@top-down-fade.png"
    
    $trans1 = "transparent.png"
    
    $expectedChecksum_sep1 = "8FFEF200F9AA2126052684FBAF5BB1B96F402FAF3055532FBBFFCABF610D9573"
    $expectedChecksum_sep2 = "940E5F5BD81B0C7388BDA0B6E639D59BAEFAABAD78F04F41982440D49BAE8871"
    $expectedChecksum_sep3 = "AB8DBC5FCE661BDFC643F9697EEC1463CD2CDE90E4594B232A6B92C272DE0561"
    $expectedChecksum_sep4 = "78DDD1552B477308047A1E6396407B96965F1B90DD738435F92187F02DA60467"
    $expectedChecksum_sep5 = "F8A173A71758B89D7EE22F04DB570A7D604F1DC5C17B5FD2D8F278C5440E0348"
    $expectedChecksum_sep6 = "9BB273DE826C9968D3B335701F0DB8C978C371C5ABF5DC1A5E554973BCDD255C"
    $expectedChecksum_sep7 = "9570B1E86BEC71CAED6DDFD6D2F18023A7C5D408B6A6D5B50C045672D4310772"
    $expectedChecksum_sep8 = "89951DFC6338ABC64444635F6F2835472418BF779A1EB5C342078AF0B8365F80"
    $expectedChecksum_sep9 = "FBFBF94423C96410EB65891CB3048B45C60586D52B71DF99550EA738F6D17AE4"
    $expectedChecksum_sep10 = "0AE3BB7DD7FE7ADDB6F788A49625224082E6DD43D3A7CD6517D15EE984E41021"
    $expectedChecksum_sep11 = "3B3B74A45A94DCA46BB82F8CAF32E39B12B9D7BF1868B9075E269A221AA3AF9B"
    $expectedChecksum_sep12 = "926D14FBBF6E113984E2F5D69BEF8620B37E0FF08C6FE4BBCDB5680C6698DEFC"
    $expectedChecksum_sep13 = "98E161CD70C3300D30340257D674FCC18B11FDADEE3FFF9B80D09C4AB09C1483"
    $expectedChecksum_sep14 = "E0B6DA722447ABB0BC47DDD93E847B37BCD3D3CA9897DB1818E5616D250DA2DA"
    $expectedChecksum_sep15 = "D383FCD9E2813144339F3FDE6A048C5A0D00EAA9443019B1B61FB2C24FF9BB2A"
    $expectedChecksum_sep16 = "3768CA736B6BD1CAD0CD02827A6BA7BDBCA2077B1A109802C57144C31B379477"
    $expectedChecksum_sep17 = "03E9026430C8F0ABD031B608225BF40CB87FD1983899C113E410A511CC5622A7"
    $expectedChecksum_sep18 = "5F72369DA3F652388A386D92F96995F1F1819F2B1FBAE90BC68DE049A426B298"
    $expectedChecksum_sep19 = "9A5E38AA7982846B47E85BF9C4FD99843D26187D37E4301F7A429F37612677C3"
    $expectedChecksum_sep20 = "4814E8E1E8A0BB65267C4B6B658390BFE79F4E6CFECA57039F98DF19E8658DB9"
    $expectedChecksum_sep21 = "A01695FAB8646079331811F381A38A529E76AFC31538285E7EE60600CA07ADC1"
    $expectedChecksum_sep22 = "8B9B71415CE0F8F1B229C2329C70D761DE99100D2FD5C49537B483B8A5A720E1"

    $expectedChecksum_ttf1 = "6AA7C9F7096B090A6783E31278ABF907EC84A4BD98F280C925AB033D1FE91EB7"
    $expectedChecksum_ttf2 = "4C3CDC5DE2D70C4EE75FC9C1723A6B8F2D7316F49B383335FD8257A17DD88ADE"
    $expectedChecksum_ttf3 = "39D2EB178FDD52B4C350AC6DEE3D2090AE5A7C187225B0D161A1473CCBB6320D"
    $expectedChecksum_ttf4 = "5F6F6396EDEE3FA1FE9443258D7463F82E6B2512A03C5102A90295A095339FB5"
    $expectedChecksum_ttf5 = "992F89F3C26BE37CCEBF784B294D36F40B96ED96AD9A3CC1396F4D389FC69D0C"
    $expectedChecksum_ttf6 = "B9ED8DA80463792A29675199B0F6580871025C35B2C539CAD7D5DE050D216A0C"
    $expectedChecksum_ttf7 = "D19CCD4211E3CAAAC2C7F1AE544456F5C67CD912E2BDFB1EFB6602C090C724EE"
    $expectedChecksum_ttf8 = "5D2C9F43D8CB4D49481A39A33CDC2A9157B1FCBFB381063A11617EDE209A105C"
    $expectedChecksum_ttf9 = "1565B395F454D5C2642D0F411030051E7342FBAF6D5BFC5DA5899C47ECD3511E"
    $expectedChecksum_ttf10 = "1A3B4D7412F10CC17C34289C357E00C5E91BB2EC61B123C2A72CB975E0CBE94D"
    $expectedChecksum_ttf11 = "17EC7D250FF590971A6D966B4FDC5AA04D5E39A7694F4A0BECB515B6A70A7228"
    $expectedChecksum_ttf12 = "B9D7736030DCA2B5849F4FA565A75F91065CC5DED8B6023444BD74445A263C77"
    $expectedChecksum_ttf13 = "722825F800CF7CEAE4791B274D45DA9DF517DB7CF7A07BFAFD34452B787C5354"
    $expectedChecksum_ttf14 = "D70EAFE96ABBAAD50D94538B11077D88BB91AC3538DD0E70F0BDC0CE04E410E9"
    $expectedChecksum_ttf15 = "77FB1AC54D2CEB980E3EBDFA7A9D0F64E85A66E4FDFB7F914A7B0AA08FB33A5D"
    $expectedChecksum_ttf16 = "14780EA85064DCB150C23C9A87E2B870439C38668B6D8F1DAD5C6DB701AB9520"
    $expectedChecksum_ttf17 = "EC48B8641254BDCACC417B77992F7776A747A14F8A16C5D5AF9D1B75F4BEC17D"

    $expectedChecksum_fade1 = "79D93B7455A694820A4DF4B27B4418EA0063AF59400ED778FC66F83648DAA110"
    $expectedChecksum_fade2 = "7ED182E395A08B4035B687E6F0661029EF938F8027923EC9434EBCBC5D144CFD"
    $expectedChecksum_fade3 = "6D36359197363DDC092FDAA8AA4590838B01B8A22C3BF4B6DED76D65BC85A87C"
    $expectedChecksum_fade4 = "5E89879184510E91E477D41C61BD86A0E9209E9ECC17909A7B0EE20427950CBC"
    $expectedChecksum_fade5 = "CBBF0B235A893410E02977419C89EE6AD97DF253CBAEE382E01D088D2CCE6B39"

    $expectedChecksum_trans1 = "64A0A1D637FF0687CCBCAECA31B8E6B7235002B1EE8528E7A60BE6A7D636F1FC"

    $failFlag = [ref] $false
    Write-Output "Begin: " $failFlag.Value

    Compare-FileChecksum -Path $script_path\@base\$sep1 -ExpectedChecksum $expectedChecksum_sep1 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep2 -ExpectedChecksum $expectedChecksum_sep2 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep3 -ExpectedChecksum $expectedChecksum_sep3 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep4 -ExpectedChecksum $expectedChecksum_sep4 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep5 -ExpectedChecksum $expectedChecksum_sep5 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep6 -ExpectedChecksum $expectedChecksum_sep6 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep7 -ExpectedChecksum $expectedChecksum_sep7 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep8 -ExpectedChecksum $expectedChecksum_sep8 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep9 -ExpectedChecksum $expectedChecksum_sep9 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep10 -ExpectedChecksum $expectedChecksum_sep10 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep11 -ExpectedChecksum $expectedChecksum_sep11 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep12 -ExpectedChecksum $expectedChecksum_sep12 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep13 -ExpectedChecksum $expectedChecksum_sep13 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep14 -ExpectedChecksum $expectedChecksum_sep14 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep15 -ExpectedChecksum $expectedChecksum_sep15 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep16 -ExpectedChecksum $expectedChecksum_sep16 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep17 -ExpectedChecksum $expectedChecksum_sep17 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep18 -ExpectedChecksum $expectedChecksum_sep18 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep19 -ExpectedChecksum $expectedChecksum_sep19 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep20 -ExpectedChecksum $expectedChecksum_sep20 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep21 -ExpectedChecksum $expectedChecksum_sep21 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\@base\$sep22 -ExpectedChecksum $expectedChecksum_sep22 -failFlag $failFlag
    
    Compare-FileChecksum -Path $script_path\fonts\$ttf1 -ExpectedChecksum $expectedChecksum_ttf1 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf2 -ExpectedChecksum $expectedChecksum_ttf2 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf3 -ExpectedChecksum $expectedChecksum_ttf3 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf4 -ExpectedChecksum $expectedChecksum_ttf4 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf5 -ExpectedChecksum $expectedChecksum_ttf5 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf6 -ExpectedChecksum $expectedChecksum_ttf6 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf7 -ExpectedChecksum $expectedChecksum_ttf7 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf8 -ExpectedChecksum $expectedChecksum_ttf8 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf9 -ExpectedChecksum $expectedChecksum_ttf9 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf10 -ExpectedChecksum $expectedChecksum_ttf10 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf11 -ExpectedChecksum $expectedChecksum_ttf11 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf12 -ExpectedChecksum $expectedChecksum_ttf12 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf13 -ExpectedChecksum $expectedChecksum_ttf13 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf14 -ExpectedChecksum $expectedChecksum_ttf14 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf15 -ExpectedChecksum $expectedChecksum_ttf15 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf16 -ExpectedChecksum $expectedChecksum_ttf16 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fonts\$ttf17 -ExpectedChecksum $expectedChecksum_ttf17 -failFlag $failFlag
    
    Compare-FileChecksum -Path $script_path\fades\$fade1 -ExpectedChecksum $expectedChecksum_fade1 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fades\$fade2 -ExpectedChecksum $expectedChecksum_fade2 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fades\$fade3 -ExpectedChecksum $expectedChecksum_fade3 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fades\$fade4 -ExpectedChecksum $expectedChecksum_fade4 -failFlag $failFlag
    Compare-FileChecksum -Path $script_path\fades\$fade5 -ExpectedChecksum $expectedChecksum_fade5 -failFlag $failFlag
    
    Compare-FileChecksum -Path $script_path\$trans1 -ExpectedChecksum $expectedChecksum_trans1 -failFlag $failFlag
        
    Write-Output "End:" $failFlag.Value

    if ($failFlag.Value) {
        WriteToLogFile "Checksums [ERROR]            : At least one checksum verification failed. Aborting..."
        exit
    }
    else {
        WriteToLogFile "Checksums                    : All checksum verifications succeeded."
    }
}

################################################################################
# Function: ShowFunctions
# Description: Prints the list of possible parameters
################################################################################
Function ShowFunctions {
    Write-Host "EXAMPLES:"
    Write-Host "You can run the script by providing the name of the function you want to run as a command-line argument:"
    Write-Host "create_default_posters.ps1 AudioLanguage "
    Write-Host "This will run only the CreateAudioLanguage function."
    Write-Host ""
    Write-Host "You can also provide multiple function names as command-line arguments:"
    Write-Host "create_default_posters.ps1 AudioLanguage Playlist Chart"
    Write-Host "This will run CreateAudioLanguage, CreatePlaylist, and CreateChart functions in that order."
    Write-Host ""
    Write-Host "Finally just running the script with All will run all of the functions"
    Write-Host "create_default_posters.ps1 All"
    Write-Host ""
    Write-Host "Possible parameters are:"
    Write-Host "AudioLanguage, Awards, Based, Charts, ContentRating, Country, Decades, Franchise, Genres, Network, Playlist, Resolution, Streaming, Studio, Seasonal, Separators, SubtitleLanguages, Universe, Years, All"
    exit
}

#################################
# MAIN
#################################
Set-Location $script_path
$font_flag = $null
if (!(Test-Path "$scriptLogPath" -ErrorAction SilentlyContinue)) {
    New-Item "$scriptLogPath" -ItemType Directory | Out-Null
}
Update-LogFile -LogPath $scriptLog

WriteToLogFile "#### START ####"

$Stopwatch = [System.Diagnostics.Stopwatch]::new()
$Stopwatch.Start()
New-SQLCache
Import-YamlModule

#################################
# Language Code
#################################
$LanguageCodes = @("ar","en", "da", "de", "es", "fr", "it", "nb_NO", "nl", "pt-br")
$DefaultLanguageCode = "en"
$LanguageCode = Read-Host "Enter language code ($($LanguageCodes -join ', ')). Press Enter to use the default language code: $DefaultLanguageCode"

if (-not [string]::IsNullOrWhiteSpace($LanguageCode) -and $LanguageCodes -notcontains $LanguageCode) {
    Write-Error "Error: Invalid language code."
    return
}

if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = $DefaultLanguageCode
}

$BranchOptions = @("master", "develop", "nightly")
$DefaultBranchOption = "nightly"
$BranchOption = Read-Host "Enter branch option ($($BranchOptions -join ', ')). Press Enter to use the default branch option: $DefaultBranchOption"

if (-not [string]::IsNullOrWhiteSpace($BranchOption) -and $BranchOptions -notcontains $BranchOption) {
    Write-Error "Error: Invalid branch option."
    return
}

if ([string]::IsNullOrWhiteSpace($BranchOption)) {
    $BranchOption = $DefaultBranchOption
}

Get-TranslationFile -LanguageCode $LanguageCode -BranchOption $BranchOption
Read-Host -Prompt "If you have a custom translation file, overwrite the downloaded one now and then Press any key to continue..."

$TranslationFilePath = Join-Path $script_path -ChildPath "@translations"
$TranslationFilePath = Join-Path $TranslationFilePath -ChildPath "$LanguageCode.yml"
$DefaultsPath = Join-Path $script_path -ChildPath "defaults-$LanguageCode"

Read-Yaml

#################################
# Imagemagick version check
#################################
Test-ImageMagick
$test = $global:magick

#################################
# Powershell version check
#################################
$pversion = $null
$pversion = $PSVersionTable.PSVersion.ToString()

WriteToLogFile "#######################"
WriteToLogFile "# SETTINGS"
WriteToLogFile "#######################"
WriteToLogFile "Script Path                  : $script_path"
WriteToLogFile "Original command line        : $($MyInvocation.Line)"
WriteToLogFile "Powershell Version           : $pversion"
WriteToLogFile "Imagemagick                  : $global:magick"
WriteToLogFile "LanguageCode                 : $LanguageCode"
WriteToLogFile "BranchOption                 : $BranchOption"
WriteToLogFile "#### PROCESSING CHECKS NOW ####"

Get-CheckSum-Files -script_path $script_path

if ($null -eq $test) {
    WriteToLogFile "Imagemagick [ERROR]          : Imagemagick is NOT installed. Aborting.... Imagemagick must be installed - https://imagemagick.org/script/download.php"
    exit 1
}
else {
    WriteToLogFile "Imagemagick                  : Imagemagick is installed."
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    WriteToLogFile "Powershell Version [ERROR]   : Error: This script requires PowerShell version 7 or higher."
    exit 1
}
else {
    WriteToLogFile "Powershell Version           : PowerShell version 7 or higher found."
}

if (-not (InstallFontsIfNeeded)) {
    # If the function returns $false, exit the script
    WriteToLogFile "Fonts Check [ERROR]          : Error: Fonts are not visible/installed for ImageMagick to use."
    exit 1
}
else {
    WriteToLogFile "Fonts Check                  : Fonts visible/installed for ImageMagick to use."
}

WriteToLogFile "#### PROCESSING POSTERS NOW ####"

#################################
# Cleanup Folders
#################################
Set-Location $script_path
Remove-Folders

#################################
# Create Paths if needed
#################################
Find-Path "$script_path\@base"
Find-Path $DefaultsPath
Find-Path "$script_path\fonts"
Find-Path "$script_path\output"


#################################
# Determine parameters passed from command line
#################################
Set-Location $script_path

foreach ($param in $args) {
    Switch ($param) {
        "AudioLanguage" { CreateAudioLanguage }
        "AudioLanguages" { CreateAudioLanguage }
        "Award" { CreateAwards }
        "Awards" { CreateAwards }
        "Based" { CreateBased }
        "Chart" { CreateChart }
        "Charts" { CreateChart }
        "ContentRating" { CreateContentRating }
        "ContentRatings" { CreateContentRating }
        "Country" { CreateCountry }
        "Countries" { CreateCountry }
        "Decade" { CreateDecade }
        "Decades" { CreateDecade }
        "Franchise" { CreateFranchise }
        "Franchises" { CreateFranchise }
        "Genre" { CreateGenre }
        "Genres" { CreateGenre }
        "Network" { CreateNetwork }
        "Networks" { CreateNetwork }
        "Overlay" { CreateOverlays }
        "Overlays" { CreateOverlays }
        "Playlist" { CreatePlaylist }
        "Playlists" { CreatePlaylist }
        "Resolution" { CreateResolution }
        "Resolutions" { CreateResolution }
        "Streaming" { CreateStreaming }
        "Studio" { CreateStudio }
        "Studios" { CreateStudio }
        "Seasonal" { CreateSeasonal }
        "Seasonals" { CreateSeasonal }
        "Separator" { CreateSeparators }
        "Separators" { CreateSeparators }
        "SubtitleLanguage" { CreateSubtitleLanguage }
        "SubtitleLanguages" { CreateSubtitleLanguage }
        "Universe" { CreateUniverse }
        "Universes" { CreateUniverse }
        "Year" { CreateYear }
        "Years" { CreateYear }
        "All" {
            CreateAudioLanguage
            CreateAwards
            CreateBased
            CreateChart
            CreateContentRating
            CreateCountry
            CreateDecade
            CreateFranchise
            CreateGenre
            CreateNetwork
            CreatePlaylist
            CreateResolution
            CreateSeasonal
            CreateSeparators
            CreateStreaming
            CreateStudio
            CreateSubtitleLanguage
            CreateUniverse
            CreateYear
            CreateOverlays
        }
        default {
            ShowFunctions
        }
    }
}

if (!$args) {
    ShowFunctions
    # CreateAwards
    # CreateResolution
    # CreateOverlays
    # CreateSeparators
    # CreateNetwork
    # CreateYear
    # CreateBased
    # CreateAudioLanguage
}

#######################
# Set current directory
#######################
Set-Location $script_path

#######################
# Wait for processes to end and then MoveFiles
#######################
Set-Location $script_path
WriteToLogFile "MonitorProcess               : Waiting for all processes to end..."
Start-Sleep -Seconds 3
MonitorProcess -ProcessName "magick.exe"
WriteToLogFile "#### PROCESSING POSTERS DONE ####"

MoveFiles

#######################
# Count files created
#######################
Set-Location $script_path
$tmp = (Get-ChildItem $DefaultsPath -Recurse -File | Measure-Object).Count
$files_to_process = $tmp

#######################
# Output files created to a file
#######################
Set-Location $script_path
Get-ChildItem -Recurse $DefaultsPath -Name -File | ForEach-Object { '"{0}"' -f $_ } | Out-File defaults-${LanguageCode}_list.txt

#######################
# Count [ERROR] lines
#######################
$errorCount = (Get-Content $scriptLog | Select-String -Pattern "\[ERROR\]" | Measure-Object).Count

#######################
# SUMMARY
#######################
Set-Location $script_path
WriteToLogFile "#######################"
WriteToLogFile "# SUMMARY"
WriteToLogFile "#######################"
WriteToLogFile "Script Path                  : $script_path"
WriteToLogFile "Original command line        : $($MyInvocation.Line)"
WriteToLogFile "Powershell Version           : $pversion"
WriteToLogFile "Imagemagick                  : $global:magick"
WriteToLogFile "LanguageCode                 : $LanguageCode"
WriteToLogFile "BranchOption                 : $BranchOption"
WriteToLogFile "Number of [ERROR] lines      : $errorCount"

$x = [math]::Round($Stopwatch.Elapsed.TotalMinutes, 2)
$speed = [math]::Round($files_to_process / $Stopwatch.Elapsed.TotalMinutes, 2)
$y = [math]::Round($Stopwatch.Elapsed.TotalMinutes, 2)

$string = "Elapsed time is              : $x minutes"
WriteToLogFile $string

$string = "Files Processed              : $files_to_process in $y minutes"
WriteToLogFile $string

$string = "Posters per minute           : " + $speed.ToString()
WriteToLogFile $string
WriteToLogFile "#### END ####"
