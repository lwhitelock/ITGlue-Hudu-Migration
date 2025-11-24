> [!CAUTION]
> **Please Read this entire document before you begin**

# Getting Started
You'll want to make sure your Hudu instance is prepared for migration and that your machine designated to run this script is also properly prepared.

> [!NOTE]
> This is the Hudu Technologies Fork of an amazing open-source project.
>
>The original project was started by Luke Whitelock and often being maintained by Mendy Green and community contributors. This fork is tested for and intended to be used with the very newest Hudu versions. It includes some features that may not (yet) be present in the main repo, [here](https://github.com/lwhitelock/ITGlue-Hudu-Migration). It also includes a more rigid minimum Hudu version requirement.

> [!CAUTION]
> Depending on the size of your ITGlue instance, the migration script can take several hours to run (we've seen it take as long as 24 hours). As such, it's highly recommended to run the migration script on a Windows Server or a machine that has ***Windows Update and Sleep [temporarily] disabled***

> [!IMPORTANT]
> You must be on the ITGlue **Enterprise Plan** (or a legacy plan with API Access) to be able to run the script.

## What the script can migrate currently:
- Companies
- Contacts
- Locations
- Configurations
- Domains
- Flexible Asset Layouts
- Flexible Assets
- Documents with folder structure
- Passwords (with OTP codes)
- Document Links
- * Password Folders [these are flattened into a single level of folders]*
- * Checklists/Checklist Templates [add your users to Hudu first to persist user assignment]

`!` Items with a double-bullet require JWT authentication and are generally for more-advanced users. Extracting JWT token requires web access and developer cosole in your web browser. If you're unsure, best to just skip these.

## What the script cannot migrate:
- Checklists - This is a limitation in the ITGlue API and export lacking functionality for checklists, so there currently is not a workaround.
- SSL Certificates
- Password Folders
 - Unforunately, the IT Glue API does not expose password folders, so there currently isn't a way to bring folders over)
- Personal Passwords
- Permissions (Folders, Companies, Passwords, KBs, etc.)
- List of share links (external articles, passwords, etc.)
 - To our knowledge, there isn't a way to know if/where/how many external share links you are using. Hudu supports external sharing as well, so you'll have to enable those on the Hudu side and get the new links shared out. 


## What you'll need
- An ITGlue API Key with password access (API access is generally limited to the Enterprise plan)
- Your IT Glue API URL
- A full export of your IT Glue tenant (it's recommended to put a hault on IT Glue data updates once you initiate an export)
- A Hudu instance (either self-hosted or cloud hosted)
- A Hudu API Key
- Your Hudu URL


# Prerequisites -  ***Hudu Instance***

It's recommended to have a fresh Hudu install with no integrations setup. You'll want to sync things like companies and contacts from your PSA and configurations from your RMM **after** the migration is completed. Don’t setup any custom Asset Layouts and let the migration create the initial assets.

If you have an existing asset layouts in Hudu, it's recommended to rename them all (i.e. suffixed "-original") before you begin or instruction the migration script to 

**1. Make sure you are on a known-compatible Hudu version--**

At this point in time, the ideal version to be on when using this fork is at least `2.39.1` image. Up to `2.39.0` has been tested to be stable thus far.

**2 (optional).** If you're self hosted, It's best to set ratelimit to be high. To do so, you can add this to your .env file and perform a docker compose down/up. If you're Cloud/Hudu hosted, the script will automatically wait if it hits the rate limit and will continue automatically.

***~$*** ```echo "RATE_LIMIT_REQUESTS=9999999" >> ~/hudu2/.env```

**3 (optional).** If you're just starting out of Hudu and don't have any important data in Hudu, it's best to start with a fresh instance.

  **Self-hosted reset:**

***~$*** ```cd ~/hudu2/ && docker compose down --volumes && docker compose up -d```

  **Cloud-hosted reset:** 
Contact Hudu support [support@hudu.com](support@hudu.com) and we can reset your instance for you. 

***Resetting your instance is completely optional and not necessary to complete the migration***

# Prerequisites - ***ITGlue Instance***

It's highly encouraged to perform a clean up of you IT Glue environment, such as removing any duplicate records and deleting any old data you don’t want to migrate.

Check that your Flexible Layouts don’t have any fields named the same thing on the same layout. For example, if you have two fields called Pre-Shared Key on the "Wireless" asset (One for primary one for guest), rename one of them to prevent script errors. 

ITGlue allows for more than one client to exist with the same Name but Hudu does not. This will cause issues during the migration as the first client will succeed and subsequent clients with the same name will fail with "Name Already Taken" error from Hudu's API. Make sure any client is at least named with a unique name so that the migration can complete successfully.

Blank passwords in ITGlue will cause issues on import and cause the entire password to fail. 

Make sure the API Key you're using has password access, and that all passwords have values, if they're important.


## Data Export

1. **Initiate ITGlue Export.** You will need to log into ITGlue and perform a full export of your instance. To do so, you'll need to log in as a Super Admin and go to Admin>Export. You can choose to run an export with or without activity logs (activity logs are not needed for the migration and having them selected can make the export take longer). ITGlue will email you when the export is completed (normally takes <30 minutes). 
<img width="750"  alt="IT_Glue_Migration_Guide" src="https://github.com/user-attachments/assets/e5b2c49d-6ae5-4960-844e-5f28390de665" />

2. **Download ITGlue Export.** Once the export is complete, navigate back to Admin>Export in ITGlue, download the .zip file, and save it to a safe and secure place (we generally recommend somewhere easy like C:\temp\export). ***Do not unzip the files yet***

3. **Unzipping the files.** Once your data is saved to a good place, it's time to extract the files. It's highly recommended to use a ZIP tool such as 7-zip as the ITGlue export can sometimes name files in a way that Windows Explorer does not natively handle and can cause file names to have strange characters (thus causing some KB articles to not migrate over correctly).

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
4. Check off "Full access" and "View Passwords"
5. Click create
6. Store the API key in a safe place as Hudu will only show you the key once.

<img width="750" alt="IT_Glue_Migration_Guide" src="https://github.com/user-attachments/assets/bf81c7fc-0d0b-4555-b698-1e25fd7da7d3" />

## Prerequisites - ***Migration Script Setup***

1. **Ensure the machine you're running the migration from has PowerShell 7+**
You can [download newest powershell release here](https://github.com/powershell/powershell/releases)

>[!IMPORTANT]
>*Currently, the script has only been tested on x86_64 Windows systems. Although Windows ARM, macOS, and Linux have PowerShell available to them, the script has not been tested on those Operating Systems and is not recommended as the script has a lot of dependencies*

2. Running the script

> [!IMPORTANT]
> Some important things to note about the migration:
> - The script will, for the most part, mirror Flexible Assets in ITGlue. The script ***will not merge asset layouts from ITGlue into ones in Hudu***. Because of this, the script prompts you to create a prefix for asset layouts coming from ITGlue. It's highly recommended to set up a prefix in the script (such as ITG-) as if there is an existing asset layout in Hudu, it will cause a collision and those asset layouts will be skipped.
> - The script will prompt you on what data types you would like to move (you don't have to migrate everything if you don't want to)
> - The script will prompt you to run the script unattended--it can take several hours for the script to run start-to-finish, so unattended mode allows you to set it to run autonomously. If you choose not to run unattended, it _does not_ time out, so you can "continue" the script at any time

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

If you have designated an organization type (like vendor, partner, non-profit, manufacturer, client, etc), you can elect to merge one of these ITGLue organization types to a single Hudu company. If you choose this option during startup questions (or if you include $ScopeOrgTypes = 1 in your env file), you'll first select which org type will be merged into a single company in Hudu. Then you'll enter the company ID for the target company. 

Any other org types will migrate as usual, but this one org type will be centralized to one hudu company.

## 3. Checklists [coming soon] - Checklists from IT Glue currently do not come over


## 4. Custom-Mapping for Target Layouts (ADVANCED)

If you have an existing Hudu instance and you like the layouts that you have created there, you can accomplish this task in a few ways. You can either:

### A. Migrate a certain type of object directly to your desired Hudu Asset Layout [coming soon]

This allows you to go from any flexible asset layout, configuration type, location/contact to whichever asset layout(s) you want. To do this directly, you can answer the startup question to allow for custom mapping (or set $settings.AllowForCustomMapping = $true in your environment file). 

for each would-be-created asset layout in Hudu, you are instead prompted:
1. do you want to allow script to create layout ($true)
2. do you wish to instead map this to an existing Hudu layout ($false).

If you choose to map directly, you will then be prompted for a target asset layout.

you'll select the number corresponding to where you want this asset type to go.

<img width="555" height="656" alt="image" src="https://github.com/user-attachments/assets/005e4cf3-f746-4e0b-84d6-4eb58019a8fe" />

After selecting, a few files will be generated. One of them is a reference and one of them is a form that you'll fill out.
Much like the after-the-fact transfer of assets to new layout, you'll have a source-fields.json file that is a reference for which fields we can grab information from. The other, named after your desired target layout will be in the same folder. These both will be in the project directory if you don't use an environment file, otherwise it will be in your chosen 'debug' folder. 

Once you fill out your form and hit enter in your active powershell session, the form will be loaded and the process will begin. SMOOSH fields are merged, constants are populated, addressdata is filled, fields are stripped of HTML per your choosing. 

<img width="161" height="636" alt="image" src="https://github.com/user-attachments/assets/928139f5-13ca-4d3f-aabb-dbc07cb7a9a8" />

For more information on the rest of the process, please see [Switching layouts guide](./SwitchingLayouts.md)

<img width="1266" height="466" alt="image" src="https://github.com/user-attachments/assets/d49d4ab8-11ee-4df1-b89e-15713a17b026" />

### B. Migrate as normal, then after completed, migrate assets from one layout to another

To migrate assets to a different layout after your ITGlue migration completes, you can simply run this post-run script,

. .\Move-AssetsToNewLayout

You'll be prompted for a source layout to get assets from and a target/destination layout.
For the standalone script, above, a template, named mapping.ps1 will be generated. You'll also see a 'sourcefields.json' file which is for reference.

Using the labels in the 'sourcefields.json', you'll fill out the from='label' fields in mapping.ps1

Just about any source field_type can be mapped to a richtext field or a text field. Just be sure to enable HTML-stripping when targeting a text field with richtext data.

You can also add multiple source field labls to the SMOOSHLABELS array, which will combine data from said fields into a richtext field or a text field.

For filling out locationdata fields, just be sure to fill those out as if they were their own fields, even though they are themselves a singular field. 
For more information on this specific tool, please see [Switching layouts guide](./SwitchingLayouts.md)

# Please Read!
We use the Magick.NET libraries that you can find here https://github.com/dlemstra/Magick.NET/ for image type validation and metadata building.

Please review the licensed rights for Magick.NET here https://github.com/dlemstra/Magick.NET/blob/main/License.txt

These are used only when the image extension was not properly retained in the export, and so we need to determine the type and rename them.

**The original blog post may still be relevant in some cases but is mostly outdated.** See [this link instead](https://mspbook.mspgeek.org/books/hudu-scripts-in-progress/page/itglue-to-hudu-migration) or [this other link here](https://demort.hosteddocs.io/shared_article/7BKhGktLGN1FEDSVEkh1bLpF)



# Known Issues
 - Password Relations to Articles, Password Folders, and SSL Certificates are not currently included

Password relations are only available from ITGlue when querying the API directly for each password individually. Since this will increase the runtime of the script by hours or days potentially we'll be making a script to run at the end which will loop through passwords and update the relations at that time. For right now relationships between Passwords and any entity that is not available in the API (Articles, and SSL Certificates) is completely invisbile to this migration script.

# Disclaimer

This PowerShell script, and all items contained within the repository, is provided "as-is" without any warranties or guarantees, express or implied. The authors and Hudu Technologies make no guarantees regarding the accuracy, reliability, or suitability of the script for any purpose.

By using this script, you acknowledge that you do so at your own risk. The authors and Hudu Technologies shall not be liable for any damages, losses, or issues that may arise from its use, including but not limited to data loss, system failures, or security breaches. Always review the code thoroughly and test it in a safe environment before deploying it in a production setting.

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
