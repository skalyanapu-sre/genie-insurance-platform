# MQGen Azure Terraform Bootstrap, Remote State, and GitHub OIDC — Dev Production Runbook

> **Audience:** Platform engineers, SRE/DevOps engineers, cloud administrators, and developers operating or rebuilding the Azure Terraform bootstrap and GitHub OIDC path.
>
> **Runbook scope:** one-time Terraform backend bootstrap, adoption/import of pre-existing Azure backend resources, GitHub OIDC workload identity, Azure Blob state RBAC, validation gates, Git hygiene, and troubleshooting.
>
> **Current implementation status:** backend resource reconciliation and state-container RBAC were validated. Remote-state migration, GitHub OIDC dry authentication, and the real dev deployment workflow are explicitly marked `PENDING` until they are exercised.
>
> **Project context used in this guide**
>
> - Azure subscription name: `<AZURE_SUBSCRIPTION_NAME>`
> - Azure subscription ID: `<AZURE_SUBSCRIPTION_ID>`
> - Terraform state resource group: `mqgen-tfstate-rg`
> - Terraform state container: `tfstate`
> - GitHub deployment application: `mqgen-github-terraform-dev`
> - GitHub Environment: `dev`
> - Bootstrap state key: `bootstrap.terraform.tfstate`
> - Future dev workload state key: `dev.terraform.tfstate`
> - Azure region used in examples: `eastus`
> - Common tags:
>   - `Owner=<OWNER_OR_TEAM>`
>   - `Org=mqgen`
>   - `cost-center=10079`
>
> Replace only values explicitly marked as placeholders. Do **not** paste passwords, client secrets, access keys, SAS tokens, or Databricks PATs into Terraform, Git, or Markdown documentation.
>
> **Environment naming rule:** the GitHub Environment name `dev` must match exactly between GitHub, the Microsoft Entra federated credential entity, and every GitHub Actions job that uses `environment: dev`. The Entra application name `mqgen-github-terraform-dev` is a separate object and does not need to equal the GitHub Environment name.

---

## 1. What are we building?

Before Terraform can safely create the Azure Databricks infrastructure from GitHub Actions, Terraform itself needs three things:

1. A place to store its **state file**.
2. An identity that GitHub Actions can use to access Azure.
3. A trust relationship between **GitHub and Microsoft Entra ID**.

The bootstrap architecture is:

```text
Developer / VS Code
       |
       | git push
       v
GitHub Repository
       |
       | GitHub Actions OIDC token
       v
Microsoft Entra ID
mqgen-github-terraform-dev
       |
       | Azure RBAC
       +-----------------------------+
       |                             |
       v                             v
Azure Subscription              Terraform State
Contributor                     Storage Account
                                      |
                                      v
                                 tfstate container
                                      |
                                      v
                          mqgen/databricks/dev.tfstate
```

The **Terraform state infrastructure is not the Databricks workload infrastructure**.

Later, Terraform will use this state backend to create:

```text
mqgen-org-rg
├── mqgen-adbx-vnet
├── Databricks subnets
├── NSG
├── NAT Gateway
└── mqgen-adbx

mqgen-org-managed-rg
└── Azure Databricks-managed resources
```

---

# 2. Why bootstrap has a one-time local phase

A Terraform remote backend must exist before a normal CI/CD workflow can use it. That does **not** mean the backend resources have to be created by hand.

The tested pattern in this project is:

```text
One-time local bootstrap from VS Code
        |
        +-- terraform init (local state initially)
        +-- import any backend resources that already exist
        +-- create only missing backend resources
        +-- create state-container RBAC
        |
        v
Azure remote backend is ready
        |
        v
Migrate bootstrap state to Azure Blob
        |
        v
Normal GitHub Actions / OIDC Terraform workflow
```

This avoids the circular dependency:

```text
terraform init needs backend
        ^
        |
backend would otherwise need terraform apply
```

Two valid bootstrap cases are covered by this runbook:

1. **Backend does not exist:** create it once from the local bootstrap stack.
2. **Backend already exists:** import the existing Resource Group, Storage Account, and container into Terraform state before applying anything.

The second case was exercised during this implementation and is documented in the tested-scenarios section later in this runbook.

---

# 3. Production security principle

We will **not** create or store an Azure client secret.

Avoid this pattern:

```text
GitHub Secret
AZURE_CLIENT_SECRET=xxxxxxxxxxxxxxxx
```

Avoid committing:

```text
terraform.tfvars containing passwords
.env containing Azure credentials
service-principal.json
storage account keys
SAS tokens
Databricks PATs
```

Instead:

```text
GitHub Actions
      |
      | short-lived OIDC token
      v
Microsoft Entra ID
      |
      | validates GitHub repository/environment
      v
Short-lived Azure access token
```

This is called **workload identity federation**.

Microsoft recommends federated credentials instead of client secrets for production workloads, and GitHub supports OIDC specifically so workflows do not need long-lived Azure credentials.

---

# 4. Prerequisites

Before starting, make sure the following are available.

## 4.1 Local workstation

Required:

```text
VS Code
Git
Terraform
Azure CLI
Internet access
Access to the existing GitHub repository
```

Test:

```bash
git --version
terraform version
az version
code --version
```

### Why test first?

If one tool is missing, later errors can be misleading.

For example:

```text
terraform: command not found
```

is not an Azure problem.

---

## 4.2 Azure permissions

For the **one-time bootstrap**, your user needs permission to:

- create resource groups;
- create Storage Accounts;
- create Microsoft Entra applications/service principals;
- create Azure RBAC role assignments.

For Azure role assignment creation, `Owner` or `User Access Administrator` capability is typically required at the relevant scope.

### Test your current subscription

```bash
az account show \
  --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
  -o table
```

Expected subscription:

```text
Name                   SubscriptionId
---------------------  ------------------------------------
<AZURE_SUBSCRIPTION_NAME>   <AZURE_SUBSCRIPTION_ID>
```

---

# 5. Step 1 — Log in to Azure

Run:

```bash
az login
```

A browser authentication flow opens.

## Purpose

`az login` authenticates your local Azure CLI session.

This session is used only for the **bootstrap operations** and local validation.

GitHub Actions will later use OIDC instead.

## Test

```bash
az account show \
  --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
  -o table
```

## Common problem

You may be logged into Azure successfully but using the wrong subscription.

Never assume the active subscription.

---

# 6. Step 2 — Select the correct Azure subscription

Run:

```bash
az account set \
  --subscription "<AZURE_SUBSCRIPTION_ID>"
```

## Purpose

Azure CLI can contain access to multiple subscriptions.

`az account set` tells Azure CLI:

> All commands after this should target this subscription unless explicitly overridden.

## Test

```bash
az account show \
  --query "{Name:name,SubscriptionId:id}" \
  -o table
```

Expected:

```text
Name                   SubscriptionId
---------------------  ------------------------------------
<AZURE_SUBSCRIPTION_NAME>   <AZURE_SUBSCRIPTION_ID>
```

## Common error

Incorrect:

```bash
az account set --subcription "..."
```

Correct:

```bash
az account set --subscription "..."
```

---

# 7. Step 3 — Save useful shell variables

Run:

```bash
export ARM_SUBSCRIPTION_ID="<AZURE_SUBSCRIPTION_ID>"

export ARM_TENANT_ID=$(az account show \
  --query tenantId \
  -o tsv)
```

Test:

```bash
echo "$ARM_SUBSCRIPTION_ID"
echo "$ARM_TENANT_ID"
```

## Purpose

Shell variables reduce typing mistakes.

Instead of repeatedly entering a long subscription ID, commands can reference:

```bash
$ARM_SUBSCRIPTION_ID
```

## Important

These two values are identifiers, not passwords.

Do not confuse:

```text
Client ID
Tenant ID
Subscription ID
```

with:

```text
Client Secret
Password
Storage Account Key
```

---

# 8. Step 4 — Verify Azure resource providers

Azure services are exposed through resource providers such as:

```text
Microsoft.Storage
Microsoft.Network
Microsoft.Databricks
Microsoft.Compute
Microsoft.ManagedIdentity
```

## Why?

Terraform later asks Azure Resource Manager to create resources through these providers.

If a provider is not registered, Terraform can fail with errors such as:

```text
MissingSubscriptionRegistration
```

## Check Storage provider

```bash
az provider show \
  --namespace Microsoft.Storage \
  --query registrationState \
  -o tsv
```

Expected:

```text
Registered
```

## Register if needed

```bash
az provider register --namespace Microsoft.Storage
```

