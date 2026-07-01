> [!CAUTION]
> **Please Read this entire document before you begin**

# Getting Started
You'll want to make sure your Hudu instance is prepared for migration and that the machine you use to run this migration (executable or PowerShell) is also properly prepared.

> [!NOTE]
> This is the Hudu Technologies Fork of an amazing open-source project.
>
>The original project was started by Luke Whitelock and often being maintained by Mendy Green and community contributors. This fork is tested for and intended to be used with the very newest Hudu versions. It includes some features that may not (yet) be present in the main repo, [here](https://github.com/lwhitelock/ITGlue-Hudu-Migration). It also includes a more rigid minimum Hudu version requirement.

> [!CAUTION]
> Depending on the size of your ITGlue instance, the migration script can take several hours to run (we've seen it take as long as 24 hours). As such, it's highly recommended to run the migration script on a Windows Server or a machine that has ***Windows Update and Sleep [temporarily] disabled***

> [!IMPORTANT]
> You must be on the ITGlue **Enterprise Plan** (or a legacy plan with API Access) to be able to run the migration.

## Windows executable (recommended)

**This is how most people run the migration.** The repository includes a pre-built Windows app at **`release/ITGlue-Hudu-Migration.exe`**. It runs the same interactive flow as the main PowerShell script and uses the same default settings location.

<img width="1248" height="1066" alt="H83uf1uxHZ2OZnqzbyMXl (1)" src="https://github.com/user-attachments/assets/09386a13-79ab-4da2-8f46-cd121da5b5f0" /> <img width="1244" height="1192" alt="u8AsTcss0nzSAjYT5tXzc (1)" src="https://github.com/user-attachments/assets/eeb70697-89cc-4666-99cb-d7f46133600c" />


- **How to run:** Clone or download the repository, open the **`release`** folder, and run **`ITGlue-Hudu-Migration.exe`** (double-click or from a terminal). You still need your ITGlue export ZIP, API keys, and a compatible Hudu instance—work through **What you'll need** and **Prerequisites** later in this document before you start.
- **Settings:** Stored by default under `%APPDATA%\HuduMigration`, same as the PowerShell workflow.
- **Use PowerShell instead** if you rely on a customized **`environ.example`**, want full session control over variables, or need to manually invoke post-run scripts such as **`Get-MissingRelations.ps1`**, **`Move-AssetsToNewLayout.ps1`**, **`Add-HuduAttachmentsViaAPI.ps1`**, or **`Replace-HuduBase64Images.ps1`** -note, these are ran as part of the main script and are always ran, so you likely wont need to consider post-run scripts.

## What the script does migrate:
- Companies
- Contacts
- Locations
- Configurations
- Domains
- Flexible Asset Layouts
- Flexible Assets
- Documents with folder structure
- Passwords (with OTP codes)
- IP Addresses / Networks
- Document Links
- Password folders (flattened to single-level)
- ! Checklists / checklist templates (optional, JWT): imported as **Hudu procedures/processes**; add users to Hudu first so checklist assignees can be matched where possible

Items marked with **!** require **JWT** authentication (ITGlue session token from your browser) and are intended for advanced users. Extracting a JWT requires web access and your browser’s developer tools. If you are unsure, skip these options.

## What the script does not migrate:
- Permissions (Folders, Companies, Passwords, KBs, etc.)
- share links- you'll have to enable those on the Hudu side and get the new links shared out.


## What you'll need
- An ITGlue API Key with password access (API access is generally limited to the Enterprise plan)
- Your IT Glue API URL
- A full export of your IT Glue tenant (it's recommended to put a halt on IT Glue data updates once you initiate an export)
- A Hudu instance (either self-hosted or cloud hosted)
- A Hudu API Key
- Your Hudu URL


# Prerequisites -  ***Hudu Instance***

It's recommended to have a fresh Hudu install with no integrations setup. You'll want to sync things like companies and contacts from your PSA and configurations from your RMM **after** the migration is completed. Don’t setup any custom Asset Layouts and let the migration create the initial assets.

If you have existing asset layouts in Hudu, rename them (for example suffix `"-original"`) before you begin, or use a **layout prefix** in the migration prompts so new ITGlue layouts do not collide with existing Hudu layouts. For newer versions of Hudu, it is recommended that if you are signing in for the first time, to click 'skip setup'

<img width="1135" height="696" alt="image" src="https://github.com/user-attachments/assets/8a9b7e01-8de6-479a-b5de-6e23afdfa470" />

If you've already elected to run through setup, that is fine, but you will need to clear out any asset layouts created as a result. It is slightly easier to 'skip setup' in the first place, but either way is fine, as long as you are using a layout prefix for your migration or (ideally) you've cleaned out any existing layouts before running. (removal pictured below)

<img width="2784" height="1742" alt="image" src="https://github.com/user-attachments/assets/899a777f-c9a5-458a-a1c6-9a9c1fb21cf5" />

**1. Make sure you are on a known-compatible Hudu version**

This fork requires **Hudu `2.39.6` or newer**. Version **`2.37.0` is blocked** (incompatible). Upgrade self-hosted instances before running the migration.

**Optional — flags and flag types:** If you choose to migrate flags during setup, that path expects **Hudu `2.40.0` or later** (the script will prompt accordingly).

**2 (optional).** If you're self hosted, It's best to set ratelimit to be high. To do so, you can add this to your .env file and perform a docker compose down/up. If you're Cloud/Hudu hosted, the script will automatically wait if it hits the rate limit and will continue automatically.

***~$*** ```echo "RATE_LIMIT_REQUESTS=9999999" >> ~/hudu2/.env```

**3 (optional).** If you're just starting out of Hudu and don't have any important data in Hudu, it's best to start with a fresh instance.

  **Self-hosted reset:**

***~$*** ```cd ~/hudu2/ && docker compose down --volumes && docker compose up -d```

  **Cloud-hosted reset:** 
Contact Hudu support [support@hudu.com](support@hudu.com) and we can reset your instance for you. 

***Resetting your instance is completely optional and not necessary to complete the migration***

# Prerequisites - ***ITGlue Instance***

It's highly encouraged to perform a clean up of your IT Glue environment, such as removing any duplicate records and deleting any old data you don’t want to migrate.

Check that your Flexible Layouts don’t have any fields named the same thing on the same layout. For example, if you have two fields called Pre-Shared Key on the "Wireless" asset (One for primary one for guest), rename one of them to prevent script errors. 

ITGlue allows for more than one client to exist with the same Name but Hudu does not. This will cause issues during the migration as the first client will succeed and subsequent clients with the same name will fail with "Name Already Taken" error from Hudu's API. Make sure any client is at least named with a unique name so that the migration can complete successfully.

Blank passwords in ITGlue will cause issues on import and cause the entire password to fail. 

Make sure the API Key you're using has password access, and that all passwords have values, if they're important.


## Data Export

1. **Initiate ITGlue Export.** You will need to log into ITGlue and perform a full export of your instance. To do so, you'll need to log in as a Super Admin and go to Admin>Export. You can choose to run an export with or without activity logs (activity logs are not needed for the migration and having them selected can make the export take longer). ITGlue will email you when the export is completed (normally takes <30 minutes). 
<img width="750"  alt="IT_Glue_Migration_Guide" src="https://github.com/user-attachments/assets/e5b2c49d-6ae5-4960-844e-5f28390de665" />

### ***NOTE- If presented with a checkbox asking whether or not to include passwords, be sure to do so!***

<img width="750" alt="include-passwords" src="https://github.com/user-attachments/assets/e75f9966-8eee-4696-b683-e8acbf150b17" />

2. **Download ITGlue Export.** Once the export is complete, navigate back to Admin>Export in ITGlue, download the .zip file, and save it to a safe and secure place (we generally recommend somewhere easy like C:\temp\export). ***Do not unzip the files yet***

3. **Unzipping the files.** Once your data is saved to a good place, it's time to extract the files. It's highly recommended to use a ZIP tool such as 7-zip as the ITGlue export can sometimes name files in a way that Windows Explorer does not natively handle and can cause file names to have strange characters (thus causing some KB articles to not migrate over correctly).

(don't manipulate or change these files after extraction)

## API Keys

### ITGlue API Key

1. Log into ITGlue as a Super Admin, navigate to the Admin center, and click the "API keys" tab at the top.
2. You want to create a new key (+) and be sure to check off "Password Access"
3. Store the API key in a safe place as ITGlue will only show you the key once. 

<img width="750" alt="IT_Glue_Migration_Guide" src="https://github.com/user-attachments/assets/f1f4868a-760f-46e2-ac94-cabf08146991" />

### Hudu API Key

1. Log into your Hudu tenant as a Super Admin
2. Go to Admin>API Keys
3. Click "+ New API Key"
4. Select "Full access" Radio Button
5. Check View passwords, Delete data, and ***(future-use)*** Export Data
6. Click create
7. Store the API key in a safe place as Hudu will only show you the key once.

<img width="1114" height="1016" alt="image" src="https://github.com/user-attachments/assets/450e9107-3f78-4137-88b5-08ecd5da6ca9" />

## Prerequisites - ***Migration Script Setup***

1. **Ensure the machine you're running the migration from has PowerShell 7+**
You can [download newest powershell release here](https://github.com/powershell/powershell/releases)

>[!IMPORTANT]
>You must run the script using **PowerShell 7+** (`pwsh.exe`). It will _not_ run in **Windows PowerShell 5.x** (`powershell.exe`).
>
>*Currently, the script has only been tested on x86_64 Windows systems. Although Windows ARM, macOS, and Linux have PowerShell available to them, the script has not been tested on those Operating Systems and is not recommended as the script has a lot of dependencies*

2. Running the script

> [!IMPORTANT]
> Some important things to note about the migration:
> - The script will, for the most part, mirror Flexible Assets in ITGlue. The script ***will not merge asset layouts from ITGlue into ones in Hudu***. Because of this, the script prompts you to create a prefix for asset layouts coming from ITGlue. It's highly recommended to set up a prefix in the script (such as ITG-) as if there is an existing asset layout in Hudu, it will cause a collision and those asset layouts will be skipped.
> - The script will prompt you on what data types you would like to move (you don't have to migrate everything if you don't want to)
> - The script will prompt you to run the script unattended--it can take several hours for the script to run start-to-finish, so unattended mode allows you to set it to run autonomously. If you choose not to run unattended, it _does not_ time out, so you can "continue" the script at any time
> - By default, the lowest-level folders will be included in your articles migration. Previously, this was not the default behavior. To change this, you can set this variable to false `$IncludeIgnoredFirstArticleDirectory = $false` in your environment file
> - Your internal docs, by default will go into your Global KB. This is usually how to do things in Hudu. However, if you want to migrate internal documents into your internal company instead, set this variable to true `PlaceInternalDocsInInternalCompany = $true` in your environment file (inside the settings hashtable).

Settings will get saved by default to %APPDATA%\HuduMigration. Settings that will be saved include API Keys, URLs, Prefixes, and so on. You can modify the settings.json file directly as long as you use expected values.


1. Download/Clone the _entire_ repo into a folder on your computer.
2. Use Dot Sourcing to run the main file ". .\ITGlue-Hudu-Migration.ps1" from the path of where you extracted the ZIP file of the repo.
3. You'll be prompted for the initial setup and it will save the settings to a file.
4. You can also resume a session and import the saved settings if you need to.

Using Dot Sourcing to load the script will save your answers into variables and so interrupting and resuming the migration but keeping the PowerShell session active will allow you to bypass most of the initial questions. With Dot Sourcing you'll also get access to the variables at the end of the script run to examine the data or modify the parameters of the run. For example change the "$resumeQuestion" from "yes" to "no" or vice versa to resume an import or start over from scratch.


It's best to run the script via dot-sourcing a copy of **environ.example** that has been filled out (if you use the environ file, rename it to something like migration.ps1 -- make sure it has the .ps1 extension so you can run it!) or via dot-sourcing the main script. It's best to store the script somewhere easy to run such as C:\temp

**For example, all of the packaged scripts in the repo will automatically run if dot-sourcing from environ file, otherwise, you'll have to manually run them at the end:**

***main invocation***


```. .\migration.ps1``` (the modified environ.example file -- recommended) 

or

```. .\ITGlue-Hudu-Migration.ps1```


# Advanced / Other Use Cases

## 1. Scoped Migrations - 

For scoped migrations, you can either set $ScopedMigration=2 in your environment file or elect for a scoped migration in the initialization questions. It's the final question before things kick off. 

Just before companies are migrated, you'll be able to select which ITGlue companies you'd like to include in transferring to Hudu. Only the companies you choose and assets/configurations/websites/contacts/locations belonging to those companies will transfer.

## 2. Merging ITGlue Organization Types

If you have designated an organization type (like vendor, partner, non-profit, manufacturer, client, etc), you can elect to merge one of these ITGlue organization types to a single Hudu company. If you choose this option during startup questions (or if you include $ScopeOrgTypes = 1 in your env file), you'll first select which org type will be merged into a single company in Hudu. Then you'll enter the company ID for the target company. 

Any other org types will migrate as usual, but this one org type will be centralized to one hudu company.

## 3. Checklists and checklist templates (optional, JWT)

When you opt in during the migration, checklists and checklist templates are imported using a **JWT** from ITGlue (see the **!** items at the top of this document under **What the script does migrate**). Tag-style relations to checklists from other assets are still not migrated--plan for manual cleanup where needed.

ITGlue and Hudu use similar names for different concepts, so the migration follows this model:

| Source | Scope | Reusable | Due dates / assignees | Hudu target |
| --- | --- | --- | --- | --- |
| ITGlue checklist template | Admin | Yes | No | Hudu global process template, or company process template when the template is tied to a matched ITGlue organization |
| ITGlue checklist | Company | No | Sometimes | Hudu process run on Hudu 2.41.0+ only when run-only metadata exists and the checklist's company is matched; otherwise a company/global process template with imported tasks |
| Hudu global process template | Admin | Reusable across companies | No | Closest ITGlue equivalent: checklist template |
| Hudu company process template | Company | Reusable inside one company | No | Closest ITGlue equivalent: checklist template |
| Hudu process run | Company/global/asset | No | Yes | Closest ITGlue equivalent: checklist |

Hudu process mapping:

- ITGlue checklist templates are reusable definitions, so they become Hudu process templates. With a matched company they become company process templates; otherwise they become global process templates.
- ITGlue checklists become company/global process templates first. On Hudu 2.41.0+, they are kicked off as process runs only when run-only metadata like due dates, assignees, or start/completion dates is present.


Checklist template tasks are retrieved from ITGlue's checklist template task endpoint. Checklist tasks and checklist template tasks are not interchangeable, which is why a preloaded checklist cache should be regenerated if it was created before this distinction was added.

In Chrome, you'll need the "JWT Inspector:"

<img width="206" height="276" alt="image" src="https://github.com/user-attachments/assets/fcd43f21-0c6e-47fe-a0af-d3356ebbcc6b" />
<img width="1502" height="650" alt="image" src="https://github.com/user-attachments/assets/7432610f-2899-4aa8-8b2b-33abee9596b4" />
(You might have to refresh the page to get it to show). 

Then when you click “copy token to clipboard,” that’s what you’ll need to copy into the script. 


. .\Move-AssetsToNewLayout

You'll be prompted for a source layout to get assets from and a target/destination layout.
For the standalone script, above, a template, named mapping.ps1 will be generated. You'll also see a 'sourcefields.json' file which is for reference.

Using the labels in the 'sourcefields.json', you'll fill out the from='label' fields in mapping.ps1

Just about any source field_type can be mapped to a richtext field or a text field. Just be sure to enable HTML-stripping when targeting a text field with richtext data.

You can also add multiple source field labels to the SMOOSHLABELS array, which will combine data from said fields into a richtext field or a text field.

For filling out locationdata fields, just be sure to fill those out as if they were their own fields, even though they are themselves a singular field. 
For more information on this specific tool, please see [Switching layouts guide](./SwitchingLayouts.md)

## 4. Organizations with Vaulted Passwords

If you have organizations that include vaulted or AES-256-GCM encrypted passwords that require a passphrase to access (not common), you'll need to perform the migration as usual, then run the `Un-Vault-Passwords.ps1` script afterwards in the same session.

If you have many orgs with vaulted passwords, they will each need to be exported on a org-by-org basis from itglue (and can be combined.)

once you have your unvaulted password CSV(s), you can run 

```powershell
. .\Un-Vault-Passwords.ps1
```

in the same powershell session. It will prompt you for the path to your unvaulted CSV file (one csv at a time) and will decrypt and update your passwords after verifying the matches with you.


# Please Read!
We use the Magick.NET libraries that you can find here https://github.com/dlemstra/Magick.NET/ for image type validation and metadata building.

Please review the licensed rights for Magick.NET here https://github.com/dlemstra/Magick.NET/blob/main/License.txt

These are used only when the image extension was not properly retained in the export, and so we need to determine the type and rename them.

**The original blog post may still be relevant in some cases but is mostly outdated.** See [this link instead](https://mspbook.mspgeek.org/books/hudu-scripts-in-progress/page/itglue-to-hudu-migration) or [this other link here](https://demort.hosteddocs.io/shared_article/7BKhGktLGN1FEDSVEkh1bLpF)


# Known Issues
 - Relations to SSL Certificates are not currently included

Password relations are only available from ITGlue when querying the API directly for each password individually. Since this will increase the runtime of the script by hours or days potentially we have a script to run at the end which will loop through passwords and update the relations at that time. For right now relationships between Passwords and any entity that is not available in the API (SSL Certificates) are completely invisible to this migration script.

# Disclaimer

This migration tool (PowerShell scripts, packaged executable, and all other items in the repository) is provided "as-is" without any warranties or guarantees, express or implied. The authors and Hudu Technologies make no guarantees regarding the accuracy, reliability, or suitability of the script for any purpose.

By using this tool, you acknowledge that you do so at your own risk. The authors and Hudu Technologies shall not be liable for any damages, losses, or issues that may arise from its use, including but not limited to data loss, system failures, or security breaches. Always review the code thoroughly and test it in a safe environment before deploying it in a production setting.

# Release Notes
## Get-MissingRelations.ps1 updated to include from-document, from locations/contacts asssets, and including both related items specifications from ITglue
This script is run at the very end but is safe to run twice, with the Matched* variables existing from the migration, it'll loop through matched Configurations and Assets (Configurations and Flexible Assets in ITGlue) and pull the latest relations

It will save variable: `$RelationsToCreate` that can be used to build relations in Hudu using the `New-HuduRelation` command. Duplicate relations won't be created as it'll throw an error so it's safe to re-run.


___
- `Replace-HuduBase64Images.ps1` has been updated to use the API and will be fully adapted for fixing completed imports that placed base64 images in articles.
___
## Version 1.2
Small bug fixes
## Version 1.1
Small bug fixes
## Version 2.0.0-beta (historical)

Older documentation referred to a **2.0.0-beta** line; the current **2.x** interactive migration on `main` is the supported path. The notes below still apply to companion utilities.

## Version 2.x - Well tested but still beta version (historical)
This version of the script brings an interactive migration process, settings will get saved by default to `%APPDATA%\HuduMigration` although they can be moved and then re-imported from a different path after creation.

Settings that will be saved include API Keys, URLs, Prefixes, and so on. You can modify the settings.json file directly as long as you use values that are expected. 

**Settings that are not saved include the migration preferences (such as what entities to migrate)**

*TIP: Dot-source the main script from the repo root, for example `. .\ITGlue-Hudu-Migration.ps1`, so the session keeps answers in context and you can re-run as necessary.*

- Powershell Secure Strings are used in Settings to encrypt sensitive API Keys
- modify the `$resumeQuestion` variable from `yes` to `no` to change if you would like to continue or start over.
- MigrationLogs are stored by default in `%APPDATA%\HuduMigration` make sure you keep these safe!
- URL Rewrites have been updated to apply to all Rich Text asset fields, articles, Company Quick Notes, and Password notes
- Image Upload has been improved to use the Hudu API endpoint instead of Base64 and will include the best quality image available
- `Add-HuduAttachmentsViaAPI.ps1` can be used to upload attachments to Hudu. This no longer uses the direct database connection although if you run the script more than once it'll upload duplicate attachments.
- Previously unsupported tagged relations have been supplemented by doing regular related items instead of tags (Articles, AssetPasswords)
- Archived Assets will be archived even after migration
- The initialization will prompt for multiple ITGlue domain names and will ATTEMPT (lightly tested) to rewrite ALL of them to the correct Hudu ones.


### Replace Base64 Images
Use this script to replace previous migrations that embedded Base64 images into your articles. If your Hudu is crashing or running out of memory trying to retrieve articles, this will generally fix it. If API isn't sufficient for collecting the articles you can switch to direct database access with an older version of this script.


### Attachment Uploads
The attachments script will use the API to upload the files create links inside of Hudu
Note that there's no way to see the attachments currently via the API so if you run the script more than once it'll upload duplicate files and can fill up your space

## Community & Socials

[![Hudu Community](https://img.shields.io/badge/Community-Forum-blue?logo=discourse)](https://community.hudu.com/)
[![Reddit](https://img.shields.io/badge/Reddit-r%2Fhudu-FF4500?logo=reddit)](https://www.reddit.com/r/hudu)
[![YouTube](https://img.shields.io/badge/YouTube-Hudu-red?logo=youtube)](https://www.youtube.com/@hudu1715)
[![X (Twitter)](https://img.shields.io/badge/X-@HuduHQ-black?logo=x)](https://x.com/HuduHQ)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Hudu_Technologies-0A66C2?logo=linkedin)](https://www.linkedin.com/company/hudu-technologies/)
[![Facebook](https://img.shields.io/badge/Facebook-HuduHQ-1877F2?logo=facebook)](https://www.facebook.com/HuduHQ/)
[![Instagram](https://img.shields.io/badge/Instagram-@huduhq-E4405F?logo=instagram)](https://www.instagram.com/huduhq/)
[![Feature Requests](https://img.shields.io/badge/Feedback-Feature_Requests-brightgreen?logo=github)](https://hudu.canny.io/)

