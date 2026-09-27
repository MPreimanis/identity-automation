@{
    Severity     = @('Error', 'Warning')

    # The scripts require PowerShell 7.2 or later, which reads UTF-8 without a byte order mark,
    # so the rule that asks for a BOM on non-ASCII files (Windows PowerShell 5.1 compatibility) is off.
    ExcludeRules = @('PSUseBOMForUnicodeEncodedFile')
}