For the later Databricks deployment:

```bash
az provider register --namespace Microsoft.Databricks
az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.ManagedIdentity
```

## Check all relevant providers

```bash
for p in \
  Microsoft.Storage \
  Microsoft.Databricks \
  Microsoft.Network \
  Microsoft.Compute \
  Microsoft.ManagedIdentity
do
  printf "%-35s " "$p"
  az provider show \
    --namespace "$p" \
    --query registrationState \
    -o tsv
done
```

Do not continue with a provider that reports a failed registration state.

---

# 9. Step 5 — Understand the Terraform state resource group

We will create:

```text
mqgen-tfstate-rg
```

## What is a Resource Group?

An Azure Resource Group is a management container for Azure resources.

For this bootstrap:

```text
mqgen-tfstate-rg
└── Terraform state Storage Account
```

We deliberately keep Terraform state separate from application resources.

## Why separate it?

If your application resource group is accidentally destroyed, Terraform's own state should not disappear with it.

Bad design:

```text
mqgen-org-rg
├── Application resources
└── Terraform state
```

Better:

```text
mqgen-tfstate-rg
└── Terraform state

mqgen-org-rg
└── Application infrastructure
```

---

# 10. Step 6 — Check whether `mqgen-tfstate-rg` already exists

Before creating a resource, always check.

Run:

```bash
az group exists \
  --name "mqgen-tfstate-rg"
```

Possible output:

```text
true
```

or:

```text
false
```

## Why?

This prevents students from blindly rerunning commands and becoming confused about whether Azure created something previously.

---

# 11. Step 7 — Create the Terraform state Resource Group

If the previous command returned `false`, run:

```bash
az group create \
  --name "mqgen-tfstate-rg" \
  --location "eastus" \
  --tags \
    Owner="<OWNER_OR_TEAM>" \
    Org="mqgen" \
    cost-center="10079"
```

## What are tags?

Tags are metadata attached to Azure resources.

Examples:

```text
Owner
Org
cost-center
Environment
ManagedBy
```

Tags help with:

- cost reporting;
- ownership;
- governance;
- inventory;
- policy enforcement.

## Test

```bash
az group show \
  --name "mqgen-tfstate-rg" \
  --query "{
    Name:name,
    Location:location,
    State:properties.provisioningState,
    Tags:tags
  }" \
  -o json
```

Expected state:

```text
Succeeded
```

---

# 12. Troubleshooting — `ResourceGroupNotFound`

Example error:

```text
(ResourceGroupNotFound)
Resource group 'mqgen-tfstate-rg' could not be found.
```

## Why this happens

A command attempted to create a resource inside:

```text
mqgen-tfstate-rg
```

before that Resource Group existed.

Example:

```bash
az storage account create \
  --resource-group "mqgen-tfstate-rg" \
  ...
```

Azure Storage Accounts must belong to an existing Resource Group.

## Fix

First:

```bash
az group exists \
  --name "mqgen-tfstate-rg"
```

If:

```text
false
```

create it:

```bash
az group create \
  --name "mqgen-tfstate-rg" \
  --location "eastus" \
  --tags Owner="<OWNER_OR_TEAM>" Org="mqgen" cost-center="10079"
```

Then rerun the Storage Account command.

## Student lesson

Always validate the **parent resource** before creating the child resource.

```text
Subscription
   |
   v
Resource Group
   |
   v
Storage Account
   |
   v
Blob Container
   |
   v
Terraform State Blob
```

---

# 13. Stop Gate 1

Before moving forward, all must be true:

```text
[ ] Azure login works
[ ] Correct subscription selected
[ ] mqgen-tfstate-rg exists
[ ] Resource Group state = Succeeded
[ ] Required tags exist
```

Verify quickly:

```bash
az group show \
  --name "mqgen-tfstate-rg" \
  --query "{Name:name,Location:location,State:properties.provisioningState,Tags:tags}" \
  -o json
```

---

# 14. Step 8 — Choose the Terraform Storage Account name

Set:

```bash
export TFSTATE_STORAGE="<TFSTATE_STORAGE_ACCOUNT>"
```

Check:

```bash
echo "$TFSTATE_STORAGE"
```

## Purpose

This variable will be reused in several commands.

## Storage Account naming rules

Azure Storage Account names:

- must be globally unique across Azure;
- use lowercase letters and numbers;
- cannot contain hyphens;
- have length restrictions.

Therefore:

```text
<TFSTATE_STORAGE_ACCOUNT>
```

may already belong to somebody else.

---

# 15. Step 9 — Check Storage Account name availability

Run:

```bash
az storage account check-name \
  --name "$TFSTATE_STORAGE"
```

Expected if available:

```json
{
  "nameAvailable": true,
  "reason": null,
  "message": null
}
```

If:

```json
"nameAvailable": false
```

choose another globally unique name.

Example:

```bash
export TFSTATE_STORAGE="mqgentfstate10079p01"
```

Check again.

## Why test?

It is better to discover a naming collision before executing a long create command.

---

# 16. Step 10 — Check whether the Storage Account already exists in your Resource Group

Run:

```bash
az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{Name:name,Location:location,State:provisioningState}" \
  -o table
```

If it exists, Azure returns its information.

If it does not exist, Azure returns a not-found error.

You can also list all Storage Accounts in the bootstrap RG:

```bash
az storage account list \
  --resource-group "mqgen-tfstate-rg" \
  --query "[].{Name:name,Location:location,SKU:sku.name}" \
  -o table
```

---

# 17. Step 11 — Create the Terraform Storage Account

Run:

```bash
az storage account create \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --location "eastus" \
  --sku "Standard_LRS" \
  --kind "StorageV2" \
  --min-tls-version "TLS1_2" \
  --allow-blob-public-access false \
  --tags \
    Owner="<OWNER_OR_TEAM>" \
    Org="mqgen" \
    cost-center="10079"
```

## Explanation of every option

### `--name`

```bash
--name "$TFSTATE_STORAGE"
```

The globally unique Azure Storage Account name.

### `--resource-group`

```bash
--resource-group "mqgen-tfstate-rg"
```

Places this Storage Account in the dedicated Terraform state Resource Group.

### `--location`

```bash
--location "eastus"
```

Azure region where Storage Account metadata/data is created.

### `--sku Standard_LRS`

`Standard_LRS` means:

```text
Standard performance
+
Locally Redundant Storage
```

For a small Terraform state backend, LRS is commonly sufficient unless your organization's disaster-recovery policy requires stronger replication.

### `--kind StorageV2`

Creates a General Purpose v2 Storage Account.

### `--min-tls-version TLS1_2`

Rejects older TLS versions.

### `--allow-blob-public-access false`

Prevents public anonymous blob/container access.

---

# 18. Step 12 — Verify the Storage Account

Run:

```bash
az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{
    Name:name,
    ResourceGroup:resourceGroup,
    Location:location,
    ProvisioningState:provisioningState,
    SKU:sku.name,
    Kind:kind,
    TLS:minimumTlsVersion,
    HTTPS:httpsOnly,
    PublicBlobAccess:allowBlobPublicAccess,
    Tags:tags
  }" \
  -o json
```

Validate:

```text
ProvisioningState = Succeeded
TLS = TLS1_2
PublicBlobAccess = false
```

---

# 19. Stop Gate 2

Do not continue until:

```text
[ ] Storage Account exists
[ ] provisioningState = Succeeded
[ ] TLS minimum = TLS1_2
[ ] public blob access = false
[ ] correct Resource Group
[ ] correct tags
```

---

# 20. Step 13 — Save the Storage Account resource ID

Run:

```bash
export TFSTATE_STORAGE_ID=$(az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query id \
  -o tsv)
```

Test:

```bash
echo "$TFSTATE_STORAGE_ID"
```

Expected structure:

```text
/subscriptions/<subscription-id>/resourceGroups/mqgen-tfstate-rg/providers/Microsoft.Storage/storageAccounts/<storage-account>
```

## Why do we need the resource ID?

Azure RBAC assignments are attached to a **scope**. For least privilege, this runbook uses the **Blob container resource ID** when granting GitHub `Storage Blob Data Contributor` access to Terraform state. Storage-account scope is broader and should only be used when required by the operating model.

---

# 21. Step 14 — Understand Azure management plane vs data plane

This distinction causes many beginner errors.

## Management plane

Controls the Storage Account itself.

Examples:

```text
Create Storage Account
Delete Storage Account
Change networking
Change tags
```

Roles such as:

```text
Contributor
Owner
```

