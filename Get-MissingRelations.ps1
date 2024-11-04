function Get-HuduIdFromItglueObject {
  param(
    $ITGObjectId,
    $AssetType
  )
  switch ($AssetType) {
    'configuration' {
      $FoundHuduAsset = $MatchedConfigurations | Where-Object {$_.ITGID -eq $ITGObjectId}
      $FoundHuduAssetType = $FoundHuduAsset.HuduObject.object_type
    }

    'document' {
      $FoundHuduAsset = $MatchedArticles | Where-Object {$_.ITGID -eq $ITGobjectId}
      $FoundHuduAssetType = 'Article'
    }

    'flexible_asset' {
      $FoundHuduAsset = $MatchedAssets | Where-Object {$_.ITGID -eq $ITGObjectId}
      $FoundHuduAssetType = $FoundHuduAsset.HuduObject.object_type
    }

    'location' {
      $FoundHuduAsset = $MatchedLocations | Where-Object {$_.ITGID -eq $ITGObjectId}
      $FoundHuduAssetType = $FoundHuduAsset.HuduObject.object_type
    }

    'password' {
      $FoundHuduAsset = $MatchedPasswords | Where-Object {$_.ITGID -eq $ITGObjectId}
      $FoundHuduAssetType = 'AssetPassword'
    }
  }
  
  if ($FoundHuduAsset) {
    return [pscustomobject]@{huduobject=$FoundHuduAsset.HuduObject; type = $FoundHuduAssetType}
  }
  else { Write-Warning "Unable to match ITGlue $AssetType to Hudu object to $($ITGobjectId)"}

}

function Get-HuduRelationObject {
  param(
    $ITGlueSourceObjects
  )

  $NewHuduRelations = foreach ($ITGlueSourceObject in $ITGlueSourceObjects) {
    switch ($ITGlueSourceObject.data.type) {
      'flexible-assets' {
        $AssetType = 'flexible_asset'
      }
      'configurations' {
        $AssetType = 'configuration'
      }
      'passwords' {
        $AssetType = 'password'
      }
    }

    $FromableHudu = Get-HuduIdFromItglueObject -AssetType $AssetType -ITGObjectId $ITGlueSourceObject.data.id
    if ($FromableHudu) {
      Write-Host "Determining Hudu objects for source $AssetType / ITGID: $($ITGlueSourceObject.data.id)" -foregroundColor Cyan
      foreach ($LinkedITGlueObject in $ITGlueSourceObject.included) {
        $LinkedHuduItem = Get-HuduIdFromItglueObject -AssetType $LinkedITGlueObject.attributes.'asset-type' -ITGObjectId $LinkedITGlueObject.attributes.'resource-id'
        if ($LinkedHuduItem){
          [pscustomobject]@{
            FromableType = $FromableHudu.type
            FromableID = $FromableHudu.HuduObject.id
            ToableType = $LinkedHuduItem.type
            ToableID = $LinkedHuduItem.HuduObject.id
          }
        }
      }
    }

  }

  return $NewHuduRelations

}


$FreshITGAssets= $MatchedAssets |% { Get-ITGlueFlexibleAssets -id $_.ITGObject.id -include related_items}
$RelatedAssets = $FreshITGAssets |? {$_.data.relationships.'related-items'.data}


$FreshConfigurations = $MatchedConfigurations | % {Get-ITGlueConfigurations -id $_.itgobject.id -include related_items}
$RelatedConfigurations = $FreshConfigurations |? {$_.data.relationships.'related-items'.data}

$FreshPasswords = $MatchedPasswords | % {Get-ITGluePasswords -id $_.itgobject.id -include related_items}
$RelatedPasswords = $FreshPasswords |? {$_.data.relationships.'related-items'.data}


$ConfigurationRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedConfigurations
$AssetRelationsToCreate = Get-HuduRelationObject -ITGlueSourceObjects $RelatedAssets
