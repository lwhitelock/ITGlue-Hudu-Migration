# Hudu Asset Layout Transfer

[original community post, Sep 2025](https://community.hudu.com/script-library-awpwerdu/post/migrating-assets-between-layouts-with-ease-xY9nzqtWj6X9wSL)


Migrate assets between **Hudu** layouts while flexibly mapping fields, concatenating (“SMOOSH”) values, translating data types, and optionally relinking related objects.

> **TL;DR**  
> 1) Dot-source `. .\Move-AssetsToNewLayout.ps1`  
> 2) Pick **Source** + **Destination** layouts  
> 3) Edit the generated `mapping.ps1` (and optionally use `SMOOSH`)  
> 4) Run the transfer and review the summary counts


---

## Features
- **Layout → Layout** migration with interactive layout pickers  
- **Field mapping** via generated `mapping.ps1`  
- **Constants**: auto-fill required fields with fixed values  
- **SMOOSH**: concatenate multiple source fields into one destination field (rich text or plain)  
- **HTML stripping & email normalization** on demand  
- **AddressData** helper block mapping (line1/line2/city/state/zip/country)  
- **Relation handling**: optional relinking of related assets; control over archived relations  
- Built-in checks + per-job settings

---

## Requirements
- **PowerShell** ≥ `7.5.1` (will not work currently on other PowerShell versions)
- Hudu **API Key** and **Base URL**
- source asset layout with assets you hope to move to another existing layout

---

## Quick Start

```powershell
# 1) Launch PowerShell 7+
# 2) Dot-source the script
. .\Move-AssetsToNewLayout.ps1

# 3) Follow the prompts to select Source and Destination layouts
#    The script generates:
#    - mapping.ps1
#    - source-fields.json
#    - dest-fields.json

# 4) Open mapping.ps1, fill in your mappings, save
# 5) Press Enter in the shell to continue and execute the transfer
```

> **Tip:** You can safely re-run the script if needed; the script backs up an existing `mapping.ps1` to `mapping.ps1.old`.

---