primarily operate here.

## Data plane

Controls data inside the Storage Account.

Examples:

```text
Create blob container
Read Terraform state blob
Write Terraform state blob
Delete Terraform state blob
```

Terraform remote state needs Blob data access.

Therefore a user may be able to create a Storage Account but still receive:

```text
AuthorizationPermissionMismatch
```

when trying to create/read a blob.

---

# 22. Step 15 — Get your signed-in user Object ID

Run:

```bash
export MY_OBJECT_ID=$(az ad signed-in-user show \
  --query id \
  -o tsv)
```

Verify:

```bash
echo "$MY_OBJECT_ID"
```

## Purpose

Azure RBAC role assignments target a principal.

Your user principal is identified by its Entra Object ID.

---

# 23. Step 16 — Assign yourself `Storage Blob Data Contributor`

Run:

```bash
az role assignment create \
  --assignee-object-id "$MY_OBJECT_ID" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" \
  --scope "$TFSTATE_STORAGE_ID"
```

## Purpose

`Storage Blob Data Contributor` permits blob/container read, write, and delete operations.

You need this so your Azure CLI login can create and test the Terraform state container using Microsoft Entra authentication.

## Why not use the Storage Account access key?

Because the production design intentionally uses:

```text
Microsoft Entra authentication
```

instead of:

```text
Storage Account shared keys
```

## Verify role assignment

```bash
az role assignment list \
  --assignee-object-id "$MY_OBJECT_ID" \
  --scope "$TFSTATE_STORAGE_ID" \
  --query "[].{Role:roleDefinitionName,Principal:principalName,Scope:scope}" \
  -o table
```

Look for:

```text
Storage Blob Data Contributor
```

---

# 24. Troubleshooting — authorization error after RBAC assignment

You may receive:

```text
AuthorizationPermissionMismatch
```

or:

```text
AuthorizationFailure
```

even though the role assignment appears in Azure.

## Check 1 — correct object ID

```bash
echo "$MY_OBJECT_ID"
```

Then:

```bash
az ad signed-in-user show \
  --query "{Name:displayName,UPN:userPrincipalName,Id:id}" \
  -o table
```

## Check 2 — role exists at correct scope

```bash
az role assignment list \
  --assignee-object-id "$MY_OBJECT_ID" \
  --scope "$TFSTATE_STORAGE_ID" \
  -o table
```

## Check 3 — re-authenticate if necessary

```bash
az logout
az login

az account set \
  --subscription "<AZURE_SUBSCRIPTION_ID>"
```

Then rerun the validation.

RBAC changes are not always visible to every token immediately, so validate the role before troubleshooting unrelated Terraform code.

---

# 25. Step 17 — Create the `tfstate` Blob Container

Run:

```bash
az storage container create \
  --name "tfstate" \
  --account-name "$TFSTATE_STORAGE" \
  --auth-mode login
```

Expected:

```json
{
  "created": true
}
```

## What is a Blob Container?

Hierarchy:

```text
Storage Account
     |
     v
Blob Container
     |
     v
Blob
```

For Terraform:

```text
Storage Account
     |
     v
tfstate
     |
     v
mqgen/databricks/dev.tfstate
```

The `.tfstate` object will be created later when Terraform initializes/applies with the remote backend.

---

# 26. Step 18 — Test whether the `tfstate` container exists

Best direct check:

```bash
az storage container exists \
  --name "tfstate" \
  --account-name "$TFSTATE_STORAGE" \
  --auth-mode login
```

Expected:

```json
{
  "exists": true
}
```

Alternative list check:

```bash
az storage container list \
  --account-name "$TFSTATE_STORAGE" \
  --auth-mode login \
  --query "[].name" \
  -o table
```

Expected:

```text
Result
-------
tfstate
```

---

# 27. Stop Gate 3

Before proceeding:

```text
[ ] TFSTATE_STORAGE_ID is populated
[ ] MY_OBJECT_ID is populated
[ ] Your user has Storage Blob Data Contributor
[ ] tfstate container exists
[ ] --auth-mode login works
```

---

# 28. Step 19 — Enable Blob versioning

Run:

```bash
az storage account blob-service-properties update \
  --account-name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --enable-versioning true
```

## Purpose

Terraform state is extremely important.

If a state file is overwritten incorrectly, Blob versioning gives you previous versions.

Conceptually:

```text
dev.tfstate
├── Version 1
├── Version 2
├── Version 3
└── Current version
```

---

# 29. Step 20 — Enable Blob soft delete

Run:

```bash
az storage account blob-service-properties update \
  --account-name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --enable-delete-retention true \
  --delete-retention-days 30
```

## Purpose

If the state blob is accidentally deleted, soft delete gives you a recovery window.

This is defense against:

```text
accidental deletion
automation error
operator mistake
```

---

# 30. Step 21 — Verify versioning and soft delete

Run:

```bash
az storage account blob-service-properties show \
  --account-name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{
    Versioning:isVersioningEnabled,
    DeleteRetentionEnabled:deleteRetentionPolicy.enabled,
    DeleteRetentionDays:deleteRetentionPolicy.days
  }" \
  -o json
```

Expected:

```json
{
  "Versioning": true,
  "DeleteRetentionEnabled": true,
  "DeleteRetentionDays": 30
}
```

---

# 31. Step 22 — Optional production hardening: disable shared-key access

After Entra ID access is proven, you can disable shared-key authorization:

```bash
az storage account update \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --allow-shared-key-access false
```

## Purpose

This forces clients toward Microsoft Entra authentication instead of Storage Account shared keys.

## Verify

```bash
az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{Name:name,SharedKeyAccess:allowSharedKeyAccess}" \
  -o table
```

Expected:

```text
SharedKeyAccess
---------------
False
```

Do this only after confirming that your backend strategy uses Microsoft Entra ID/OIDC.

---

# 32. Terraform remote-state architecture after bootstrap

You should now have:

```text
Azure Subscription
└── mqgen-tfstate-rg
    └── <your globally unique storage account>
        └── tfstate
```

Terraform will later create:

```text
tfstate/
└── mqgen/
    └── databricks/
        └── dev.tfstate
```

The logical path is controlled by the Terraform backend `key`.

Example:

```hcl
terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true

    key = "dev.terraform.tfstate"
  }
}
```

---

# 33. Step 23 — Understand the GitHub deployment identity

The next bootstrap component is:

```text
mqgen-github-terraform-dev
```

This is a Microsoft Entra application/service principal representing the **GitHub Actions deployment workload**.

Do not confuse it with a human user.

```text
Human:
you@example.com

Workload identity:
mqgen-github-terraform-dev
```

## Why does GitHub need an Azure identity?

Terraform running inside GitHub Actions needs permission to call Azure APIs.

Example:

```text
GitHub Runner
     |
     | terraform apply
     v
Azure Resource Manager
     |
     +-- create RG
     +-- create VNet
     +-- create subnet
     +-- create Databricks workspace
```

Azure must know who is making those requests.

---

# 34. Step 24 — Create the GitHub `dev` Environment

In GitHub:

```text
Repository
→ Settings
→ Environments
→ New environment
```

Name:

```text
dev
```

## Why use an Environment?

GitHub Environments provide a security boundary around deployment.

They can control:

- which branch may deploy;
- required reviewers;
- environment secrets;
- environment variables;
- OIDC trust conditions.

Configure the dev deployment environment so that only:

```text
main
```

is allowed to deploy.

For stronger production controls, add required reviewers.

---

# 35. Step 25 — Create the Microsoft Entra application

In Azure Portal:

```text
Microsoft Entra ID
→ App registrations
→ New registration
```

Name:

```text
mqgen-github-terraform-dev
```

Choose:

```text
Accounts in this organizational directory only
```

Leave Redirect URI empty.

Click:

```text
Register
```

## Record

After creation, record:

```text
Application (client) ID
Directory (tenant) ID
```

### Important

Do not create:

```text
Client secret
```

We are using federation instead.

---

# 36. Step 26 — Verify the Entra application exists

From Azure CLI:

```bash
az ad app list \
  --display-name "mqgen-github-terraform-dev" \
  --query "[].{DisplayName:displayName,ClientId:appId,ObjectId:id}" \
  -o table
```

Expected: one row for:

```text
mqgen-github-terraform-dev
```

Save the Client ID:

```bash
export GITHUB_CLIENT_ID="<APPLICATION-CLIENT-ID>"
```

Verify:

```bash
echo "$GITHUB_CLIENT_ID"
```

---

