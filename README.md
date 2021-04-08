# CreateBug-VSTS-Task

VSTS provides "Create work item on build failure" functionality for the Build but not Release.
This extension emulates the same for Release by dynamically creating a bug (work item) in current or custom defined area & iteration path for the team project in VSTS on release failure with details like repro steps, errors, description, title, priority, severity & assigns it to the person who triggered the release.

## Changelog v2

* Task is updated to work with ADO v5.0 API's to support new dev.azure conventions and organization model to access team projects & API endpoints
* Custom requestor is now supported
* Added YAML multi-stage pipelines support (need additional config to enable as documented)
* Improved telemetry logs and stability fixes

## Requirements

The task requires access to OAuth token in order to get error details for a release and create a bug in VSTS.
* Please enable "Allow scripts to access OAuth token" flag in in Agent Phase -> Additional options (as shown below).

![ScreenShot](images/AllowOAuth.PNG)

* In case of YAML pipeline, the value of OAuth token needs to be passed as environment variable to the task as follows:

![ScreenShot](images/YAMLConfig.PNG)

## How to use

The task can be added at any step in the release pipeline.

It can be added to the same phase (single phase pipeline) or a different phase (multi-phase pipeline). The recommended approach for either case is covered in the following steps.

1. Add the task
* Goto "Add Task to Agent phase" and add task from utility tab in the desired release pipeline.

![ScreenShot](images/AddTask.PNG)

2. Configure the task
* Enable OAuth token access as per "Requirements" section for classic OR YAML pipeline.
* The task can then be used as is without any configuration provided.
* The default behaviour will add the bug to default area and iteration path setting of the team project to which the release definition belongs to.

![Screenshot](images/DefaultConfig.PNG)

* In order to override the default area and iteration path select the "Custom Area & Iteration Paths" option.
* This will enable required settings for "Area Path" & "Iteration Path". Provide the custom paths as shown in the screenshot, the bug will be created against the same.

![ScreenShot](images/CustomConfig.PNG)

* Below is an example of custom Area Path & Iteration Path in a YAML multi stage pipeline:

![ScreenShot](images/CustomConfigyaml.PNG)

* In case the bug created on failure needs to be assigned to a particular person, check the "Provide custom requestor" checkbox and provide the value for the custom requestor.
* This is particularly useful when pipelines run on scheduled or trigerred by some other process in which case there is no default release requestor.

![ScreenShot](images/CustomRequestor.PNG)

3. Stand-alone step (single phase pipelines)
* In a single phase release pipeline add the task after all the deployment tasks.
* Ensure that "Run this task" setting for the task is set to "Only when a previous task has failed". This enables the task able to get error logs from all the tasks in the release pipeline which have failed in the current environment.
* The same strategy can be applied to all release pipelines of different environments in the release definition so that the error's from failed steps in each environment's release pipeline can be consolidated in final error report for the bug.

![ScreenShot](images/SinglePhase.PNG)

4. Multi-Phase configuration (multi-phase pipelines)
* In a multi-phase pipeline where the release pipeline has various deployment phases, add another phase after the deployment phases to run the task.
* Also ensure that the "Run This Phase" setting for the phase (containing the task) is set to "Only when a previous phase has failed". This enables the task will be able to get error details for all the deployment phases in the failed environments.
* The same strategy can be applied to all release pipelines of different environments in the release definition so that the error's from failed steps in each environment's release pipeline can be consolidated in final error report for the bug.

![ScreenShot](images/MultiPhase.PNG)

5. Multi-Stage YAML pipeline configuration
* In a multi-stage YAML pipeline where the  pipeline has various stages, jobs and phases, add & configure this task such that it is guaranteed to run in case any of the stage fails.
* This can be achieved by figuring out which phase is bound to run irrespective of failures and accordingly configuring "condition" property of the task provided by YAML constructs. In below example setting it to "failed()" ensures that this task will only run when any previous task in the stage has failed. You can also pass custom flag based on previous stages to this condition but the bottomline is that the task needs to be present in one of the stages of the same release and trigger based on correct conditions. 

![ScreenShot](images/YAMLSinglePhase.PNG)

## Sample Runs

Below are sample runs to showcase the task for both single phase and multi phase pipelines. For demo purpose there is only one environment in the release definition but in actual practice, the task will consolidate error logs for all environments that have been executed before the task's execution and have failed phases due to errors in their respective tasks.

