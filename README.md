# JAMF-DSE-BindToAD
 Script to bind computers to our AD
- Editor: Andrew W. Johnson
- Date: 2020.02.13
- Version 2.00
- Organization: Stony Brook University/DoIT
---
### Description

Originally written by the folks at DeployStudio, and modified over the years to work without DeployStudio.

Converted it to ZSH in February 2020.

We find that there are issues when binding with a profile that are not present when dsconfigad is used to bind.

Using $4 (Jamf parameter) for the OU to bind to.

**This version of the script has been sanitized**