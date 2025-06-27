# ITGlue-Hudu-Migration

# Getting Started
You'll want to make sure your Hudu instance is prepared for migration and that your machine designated to run this script is also properly prepared.

## Prerequisites-  ***Hudu Instance***

### 1. Make sure you are on a known-compatible Hudu version--

At this point in time **(Jun 27, 2025)**, the ideal version to be on when using this fork is at least `2.37.1` image. `2.38.0` is being tested at this very moment and likely works just fine as well.

### 2. It's best to set ratelimit to be high. to do so, you can add this yo your .env file and perform a docker compose down/up

***~$*** ```echo "RATE_LIMIT_REQUESTS=9999999" >> ~/hudu2/.env```

### 3. Make sure you are on a newly-reset instance --

To reset:

***~$*** ```cd ~/hudu2/ && docker compose down --volumes && docker compose up -d```

## Prerequisites- ***Migration Setup***

### 1. Ensure will need to be on powershell 7+, best ran from Windows Machine
You can [download newest powershell release here](https://github.com/powershell/powershell/releases)

### 2. Until ratelimiting fix is published for Hudu API module in PSgallery, it's reccomended to use our fork for this-- `https://github.com/Hudu-Technologies-Inc/HuduAPI` to this directory: `c:\users\$env:USERNAME\Documents\GitHub\HuduAPI`
***See examples, below***

Option 1: Clone with Git to ***expected path***

***pwsh*** ```git clone https://github.com/Hudu-Technologies-Inc/HuduAPI "C:\Users\$env:USERNAME\Documents\GitHub\HuduAPI"```

Option 2: Download & Extract to ***expected path***

***pwsh*** ```
$dst = "$HOME\Documents\GitHub\HuduAPI"
$zip = "$env:TEMP\huduapi.zip"
Invoke-WebRequest -Uri "https://github.com/Hudu-Technologies-Inc/HuduAPI/archive/refs/heads/master.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $env:TEMP -Force
$extracted = Join-Path $env:TEMP "HuduAPI-master"
if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
Move-Item -Path $extracted -Destination $dst
Remove-Item $zip -Force```

### 3. Invocation-

you can run via dot-sourcing a copy of environ.example that has been filled out or via dot-sourcing the main script. Here are some handy snippets that will already run if dot-sourcing from environ file, but you will want to run manually otherwise.

***main invocation***

```. .\ITGlue-Hudu-Migration.ps1```


***set layouts as active post-run***

```foreach ($layout in Get-HuduAssetLayouts) {write-host "setting $($(Set-HuduAssetLayout -id $layout.id -Active $true).asset_layout.name) as active" }```

***populate remaining relations variables***

```. .\Get-MissingRelations.ps1```

***adding attachments***

```. .\Add-HuduAttachmentsViaAPI.ps1```

***add any remaining relations***

```
$ConfigurationRelationsToCreate + $AssetRelationsToCreate | ForEach-Object {try {New-HuduRelation -FromableType  $_.FromableType -FromableID    $_.FromableID -ToableType    $_.ToableType -ToableID      $_.ToableID} catch {Write-Host "Skipped or errored: $_" -ForegroundColor Yellow}}
```


# Please Read!
We use the Magick.NET libraries that you can find here https://github.com/dlemstra/Magick.NET/ for image type validation and metadata building.

Please review the licensed rights for Magick.NET here https://github.com/dlemstra/Magick.NET/blob/main/License.txt

These are used only when the image extension was not properly retained in the export, and so we need to determine the type and rename them.

**The original blog post may still be relevant in some cases but is mostly outdated.** See [this link instead](https://mspbook.mspgeek.org/books/hudu-scripts-in-progress/page/itglue-to-hudu-migration) or [this other link here](https://demort.hosteddocs.io/shared_article/7BKhGktLGN1FEDSVEkh1bLpF)

## Note- This is the Hudu Technologies Fork of an amazing open-source project

The original project was started by Luke Whitelock and often being maintained by Mendy Green and community contributors. This fork is tested for and intended to be used with the very newest Hudu versions. It includes some features that may not (yet) be present in the main repo, [here](https://github.com/lwhitelock/ITGlue-Hudu-Migration). It also includes a more rigid minimum Hudu version requirement.

At present, this fork works very well with 2.37.1 and is also being tested against some beta builds. 

# Known Issues
 - Password Relations to Articles and SSL Certificates are not currently included

Password relations are only available from ITGlue when querying the API directly for each password individually. Since this will increase the runtime of the script by hours or days potentially we'll be making a script to run at the end which will loop through passwords and update the relations at that time. For right now relationships between Passwords and any entity that is not available in the API (Articles, and SSL Certificates) is completely invisbile to this migration script.

# Release Notes
## Get-MissingRelations.ps1 added
This script should be run at the very end, with the Matched* variables existing from the migration, it'll loop through matched Configurations and Assets (Configurations and Flexible Assets in ITGlue) and pull the latest relations

It will save two variables `$ConfigurationRelationsToCreate` and `$AssetRelationsToCreate` that can be used to build relations in Hudu using the `New-HuduRelation` command. Duplicate relations won't be created as it'll throw an error so it's safe to re-run.

## Version 2.x - Well tested but still beta version
This version of the script brings an interactive migration process, settings will get saved by default to `%APPDATA%\HuduMigration` although they can be moved and then re-imported from a different path after creation.

Settings that will be saved include API Keys, URLs, Prefixes, and so on. You can modify the settings.json file directly as long as you use values that are expected. 

**Settings that are not saved include the migration preferences (such as what entites to migrate)**
*TIP: Load the script through DOT SOURCING `. .\migration\ITGlue-Hudu-Migration.ps1` so that the session saves the answers in context and you can re-run as necessary.*

- Powershell Secure Strings are used in Settings to encrypt sensitive API Keys
- modify the `$resumeQuestion` variable from `yes` to `no` to change if you would like to continue or start over.
- MigrationLogs are stored by default in `%APPDATA%\HuduMigration` make sure you keep these safe!
- URL Rewrites have been updated to apply to all Rich Text asset fields, articles, Company Quick Notes, and Password notes
- Image Upload has been improved to use the Hudu API endpoint instead of Base64 and will include the best quality image available
- `Add-HuduAttachmentsViaAPI.ps1` can be used to upload attachments to Hudu. This no longer uses the direct database connection although if you run the script more than once it'll upload duplicate attachments.
- Previously unsupported tagged relations have been supplemented by doing regular related items instead of tags (Articles, AssetPasswords)
- Archived Assets will be archived even after migration
- The initialization will prompt for multiple ITGlue domain names and will ATTEMPT (lightly tested) to rewrite ALL of them to the correct Hudu ones.


___
**COMING SOON:** 
- Archived Articles will be archived even after migration
- `Replace-HuduBase64images.ps1` has been updated to use the API and will be fully adapted for fixing completed imports that placed base64 images in articles.
___
## Version 1.2
Small bug fixes
## Version 1.1
Small bug fixes
## Version 2.0.0-beta
This is under development right now and should not be used.

### Replace Base64 Images
Use this script to replace previous migrations that embedded Base64 images into your articles. If your Hudu is crashing or running out of memory trying to retrieve articles, this wil generally fix it. If API isn't sufficient for collecting the articles you can switch to direct database access with an older version of this script.


### Attachment Uploads
The attachments script will use the API to upload the files create links inside of Hudu
Note that there's no way to see the attachments currently via the API so if you run the script more than once it'll upload duplicate files and can fill up your space
