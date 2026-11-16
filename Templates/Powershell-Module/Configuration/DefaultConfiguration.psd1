# Settings that ship with the module. Import-TemplateSetting reads this file with
# Import-PowerShellDataFile, which returns the hashtable and does not run code, so every value is a
# literal. Secrets do not belong here: read them at run time from a secret store.
@{
    Environments = @{
        Development = @{
            LogLevel = 'Verbose'
            TimeoutSeconds = 30
            RetryCount = 3
        }

        Testing = @{
            LogLevel = 'Information'
            TimeoutSeconds = 20
            RetryCount = 2
        }

        Production = @{
            LogLevel = 'Warning'
            TimeoutSeconds = 10
            RetryCount = 1
        }
    }
}