## How It Works
1. **Scans layouts** and builds summaries (# required/optional fields, asset counts).  
2. **Prompts** you to choose Source and Destination layouts.  
3. **Emits templates**: `mapping.ps1` and `*-fields.json` (for reference).  
4. **You edit** `mapping.ps1` to define how source fields map to destination fields.  
5. **Transfers**: for each source asset, builds a destination payload, applies transformations, optionally **SMOOSH**es values, and creates the new asset.  
6. **Relations**: can relink related assets; archive policies are configurable.  
7. **Wrap-up**: optional renaming/archiving of the source layout and/or its assets; summary statistics printed.

---

## The Mapping File (`mapping.ps1`)

The script generates `mapping.ps1` with placeholders you can fill. It contains three key blocks:

### 1) `$CONSTANTS`
Predefined pseudo-source fields to satisfy required destination fields or inject static values.

```powershell
$CONSTANTS = @(
    # @{ literal = "const value"; to_label = "Destination Field Label" }
)
```

**Behavior:** For each entry, the destination field named in `to_label` receives `literal`.

---

### 2) `$SMOOSHLABELS`
A list of **source labels** to concatenate into a single pseudo-source field named **`SMOOSH`**. You can then map `SMOOSH` to any destination field.

```powershell
$SMOOSHLABELS = @(
    'Manufacturer Name','Model ID','Hostname','Default Gateway','Asset Tag',
    'Operating System Name','Installed By','Installed At','Purchased By',
    'Purchased At','Contact Name','Operating System Notes','Notes',
    'Configuration Status Name','Location Name'
)
```

> **Tip:** `SMOOSH` renders as rich text by default; set `excludeHTMLinSMOOSH = $true` to emit a single-line, plain-text value.

---

### 3) `$mapping`
The core mapping array. Each entry maps a single **source** label (`from`) to a **destination** label (`to`), with a **destination type** and options.

```powershell
$mapping = @(
    @{ from = 'Model Name'         ; to = 'Model'                        ; dest_type = 'Text'    ; required = 'True'  ; striphtml='False' },
    @{ from = 'Primary IP'         ; to = 'IP Address'                   ; dest_type = 'Website' ; required = 'False' ; striphtml='False' },
    @{ from = 'MAC Address'        ; to = 'Mac Address'                  ; dest_type = 'Text'    ; required = 'False' ; striphtml='False' },
    @{ from = 'Serial Number'      ; to = 'Serial Number / Service Tag'  ; dest_type = 'Text'    ; required = 'False' ; striphtml='False' },
    @{ from = 'Warranty Expires At'; to = 'Warranty Expiration'          ; dest_type = 'Date'    ; required = 'False' ; striphtml='False' },
    @{ from = 'SMOOSH'             ; to = 'Notes'                        ; dest_type = 'RichText'; required = 'False' ; striphtml='False' }
)
```

#### Supported `dest_type` values

| Type         | Notes |
|--------------|------|
| `Text`       | Plain text. Combine with `striphtml='True'` if source may have markup. |
| `RichText`   | HTML content preserved. |
| `Website`    | URL/string field. (Often used for IP/URL fields.) |
| `Date`       | ISO/parseable date values recommended. |
| `Email`      | Extracts and normalizes emails from source value. |
| `ListSelect` | Must match one of the destination list options; see **List Mapping** below. |
| `AddressData`| Structured mapping block (see next section). |

> You can map e.g. **Dropdown/Checkbox/Website** sources to **Text/RichText** if a 1:1 dest type isn’t available.

---

## ListSelect Item-Mapping

ListSelect destination fields support fuzzy value mapping—a way to translate many different source values into the correct ListSelect option in the target layout.

This works by defining, for each destination list item, an array of possible source values that should map to that item. During migration, if the source field’s value matches any entry in that list, the destination field is assigned that list item.

This allows text fields, dropdowns, richtext (with HTML-stripping), or any loosely structured source input to be normalized into consistent ListSelect values in Hudu.


In the example below, the source field "Weather Information" may contain arbitrary text like “floor”, “wind”, “sunshine” etc.

We map it to the ListSelect field WeatherType in the target layout, and specify which possible source values should correspond to each destination list item:
```powershell
@{
  to            = 'WeatherType'
  from          = 'Weather Information'
  dest_type     = 'ListSelect'
  add_listitems = 'false'
  required      = 'False'
  Mapping       = @{
    'ground stuff'  = @{ whenvalues = @("floor","ground","dirt") }
    'water stuff' = @{ whenvalues = @("cloud","precipitation") }
    'solar stuff' = @{ whenvalues = @("sunny","sunshine") }
    'sky stuff'  = @{ whenvalues = @("windy","wind","windspeed") }
  }
}
```

Example: Mapping “Weather Information” to a ListSelect field


During migration, the script examines the value of the "Weather Information" field on the source asset.

If the value is "floor", "ground", or "dirt" in source-field 'Weather Information"
→ the destination "WeatherType" will be set to "ground stuff"

If the value is "cloud" or "precipitation" in source-field 'Weather Information"
→ "WeatherType" becomes "water stuff"

If the value is "sunny" or "sunshine" in source-field 'Weather Information"
→ "WeatherType" becomes "solar stuff"

If the value is "windy", "wind", or "windspeed" in source-field 'Weather Information"
→ "WeatherType" becomes "sky stuff"

The match is case-insensitive and honors first-match-first

## Address Mapping (`AddressData`)
Use the built-in template to map structured address lines. The generator will emit a scaffold like:

```powershell
@{ to='Office Address'; from='Meta'; dest_type='AddressData'; required='False'; address=@{
    address_line_1=@{from='Street 1'}
    address_line_2=@{from='Street 2'}
    city          =@{from='City'}
    state         =@{from='State'}
    zip           =@{from='ZIP'}
    country_name  =@{from='Country'}
}}
```

The script normalizes common state/country variants and composes an Address object only when at least one sub-field is present.

---

## Per-Job Settings
These live directly in `mapping.ps1` under the **PerJob** section:

| Variable | Default | Description |
|---|---:|---|
| `$includeblanksduringsmoosh` | `$false` | Skip blank/null values when SMOOSHing; avoids empty headers. |
| `$includeLabelInSmooshedValues` | `$true` | Prepend label before each SMOOSHed value. For plain text SMOOSH, set this to `$false` for cleaner output. |
| `$excludeHTMLinSMOOSH` | `$false` | When `$true`, strips HTML, collapses whitespace, joins values into a single line (semicolon-style). |
| `$includeRelationsForArchived` | `$true` | Preserve relations even when the related asset is archived. Set to `$false` to omit. |
| `$describeRelatedInSmoosh` | `$true` | Append 1-line descriptions/links for related items into the SMOOSH text. |

### SMOOSH Examples
**RichText (default):**
```
Serial Number:
9JD2NLAL4
Notes:
This is a good computer
```

**PlainText (`excludeHTMLinSMOOSH=$true`, `includeLabelInSmooshedValues=$false`):**
```
9JD2NLAL4; This is a good computer; John https://huduurl.huducloud.com/a/johnsslug; Johns House https://huduurl.huducloud.com/a/houseslug
```

---

## List Mapping (`ListSelect`)[coming soon]

> You can still map list-style fields to `Text`/`RichText` if you don’t need enforced list integrity.

---

## Matching & Relinking
- **Existing asset matching**: before creating a destination asset, the script checks for a likely match (same company, fuzzy name). You can choose to archive/skip/continue.  
- **Relations**: the script can re-establish relations (`Asset→Asset`, `Asset→Website`, etc.) and honors `$includeRelationsForArchived`.  
- **Linkables**: for fields based on **AssetTag** with a `linkable_id`, the script can discover target layouts and reconstruct links.

---

## Outputs & Logs
- `mapping.ps1` (and `mapping.ps1.old` backups)  
- `source-fields.json`, `dest-fields.json` (reference only)  
- Console logs for each mapped field and created relation  
- Summary **counts** at the end:
  - created, matched, archived, skipped, errors, etc.

When errors occur, structured details are written via `Write-ErrorObjectsToFile` for later review.

---

**Emails not cleaning up**  
Make sure `dest_type='Email'` **or** your destination label includes "Email"; the extractor runs in both cases. This makes sure to just extract the email address(es) from the source field, leaving only the good stuff for the destination field.

**Weird address casing**  
The helpers normalize US states to two-letter codes and map common country shorthands (e.g., `US`, `USA`, `United States`).

---

## Example: Minimal Mapping

```powershell
$CONSTANTS = @(
  @{ literal = 'Vonage'; to_label = 'VOIP Service Provider' }
)

$SMOOSHLABELS = @('Serial Number','Notes')

$mapping = @(
  @{ from='Model Name'         ; to='Model'               ; dest_type='Text'    ; required='True'  ; striphtml='False' },
  @{ from='Primary IP'         ; to='IP Address'          ; dest_type='Website' ; required='False' ; striphtml='False' },
  @{ from='Warranty Expires At'; to='Warranty Expiration' ; dest_type='Date'    ; required='False' ; striphtml='False' },
  @{ from='SMOOSH'             ; to='Notes'               ; dest_type='RichText'; required='False' ; striphtml='False' }
)

$includeblanksduringsmoosh    = $false
$includeRelationsForArchived  = $true
$excludeHTMLinSMOOSH          = $false
$describeRelatedInSmoosh      = $true
$includeLabelInSmooshedValues = $true
```

---

## Conventions & Tips
- Prefer **matching dest types** when possible; otherwise map to `Text`/`RichText`.  
- Use **constants** to prefill required dest fields when there’s no source.
- For **plain text** targets, set `striphtml='True'` in the mapping and consider `excludeHTMLinSMOOSH=$true` when using SMOOSH.  

---

## Changelog
- **v0.3** – Initial public draft of SwitchingLayouts.MD, 19, Nov 2025
