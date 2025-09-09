# Purpose: Move assets to new layout, mapping source and destination fields

Use: invoke via dotsourcing
. .\transfer-assets.ps1

Select source Asset Layout
Select destination Asset Layout

files, named mapping.ps1 and source-fields.json will be generated
use labels in source fields to map to destination fields in mapping.ps1
It's best to match field_types to destination field_types when possivble
That said, list select, dropdown, checkbox, website, and other fields do translate nicely to text/richtext destinations

To combine source fields into a single destination field (concatenate them), you can designate which fields you would
like to 'Smoosh' into a pseudo-source field, labeled SMOOSH. SMOOSH field translates nicely into richtext or text fields.

Mapping.ps1 is generated with the target layout fields and you just need to fill in what source fields you want to place/combine into them
Here is an example filled mapping.ps1
# source 
$CONSTANTS=@(
    @{literal="Vonage";to_label="VOIP Service Provider"}
)
$SMOOSHLABELS=@(
"Manufacturer Name","Model ID","Hostname","Default Gateway","Asset Tag","Operating System Name",
"Installed By","Installed At",
"Purchased By","Purchased At","Contact Name","Operating System Notes",
"Notes","Configuration Status Name","Location Name","Contact Name"
)
$mapping=@(
@{from='Model Name';to='Model'; dest_type='Text'; required='True'},
@{from='Primary IP';to='IP Address'; dest_type='Website'; required='False'},
@{from='MAC Address';to='Mac Address'; dest_type='Text'; required='False'},
@{from='Serial Number';to='Serial Number / Service Tag'; dest_type='Text'; required='False'},
@{from='Warranty Expires At';to='Warranty Expiration'; dest_type='Date'; required='False'},
@{from='SMOOSH';to='Notes'; dest_type='RichText'; required='False'})# if fields are blank, exclude during smoosh procress?
$includeblanksduringsmoosh = $false

# relate archived objects to new asset / object
$includeRelationsForArchived = $true

# set below to true if smooshing to plaintext field, otherwise leave for richtext field
# (strip html when going to text field)
$excludeHTMLinSMOOSH = $false

# include description of related objects in smoosh
# related objects will have a 1-line description based on related object type and name
$describeRelatedInSmoosh = $true

# include label - above value in smooshed? IE - 
# label -
# value
$includeLabelInSmooshedValues = $true



There are a few variables in this mapping.ps1 file that you can set per-job. Here are their explanations:

### 
the $CONSTANTS variable provides an array of predefined psudo-source fields of your choosing.
All target assets will be pre-filled with the value, literal for field to_label for however many of these you want.
This is useful for filling required fields that dont have a source field which matches up. It's important to make sure 
values in the to_label correspond with a value in the target layout.

$CONSTANTS=@(
    ## @{literal="constval";to_label="constfield"}
)


###

$includeblanksduringsmoosh [default $false]: this excludes null/blank values if present in a source smoosh field. for instance, if you have:
Asset A: has serial number but no purchase date
Asset B: has purchase date but no serial number

and your smoosh definition is:
$SMOOSHLABELS=@("serial number","purchase date","Notes")
and you mapped SMOOSH psuedo-source field to "Notes", Notes for assest A in destination layout would be:
Serial Number:
9JD2NLAL4
Notes:
This is a good computer

Notes for asset B would be:
Purchase Date:
01/11/2023
Notes:
This is a pretty decent machine

###

$includeLabelInSmooshedValues [default: $true]: if you turn this off, you do not get smooshed labels, so asset A would be:
9JD2NLAL4
This is a good computer

If you are smooshing values together for a text field (not richtext), you will almost certainly want to set this to $false for that migration/job

###

$includeRelationsForArchived [default: $true]: if you leave this on, relations to archived assets are retained.  set this to $false to not carry over archived relationships.

###

$describeRelatedInSmoosh [default: $true]: if you leave this on, relations are described in addition to smooshed fields. 
This would mean asset A looks like:
Serial Number:
9JD2NLAL4
Notes:
This is a good computer
Related People:
John https://huduurl.huducloud.com/a/johnsslug
Related Location:
Johns House https://huduurl.huducloud.com/a/houseslug

###

excludeHTMLinSMOOSH [default: $false]:
If you are setting your SMOOSH field to a Text field (not richtext), you'll want to  strip HTML tags by setting
$excludeHTMLinSMOOSH = $true in your generated mapping.ps1 file. This also sets it as a one line value with values delimited by semicolon.
This would mean asset A looks like [in conjunction with not including labels]:
9JD2NLAL4; This is a good computer; John https://huduurl.huducloud.com/a/johnsslug; Johns House https://huduurl.huducloud.com/a/houseslug

