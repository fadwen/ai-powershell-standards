# Root module. Files load in the order Classes, Private, Public, so that a type exists before a
# function that names it is defined. The manifest's FunctionsToExport decides what is exported.

Set-StrictMode -Version Latest

foreach ($folder in 'Classes', 'Private', 'Public') {
    $folderPath = Join-Path -Path $PSScriptRoot -ChildPath $folder
    if (-not (Test-Path -LiteralPath $folderPath)) {
        continue
    }

    foreach ($file in Get-ChildItem -LiteralPath $folderPath -Filter '*.ps1' -File) {
        try {
            . $file.FullName
        } catch {
            # A file that fails to load must fail the import. Without this, the loop would carry
            # on and the module would import with commands missing.
            throw
        }
    }
}