# 37. Step 27 — Verify/create the Service Principal

Check:

```bash
az ad sp show \
  --id "$GITHUB_CLIENT_ID" \
  --query "{DisplayName:displayName,ClientId:appId,ObjectId:id}" \
  -o table
```

If the service principal does not yet exist, create it:

```bash
az ad sp create \
  --id "$GITHUB_CLIENT_ID"
```

Then retrieve its Object ID:

```bash
export GITHUB_SP_OBJECT_ID=$(az ad sp show \
  --id "$GITHUB_CLIENT_ID" \
  --query id \
  -o tsv)
```

Verify:

```bash
echo "$GITHUB_SP_OBJECT_ID"
```

## Client ID vs Object ID

This is a common implementation distinction.

```text
Application (client) ID
→ identifies the application globally

Service Principal Object ID
→ identifies this application's enterprise identity object in this tenant
```

Azure RBAC assignment commands commonly use the Service Principal **Object ID**.

---

# 38. Step 28 — Configure GitHub OIDC federation

Azure Portal:

```text
Microsoft Entra ID
→ App registrations
→ mqgen-github-terraform-dev
→ Certificates & secrets
→ Federated credentials
→ Add credential
```

Choose:

```text
GitHub Actions deploying Azure resources
```

Select:

```text
GitHub owner / organization
GitHub repository
Entity type: Environment
Environment: dev
```

Recommended audience:

```text
api://AzureADTokenExchange
```

Credential name:

```text
github-dev
```

## Purpose

This tells Microsoft Entra ID:

> Trust OIDC tokens from this specific GitHub workload under the configured conditions.

It does **not** mean every GitHub repository can access Azure.

---

# 39. Why environment-scoped OIDC is safer

A broad trust relationship could accidentally allow more workflows to request Azure tokens.

Instead:

```text
Repository
   |
   v
Environment = dev
   |
   v
Federated credential matches
   |
   v
Azure token allowed
```

GitHub recommends environment protection rules when environments are used with OIDC.

> Note: GitHub changed default OIDC subject behavior for repositories created after July 15, 2026 and for repositories renamed/transferred after that date. Prefer GitHub/Azure's supported federation configuration rather than manually guessing a `sub` string.

---

# 40. Step 29 — Give the GitHub identity Azure `Contributor`

For this initial infrastructure deployment, the GitHub identity needs to create Azure resources.

Example scope:

```text
/subscriptions/<AZURE_SUBSCRIPTION_ID>
```

Assign:

```bash
az role assignment create \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>"
```

## Why Contributor?

It permits normal resource creation and management.

For this initial phase, GitHub needs to create resources such as:

```text
Resource Group
VNet
Subnets
NSG
NAT Gateway
Public IP
Azure Databricks Workspace
```

## What Contributor cannot do

Contributor does not grant unrestricted Azure RBAC role-assignment management.

That is good for least privilege.

---

# 41. Step 30 — Verify GitHub's Contributor role

Run:

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>" \
  --query "[].{Role:roleDefinitionName,Scope:scope}" \
  -o table
```

Expected:

```text
Contributor
```

If nothing is returned, do not proceed to pipeline testing.

---

# 42. Step 31 — Give GitHub access to Terraform state

GitHub must also read/write Terraform's Blob state.

Run:

```bash
az role assignment create \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$TFSTATE_STORAGE_ID"
```

## Why a second role?

These are two different permission planes.

```text
Contributor
→ Azure management plane

Storage Blob Data Contributor
→ Storage Blob data plane
```

Terraform needs both:

```text
Create Azure resources
+
Read/write Terraform state
```

---

# 43. Step 32 — Verify GitHub state permissions

Run:

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "$TFSTATE_STORAGE_ID" \
  --query "[].{Role:roleDefinitionName,Scope:scope}" \
  -o table
```

Expected:

```text
Storage Blob Data Contributor
```

---

# 44. Stop Gate 4

Before configuring workflows:

```text
[ ] Entra app exists
[ ] Service Principal exists
[ ] Federated credential exists
[ ] Federation points to correct GitHub repository
[ ] Federation entity is the GitHub `dev` environment
[ ] GitHub identity has Contributor
[ ] GitHub identity has Storage Blob Data Contributor on tfstate
```

---

# 45. Step 33 — Configure GitHub Environment settings

Go to:

```text
GitHub
→ Repository
→ Settings
→ Environments
→ mqgen-github-terraform-dev
```

Recommended storage:

## GitHub Environment Variables

Use Environment Variables for non-secret identifiers and backend configuration:

```text
AZURE_CLIENT_ID
AZURE_TENANT_ID
AZURE_SUBSCRIPTION_ID
TFSTATE_RESOURCE_GROUP
TFSTATE_STORAGE_ACCOUNT
TFSTATE_CONTAINER
```

There is still **no**:

```text
AZURE_CLIENT_SECRET
```

Use GitHub Environment Secrets only for values that are actually secret.

Backend configuration:

```text
TFSTATE_RESOURCE_GROUP
TFSTATE_STORAGE_ACCOUNT
TFSTATE_CONTAINER
```

Example:

```text
TFSTATE_RESOURCE_GROUP = mqgen-tfstate-rg
TFSTATE_STORAGE_ACCOUNT = <actual globally unique storage account name>
TFSTATE_CONTAINER = tfstate
```

---

# 46. Step 34 — Create a minimal GitHub OIDC test workflow

Before involving Terraform, test Azure authentication independently.

Create:

```text
.github/workflows/test-azure-oidc.yml
```

```yaml
name: Test Azure OIDC

on:
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

jobs:
  test:
    runs-on: ubuntu-latest

    environment: dev

    steps:
      - name: Login to Azure with GitHub OIDC
        uses: azure/login@v3
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      - name: Verify Azure subscription
        run: |
          az account show \
            --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
            -o table
```

## Why test OIDC separately?

If this workflow fails:

```text
Problem = identity/federation/RBAC
```

not:

```text
Terraform syntax
Terraform provider
Terraform backend
Databricks configuration
```

This isolates failures.

---

# 47. Step 35 — Run the OIDC test

Push the test workflow to GitHub.

Then:

```text
GitHub
→ Actions
→ Test Azure OIDC
→ Run workflow
```

Expected steps:

```text
Login to Azure with GitHub OIDC    ✓
Verify Azure subscription          ✓
```

The subscription should be:

```text
<AZURE_SUBSCRIPTION_NAME>
<AZURE_SUBSCRIPTION_ID>
```

Do not begin Terraform deployment troubleshooting until this test succeeds.

---

# 48. Troubleshooting OIDC — no matching federated identity

Typical error family:

```text
AADSTS700213
No matching federated identity record found
```

Check:

1. Correct Entra application Client ID.
2. Correct tenant ID.
3. Correct subscription ID.
4. Federated credential points to the correct GitHub owner/repository.
5. Workflow uses:

```yaml
environment: dev
```

6. Federated credential entity is also:

```text
Environment = dev
```

7. Workflow has:

```yaml
permissions:
  id-token: write
```

8. Repository OIDC subject behavior matches the configured federated credential.

---

# 49. Troubleshooting OIDC — insufficient Azure permission

OIDC login can succeed while Terraform later gets:

```text
AuthorizationFailed
```

That means:

```text
Authentication succeeded
but
Authorization failed
```

Check GitHub identity role:

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>" \
  -o table
```

You should see:

```text
Contributor
```

---

# 50. Troubleshooting backend — cannot read/write Terraform state

If Terraform initialization reaches Azure but fails on Blob access, check:

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "$TFSTATE_STORAGE_ID" \
  -o table
```

Required:

```text
Storage Blob Data Contributor
```

Then test the container separately with an appropriately authenticated principal.

---

# 51. Step 36 — Terraform backend configuration

Example:

```hcl
terraform {
  backend "azurerm" {
    use_oidc         = true
    use_azuread_auth = true

    key = "dev.terraform.tfstate"
  }
}
```

## Explanation

### `use_oidc = true`

Terraform should use workload identity federation/OIDC.

### `use_azuread_auth = true`

Terraform authenticates to Azure Blob Storage using Microsoft Entra ID rather than Storage Account keys.

### `key`

```text
mqgen/databricks/dev.tfstate
```

is the blob name/path containing this Terraform stack's state.

---

# 52. Step 37 — GitHub Terraform environment variables

A dev Terraform deployment job can expose:

