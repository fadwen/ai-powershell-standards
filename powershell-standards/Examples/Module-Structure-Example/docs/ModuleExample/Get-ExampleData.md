---
document type: cmdlet
external help file: ModuleExample-Help.xml
HelpUri: ''
Locale: en-US
Module Name: ModuleExample
ms.date: 11 15 2026
PlatyPS schema version: 2024-05-01
title: Get-ExampleData
---

# Get-ExampleData

## SYNOPSIS

Gets the status of one or more services.

## SYNTAX

### __AllParameterSets

```
Get-ExampleData [-ServiceName] <string[]> [[-Environment] <string>]
```

## DESCRIPTION

Emits one ExampleServiceResult object for each service name, in the order the names are received. A service that cannot be queried is reported as a non-terminating error, and the remaining names are still processed.

There is no real service behind this module. The statuses come from a fixed table that knows the services Billing, Identity, and Reporting. Every other name fails with the error ID ServiceNotFound.

## EXAMPLES

### Example 1: Get the status of one service

```powershell
Get-ExampleData -ServiceName 'Billing'
```

Gets the status of the Billing service in the Development environment.

### Example 2: Take the service names from the pipeline

```powershell
'Billing', 'Identity', 'Reporting' | Get-ExampleData -Environment 'Test'
```

Gets the status of three services in the Test environment, taking the names from the pipeline.

### Example 3: Continue after a service that cannot be queried

```powershell
Get-ExampleData -ServiceName 'Billing', 'Missing', 'Reporting'
```

Gets the status of Billing and Reporting, and writes a non-terminating error for Missing.

## PARAMETERS

### -Environment

Environment to query, which is recorded on each result.

```yaml
Type: System.String
DefaultValue: Development
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ServiceName

One or more names of services to query.

```yaml
Type: System.String[]
DefaultValue: ''
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: true
  ValueFromPipeline: true
  ValueFromPipelineByPropertyName: true
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

### System.String[]

You can pipe service names to this function, or objects that have a ServiceName property.

## OUTPUTS

### ExampleServiceResult

One object for each service that was queried, with ServiceName, Environment, Status, and CheckedAt properties.

## NOTES

The error for a service that cannot be queried is non-terminating. To end the command at the first such service, pass -ErrorAction Stop.

## RELATED LINKS

- [about_ModuleExample]()
- [PowerShell-Copilot-Standards](https://github.com/fadwen/Powershell-Copilot-Standards)
