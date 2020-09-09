#
# Sample file. expects FSSAPI directory in same folder as this script
#
# Supply your own url:
#
#   ./fssapi-test.ps1 -fssUrl "https://my-hcpaw-server.example.com"
#
# Run it twice to see before and after file creation
# 

param(
    $fssUrl = "https://hcpaw-fss.example.com",
    $userFile
)

Import-Module "./FSSAPI"

if($userFile){
    # you can supply a file that was saved with
    # Get-Credential | Export-CliXml "creds/user.xml"
    $creds = Import-Clixml $userFile
} else {
    $creds = Get-Credential
}

$fss = New-FSSAPI $fssUrl $creds
if($fss.message){
    Write-Warning $fss.message.error
} else {
    $files = $fss.ListFolderContents("fss-test")
    $files | ConvertTo-Json

    foreach($file in $files.entries){
        $fileSpec = "$($file.parent)/$($file.name)"
        $content = $fss.DownloadFile($fileSpec)
        "$($file.name) : $content"
    }

    $file = $fss.GetEntry("/fss-test/new-file.txt")
    if($file){
        $fileSpec = "$($file.parent)/$($file.name)"
        $fss.DeleteEntry($fileSpec, $file.etag, $true)
        if($fss.message){
            $fss.message.error_description
        } else {
            "deleted $fileSpec"
        }
    } else {
        $fss.message.error_description
    }

    $file = $fss.UploadFile("/fss-test/new-file.txt","new file content")
    if(-not $file){
        $fss.message.error_description
    } else {
        "uploaded new-file.txt"
    }

    $entries = $fss.Search("/fss-test", ".txt", 100)
    $entries | ConvertTo-Json
}