```yaml
env:
  ARM_USE_OIDC: "true"
  ARM_USE_AZUREAD: "true"

  ARM_CLIENT_ID: ${{ vars.AZURE_CLIENT_ID }}
  ARM_TENANT_ID: ${{ vars.AZURE_TENANT_ID }}
  ARM_SUBSCRIPTION_ID: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

HashiCorp's `azurerm` backend supports `ARM_USE_OIDC`, `ARM_USE_AZUREAD`, `ARM_CLIENT_ID`, and `ARM_TENANT_ID`.

The backend values can be passed during initialization:

```bash
terraform init \
  -backend-config="resource_group_name=${TFSTATE_RESOURCE_GROUP}" \
  -backend-config="storage_account_name=${TFSTATE_STORAGE_ACCOUNT}" \
  -backend-config="container_name=${TFSTATE_CONTAINER}"
```

---

# 53. Final bootstrap validation checklist

Run through this before writing or merging the main Azure Databricks deployment.

## Azure context

```text
[ ] az login works
[ ] Correct tenant
[ ] Correct subscription
```

Test:

```bash
az account show -o table
```

## Terraform state Resource Group

```text
[ ] mqgen-tfstate-rg exists
[ ] correct location
[ ] correct tags
```

Test:

```bash
az group show \
  --name "mqgen-tfstate-rg" \
  -o json
```

## Storage Account

```text
[ ] exists
[ ] StorageV2
[ ] Standard_LRS or approved organization SKU
[ ] minimum TLS 1.2
[ ] public Blob access disabled
[ ] correct tags
```

Test:

```bash
az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  -o json
```

## Blob container

```text
[ ] tfstate exists
```

Test:

```bash
az storage container exists \
  --name "tfstate" \
  --account-name "$TFSTATE_STORAGE" \
  --auth-mode login
```

## State protection

```text
[ ] versioning enabled
[ ] soft delete enabled
[ ] retention = 30 days
```

Test:

```bash
az storage account blob-service-properties show \
  --account-name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{
    Versioning:isVersioningEnabled,
    DeleteRetentionEnabled:deleteRetentionPolicy.enabled,
    DeleteRetentionDays:deleteRetentionPolicy.days
  }" \
  -o json
```

## GitHub workload identity

```text
[ ] mqgen-github-terraform-dev application exists
[ ] service principal exists
[ ] federated credential exists
[ ] points to correct repository
[ ] environment = dev
```

## Azure RBAC

GitHub Service Principal:

```text
[ ] Contributor on deployment scope
[ ] Storage Blob Data Contributor on state storage scope
```

## GitHub

```text
[ ] `dev` environment exists
[ ] main is the dev deployment branch
[ ] Azure ID values configured securely
[ ] backend variables configured
[ ] no AZURE_CLIENT_SECRET exists
```

## OIDC

```text
[ ] test-azure-oidc workflow succeeds
[ ] az account show returns correct subscription
```

---

# 54. One-command-style verification section

Use these commands whenever you want to audit the bootstrap foundation.

## Subscription

```bash
az account show \
  --query "{Name:name,SubscriptionId:id,TenantId:tenantId}" \
  -o table
```

## Resource Group

```bash
az group exists \
  --name "mqgen-tfstate-rg"
```

## Storage Account

```bash
az storage account show \
  --name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{Name:name,State:provisioningState,TLS:minimumTlsVersion,PublicBlobAccess:allowBlobPublicAccess}" \
  -o table
```

## Container

```bash
az storage container exists \
  --name "tfstate" \
  --account-name "$TFSTATE_STORAGE" \
  --auth-mode login
```

## Blob protection

```bash
az storage account blob-service-properties show \
  --account-name "$TFSTATE_STORAGE" \
  --resource-group "mqgen-tfstate-rg" \
  --query "{Versioning:isVersioningEnabled,SoftDelete:deleteRetentionPolicy.enabled,RetentionDays:deleteRetentionPolicy.days}" \
  -o table
```

## Entra app

```bash
az ad app list \
  --display-name "mqgen-github-terraform-dev" \
  --query "[].{Name:displayName,ClientId:appId,ObjectId:id}" \
  -o table
```

## Service Principal

```bash
az ad sp show \
  --id "$GITHUB_CLIENT_ID" \
  --query "{Name:displayName,ClientId:appId,ObjectId:id}" \
  -o table
```

## Subscription role

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "/subscriptions/<AZURE_SUBSCRIPTION_ID>" \
  --query "[].{Role:roleDefinitionName,Scope:scope}" \
  -o table
```

## State role

```bash
az role assignment list \
  --assignee-object-id "$GITHUB_SP_OBJECT_ID" \
  --scope "$TFSTATE_STORAGE_ID" \
  --query "[].{Role:roleDefinitionName,Scope:scope}" \
  -o table
```

---

# 55. Error-prevention rules for students

## Rule 1 — Never assume a parent resource exists

Check before creating children.

```text
Resource Group
→ Storage Account
→ Container
→ State Blob
```

---

## Rule 2 — Always verify the active subscription

Before destructive or provisioning commands:

```bash
az account show -o table
```

---

## Rule 3 — Never put secrets into Git

Before committing:

```bash
git status
git diff --cached
```

Never commit:

```text
terraform.tfstate
*.tfplan
.env
.databrickscfg
Azure client secrets
Storage Account keys
SAS tokens
PAT tokens
```

---

## Rule 4 — Understand management plane vs data plane

Being Azure `Contributor` does not automatically mean you can read/write Blob data.

Terraform state needs:

```text
Storage Blob Data Contributor
```

---

## Rule 5 — Test identity before Terraform

Correct sequence:

```text
Test GitHub OIDC
      ↓
Test Azure subscription
      ↓
Test state backend
      ↓
terraform init
      ↓
terraform validate
      ↓
terraform plan
      ↓
terraform apply
```

Not:

```text
Write everything
→ merge
→ debug five unrelated problems together
```

---

## Rule 6 — Do not create a client secret just because authentication failed

OIDC authentication failures should be fixed by checking:

```text
federated credential
repository
environment
subject claim
client ID
tenant ID
id-token permission
Azure RBAC
```

Do not "solve" the problem by inserting a long-lived client secret.

---

## Rule 7 — Separate bootstrap state from application state

Bootstrap:

```text
mqgen-tfstate-rg
```

Application:

```text
mqgen-org-rg
```

Databricks-managed:

```text
mqgen-org-managed-rg
```

Each has a different responsibility.

---

# 56. What happens after this guide is complete?

Once every bootstrap stop gate passes, the next phase is:

```text
VS Code
   |
   v
Terraform files
   |
   v
Feature branch
   |
   v
Pull Request
   |
   +-- terraform fmt
   +-- terraform init -backend=false
   +-- terraform validate
   |
   v
Merge to main
   |
   v
GitHub Actions production workflow
   |
   +-- OIDC login
   +-- terraform init using Azure remote state
   +-- terraform plan
   +-- terraform apply
   |
   v
Azure
```

The first Databricks infrastructure deployment can then create only the initially requested resources:

```text
mqgen-org-rg
├── mqgen-adbx-vnet
│   ├── dbx-private-subnet  10.0.1.0/25
│   └── dbx-public-subnet   10.0.1.128/25
├── NSG
├── NAT Gateway
├── NAT public egress IP
└── mqgen-adbx
    Premium Hybrid/Classic Azure Databricks workspace

mqgen-org-managed-rg
└── Azure Databricks-managed infrastructure
```

VNet:

```text
10.0.1.0/24
```

contains:

```text
256 total IPv4 addresses
```

Each `/25` subnet contains:

```text
128 total addresses
5 Azure-reserved addresses
123 usable addresses
```

---

# 57. Recommended repository location for this guide

Store this file in the repository as:

```text
docs/initial-software-setup/01-azure-terraform-bootstrap-github-oidc-dev.md
```

Then students can begin with this guide before opening the infrastructure Terraform directories.

Suggested documentation flow:

```text
docs/
└── initial-software-setup/
    ├── README.md
    ├── 01-azure-terraform-bootstrap-github-oidc-dev.md
    └── images/
```

---

# 58. Official references

These are the primary references used for the implementation pattern.

- Microsoft Learn — Manage Azure resource groups with Azure CLI
  https://learn.microsoft.com/en-us/cli/azure/manage-azure-groups-azure-cli

- Microsoft Learn — Create an Azure Storage Account
  https://learn.microsoft.com/en-us/azure/storage/common/storage-account-create

- Microsoft Learn — Azure built-in Storage roles (`Storage Blob Data Contributor`)
  https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/storage

