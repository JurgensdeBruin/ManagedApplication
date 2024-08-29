$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "I accept the license agreement."
$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "I do not accept and wish to stop execution."
$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
$title = "Agreement"
$message = "By typing [Y], I hereby confirm that I have read the license ( available at https://github.com/microsoft/Azure-Analytics-and-AI-Engagement/blob/main/license.md ) and disclaimers ( available at https://github.com/microsoft/Azure-Analytics-and-AI-Engagement/blob/main/README.md ) and hereby accept the terms of the license and agree that the terms and conditions set forth therein govern my use of the code made available hereunder. (Type [Y] for Yes or [N] for No and press enter)"
$result = $host.ui.PromptForChoice($title, $message, $options, 1)
if ($result -eq 1) {
    write-host "Thank you. Please ensure you delete the resources created with template to avoid further cost implications."
}
else {
    function RefreshTokens()
    {
        #Copy external blob content
        $global:powerbitoken = ((az account get-access-token --resource https://analysis.windows.net/powerbi/api) | ConvertFrom-Json).accessToken
        $global:synapseToken = ((az account get-access-token --resource https://dev.azuresynapse.net) | ConvertFrom-Json).accessToken
        $global:graphToken = ((az account get-access-token --resource https://graph.microsoft.com) | ConvertFrom-Json).accessToken
        $global:managementToken = ((az account get-access-token --resource https://management.azure.com) | ConvertFrom-Json).accessToken
        $global:purviewToken = ((az account get-access-token --resource https://purview.azure.net) | ConvertFrom-Json).accessToken
        $global:fabric = ((az account get-access-token --resource https://api.fabric.microsoft.com) | ConvertFrom-Json).accessToken
    }

    function Check-HttpRedirect($uri) {
        $httpReq = [system.net.HttpWebRequest]::Create($uri)
        $httpReq.Accept = "text/html, application/xhtml+xml, */*"
        $httpReq.method = "GET"   
        $httpReq.AllowAutoRedirect = $false;

        #use them all...
        #[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls;

        $global:httpCode = -1;

        $response = "";            

        try {
            $res = $httpReq.GetResponse();

            $statusCode = $res.StatusCode.ToString();
            $global:httpCode = [int]$res.StatusCode;
            $cookieC = $res.Cookies;
            $resHeaders = $res.Headers;  
            $global:rescontentLength = $res.ContentLength;
            $global:location = $null;
                                
            try {
                $global:location = $res.Headers["Location"].ToString();
                return $global:location;
            }
            catch {
            }

            return $null;

        }
        catch {
            $res2 = $_.Exception.InnerException.Response;
            $global:httpCode = $_.Exception.InnerException.HResult;
            $global:httperror = $_.exception.message;

            try {
                $global:location = $res2.Headers["Location"].ToString();
                return $global:location;
            }
            catch {
            }
        } 

        return $null;
    }

    function ReplaceTokensInFile($ht, $filePath) {
        $template = Get-Content -Raw -Path $filePath
        
        foreach ($paramName in $ht.Keys) {
            $template = $template.Replace($paramName, $ht[$paramName])
        }

        return $template;
    }

    Write-Host "------------Prerequisites------------"
    Write-Host "-An Azure Account with the ability to create Fabric Workspace."
    Write-Host "-A Power BI with Fabric License to host Power BI reports."
    Write-Host "-Make sure the user deploying the script has atleast a 'Contributor' level of access on the 'Subscription' on which it is being deployed."
    Write-Host "-Make sure your Power BI administrator can provide service principal access on your Power BI tenant."
    Write-Host "-Make sure to register the following resource providers with your Azure Subscription:"
    Write-Host "-Microsoft.Fabric"
     Write-Host "-Microsoft.StorageAccount"
    Write-Host "-Make sure you use the same valid credentials to log into Azure and Power BI."

    Write-Host "    -----------------   "
    Write-Host "    -----------------   "
    Write-Host "If you fulfill the above requirements pleaseprocess otherwise press 'Ctrl+C' to end script execution."
    Write-Host "    -----------------   "
    Write-Host "    -----------------   "

    Start-Sleep -s 30

    az login --tenant 16b3c013-d300-468d-ac64-7eda0820b6d3

    #for powershell...
    Connect-AzAccount -DeviceCode

    $starttime=get-date

    $subs = Get-AzSubscription | Select-Object -ExpandProperty Name
    if($subs.GetType().IsArray -and $subs.length -gt 1)
    {
    $subOptions = [System.Collections.ArrayList]::new()
        for($subIdx=0; $subIdx -lt $subs.length; $subIdx++)
        {
            $opt = New-Object System.Management.Automation.Host.ChoiceDescription "$($subs[$subIdx])", "Selects the $($subs[$subIdx]) subscription."   
            $subOptions.Add($opt)
        }
        $selectedSubIdx = $host.ui.PromptForChoice('Enter the desired Azure Subscription for this lab','Copy and paste the name of the subscription to make your choice.', $subOptions.ToArray(),0)
        $selectedSubName = $subs[$selectedSubIdx]
        Write-Host "Selecting the subscription : $selectedSubName "
        $title    = 'Subscription selection'
        $question = 'Are you sure you want to select this subscription for this lab?'
        $choices  = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)
        if($decision -eq 0)
        {
        Select-AzSubscription -SubscriptionName $selectedSubName
        az account set --subscription $selectedSubName
        }
        else
        {
        $selectedSubIdx = $host.ui.PromptForChoice('Enter the desired Azure Subscription for this lab','Copy and paste the name of the subscription to make your choice.', $subOptions.ToArray(),0)
        $selectedSubName = $subs[$selectedSubIdx]
        Write-Host "Selecting the subscription : $selectedSubName "
        Select-AzSubscription -SubscriptionName $selectedSubName
        az account set --subscription $selectedSubName
        }
    }

    $response = az ad signed-in-user show | ConvertFrom-Json
    $date = get-date
    $demoType = "MicrosoftFabric2.0"
    $body = '{"demoType":"#demoType#","userPrincipalName":"#userPrincipalName#","displayName":"#displayName#","companyName":"#companyName#","mail":"#mail#","date":"#date#"}'
    $body = $body.Replace("#userPrincipalName#", $response.userPrincipalName)
    $body = $body.Replace("#displayName#", $response.displayName)
    $body = $body.Replace("#companyName#", $response.companyName)
    $body = $body.Replace("#mail#", $response.mail)
    $body = $body.Replace("#date#", $date)
    $body = $body.Replace("#demoType#", $demoType)

    $uri = "https://registerddibuser.azurewebsites.net/api/registeruser?code=pTrmFDqp25iVSxrJ/ykJ5l0xeTOg5nxio9MjZedaXwiEH8oh3NeqMg=="
    $result = Invoke-RestMethod  -Uri $uri -Method POST -Body $body -Headers @{} -ContentType "application/json"

    [string]$suffix =  -join ((48..57) + (97..122) | Get-Random -Count 7 | % {[char]$_})
    $rgName = "fabric-dpoc-$suffix"
    # $preferred_list = "australiaeast","centralus","southcentralus","eastus2","northeurope","southeastasia","uksouth","westeurope","westus","westus2"
    # $locations = Get-AzLocation | Where-Object {
    #     $_.Providers -contains "Microsoft.Synapse" -and
    #     $_.Providers -contains "Microsoft.Sql" -and
    #     $_.Providers -contains "Microsoft.Storage" -and
    #     $_.Providers -contains "Microsoft.Compute" -and
    #     $_.Location -in $preferred_list
    # }
    # $max_index = $locations.Count - 1
    # $rand = (0..$max_index) | Get-Random
    $Region = read-host "Enter the region for deployment"
    $OrganizationName = read-host "Enter the organization name"
    $subscriptionId = (Get-AzContext).Subscription.Id
    $tenantId = (Get-AzContext).Tenant.Id
    $storage_account_name = "storage$suffix"
    
    #create variables with OrganizationName in it
    $wsId =  Read-Host "Enter your 'contosoSales' PowerBI workspace Id "
    
    RefreshTokens
    $url = "https://api.powerbi.com/v1.0/myorg/groups/$wsId";
    $WsName = Invoke-RestMethod -Uri $url -Method GET -Headers @{ Authorization="Bearer $powerbitoken" };
    $WsName = $WsName.name
   
    $lakehouseBronze =  "lakehouseBronze_$suffix"
    $lakehouseSilver =  "lakehouseSilver_$suffix"
    $lakehouseGold =  "lakehouseGold_$suffix"
 
    Add-Content log.txt "------FABRIC assets deployment STARTS HERE------"
    Write-Host "------------FABRIC assets deployment STARTS HERE------------"

    Add-Content log.txt "------Creating Lakehouses in '$WsName' workspace------"
    Write-Host "------Creating Lakehouses in '$WsName' workspace------"
    $lakehouseNames = @($lakehouseBronze, $lakehouseSilver, $lakehouseGold)
    # Set the token and request headers
    $pat_token = $fabric
    $requestHeaders = @{
        Authorization  = "Bearer" + " " + $pat_token
        "Content-Type" = "application/json"
    }

    # Iterate through each Lakehouse name and create it
    foreach ($lakehouseName in $lakehouseNames) {
    # Create the body for the Lakehouse creation
    $body = @{
        displayName = $lakehouseName
        type        = "Lakehouse"
    } | ConvertTo-Json

    # Set the API endpoint
    $endPoint = "https://api.fabric.microsoft.com/v1/workspaces/$wsId/items/"

    # Invoke the REST method to create a new Lakehouse
    try {
        $Lakehouse = Invoke-RestMethod $endPoint `
            -Method POST `
            -Headers $requestHeaders `
            -Body $body

        Write-Host "Lakehouse '$lakehouseName' created successfully."
    } catch {
        Write-Host "Error creating Lakehouse '$lakehouseName': $_"
        if ($_.Exception.Response -ne $null) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.ReadToEnd()
        }
    }
    }
    Add-Content log.txt "------Creation of Lakehouses in '$WsName' workspace COMPLETED------"
    Write-Host "-----Creation of Lakehouses in '$WsName' workspace COMPLETED------"

    Add-Content log.txt "------Uploading assets to Lakehouses------"
    Write-Host "------------Uploading assets to Lakehouses------------"
    $tenantId = (Get-AzContext).Tenant.Id
    azcopy login --tenant-id $tenantId

    #azcopy copy "https://fabric2dpoc.blob.core.windows.net/bronzelakehousefiles/*" "https://onelake.blob.fabric.microsoft.com/$contosoSalesWsName/$lakehouseBronze.Lakehouse/Files/" --overwrite=prompt --from-to=BlobBlob --s2s-preserve-access-tier=false --check-length=true --include-directory-stub=false --s2s-preserve-blob-tags=false --recursive --trusted-microsoft-suffixes=onelake.blob.fabric.microsoft.com --log-level=INFO;
    #azcopy copy "https://fabric2dpoc.blob.core.windows.net/bronzelakehousetables/*" "https://onelake.blob.fabric.microsoft.com/$contosoSalesWsName/$lakehouseBronze.Lakehouse/Tables/" --overwrite=prompt --from-to=BlobBlob --s2s-preserve-access-tier=false --check-length=true --include-directory-stub=false --s2s-preserve-blob-tags=false --recursive --trusted-microsoft-suffixes=onelake.blob.fabric.microsoft.com --log-level=INFO;
    #azcopy copy "https://fabric2dpoc.blob.core.windows.net/silverlakehousetables/*" "https://onelake.blob.fabric.microsoft.com/$contosoSalesWsName/$lakehouseSilver.Lakehouse/Tables/" --overwrite=prompt --from-to=BlobBlob --s2s-preserve-access-tier=false --check-length=true --include-directory-stub=false --s2s-preserve-blob-tags=false --recursive --trusted-microsoft-suffixes=onelake.blob.fabric.microsoft.com --log-level=INFO;
    #azcopy copy "https://fabric2dpoc.blob.core.windows.net/silverlakehousefiles/*" "https://onelake.blob.fabric.microsoft.com/$contosoSalesWsName/$lakehouseSilver.Lakehouse/Files/" --overwrite=prompt --from-to=BlobBlob --s2s-preserve-access-tier=false --check-length=true --include-directory-stub=false --s2s-preserve-blob-tags=false --recursive --trusted-microsoft-suffixes=onelake.blob.fabric.microsoft.com --log-level=INFO;

    #azcopy copy "https://fabricddib.blob.core.windows.net/goldlakehousetables/*" "https://onelake.blob.fabric.microsoft.com/$contosoSalesWsName/$lakehouseGold.Lakehouse/Tables/" --overwrite=prompt --from-to=BlobBlob --s2s-preserve-access-tier=false --check-length=true --include-directory-stub=false --s2s-preserve-blob-tags=false --recursive --trusted-microsoft-suffixes=onelake.blob.fabric.microsoft.com --log-level=INFO;

    Add-Content log.txt "------Uploading assets to Lakehouses COMPLETED------"
    Write-Host "------------Uploading assets to Lakehouses COMPLETED------------"


    ## notebooks
    Add-Content log.txt "-----Configuring Fabric Notebooks w.r.t. current workspace and lakehouses-----"
    Write-Host "----Configuring Fabric Notebooks w.r.t. current workspace and lakehouses----"

    (Get-Content -path "artifacts/fabricnotebooks/01 Date to Lakehouse (Bronze) - Code-First Experience.ipynb" -Raw) | Foreach-Object { $_ `
        -replace '#WORKSPACE_NAME#', $WsName `
        -replace '#LAKEHOUSE_BRONZE#', $lakehouseBronze `
    } | Set-Content -Path "artifacts/fabricnotebooks/01 Data to Lakehouse (Bronze) - Code-First Experience.ipynb"

    (Get-Content -path "artifacts/fabricnotebooks/02 Bronze to Silver layer_ Medallion Architecture.ipynb" -Raw) | Foreach-Object { $_ `
        -replace '#WORKSPACE_NAME#', $WsName `
        -replace '#LAKEHOUSE_BRONZE#', $lakehouseBronze `
        -replace '#LAKEHOUSE_SILVER#', $lakehouseSilver `
    } | Set-Content -Path "artifacts/fabricnotebooks/02 Bronze to Silver layer_ Medallion Architecture.ipynb"

    (Get-Content -path "artifacts/fabricnotebooks/03 Silver to Gold layer_ Medallion Architecture.ipynb" -Raw) | Foreach-Object { $_ `
        -replace '#LAKEHOUSE_GOLD#', $lakehouseGold `
        -replace '_LAKEHOUSE_GOLD_', $lakehouseGold `
    } | Set-Content -Path "artifacts/fabricnotebooks/03 Silver to Gold layer_ Medallion Architecture.ipynb"

    Add-Content log.txt "-----Fabric Notebook Configuration COMPLETED-----"
    Write-Host "----Fabric Notebook Configuration COMPLETED----"

    Add-Content log.txt "-----Uploading Notebooks-----"
    Write-Host "-----Uploading Notebooks-----"
    RefreshTokens
    $requestHeaders = @{
        Authorization  = "Bearer " + $fabric
        "Content-Type" = "application/json"
        "Scope"        = "Notebook.ReadWrite.All"
    }

    $files = Get-ChildItem -Path "./artifacts/fabricnotebooks" -File -Recurse
    Set-Location ./artifacts/fabricnotebooks

    foreach ($name in $files.name) {
    if ($name -eq "01 Data to Lakehouse (Bronze) - Code-First Experience.ipynb" -or
        $name -eq "02 Bronze to Silver layer_ Medallion Architecture.ipynb" -or
        $name -eq "03 Silver to Gold layer_ Medallion Architecture.ipynb") {
        
        $fileContent = Get-Content -Raw $name
        $fileContentBytes = [System.Text.Encoding]::UTF8.GetBytes($fileContent)
        $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

        $body = '{
            "displayName": "' + $name + '",
            "type": "Notebook",
            "definition": {
                "format": "ipynb",
                "parts": [
                    {
                        "path": "artifact.content.ipynb",
                        "payload": "' + $fileContentEncoded + '",
                        "payloadType": "InlineBase64"
                    }
                ]
            }
        }'

        $endPoint = "https://api.fabric.microsoft.com/v1/workspaces/$wsId/items/"
        $Lakehouse = Invoke-RestMethod $endPoint -Method POST -Headers $requestHeaders -Body $body

        Write-Host "Notebook uploaded: $name"
    } elseif ($name -eq "04 ML Silver To Gold Layer.ipynb" -or
            $name -eq "05 Forecasting for item in Gold Layer.ipynb") {
        
        $fileContent = Get-Content -Raw $name
        $fileContentBytes = [System.Text.Encoding]::UTF8.GetBytes($fileContent)
        $fileContentEncoded = [System.Convert]::ToBase64String($fileContentBytes)

        $body = '{
            "displayName": "' + $name + '",
            "type": "Notebook",
            "definition": {
                "format": "ipynb",
                "parts": [
                    {
                        "path": "artifact.content.ipynb",
                        "payload": "' + $fileContentEncoded + '",
                        "payloadType": "InlineBase64"
                    }
                ]
            }
        }'

        $endPoint = "https://api.fabric.microsoft.com/v1/workspaces/$wsId/items/"
        $Lakehouse = Invoke-RestMethod $endPoint -Method POST -Headers $requestHeaders -Body $body

        Write-Host "Notebook uploaded: $name"
        }
    }
    Add-Content log.txt "-----Uploading Notebooks COMPLETED-----"
    Write-Host "-----Uploading Notebooks COMPLETED-----"

    cd..
    cd..

    RefreshTokens

    Start-Sleep -s 10

    Add-Content log.txt "------FABRIC assets deployment DONE------"
    Write-Host "------------FABRIC assets deployment DONE------------"

    Add-Content log.txt "------AZURE assets deployment STARTS HERE------"
    Write-Host "------------AZURE assets deployment STARTS HERE------------"

    Write-Host "Creating $rgName resource group in $Region ..."
    New-AzResourceGroup -Name $rgName -Location $Region | Out-Null
    Write-Host "Resource group $rgName creation COMPLETE"

    Write-Host "Creating resources in $rgName..."
    New-AzResourceGroupDeployment -ResourceGroupName $rgName `
    -TemplateFile "mainTemplate.json" `
    -Mode Complete `
    -location $Region `
    -storage_account_name $storage_account_name `
    -Force

    Write-Host "Resource creation in $rgName resource group COMPLETE"

    #Adding tags
    $tags = @{
        "wsId" = $wsId
    }
    Set-AzResourceGroup -ResourceGroupName $rgName -Tag $tags

    Add-Content log.txt "------Fetching az copy library------"
    Write-Host "------------Fetching az copy library------------"

    #download azcopy command
    if ([System.Environment]::OSVersion.Platform -eq "Unix") {
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-linux"

        if (!$azCopyLink) {
            $azCopyLink = "https://azcopyvnext.azureedge.net/release20200709/azcopy_linux_amd64_10.5.0.tar.gz"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.tar.gz"
        tar -xf "azCopy.tar.gz"
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy).Directory.FullName

        if ($azCopyCommand.count -gt 1) {
            $azCopyCommand = $azCopyCommand[0];
        }

        cd $azCopyCommand
        chmod +x azcopy
        cd ..
        $azCopyCommand += "\azcopy"
    } else {
        $azCopyLink = Check-HttpRedirect "https://aka.ms/downloadazcopy-v10-windows"

        if (!$azCopyLink) {
            $azCopyLink = "https://azcopyvnext.azureedge.net/release20200501/azcopy_windows_amd64_10.4.3.zip"
        }

        Invoke-WebRequest $azCopyLink -OutFile "azCopy.zip"
        Expand-Archive "azCopy.zip" -DestinationPath ".\" -Force
        $azCopyCommand = (Get-ChildItem -Path ".\" -Recurse azcopy.exe).Directory.FullName

        if ($azCopyCommand.count -gt 1) {
            $azCopyCommand = $azCopyCommand[0];
        }

        $azCopyCommand += "\azcopy"
    }


    Add-Content log.txt "------Fetching az copy library COMPLETED------"
    Write-Host "------------Fetching az copy library COMPLETED------------"

    Add-Content log.txt "------Copying assets to the Storage Account------"
    Write-Host "------------Copying assets to the Storage Account------------"

    ## storage AZ Copy
    $storage_account_key = (Get-AzStorageAccountKey -ResourceGroupName $rgName -AccountName $storage_account_name)[0].Value
    $dataLakeContext = New-AzStorageContext -StorageAccountName $storage_account_name -StorageAccountKey $storage_account_key

    ## Copying data to the storage account
    ## Example: azcopy copy "https://fabric2dpoc.blob.core.windows.net/bronzeshortcutdata/*" "https://storageaccountname.blob.core.windows.net/bronzeshortcutdata/" --recursive
    # $destinationSasKey = New-AzStorageContainerSASToken -Container "bronzeshortcutdata" -Context $dataLakeContext -Permission rwdl
    # if (-not $destinationSasKey.StartsWith('?')) { $destinationSasKey = "?$destinationSasKey"}
    # $destinationUri = "https://$($storage_account_name).blob.core.windows.net/bronzeshortcutdata$($destinationSasKey)"
    # & $azCopyCommand copy "https://fabric2dpoc.blob.core.windows.net/bronzeshortcutdata/" $destinationUri --recursive

    Add-Content log.txt "------Copying assets to the Storage Account COMPLETED------"
    Write-Host "------------Copying assets to the Storage Account COMPLETED------------"

    Add-Content log.txt "------AZURE assets deployment DONE------"
    Write-Host "------------AZURE assets deployment DONE------------"

    $endtime=get-date
    $executiontime=$endtime-$starttime
    Write-Host "Execution Time"$executiontime.TotalMinutes
    Add-Content log.txt "-----------------Execution Complete---------------"

    Write-Host "List of resources deployed in $rgName resource group"
    $deployed_resources = Get-AzResource -resourcegroup $rgName
    $deployed_resources = $deployed_resources | Select-Object Name, Type | Format-Table -AutoSize
    Write-Output $deployed_resources

    Write-Host "List of resources deployed in $WsName workspace"
    $endPoint = "https://api.fabric.microsoft.com/v1/workspaces/$wsId/items"
    $fabric_items = Invoke-RestMethod $endPoint `
            -Method GET `
        -Headers $requestHeaders 

    $table = $fabric_items.value | Select-Object DisplayName, Type | Format-Table -AutoSize

    Write-Output $table

    Write-Host  "-----------------Execution Complete----------------"
}