#Requires -Version 5
<#
	.NOTES
		==============================================================================================
		Copyright(c) Aman Bedi. All rights reserved.
		
		File:		CreateWorkItem.ps1
		
		Purpose:	Create work item on release failure in VSTS.
		
		Version: 	1.0.0.2 - 28th May 2018 - Aman Bedi
		==============================================================================================	

	.SYNOPSIS
		Create a work item in VSTS
	
	.DESCRIPTION
		Dynamically creates a bug (work item) in current
		or custom defined area & iteration path for the
		team project in VSTS on release failure with 
		details like repro steps, errors, description,
		title, priority, severity & assigns it to the
		person who triggered the release or custom 
		requestor in case it is provided. Supports
		classic UI based pipelines as well as YAML
		multi stage pipelines. Configure & customize
		accordingly (read documentation for the same).
		
		Deployment steps of the script are outlined below.
	
	.EXAMPLE
		Default:
		C:\PS> CreateWorkItem.ps1 `
#>

#region - Script

[CmdletBinding()]
param()

#region - Control Routine
Import-Module -Name $PSScriptRoot\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1 -Verbose
Trace-VstsEnteringInvocation $MyInvocation
#endregion

try {

[string]$AuthToken = $env:SYSTEM_ACCESSTOKEN
if($AuthToken -eq $null -or $AuthToken -eq "")
{
	throw "The script cannot access Personal Access Token, Please enable `"Allow scripts to access OAuth token`" flag in in Agent Phase -> Additional options (For classic UI based pipelines). For YAML pipelines ensure System.AccessToken is passed as environment variable to the task (check documentation)."
}

Write-Host "Starting Create Bug VSTS Task"
Write-Host "Ensure the task is configured correctly in target YAML or classic release pipeline with correct condition and control options respectively as documented to avoid unexpected errors"
Write-Host "Check isyamlpipeline flag in settings if this task is part of YAML pipeline as it has different API to get release details as compared to classic release pipelines & make sure System.AccessToken is passed as environment variable to the task."

$Build = $env:BUILD_DEFINITIONNAME
$ReleaseName = $env:RELEASE_RELEASENAME
$EnvironmentName = $env:RELEASE_ENVIRONMENTNAME
[int] $ReleaseId = ( $env:RELEASE_RELEASEID -as [int])
[string]$ReleaseDefinition = $env:RELEASE_DEFINITIONNAME
$vstsAccount = $env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
$vstsUri = $env:SYSTEM_TEAMFOUNDATIONSERVERURI
$teamProject = $env:SYSTEM_TEAMPROJECTID
$collectionId = $env:SYSTEM_COLLECTIONID

$Authentication = [Text.Encoding]::ASCII.GetBytes(":$AuthToken")
$Authentication = [System.Convert]::ToBase64String($Authentication)

$Headers = @{
	Authorization   = ("Basic {0}" -f $Authentication)
}

$isyaml = Get-VstsInput -Name 'isyamlpipeline' -Require
$iscustomrequestor = Get-VstsInput -Name 'customrequestor' -Require

if ($iscustomrequestor -eq $true) {
	Write-Host "Custom Requestor provided."
	$Requestor = Get-VstsInput -Name 'customrequestorid' -Require
	Write-Host "Custom Requestor: $Requestor"
}
else {
$Requestor = $env:RELEASE_REQUESTEDFOR
}

$customPaths = Get-VstsInput -Name 'custompaths' -Require
if ($customPaths -eq $true) {
	Write-Host "Custom Paths provided."
	$AreaPath = Get-VstsInput -Name 'areapath' -Require
	$currentIteration = Get-VstsInput -Name 'iterationpath' -Require
	Write-Host "Custom Area Path: $AreaPath"
	Write-Host "Custom Iteration Path: $currentIteration"
}
else {
	Write-Host "Getting default area and iteration paths for current team project."
	
	#$iterationPropertiesUri = "$vstsAccount" + "DefaultCollection/" + $teamProject + "/_apis/work/TeamSettings/Iterations?$timeframe=current&api-version=4.1"
	#$iterationPropertiesUri = "https://dev.azure.com/" + $collectionId + "/" +  $teamProject + "/_apis/work/teamsettings/iterations?$timeframe=current&api-version=5.0"
	$iterationPropertiesUri = "$vstsAccount$teamProject/_apis/work/TeamSettings/Iterations?$timeframe=current&api-version=5.0"
	
	Write-Host "Invoking Rest Endpoint for getting default current iteration path: $iterationPropertiesUri"
	
	$Parameters = @{
		Uri			    = $iterationPropertiesUri
		Method		    = 'Get'
		Headers		    = $Headers
	}
	$iterations = Invoke-RestMethod @Parameters
	$cIteration = $iterations.value | Where-Object { $PSItem.attributes.timeFrame -eq 'current' }
	$currentIteration = $cIteration.path
	Write-Host "Default current iteration Path: $currentIteration"
	
	#$areaPathUri = "$vstsAccount" + "DefaultCollection/" + $teamProject + "/_apis/work/TeamSettings/TeamFieldValues?api-version=4.1"
	#$areaPathUri = "https://dev.azure.com/" + $collectionId + "/" +  $teamProject + "/_apis/work/teamsettings/teamfieldvalues?api-version=5.0"
	$areaPathUri = "$vstsAccount$teamProject/_apis/work/teamsettings/teamfieldvalues?api-version=5.0"

	Write-Host "Invoking Rest Endpoint for getting default area path: $areaPathUri"
	
	$Parameters = @{
		Uri			    = $areaPathUri
		Method		    = 'Get'
		Headers		    = $Headers
	}
	$areaPathProperty = Invoke-RestMethod @Parameters
	$currentAreaPath = $areaPathProperty.defaultvalue
	$AreaPath = $currentAreaPath
	Write-Host "Default area path: $AreaPath"
}