- HashiCorp Terraform — `azurerm` backend, Microsoft Entra ID and OIDC
  https://developer.hashicorp.com/terraform/language/backend/azurerm

- GitHub Docs — Configure OpenID Connect in Azure
  https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-azure

- GitHub Docs — OpenID Connect reference
  https://docs.github.com/en/actions/reference/security/oidc

- Azure Login GitHub Action — OIDC authentication
  https://github.com/Azure/login

- Microsoft Entra — Application credentials and workload identity federation
  https://learn.microsoft.com/en-us/entra/identity-platform/how-to-add-credentials

---

# 59. Final learning objective

A student who completes this guide should be able to explain:

1. Why Terraform state is required.
2. Why remote state is better than committing local state.
3. Why state storage is bootstrapped before normal Terraform CI/CD.
4. What an Azure Resource Group does.
5. What a Storage Account and Blob Container do.
6. The difference between Azure management-plane and Blob data-plane permissions.
7. Why `Storage Blob Data Contributor` is needed.
8. What a Microsoft Entra application/service principal represents.
9. How GitHub OIDC eliminates long-lived Azure client secrets.
10. Why Azure `Contributor` and Blob Data Contributor are separate permissions.
11. How to test every resource before moving to the next dependency.
12. How to isolate OIDC, RBAC, backend, and Terraform errors instead of debugging everything at once.

---

# 60. Production runbook — tested bootstrap scenarios and recovery procedures

This section records the bootstrap path that was actually exercised while building the dev Terraform foundation. It is intended for production support, rebuilds, onboarding, and incident recovery.

Status labels used below:

```text
VERIFIED  = command/path was exercised successfully
FIXED     = issue was encountered and corrected
PENDING   = documented next step; not yet validated in the captured session
```

## 60.1 Boundary verification order

Always troubleshoot in this order:

```text
1. GitHub Environment
        |
2. GitHub OIDC -> Microsoft Entra federated trust
        |
3. Azure RBAC + Terraform state access
        |
4. Workflow behavior
        |
5. Terraform init / plan / apply
```

Do not start with Terraform if Azure login itself has not been proven.

---

# 61. Tested scenario — GitHub repository owner lookup returned 404

**Status: FIXED**

### Symptom

A repository API call returned:

```text
404 Not Found
```

Example pattern:

```bash
gh api repos/<WRONG_OWNER>/<REPOSITORY>
```

### Root cause

The repository owner was guessed incorrectly. The local shell username and the GitHub repository owner are not necessarily the same value.

### Fix

Determine the repository owner from Git rather than guessing:

```bash
git remote -v
```

Then query the actual repository:

```bash
gh api repos/<GITHUB_OWNER>/<GITHUB_REPOSITORY> \
  --jq '{
    owner: .owner.login,
    owner_id: .owner.id,
    repository: .name,
    repository_id: .id
  }'
```

### Validation

Confirm all four values are returned:

```text
owner
owner_id
repository
repository_id
```

Use the numeric `owner_id` and `repository_id` in the Azure federated-credential form when Azure requests immutable GitHub IDs.

---

# 62. Tested scenario — `bash: --jq: command not found`

**Status: FIXED**

### Symptom

The GitHub API returned the complete JSON response, followed by:

```text
bash: --jq: command not found
```

### Root cause

A blank line was inserted after a shell continuation character (`\`). Bash treated the `gh api` line as one completed command and then tried to execute `--jq` as a new command.

### Correct command

Use one line when troubleshooting shell continuation problems:

```bash
gh api repos/<GITHUB_OWNER>/<GITHUB_REPOSITORY> --jq '{owner: .owner.login, owner_id: .owner.id, repository: .name, repository_id: .id}'
```

Or use multiline syntax with **no blank line after `\`**:

```bash
gh api repos/<GITHUB_OWNER>/<GITHUB_REPOSITORY> \
  --jq '{
    owner: .owner.login,
    owner_id: .owner.id,
    repository: .name,
    repository_id: .id
  }'
```

---

# 63. Tested scenario — GitHub Environment name vs Entra application name

**Status: FIXED**

These are separate objects and should not be confused:

```text
Microsoft Entra application:
mqgen-github-terraform-dev

GitHub Environment:
dev

Federated credential name:
github-terraform-dev
```

The OIDC trust must reference:

```text
Entity type: Environment
Environment: dev
```

The workflow must also use:

```yaml
environment: dev
```

The Entra application may still be named:

```text
mqgen-github-terraform-dev
```

A dev credential should not have a production description. Keep names, entity type, environment, and description internally consistent.

---

# 64. Tested scenario — GitHub immutable OIDC subject fields

**Status: VERIFIED**

The Azure portal requested both human-readable and immutable GitHub identifiers:

```text
Organization / repository owner
Organization numeric ID
Repository name
Repository numeric ID
Entity type
Environment
```

Retrieve IDs from GitHub API instead of copying guessed values:

```bash
gh api repos/<GITHUB_OWNER>/<GITHUB_REPOSITORY> \
  --jq '{
    owner: .owner.login,
    owner_id: .owner.id,
    repository: .name,
    repository_id: .id
  }'
```

Azure then generates a subject conceptually similar to:

```text
repo:<OWNER>@<OWNER_ID>/<REPOSITORY>@<REPOSITORY_ID>:environment:dev
```

Do not hand-edit the generated subject unless the federation design explicitly requires it.

---

# 65. Tested scenario — Application Client ID, application Object ID, and service-principal Object ID

**Status: VERIFIED**

Three different identifiers appear in Microsoft Entra and must not be interchanged.

```text
Application (client) ID
    -> used by GitHub OIDC / azure/login

Application Object ID
    -> identifies the App Registration object

Service Principal Object ID
    -> used as Azure RBAC principal_id
```

Retrieve the service-principal Object ID from the Application Client ID:

```bash
export AZURE_CLIENT_ID="<APPLICATION_CLIENT_ID>"

az ad sp show \
  --id "$AZURE_CLIENT_ID" \
  --query id \
  --output tsv
```

For Terraform:

```hcl
principal_id = var.github_actions_principal_object_id
```

The value supplied to that variable must match the service-principal Object ID returned by `az ad sp show`.

---

# 66. Tested scenario — Terraform validation failed on `resource_manager_id`

**Status: FIXED**

### Symptom

```text
Error: Unsupported attribute

azurerm_storage_container.tfstate.resource_manager_id
```

### Root cause

The installed AzureRM provider did not export `resource_manager_id` on `azurerm_storage_container`.

### Fix

Use:

```hcl
azurerm_storage_container.tfstate.id
```

Role assignment:

```hcl
resource "azurerm_role_assignment" "github_tfstate" {
  count = var.github_actions_principal_object_id != null ? 1 : 0

  scope                = azurerm_storage_container.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.github_actions_principal_object_id
  principal_type       = "ServicePrincipal"
}
```

Output:

```hcl
output "tfstate_container_id" {
  description = "Azure Resource Manager ID of the Terraform state container."
  value       = azurerm_storage_container.tfstate.id
}
```

### Revalidation

```bash
terraform fmt -recursive
terraform validate
```

Expected:

```text
Success! The configuration is valid.
```

---

# 67. Tested scenario — `terraform state list` returned `No state file was found`

**Status: FIXED / EXPECTED DURING FIRST BOOTSTRAP**

### Symptom

```text
No state file was found!
```

### Explanation

`terraform plan` does not create Terraform state for managed resources. Before the first successful import/apply, an empty bootstrap directory may have no managed state.

Correct lifecycle:

```text
terraform init
        |
terraform validate
        |
terraform plan
        |
import existing resources and/or terraform apply
        |
terraform state list now has managed resources
```

Do not treat an empty state as an Azure RBAC failure.

---

# 68. Tested scenario — `TFSTATE_CONTAINER_ID` was empty

**Status: FIXED**

### Symptom

```bash
echo "$TFSTATE_CONTAINER_ID"
```

returned nothing, and Azure CLI then failed with:

```text
--scope can't be an empty string
```

### Root cause

The shell variable was populated before Terraform state contained the container output.

### Fix

After the container exists in Terraform state:

```bash
export TFSTATE_CONTAINER_ID="$(terraform output -raw tfstate_container_id)"
```

Validate before using it:

```bash
if [ -z "$TFSTATE_CONTAINER_ID" ]; then
  echo "ERROR: TFSTATE_CONTAINER_ID is empty"
  exit 1
fi

