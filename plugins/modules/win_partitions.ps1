#!powershell
#Requires -Module Ansible.ModuleUtils.Legacy
#AnsibleRequires -CSharpUtil Ansible.Basic

# s.fauquembergue(sii)
# v1.0
# 02/05/2024
# initial release

function Get-Resources ($diskNumber, $partNumber){
    $partition = $null
    $partition_get = Get-Disk | ? number -eq $diskNumber | Get-Partition | ? PartitionNumber -eq $partNumber
    
    if ($partition_get){
        $partition = [ordered]@{
            "disk_number" = $diskNumber
            "partition_number" = $partNumber
            "DriveLetter" = $partition_get.DriveLetter
            "FileSystem" = ($partition_get | get-volume).FileSystem 
            "FileSystemLabel" = ($partition_get | get-volume).FileSystemLabel
            "Size" = $($partition_get.Size)
            "state" = "present" 
        }
    }

    return $partition
}

function Create-Resources ($parameters){
    $expr = "New-Partition -DiskNumber $($parameters.disk_number) -DriveLetter $($parameters.DriveLetter) "
    if ($parameters.Size){$expr += '-Size ' + $(iex $([regex]::new("\s").replace($parameters.Size, "*1")))  + ' '}else{$expr += '-UseMaximumSize '}
    iex $expr

    $expr = "Format-Volume -DriveLetter $($parameters.DriveLetter) -FileSystem $($parameters.FileSystem)  "
    if ($parameters.FileSystemLabel){$expr += '-NewFileSystemLabel "' + $parameters.FileSystemLabel + '" '}    
    iex $expr

    return "new partition $($parameters.FileSystem) created on disk $($parameters.disk_number)"
}

function Test-Resources ($resource, $parameters){
    $compliant = $true

    $parameters.keys | %{
        if ($parameters.$_){
            if ($_ -eq "Size"){
                $level = [regex]::new('\w*$').match($parameters.$_).value 
                $nbAfter = [regex]::new('\.[0-9]*').match($parameters.$_).value.length -1 
                if($nbAfter -lt 0){$nbAfter = 0}
                $sizeSrcConvert =  [string](iex "[math]::round($($resource.Size)/1$level, $nbAfter)") + " $level" 
                
                if ($sizeSrcConvert-ne $parameters.$_){
                    $compliant = $false
                }
            }
            elseif ($resource.$_ -ne $parameters.$_){
                $compliant = $false
            }
        }
    }

    return $compliant
}

function Set-Resources ($resource, $parameters){
    if ($parameters.state -eq "absent"){
        Remove-Partition -DriveLetter $resource.DriveLetter -confirm:$False
        return "$($parameters.DriveLetter) removed"
    }  
    else{
        $result = @()

        $parameters.keys | %{
            if ($parameters.$_ -and $parameters.$_){
                if ($resource.$_ -ne $parameters.$_){
                    if($_ -eq "FileSystem"){
                        Format-Volume -DriveLetter $resource.DriveLetter -FileSystem $parameters.FileSystem -confirm:$False
                        Set-Volume -DriveLetter $resource.DriveLetter -NewFileSystemLabel $parameters.FileSystemLabel
                    }
                    elseif($_ -eq "FileSystemLabel"){
                        Set-Volume -DriveLetter $resource.DriveLetter -NewFileSystemLabel $parameters.FileSystemLabel
                    }
                    elseif($_ -eq "Size" -and $resource.$_ -ne $(iex $([regex]::new('\s').replace($parameters.size,'*1')))){
                        iex "Get-disk $($parameters.disk_number)| Resize-Partition -PartitionNumber $($parameters.partition_number) -Size $(iex $([regex]::new('\s').replace($parameters.size,'*1')))"
                    }
                    elseif($_ -eq "DriveLetter"){
                        Get-Partition -DriveLetter $resource.DriveLetter | Set-Partition -NewDriveLetter $parameters.DriveLetter
                    }
                                        
                    $result += "$($_) : $($resource.$_) > $($parameters.$_)"
                }
            }
        }

        return $result
    }
}

#region ansible
$spec = @{
    options = @{
        disk_number = @{ type = "int" ; required = $True }
        partition_number = @{ type = "int" ; required = $True }
        DriveLetter = @{ type = "str" ; required = $True }
        FileSystem = @{ type = "str" ; required = $True }
        FileSystemLabel = @{ type = "str" ; required = $False }
        Size = @{ type = "str" ; required = $True }
        state = @{ type = "str" ; required = $True }
    }
    supports_check_mode = $true
}

Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
#endregion


#region main
try{
    $resource = Get-Resources -diskNumber $module.params.disk_number -partNumber $module.params.partition_number 
    $module.Result.message = $resource

    if ($resource){
        $compliance = Test-Resources -resource $resource -parameters $module.params
                
        if (!$compliance){
            $result = Set-Resources -resource $resource -parameters $module.params
            $module.Result.message = $result 
            $module.Result.changed = $true
        }
    }

    if (!$resource -and $module.params.state -eq "present"){
        $result = Create-Resources -parameters $module.params
        $module.Result.message = $result 
        $module.Result.changed = $true
    }
}

catch{
    $module.FailJson($_.exception.message)

}
finally{
    $module.ExitJson()
}

#endregion