$script:errorText = "<font color = ""red""><b>The release failed due to following errors: </b></font><br/><br/>"

if ($isyaml -eq $true) {
	Write-Host "YAML pipeline selected, getting details for multi stage pipeline configured with this task"
	$BuildId = $env:BUILD_BuildId

	$uri = "$vstsUri$teamProject/_apis/build/builds/$($BuildId)?api-version=5.0"
	
	Write-Host "Invoking Rest Endpoint to get current release details: $uri"

	$Parameters = @{
		Uri			    = $uri
		Method		    = 'Get'
		Headers		    = $Headers
	}

	$result = Invoke-RestMethod @Parameters

	$script:errorText += "<font color = ""red""><b>Errors occured in yaml pipeline: </b></font><br/><br/>"

	$BugTitle = "Pipeline $($result.definition.name) failed against the build $($result.buildNumber)."

	$uri = "$vstsUri$teamProject/_apis/build/builds/$($BuildId)/timeline?api-version=5.1"
	$Parameters = @{
		Uri			    = $uri
		Method		    = 'Get'
		Headers		    = $Headers
	}

	Write-Host "Invoking Rest Endpoint to get current release details: $uri"

	$result = Invoke-RestMethod @Parameters

	Write-Host "Getting Stages details"
	$failedStages = $result.records | Where-Object { ($PSItem.result -eq "failed" -or $PSItem.state -eq "inProgress") -and $PSItem.type -eq "stage" }

	if ($failedStages -ne $null)
	{
		foreach ($failedStage in $failedStages)
		{
			Write-Host "Getting details for failed stage of current environment: $($failedStage.name)"
			$script:errorText += "<font color = ""red""><b>Errors in stage $($failedStage.name) : </b></font><br/><br/>"

			$failedPhases = $result.records | Where-Object { $PSItem.parentId -eq $failedStage.id -and $PSItem.type -eq "phase" -and ($PSItem.result -eq "failed" -or $PSItem.state -eq "inProgress") }

			foreach ($phase in $failedPhases)
			{
				Write-Host "Getting details of the phase: $($phase.name)"
				$failedjobs = $result.records | Where-Object { $PSItem.parentId -eq $phase.id -and $PSItem.type -eq "job" -and ($PSItem.result -eq "failed" -or $PSItem.state -eq "inProgress") }

				foreach ($job in $failedjobs)
				{
					Write-Host "Getting details of the tasks which failed in the current job."
					$failedtasks = $result.records | Where-Object { $PSItem.parentId -eq $job.id -and $PSItem.type -eq "task" -and $PSItem.result -eq "failed" }

					foreach ($failedtask in $failedtasks)
					{
						Write-Host "Getting error details of the failed task: $($failedtask.name)"
						$script:errorText += "<font color = ""red"">Errors in task $($failedtask.name) : </font><br/><br/>"
						$script:errorText += "<ul>"
						Write-Host "Following errors found."

						foreach ($issue in $failedtask.issues)
						{
							Write-Host "Error message: $($issue.message)"																									
							$script:errorText += "<li>"
							$script:errorText += "$($issue.message) <br/><br/>"
							$script:errorText += "</li>"
						}
						$script:errorText += "</ul>"
					}
				}
			}
		}
	}

Write-Host "Consolidated error report:"
Write-Host $script:errorText
}
else
{
	Write-Host "YAML pipeline unchecked, getting details for classic release pipeline configured with this task"
	#$uri = "$vstsUri$teamProject/_apis/Release/releases/$($ReleaseId)?api-version=3.0-preview.1"
	#$uri = "https://vsrm.dev.azure.com/" + $collectionId + "/" +  $teamProject + "/_apis/release/releases/$($ReleaseId)?api-version=5.0"
	$uri = "$vstsUri$teamProject/_apis/Release/releases/$($ReleaseId)?api-version=5.0"

	Write-Host "Invoking Rest Endpoint to get current release details: $uri"

	$Parameters = @{
		Uri			    = $uri
		Method		    = 'Get'
		Headers		    = $Headers
	}
	$result = Invoke-RestMethod @Parameters

	$environments = $result.environments
	Write-Host "Getting Environment details"
	$failedEnvironments = $environments | Where-Object { $PSItem.status -eq "rejected" -or $PSItem.status -eq "inProgress" }

	if ($failedEnvironments -ne $null)
	{
		Write-Host "Getting details for the environments where the release failed."
		foreach ($environment in $failedEnvironments)
		{
			$script:errorText += "<font color = ""red""><b>Errors in environment $($environment.name) : </b></font><br/><br/>"
			Write-Host "Getting failed phases for current environment: $($environment.name)"
			
			$deploymentPhases = $environment.deploySteps.releasedeployphases
			foreach ($phase in $deploymentPhases)
			{
				Write-Host "Getting details of the phase: $($phase.name)"
				$issueTasks = $phase.deploymentJobs.Tasks | Where-Object { $PSItem.issues -ne $null }
				if ($issueTasks -ne $null)
				{
					Write-Host "Getting details of the tasks which failed in the current phase."			
					foreach ($Task in $issueTasks)
					{
						Write-Host "Getting error details of the failed task: $($Task.name)"							
						$script:errorText += "<font color = ""red"">Errors in task $($Task.name) : </font><br/><br/>"
						$script:errorText += "<ul>"
						Write-Host "Following errors found."	
						
						foreach ($issue in $Task.issues)
						{
							Write-Host "Error message: $($issue.message)"																									
							$script:errorText += "<li>"
							$script:errorText += "$($issue.message) <br/><br/>"
							$script:errorText += "</li>"
						}
						$script:errorText += "</ul>"
					}
				}
			}
		}
	}

	Write-Host "Consolidated error report:"
	Write-Host $script:errorText
	$BugTitle = "Release $ReleaseName failed for release definition $ReleaseDefinition in the environment $EnvironmentName against the build $Build"
}