echo "$TFSTATE_CONTAINER_ID"
```

Then run the RBAC query.

---

# 69. Tested scenario — Resource Group already existed

**Status: FIXED BY IMPORT**

### Symptom

`terraform apply` failed with:

```text
a resource with the ID .../resourceGroups/mqgen-tfstate-rg already exists
```

### Root cause

The Azure Resource Group existed, but the local Terraform bootstrap state did not know about it.

### Correct recovery

Do **not** delete the Resource Group.

Import it:

```bash
export AZURE_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

terraform import \
  azurerm_resource_group.tfstate \
  "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/mqgen-tfstate-rg"
```

Validate:

```bash
terraform state list
terraform state show azurerm_resource_group.tfstate
```

Delete any plan generated before the import:

```bash
rm -f tfplan
```

Generate a new plan:

```bash
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
```

Never apply a saved plan created before an import or material configuration change.

---

# 70. Tested scenario — Terraform state Storage Account already existed

**Status: FIXED BY IMPORT**

### Discovery command

```bash
az storage account list \
  --resource-group "mqgen-tfstate-rg" \
  --query "[].{Name:name,Location:location,SKU:sku.name}" \
  --output table
```

An existing state Storage Account was discovered.

### Risk

The bootstrap code originally generated another globally unique Storage Account name. Applying that plan would have created a second backend instead of adopting the existing backend.

### Fix 1 — stop generating the name

Use a variable:

```hcl
variable "tfstate_storage_account_name" {
  description = "Name of the existing Azure Storage Account used for Terraform remote state."
  type        = string
}
```

Storage resource:

```hcl
name = var.tfstate_storage_account_name
```

### Fix 2 — keep the real value local

Create local-only:

```text
infra/bootstrap/terraform.tfvars
```

Example:

```hcl
location                     = "eastus"
tfstate_resource_group_name  = "mqgen-tfstate-rg"
tfstate_storage_account_name = "<TFSTATE_STORAGE_ACCOUNT>"
tfstate_container_name       = "tfstate"
```

Do not commit the real `terraform.tfvars`.

Committed example:

```hcl
tfstate_storage_account_name = "<TFSTATE_STORAGE_ACCOUNT_NAME>"
```

### Fix 3 — import the existing account

```bash
terraform import \
  azurerm_storage_account.tfstate \
  "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/mqgen-tfstate-rg/providers/Microsoft.Storage/storageAccounts/<TFSTATE_STORAGE_ACCOUNT>"
```

Validate:

```bash
terraform state list
```

Expected to include:

```text
azurerm_resource_group.tfstate
azurerm_storage_account.tfstate
```

---

# 71. Tested scenario — existing `tfstate` Blob container

**Status: FIXED BY IMPORT**

Check before creating anything:

```bash
az storage container list \
  --account-name "<TFSTATE_STORAGE_ACCOUNT>" \
  --auth-mode login \
  --query "[].name" \
  --output table
```

If `tfstate` already exists, import it:

```bash
terraform import \
  azurerm_storage_container.tfstate \
  "/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/mqgen-tfstate-rg/providers/Microsoft.Storage/storageAccounts/<TFSTATE_STORAGE_ACCOUNT>/blobServices/default/containers/tfstate"
```

Do not attempt to create a duplicate container.

---

# 72. Tested scenario — imported Resource Group tags would be overwritten

**Status: FIXED**

### Symptom in plan

Terraform proposed removing existing organization/cost-management tags and replacing them with only the bootstrap tags.

### Production decision

For an existing Resource Group whose tags are governed externally, do not let this bootstrap stack take ownership of those tags.

Use:

```hcl
resource "azurerm_resource_group" "tfstate" {
  name     = var.tfstate_resource_group_name
  location = var.location

  lifecycle {
    prevent_destroy = true

    ignore_changes = [
      tags
    ]
  }
}
```

Use the same pattern on the imported Storage Account if its tags are managed by an organizational tagging process:

```hcl
lifecycle {
  prevent_destroy = true

  ignore_changes = [
    tags
  ]
}
```

Do not use `ignore_changes` merely to hide unexplained drift. Use it only when ownership is intentionally external.

---

# 73. Tested scenario — plan attempted to reduce retention from 30 days to 14 days

**Status: FIXED**

### Symptom

The imported Storage Account had a 30-day delete-retention policy. Terraform code proposed:

```text
30 -> 14 days
```

### Decision

Do not reduce the existing recovery window during adoption.

Use:

```hcl
blob_properties {
  versioning_enabled = true

  delete_retention_policy {
    days = 30
  }

  container_delete_retention_policy {
    days = 30
  }
}
```

After the imported resource matches the desired production policy, future changes should be reviewed as intentional configuration changes.

---

# 74. Tested scenario — dangerous Storage Account replacement prevention

**Status: VERIFIED AS A STOP-GATE RULE**

After importing an existing state Storage Account, regenerate the plan and inspect it before applying.

Safe patterns:

```text
~ update in-place
+ role assignment
+ container only if it genuinely does not exist
```

Stop immediately if the plan contains:

```text
+ azurerm_storage_account.tfstate will be created
```

or:

```text
-/+ azurerm_storage_account.tfstate must be replaced
```

A Terraform state backend is critical infrastructure. Never approve replacement casually.

Use:

```hcl
lifecycle {
  prevent_destroy = true
}
```

for the state Resource Group, Storage Account, and state container.

---

# 75. Tested scenario — successful bootstrap reconciliation

**Status: VERIFIED**

After imports and configuration corrections, the safe plan became conceptually:

```text
1 to add
1 to change in-place
0 to destroy
```

The apply successfully:

1. updated the imported Storage Account in place;
2. created the GitHub state-container role assignment;
3. destroyed nothing.

Validation after apply:

```bash
terraform state list
```

Expected resources:

```text
data.azurerm_client_config.current
azurerm_resource_group.tfstate
azurerm_role_assignment.github_tfstate[0]
azurerm_storage_account.tfstate
azurerm_storage_container.tfstate
```

Outputs:

```bash
terraform output
```

Expected output names:

```text
tfstate_container_id
tfstate_container_name
tfstate_resource_group_name
tfstate_storage_account_name
```

---

# 76. Tested scenario — verify the RBAC principal before trusting the plan

**Status: VERIFIED**

Retrieve the service-principal Object ID:

```bash
export SP_OBJECT_ID="$(az ad sp show \
  --id "$AZURE_CLIENT_ID" \
  --query id \
  --output tsv)"
```

Compare that value with the `principal_id` shown in `terraform plan`.

They must match.

Then verify the role assignment after apply:

```bash
export TFSTATE_CONTAINER_ID="$(terraform output -raw tfstate_container_id)"

az role assignment list \
  --assignee-object-id "$SP_OBJECT_ID" \
  --scope "$TFSTATE_CONTAINER_ID" \
  --query "[].{Role:roleDefinitionName,Scope:scope}" \
  --output table
```

Expected role:

```text
Storage Blob Data Contributor
```

Expected scope:

```text
.../blobServices/default/containers/tfstate
```

This is a data-plane role. Do not confuse it with Azure management-plane `Contributor`.

---

# 77. Tested scenario — Git ignore policy for Terraform

**Status: VERIFIED**

The following local files were intentionally ignored:

```gitignore
# macOS
.DS_Store

