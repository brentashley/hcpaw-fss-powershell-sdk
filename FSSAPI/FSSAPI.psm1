#
# HCP Anywhere FSS PowerShell SDK
#
# This SDK provides simple functionality for small to medium files
# File content is held in string variables, there is no streaming
# For larger files you can use the FSS portal or Curl against the API directly
#

Class FSSAPI {
    [String] $url
    [PSCredential] $creds
    [String] $token
    [DateTime] $expires
    # if there was an exception, this will contain the errorRecord from the last API call
    # if it is null, the last call was successful
    $message
    [string] hidden $APIVersion = "4.3.0"

    FSSAPI(
        [String] $_url,
        [PSCredential] $_credential
    ){
        $this.url = $_url
        $this.creds = $_credential
        $this.StartSession()
    }

    # Session Initialization
    [void] StartSession() {
        # extract raw pass from creds via BSTR
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.creds.Password)
        $encodedCreds = [System.Convert]::ToBase64String(
            [System.Text.Encoding]::ASCII.GetBytes(
                "$($this.creds.UserName):$([System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR))"
            )
        )
        $headers = @{
            Authorization = "Basic $encodedCreds"
            Accept = "application/json"
            "Content-type" = "application/x-www-form-urlencoded"
            "X-HCPAW-FSS-API-VERSION" = $this.APIVersion
        }
        $body = @{"grant_type"="urn:hds:oauth:negotiate-client"}
        $this.message = $null
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Method POST -uri "$($this.url)/fss/public/login/oauth" -Headers $headers -body $body
            $result = $response.content | ConvertFrom-Json
            $this.token = $result.access_token
            $this.expires = (Get-Date).addSeconds($result.expires_in)
        } catch { 
            # stringify to avoid null errors
            $this.message = ("$($_.ErrorDetails.Message)" | ConvertFrom-Json)
        }
    }

    #
    # CallAPI - generic API calls
    # Multiple signatures to enable optional params
    #
    # two args - use default accept/contentType
    [Object] CallAPI(
        [string]$path, 
        $params
    ) {
        return $this.CallAPI($path, $params, "application/json","application/json")
    }
    # 3 args - specify accept, use default contentType
    [Object] CallAPI(
        [string]$path, 
        $params,
        [string]$accept
    ) {
        return $this.CallAPI($path, $params, $accept,"application/json")
    }
    # 4 args - specify all args
    [Object] CallAPI(
        [string]$path, 
        $params, 
        [string]$accept,
        [string]$contentType
    ) {
       if((Get-Date) -gt $this.expires){
            $this.StartSession()
        }
        $headers = @{
            Authorization = "Bearer $($this.token)"
            Accept = $accept
            "Content-type" = $contentType
            "X-HCPAW-FSS-API-VERSION" = $this.APIVersion
        }
        # params argument: 
        #   for most calls is a hashtable ie @{path='/this/that.txt'}
        #     it is converted to a json string and becomes the body
        #   for file creation/update it is a string
        #     it is the content of the file
        #       it becomes the body of the call 
        if($params.getType().Name -eq 'Hashtable'){
            $body = $params | convertto-json
        } else {
            $body = $params
        }
        $response = $null
        $this.message = $null
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Method POST -uri "$($this.url)$($path)" -Headers $headers -body $body
        } catch { 
            $this.message = ($_.ErrorDetails.Message | ConvertFrom-Json)
            $response = $null
        }
        return $response
    }

    #
    # ListFolderContents
    # Multiple signatures for optional params
    # to enable paging of results
    # returns object with 
    #    entries collection
    #        folders and files
    #    pageToken to get next page

    # one arg - default pagesize of 100, no pageToken
    [PSCustomObject] ListFolderContents([string]$folderPath){
        return $this.ListFolderContents($folderPath,100,"")
    }
    # two args - supply pageSize, no PageToken
    [PSCustomObject] ListFolderContents([string]$folderPath, [int]$pageSize){
        return $this.ListFolderContents($folderPath,$pageSize,"")
    }    
    # 3 args - supply pageSize and pageToken
    [PSCustomObject] ListFolderContents([string]$folderPath, [int]$pageSize, [string]$pageToken){
        $params = @{
            "path" = $folderPath
            "pageSize" = $pageSize
            "pageToken" = $pageToken
        }
        $response = $this.CallAPI("/fss/public/folder/entries/list", $params)
        if($response){
            return ($response.content | ConvertFrom-Json)
        }
        return $null
    }

    #
    # Other simplified API calls
    #

    # returns collection of folders
    [Array] ListSubdirectories([string]$folderPath){
        $response = $this.CallAPI("/fss/public/folder/listSubdirectories", @{"path"=$folderPath})
        if($response){
            return ($response.content | ConvertFrom-Json).entries
        }
        return $null
    } 

    # returns object with file/folder metadata
    [PSCustomObject] GetEntry([string]$path){
        $response = $this.CallAPI("/fss/public/path/info/get", @{"path"=$path})
        if($response){
            return ($response.content | ConvertFrom-Json)
        }
        return $null
    }

    # downloads file, returns string containing file content
    [String] DownloadFile([string]$fileSpec){
        $response = $this.CallAPI("/fss/public/file/stream/read", @{"path"=$fileSpec}, "application/octet-stream")
        if($response){
            return $response.content
        }
        return $null
    }

    # uploads file, returns file info object
    [PSCustomObject] UploadFile([string]$fileSpec,[string]$fileContent){
        $callUrl = "/fss/public/file/stream/create?path=$($fileSpec)&createParents=true"
        $response = $this.CallAPI($callUrl,$fileContent,"application/json","application/octet-stream")
        if($response){
            return ($response.content | ConvertFrom-Json)
        }
        return $null
    }

    # deletes file or folder
    # 2 args - default recursive to false
    [PSCustomObject] DeleteEntry([string]$path,[string]$eTag){
        return $this.DeleteEntry($path,$eTag,$false)
    }
    # 3 args - specify recursive
    [PSCustomObject] DeleteEntry([string]$path,[string]$eTag,[bool]$recursive){
        $callUrl = "/fss/public/path/delete"
        $params = @{
            "path" = $path
            "etag" = $eTag
            "recursive" = $recursive
        }
        $response = $this.CallAPI($callUrl,$params)
        if($response){
            return ($response.content | ConvertFrom-Json)
        }
        return $null
    }
    
    # creates folder, returns folder info object
    [PSCustomObject] CreateFolder([string]$folderPath){
        $params = @{
            "path" = $folderPath
            "createParents" = $true
        }
        $response = $this.CallAPI("/fss/public/folder/create", $params)
        if($response){
            return ($response.content | ConvertFrom-Json)
        }
        return $null
    }

    [Array] Search([string]$path, [string]$substring, [int]$maxResults){
        $params = @{
            "path" = $path
            "substring" = $substring
            "maxResults" = $maxResults
        }
        $response = $this.CallAPI("/fss/public/path/search", $params)
        if($response){
            return ($response.content | ConvertFrom-Json).entries
        }
        return $null
    }

    # computes SHA384 hash of input str
    # useful for comparison of file entries without retrieving files
    [String] ComputeHash($str){
        $inbytes = ([System.Text.Encoding]::UTF8).GetBytes($str)
        $sha = New-Object System.Security.Cryptography.SHA384CryptoServiceProvider 
        $outbytes = $sha.ComputeHash($inbytes)
        $hex = ($outbytes | ForEach-Object ToString X2) -join ''
        return $hex.toLower()
    }

}

