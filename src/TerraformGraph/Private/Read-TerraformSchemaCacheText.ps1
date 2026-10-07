function Read-TerraformSchemaCacheText {
    # Not exported. Decompressed text of a cache file; with -MaxChars, only that many
    # characters from the start.
    param([string]$Path, [int]$MaxChars)

    $file = [System.IO.File]::OpenRead($Path)
    try {
        $gzip = [System.IO.Compression.GZipStream]::new($file, [System.IO.Compression.CompressionMode]::Decompress)
        $reader = [System.IO.StreamReader]::new($gzip, [System.Text.Encoding]::UTF8)
        try {
            if ($MaxChars -le 0) { return $reader.ReadToEnd() }
            $buffer = [char[]]::new($MaxChars)
            $read = $reader.ReadBlock($buffer, 0, $MaxChars)
            [string]::new($buffer, 0, $read)
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $file.Dispose()
    }
}