# Terraform working directories
**/.terraform/*

# Terraform state
*.tfstate
*.tfstate.*

# Terraform plan files
*.tfplan
tfplan

# Local Terraform variable files
*.tfvars
*.tfvars.json

# Local environment files
.env
.env.*

# Private keys / certificates
*.pem
*.key
*.pfx

# Terraform crash logs
crash.log
crash.*.log

# Terraform CLI configuration
.terraformrc
terraform.rc
```

Do **not** ignore:

```text
.terraform.lock.hcl
```

The lock file should normally be committed so that local runs and CI use reproducible provider selections.

Verification:

```bash
git status --short --ignored
```

Expected local-only Terraform artifacts should appear with:

```text
!!
```

for example:

```text
!! infra/bootstrap/.terraform/
!! infra/bootstrap/terraform.tfstate
!! infra/bootstrap/terraform.tfstate.backup
!! infra/bootstrap/terraform.tfvars
!! infra/bootstrap/tfplan
```

---

# 78. Tested scenario — staging only safe Terraform files

**Status: VERIFIED**

Before commit:

```bash
git status --short --untracked-files=all infra
```

Files that should normally be committed:

```text
infra/bootstrap/.terraform.lock.hcl
infra/bootstrap/backend.tf
infra/bootstrap/main.tf
infra/bootstrap/outputs.tf
infra/bootstrap/providers.tf
infra/bootstrap/terraform.tfvars.example
infra/bootstrap/variables.tf
infra/bootstrap/versions.tf
```

Files that must remain local:

```text
infra/bootstrap/terraform.tfvars
infra/bootstrap/terraform.tfstate
infra/bootstrap/terraform.tfstate.backup
infra/bootstrap/tfplan
infra/bootstrap/.terraform/
```

Stage deliberately:

```bash
git add .gitignore
git add docs/01-azure-terraform-bootstrap-github-oidc-dev.md
git add infra/bootstrap
```

Then verify exactly what is staged:

```bash
git diff --cached --name-only
```

---

# 79. Tested scenario — secret scan produced documentation false positives

**Status: VERIFIED**

A staged-content scan such as:

```bash
git grep --cached -n -I -E \
'client[_-]?secret|password|access[_-]?token|sas[_-]?token|private[_-]?key|storage.*key'
```

may match safe documentation statements such as:

```text
Do not store passwords
AZURE_CLIENT_SECRET is not required
Do not use Storage Account keys
```

These are not leaked secrets.

Review each match semantically.

Unsafe examples would look like:

```text
client_secret = "<real-secret>"
password = "<real-password>"
STORAGE_ACCOUNT_KEY=<REDACTED>
sig=<real-sas-signature>
GITHUB_TOKEN=<REDACTED>
```

Never commit actual values.

---

# 80. Tested scenario — `git diff --cached --check` found trailing whitespace

**Status: FIXED**

### Symptom

```text
trailing whitespace.
```

### Fix

Remove trailing spaces from the reported Markdown lines and restage the file.

A safe general cleanup for Markdown/Terraform source before commit is:

```bash
python - <<'PYEOF'
from pathlib import Path
p = Path('docs/01-azure-terraform-bootstrap-github-oidc-dev.md')
lines = p.read_text(encoding='utf-8').splitlines()
p.write_text('\n'.join(line.rstrip() for line in lines) + '\n', encoding='utf-8')
PYEOF

git add docs/01-azure-terraform-bootstrap-github-oidc-dev.md
git diff --cached --check
```

Expected result:

```text
<no output>
```

---

# 81. Production pre-commit stop gate

Do not commit until every item is true:

```text
[ ] terraform fmt -recursive passes
[ ] terraform validate passes
[ ] latest terraform plan has been reviewed
[ ] no Storage Account create/replacement is unexpected
[ ] no destroy actions are unexpected
[ ] service-principal Object ID matches Terraform principal_id
[ ] state role is scoped intentionally
[ ] terraform.tfvars is ignored
[ ] terraform.tfstate files are ignored
[ ] tfplan is ignored
[ ] .terraform/ is ignored
[ ] .terraform.lock.hcl is staged
[ ] secret scan has been reviewed
[ ] git diff --cached --check returns no output
```

Recommended commands:

```bash
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan

git status --short --ignored
git diff --cached --name-only
git grep --cached -n -I -E \
'client[_-]?secret|password|access[_-]?token|sas[_-]?token|private[_-]?key|storage.*key'
git diff --cached --check
```

---

# 82. Pending next step — migrate bootstrap state to Azure Blob

**Status: PENDING in the captured implementation session**

Do not mark this VERIFIED until the remote blob has been confirmed.

Create/keep:

```hcl
terraform {
  backend "azurerm" {}
}
```

Verify the current Azure CLI identity can access the container:

```bash
az storage blob list \
  --account-name "<TFSTATE_STORAGE_ACCOUNT>" \
  --container-name "tfstate" \
  --auth-mode login \
  --query "[].name" \
  --output table
```

Then migrate:

```bash
terraform init -migrate-state \
  -backend-config="resource_group_name=mqgen-tfstate-rg" \
  -backend-config="storage_account_name=<TFSTATE_STORAGE_ACCOUNT>" \
  -backend-config="container_name=tfstate" \
  -backend-config="key=bootstrap.terraform.tfstate" \
  -backend-config="use_azuread_auth=true" \
  -backend-config="use_cli=true"
```

If prompted to copy the existing state, review the backend details and answer `yes`.

Verify afterward:

```bash
terraform state list

az storage blob list \
  --account-name "<TFSTATE_STORAGE_ACCOUNT>" \
  --container-name "tfstate" \
  --auth-mode login \
  --query "[].{StateFile:name,Size:properties.contentLength}" \
  --output table
```

Expected remote key:

```text
bootstrap.terraform.tfstate
```

Do not delete local backup state until the remote backend has been verified and recovery expectations are understood.

---

# 83. Pending next step — GitHub OIDC dry authentication test

**Status: PENDING in the captured implementation session**

Before running Terraform from GitHub, test only:

```text
GitHub Environment: dev
        |
OIDC token
        |
Microsoft Entra federated credential
        |
Azure login
        |
Blob state access
```

Required workflow permissions:

```yaml
permissions:
  contents: read
  id-token: write
```

Job:

```yaml
environment: dev
```

Login:

```yaml
- name: Login to Azure using OIDC
  uses: azure/login@v2
  with:
    client-id: ${{ vars.AZURE_CLIENT_ID }}
    tenant-id: ${{ vars.AZURE_TENANT_ID }}
    subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}
```

State-access test:

```yaml
- name: Verify Terraform state access
  run: |
    az storage blob list \
      --account-name "${{ vars.TFSTATE_STORAGE_ACCOUNT }}" \
      --container-name "${{ vars.TFSTATE_CONTAINER }}" \
      --auth-mode login \
      --query "[].name" \
      --output table
```

Do not add Terraform deployment logic until this dry test passes.

---

# 84. Pending next step — real dev deployment workflow

**Status: PENDING in the captured implementation session**

Only after remote state and OIDC dry authentication are proven should the dev workload stack be enabled.

Recommended behavior:

```text
Pull Request
    -> terraform fmt
    -> terraform validate
    -> terraform plan where the authentication model allows it

Merge to main
    -> GitHub Environment: dev
    -> OIDC login
    -> terraform init against dev.terraform.tfstate
    -> terraform plan
    -> terraform apply
```

Keep bootstrap state and workload state separate:

```text
tfstate/
├── bootstrap.terraform.tfstate
└── dev.terraform.tfstate
```

---

# 85. Troubleshooting matrix

| Failure | Most likely boundary | First check |
|---|---|---|
| GitHub environment job is blocked | GitHub Environment | Environment name and deployment branch policy |
| Azure Login reports no matching federated identity | OIDC trust | Repository owner/ID, repository ID, entity type, `environment: dev`, issuer, audience |
| Azure Login succeeds but Blob list fails | Azure RBAC / Storage data plane | `Storage Blob Data Contributor` on the state container and storage networking |
| `--scope can't be an empty string` | Local shell / Terraform output | Re-populate and validate `TFSTATE_CONTAINER_ID` |
| `terraform state list` says no state | Terraform bootstrap state | Import/apply has not yet created managed state |
| Existing Resource Group error | Terraform ownership | Import the Resource Group; do not recreate it |
| Terraform proposes another state Storage Account | Terraform configuration/import | Use existing account variable and import the account |
| Terraform proposes Storage Account replacement | High-risk configuration drift | Stop; inspect ForceNew property differences before apply |
| Plan removes organization tags | Ownership boundary | Preserve externally managed tags or explicitly adopt ownership |
| Plan reduces retention | Policy drift | Keep/raise approved recovery window unless change is intentional |
| `resource_manager_id` unsupported | Provider schema | Use `azurerm_storage_container.<name>.id` |
| `bash: --jq: command not found` | Shell syntax | Remove blank line after `\` or use one-line command |
| Git staged secret scan finds words like `password` | Documentation review | Confirm matches are prose/placeholders, not values |
| `git diff --cached --check` reports whitespace | Git quality gate | Remove trailing whitespace, restage, rerun |

---

# 86. Operational rollback principle

For the Terraform backend, prefer **reconciliation and import** over delete/recreate operations.

If a production plan unexpectedly proposes destruction of:

```text
Terraform state Resource Group
Terraform state Storage Account
Terraform state Blob container
```

stop the deployment.

Do not use `-auto-approve` to bypass an unexplained backend plan.

Collect:

```bash
terraform state list
terraform state show <resource-address>
terraform plan
az resource show ...
az role assignment list ...
```

Then determine whether the problem is:

```text
state ownership
configuration drift
provider schema change
RBAC
networking
or an intentional infrastructure change
```

The state backend is a control-plane dependency for all later Terraform deployments and should be treated as protected infrastructure.