#Uri = "$vstsAccount$teamProject/_apis/wit/workitems/`$Bug?api-version=2.2"
#Uri = "https://dev.azure.com/" + $collectionId + "/" +  $teamProject +  "/_apis/wit/workitems/`$Bug?api-version=5.0"
$ep = "$vstsAccount$teamProject/_apis/wit/workitems/`$Bug?api-version=5.1"
Write-Host "Calling workitem API at following endpoint to create bug $ep"
Write-Host "Ensure ADO project template supports bug work item type, at the minimum you'd need Agile, Scrum or CMMI processes. Basic process template does not support bug workitem type and will cause 404"

$RestParams = @{
	Uri		       = "$vstsAccount$teamProject/_apis/wit/workitems/`$Bug?api-version=5.1"
	ContentType    = 'application/json-patch+json'
	Headers	       = @{
		Authorization    = ("Basic {0}" -f $authentication)
	}
	Method		   = "Patch"
	Body		   = @(
		@{
			op	     = "add"
			path	 = "/fields/System.Title"
			value    = "$BugTitle"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.AreaPath"
			value    = "$AreaPath"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.IterationPath"
			value    = "$currentIteration"
		}
		@{
			op	     = "add"
			path	 = "/fields/System.AssignedTo"
			value    = "$Requestor"
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.Common.Priority"
			value    = 2
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.Common.Severity"
			value    = "2 - High"
		}
		@{
			op	     = "add"
			path	 = "/fields/Microsoft.VSTS.TCM.ReproSteps"
			value    = $script:errorText
		}
	) | ConvertTo-Json
}
Write-Host "Creating a bug with the generated error report under the configured area & iteration path with default severity & priority, populated with release details in title & assigned to the person who triggered the release."
#$RestParams.Body

# try
# {
	Invoke-RestMethod @RestParams -Verbose
# }
# catch
# {
# 	$PSItem.Exception.Message
# }

Write-Host "Bug created successully, enable Bug work items via Working with bugs setting under sprints tab to view them in taskboard. Optionally configure email in project settings on Bug creation."
} finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
#endregion