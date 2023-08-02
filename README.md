___
# Please Read!

_This project relies on external libraries, please read this carefully_
We use the Magick.NET libraries that you can find here https://github.com/dlemstra/Magick.NET/ for image type validation and metadata building.

Please review the licensed rights for Magick.NET here https://github.com/dlemstra/Magick.NET/blob/main/License.txt

**No modifications have been made to the binaries at this time**
___
# ITGlue-Hudu-Migration

**For the early beta version of the script, 2024-dev branch, the blog post may still be relevant in some cases but is mostly outdated.**

**For the current stable version of the script please see the following directions.**
Please see the blog post at: https://mspp.io/automated-it-glue-to-hudu-migration-script/ for details on running this script.

# Release Notes
## Version 2.x - NON-STABLE EARLY VERSION
This version of the script brings an interactive migration process, settings will get saved by default to `%APPDATA%\HuduMigration` although they can be moved and then re-imported from a different path after creation.

Settings that will be saved include API Keys, URLs, Prefixes, and so on. You can modify the settings.json file directly as long as you use values that are expected. 

**Settings that are not saved include the migration preferences (such as what entites to migrate)**
*TIP: Load the script through DOT SOURCING `. .\migration\ITGlue-Hudu-Migration.ps1` so that the session saves the answers in context and you can re-run as necessary.*

- Powershell Secure Strings are used in Settings to encrypt sensitive API Keys
- modify the `$resumeQuestion` variable from `yes` to `no` to change if you would like to continue or start over.
- MigrationLogs are stored by default in `%APPDATA%\HuduMigration` make sure you keep these safe!
- URL Rewrites have been updated to apply to all Rich Text asset fields, articles, Company Quick Notes, and Password notes
- Image Upload has been improved to use the Hudu API endpoint instead of Base64 and will include the best quality image available
___
**COMING SOON:** 
- Archived Companies, Articles, and Assets will be archived even after migration
- Previously unsupported tagged relations have been supplemented by doing regular related items instead of tags (Articles, AssetPasswords)
- `Replace-HuduBase64images.ps1` has been updated to use the API and will be available for fixing completed imports that placed base64 images in articles.
- `Add-HuduAttachments.ps1` can be used to upload and connect attachments to Hudu (NOT READY YET). This will be updated as this gets completed and more instructions are provided.
___
## Version 1.2
Small bug fixes
## Version 1.1
Small bug fixes
## Version 2.0.0-beta
This is under development right now and should not be used.

# Replace Base64 Images
## NON-SUPPORTED BY HUDU
## Please see https://mspbook.mspgeek.org/books/hudu-database for more details

Use this script to replace previous migrations that embedded Base64 images into your articles. If your Hudu is crashing or running out of memory trying to retrieve articles, this wil fix it.
