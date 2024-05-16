#!powershell
#Requires -Module Ansible.ModuleUtils.Legacy
#AnsibleRequires -CSharpUtil Ansible.Basic

# s.fauquembergue(sii)
# v1.0
# 24/04/2024
# initial release

function Get-Resources ($parameters){
    $resources = $null
    $collect = Get-NetFirewallRule | ? name -eq $parameters.name 
    
    
    if ($collect){
        $filters = $collect | Get-NetFirewallPortFilter
        
        $resources = [ordered]@{
            "name" = $collect.Name;
            "displayName" = $collect.DisplayName;
            "localport" = $filters.LocalPort;
            "remoteport" = $filters.RemotePort;
            "action" = $collect.Action.tostring();
            "direction" = $(switch ($collect.Direction.tostring()){"Inbound"{"In"}"Outbound"{"Out"}});
            "protocol" = $filters.Protocol;
            "profiles" = $(if ($collect.Profile.tostring() -eq "Any"){"Domain, Private, Public"}else{$collect.Profile.tostring()});
            "state" = "present"
            "enabled" = $collect.Enabled.tostring();
        }
    }

    return $resources
}

function Create-Resources ($parameters){
    New-NetFirewallRule `
        -Name $parameters.name `
        -DisplayName $parameters.displayName `
        -localport $(if($parameters.localport){$parameters.localport}else{"Any"}) `
        -remoteport $(if($parameters.remoteport){$parameters.remoteport}else{"Any"}) `
        -action $(if($parameters.action){$parameters.action}else{"Allow"}) `
        -direction $(if($parameters.direction){$parameters.direction}else{"In"}) `
        -protocol $(if($parameters.protocol){$parameters.protocol}else{"TCP"}) `
        -profile $(if($parameters.profiles){$parameters.profiles}else{"Public"}) `
        -enabled $(if($parameters.enabled){$parameters.enabled}else{"False"})

    return "firewall rule $($parameters.name) created"
}

function Test-Resources ($resource, $parameters){
    $compliant = $true

    $parameters.keys | %{
        if ($parameters.$_){
            if ($resource.$_ -ne $parameters.$_){
                $compliant = $false
            }
        }
    }

    return $compliant
}

function Set-Resources ($resource, $parameters){
    if ($parameters.state -eq "absent"){
        Remove-NetFirewallRule -name $parameters.Name 
        return "$($parameters.Name ) removed"
    }  
    else{
        $result = @()

        $parameters.keys | %{
            if ($parameters.$_){
                if ($resource.$_ -ne $parameters.$_){
                    iex "Set-NetFirewallRule -name '$($parameters.Name)' -$($_) '$($parameters.$_)'"
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
        name = @{ type = "str" ; required = $True }
        displayName = @{ type = "str" ; required = $True}
        localport = @{ type = "str" ; required = $False}
        remoteport = @{ type = "str"; required = $False}
        action = @{ type = "str" ; required = $False }
        direction = @{ type = "str" ; required = $False }
        protocol = @{ type = "str" ; required = $False }
        profiles = @{ type = "str" ; required = $False}
        state = @{ type = "str" ; required = $True }
        enabled = @{ type = "str" ; required = $False }
    }
    supports_check_mode = $true
}


Set-StrictMode -Version 2
$ErrorActionPreference = "Stop"
$module = [Ansible.Basic.AnsibleModule]::Create($args, $spec)
#endregion

 
#region main
try{
    $resource = Get-Resources -parameters $module.params 
    $module.Result.message = $resource

    if ($resource){
        $compliance = Test-Resources -resource $resource -parameters $module.params
        $module.Result.message = $resource #
        
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