### Single Phase Release pipeline

1. Below is a single phase release pipeline having 2 steps:
* An inline PowerShell script execution step which is rigged to blow the release:

![ScreenShot](images/Psstep.PNG)

* The "Create a bug on release failure" step as the last step in the release pipeline with "Run this task" set to "Only when a previous task has failed" to ensure that the bug is only created when any of the previous task fails.

![ScreenShot](images/Pipeline.PNG)

2. On executing a release, the Release fails on the "PowerShell Script" step as a result the "Create a bug on release failure" task executes as configured by "Run this task" property. 
* The task gets the default area and iteration path for the Team Project against which the release was made. 
* It scans through the release, gets all failed environments upto this point, gets all failed phases & tasks in each failed phase and errors for each such task to consolidate the same into an error report.
* The same is written to the host in the logs window

![ScreenShot](images/Release.PNG)

3. Finally the bug is created with environment and build details in the title, consolidated error report, severit & priority, under default area and iteration path, assigned to the person who triggered the release.

![ScreenShot](images/BugReport.PNG)

### Multi Phase Release pipeline

1. Below is a multi phase release pipeline having 2 phases:
* Phase 1 has the same inline PowerShell script execution step which is rigged to blow the release assuming there can be other deployment steps too in the same phase.
* Phase 2 has the "Create a bug on release failure"
* Also the "Create a bug on release failure" step has the Area and Iteration Paths set to custom values as highlighted in the screenshot below.

![ScreenShot](images/MultiCustom.PNG)

* Also the phase 2 has "Run This Phase" setting set to "Only when a previous phase has failed". To ensure that the bug is only created when the previous phase fails.

![ScreenShot](images/MultiPhase.PNG)

2. On executing a release, like before the Release fails on the "PowerShell Script" in the first phase step as a result the second phase starts execution as configured by its "Run This Phase" setting. This results in "Create a bug on release failure" task to be executed.

* The task will now use the custom area and iteration path for the Team Project against which the release was made. 
* It scans through the release, gets all failed environments upto this point, gets all failed phases & tasks in each failed phase and errors for each such task to consolidate the same into an error report.
* The same is written to the host in the logs window

![ScreenShot](images/MultiPhaseRelease.PNG)

3. Finally the bug is created with environment and build details in the title, consolidated error report, severit & priority, under custom area and iteration path, assigned to the person who triggered the release.

![ScreenShot](images/MultiPhaseBug.PNG)

### Multi-stage YAML pipeline

1. Below is a multi stage YAML pipeline having 3 stages:
* Build: Simulates a solution build phase with a dummy task.
* Deploy to Dev: Simulates deployment to dev environment.
* Deploy to QA: Simulates deployment to QA environment.
* The "Create a bug on release failure" has been configured in Deploy to QA step for this example but ideally it should execute on all stages which are expected to fail with condition of only running when any previous task in the stage has failed (refer how to use section for YAML pipelines).

![ScreenShot](images/MultiStageYAML.PNG)

2. On executing a release, like before the Release fails on the "PowerShell Script" in the first phase step in deployment to QA environment stage as a result the task executes next.

![ScreenShot](images/MultiStageYAMLSample.PNG)

* The task will now use the custom area and iteration path for the Team Project against which the release was made.
* Also it will assign to custom identity since "customrequestor" flag was enabled and "customrequestorid" value was set in the task config. 
* Since "isYAML" flag was enable, the task would leverage different set of API's to get details for multi-stage YAML pipeline (if this flag was not set in YAML config, the task would use vsrm API's for classic Release definitions and error out) .
* It scans through the release, gets all failed stages (QA in this case) upto this point, gets all failed jobs & tasks in each failed phase and errors for each such task to consolidate the same into an error report.
* The same is written to the host in the logs window

![ScreenShot](images/YAMLMultiStage.PNG)

3. Finally the bug is created with multi stage pipeline name and build details in the title, consolidated error report, severit & priority, under custom area and iteration path, assigned to the custom requestor.

![ScreenShot](images/YAMLMultiStageBug.PNG)


**_TIP: Ensure that "A work item assigned notification" state is enabled (as shown below) so that the person to whom the bug is assigned can receive an email for the same._**

![ScreenShot](images/Notification.PNG)