<#
.SYNOPSIS
    This separate instantiator function is necessary because Include-Module does not expose classes
.DESCRIPTION
    Creates an FSSAPI object to interact with HCP AnyWhere's File Sync and Share API
    See official API docs for more info and object schemas:
        https://knowledge.hitachivantara.com/Documents/Storage/Content_Platform_Anywhere/Server/4.3.x/For_developers/File_Sync_and_Share_API_Reference
.PARAMETER url
    The FSS API endpoint url e.g. "https://hcpaw-fss.example.com"
.PARAMETER creds
    A PSCredential object containing username and encrypted password
.EXAMPLE
    # get credentials from user
    # create FSSAPI object 
    # get root folder content listing
    # display result
    # error checking

    Import-Module "./FSSAPI"
    $creds = Get-Credential
    $fss = New-FSSAPI "https://hcpaw.example.com" $creds
    if($fss.message){
        Write-Warning $fss.message.error_description
    } else {
        $files = $fss.ListFolderContents("/")
        if($files){
            foreach($file in $files){
                $file.name
            }
        } else {
            Write-Warning $fss.message.error_description
        }
    }
.NOTES
    The FSSAPI object exposes the following properties and methods:

    Property: message (hashtable or $null)
        If a method call results in an error, the message property is populated with 
            { error: "error_name", "error_description: "description of error" }
        If the method is successful, message is $null

    Method: CallAPI($path,$params [,$accept [,$contentType]])
        Generic API call - used internally but available if you need it
            path: path of API call e.g. /fss/public/folder/list
            params: 
                for most calls is a hashtable of params
                for upload is string containing file content
            accept: optional value of accept header
            contentType: optional value of content-type header

    Method: ListFolderContents($folderPath[ [,$pageSize [,$pageToken]])
        Returns collection of items in a folder (files and folders)
            folderPath: the folder to list
            pageSize: number of entries to retrieve (default 100)
            pageToken: pageToken from previous call to continue paging

    Method: ListSubdirectories($folderPath)
        Returns collection of subdirectories in a folder (only folders)
            folderPath: the folder to get the subdirectories from

    Method: GetEntry($path)
        Returns metadata for a single entry (file or folder)

    Method: DownloadFile($fileSpec)
        Returns string containing content of file

    Method: UploadFile($fileSpec,$fileContent)
        Uploads file content into destination file

    Method: DeleteEntry($path,$eTag[,$recursive])
        Deletes file or folder
            path: file or folder path
            eTag: identifier from file metadata to ensure exact item deleted
            recursive: optional, default $false

    Method: CreateFolder($folderSpec)
        Creates folder

    Method: Search($path,$substring,$maxResults)
        Returns list of entries (files and folders)
            path: path to start search (always recursive)
            substring: substring to match (exact substring match, no wildcards)
            maxResults: limit number of results

    Method: ComputeHash($str)
        returns hex string representation of the SHA394 hash of str

#>
Function New-FSSAPI {
    Param(
        [Parameter (Mandatory=$true)][string] $url,
        [Parameter (Mandatory=$true)][PSCredential] $creds
    )
    return [FSSAPI]::new($url, $creds)
}
