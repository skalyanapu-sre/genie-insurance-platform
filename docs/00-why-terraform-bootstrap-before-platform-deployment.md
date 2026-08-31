# Why Terraform Bootstrap, GitHub OIDC, and Azure State Must Be Built First

## Purpose

This document explains why the Terraform bootstrap foundation is created **before** deploying the actual Azure Databricks platform.

The bootstrap layer establishes the controls required for safe, repeatable, auditable, and automated infrastructure deployment.

Before creating resources such as:

- Azure Virtual Networks
- Databricks public and private subnets
- Network Security Groups
- NAT Gateway
- Azure Databricks workspace
- ADLS Gen2
- Key Vault
- Unity Catalog resources
- Databricks compute
- CI/CD-managed platform resources

we first establish:

1. Who is allowed to deploy?
2. How does GitHub authenticate to Azure without passwords?
3. What permissions does the deployment identity receive?
4. Where is Terraform state stored?
5. How do engineers and GitHub Actions share the same state?
6. How do we prevent accidental recreation or destruction?
7. How do we validate infrastructure before production deployment?
8. How do we troubleshoot and recover when something fails?

---

# 1. High-Level Architecture

```text
Developer Mac
     |
     | git push
     v
GitHub Repository
genie-insurance-platform
     |
     +------------------------------+
     |                              |
     v                              v
GitHub Environment             Terraform Code
dev                            infra/bootstrap/
     |
     | GitHub OIDC
     v
Microsoft Entra ID
     |
     v
Dedicated Automation Application
mqgen-github-terraform-dev
     |
     v
Service Principal
     |
     | Azure RBAC
     v
Azure
     |
     v
mqgen-tfstate-rg
     |
     v
Terraform State Storage Account
     |
     v
tfstate Blob Container
     |
     +-- bootstrap.terraform.tfstate
     |
     +-- dev.terraform.tfstate        # later
```

The actual application platform is created only after this foundation is validated.

---

# 2. Why We Need a GitHub Environment

A GitHub Environment creates a deployment boundary.

```text
GitHub Repository
     |
     +-- dev
     +-- test
     +-- prod
```

Each environment can have its own:

- Azure subscription
- Azure identity
- environment variables
- deployment approvals
- branch restrictions
- environment secrets
- deployment history

## Use Case

Development and production should not use the same unrestricted deployment configuration.

```text
dev
  |
  +-- Development subscription
  +-- Development identity
  +-- Development state

prod
  |
  +-- Production subscription
  +-- Production identity
  +-- Production state
  +-- Required approvers
```

A GitHub Environment answers:

> **Where is this workflow allowed to deploy?**

For this project, the current development deployment boundary is:

```text
dev
```

---

# 3. Why We Need a Dedicated Microsoft Entra Application

GitHub Actions is an automated workload, not a human user.

It should not authenticate to Azure with:

```text
Developer username
Developer password
Developer MFA session
Personal Azure credentials
```

Instead, GitHub Actions receives its own workload identity.

```text
Human Engineer
     |
     v
Personal Microsoft Entra Identity


GitHub Actions
     |
     v
Dedicated Microsoft Entra Application
```

For this project:

```text
mqgen-github-terraform-dev
```

is the automation identity.

## Use Case

If a pipeline uses an employee account:

```text
Employee account disabled
          |
          v
CI/CD deployment stops
```

With a dedicated automation identity:

```text
Employee account changes
          |
          X
          |
GitHub automation identity continues
```

The Entra application answers:

> **Who is GitHub Actions when it talks to Azure?**

---

# 4. App Registration vs Service Principal

These Azure concepts are related but serve different purposes.

## App Registration

The App Registration defines the application identity.

It includes values such as:

```text
Application (client) ID
Application Object ID
Tenant ID
Federated credentials
```

## Service Principal

The Service Principal represents the application inside the Microsoft Entra tenant and is the object to which Azure RBAC permissions are assigned.

```text
App Registration
       |
       | defines identity
       v
Service Principal
       |
       | receives Azure RBAC
       v
Azure Resources
```

## Important Terraform Rule

When Terraform creates an Azure RBAC role assignment:

```hcl
principal_id = ...
```

the value must be the:

```text
Service Principal Object ID
```

not the:

```text
App Registration Object ID
```

Both values look like GUIDs, but they represent different objects.

---

# 5. Why We Use GitHub OIDC

Traditional Azure CI/CD authentication often uses:

```text
AZURE_CLIENT_ID
AZURE_CLIENT_SECRET
AZURE_TENANT_ID
```

The problem is the client secret.

A client secret:

- expires
- must be rotated
- must be stored
- can be copied
- can leak into logs
- can leak into Git
- creates operational overhead

This project uses **OpenID Connect workload identity federation** instead.

```text
GitHub Actions Job
       |
       | requests short-lived OIDC token
       v
GitHub OIDC Provider
       |
       v
Microsoft Entra ID
       |
       | validates federated trust
       v
Short-Lived Azure Access Token
       |
       v
Terraform / Azure CLI
```

There is no long-lived Azure client secret stored in GitHub.

OIDC answers:

> **How does GitHub securely prove its identity to Azure?**

---

# 6. Why We Need a Federated Credential

Creating an Entra application does not automatically make GitHub trusted.

A federated credential defines the trust relationship.

Conceptually:

```text
Microsoft Entra:

Trust GitHub OIDC tokens

ONLY when:

Repository = approved repository
Environment = dev
Audience = AzureADTokenExchange
```

At runtime:

```text
GitHub:
"I am repository X running environment dev."

          |
          v

Microsoft Entra:
"Does a configured federated credential allow this subject?"

          |
     +----+----+
     |         |
    YES        NO
     |         |
     v         v
Issue token   Deny
```

The federated credential answers:

> **Which GitHub workload is allowed to use this Azure identity?**

---

# 7. Authentication vs Authorization

Authentication answers:

> **Who are you?**

Authorization answers:

> **What are you allowed to do?**

GitHub OIDC handles authentication.

Azure RBAC handles authorization.

```text
GitHub OIDC
     |
     v
Identity Verified
     |
     v
Azure RBAC
     |
     v
Allowed Actions Determined
```

Successful authentication does not automatically grant permission to every Azure resource.

---

# 8. Why We Need Azure RBAC

Azure RBAC assigns:

```text
WHO
+
WHAT ROLE
+
WHAT SCOPE
```

For Terraform state access:

```text
WHO:
GitHub Terraform Service Principal

ROLE:
Storage Blob Data Contributor

SCOPE:
tfstate Blob Container
```

This supports the **principle of least privilege**.

## Why Not Give Owner?

`Owner` is significantly broader than required.

The preferred pattern is:

```text
Minimum required role
+
Minimum required scope
```

---

# 9. Why We Need a Dedicated Terraform State Resource Group

Terraform state infrastructure should have a different lifecycle from application infrastructure.

```text
Bootstrap Resource Group
mqgen-tfstate-rg
     |
     +-- Terraform state Storage Account
     +-- tfstate container
     +-- state-related RBAC
```

Later:

```text
Application Resource Group
     |
     +-- VNet
     +-- Subnets
     +-- NSGs
     +-- NAT Gateway
     +-- Databricks
     +-- ADLS
     +-- Key Vault
```

Separating them provides:

- clearer ownership
- safer lifecycle boundaries
- easier recovery
- reduced blast radius
- cleaner operations

---

# 10. Why Terraform Needs State

Terraform is declarative.

You write what should exist:

```hcl
resource "azurerm_resource_group" "example" {
  name     = "example-rg"
  location = "eastus"
}
```

Terraform must remember which real Azure resource corresponds to that logical Terraform address.

```text
Terraform Resource Address
        |
        v
Terraform State
        |
        v
Azure Resource ID
```

Without state, Terraform cannot reliably know what it already manages.

---

# 11. Why Local Terraform State Is Not Enough

Local state may be acceptable for initial bootstrap work.

It is not appropriate as the permanent team backend.

```text
Engineer A Mac
  |
  +-- terraform.tfstate A

Engineer B Mac
  |
  +-- terraform.tfstate B

GitHub Runner
  |
  +-- separate execution context
```

This can cause:

- inconsistent state
- duplicate resource creation attempts
- conflicting plans
- accidental destruction
- poor collaboration
- difficult recovery

With remote state:

```text
Engineer A --------\
                    \
Engineer B ----------> Azure Blob Terraform State
                    /
GitHub Actions -----/
```

Everyone uses one authoritative state.

---

# 12. Why We Use Azure Blob Storage for Terraform State

Azure Blob Storage provides a centralized Terraform backend.

```text
Storage Account
     |
     v
tfstate Container
     |
     +-- bootstrap.terraform.tfstate
     +-- dev.terraform.tfstate
     +-- test.terraform.tfstate
     +-- prod.terraform.tfstate
```

Benefits include:

- shared state
- durable storage
- centralized access control
- Azure RBAC integration
- backend locking behavior
- versioning and retention options
- recovery capability

---

# 13. Why We Need a Blob Container

The Storage Account is the storage service.

The container is the logical location for Terraform state blobs.

```text
Storage Account
     |
     v
Container: tfstate
     |
     +-- bootstrap.terraform.tfstate
     +-- dev.terraform.tfstate
```

RBAC can also be scoped specifically to this container.

---

# 14. Why Bootstrap State and DEV State Should Be Separate

The bootstrap stack manages infrastructure Terraform itself depends on.

```text
bootstrap.terraform.tfstate
```

typically tracks:

- Terraform state Resource Group
- Terraform state Storage Account
- Blob Container
- state-access RBAC

The application stack:

```text
dev.terraform.tfstate
```

later tracks:

- development Resource Groups
- VNet
- Databricks subnets
- NSGs
- NAT Gateway
- Azure Databricks workspace
- other development resources

```text
BOOTSTRAP
   |
   +-- state infrastructure

DEV
   |
   +-- application platform
```

This creates safer lifecycle separation.

---

# 15. Why Bootstrap Initially Uses Local State

There is a dependency problem:

```text
Terraform remote backend
       |
       requires
       v
Storage Account + Blob Container
```

But Terraform is also intended to manage those resources.

Therefore:

```text
Step 1
Use local Terraform state

       |
       v

Step 2
Create or adopt backend resources

       |
       v

Step 3
Configure backend.tf

       |
       v

Step 4
Migrate state to Azure Blob

       |
       v

Step 5
Use Azure Blob as authoritative state
```

This resolves the bootstrap dependency cleanly.

---

# 16. Why We Import Existing Azure Resources

A resource may already exist in Azure before Terraform manages it.

```text
Azure:
Resource exists

Terraform State:
Resource is absent
```

Terraform can then incorrectly plan:

```text
+ create
```

The correct approach is to import/adopt the existing resource so that:

```text
Terraform Configuration
          |
          v
Terraform State
          |
          v
Existing Azure Resource
```

all refer to the same infrastructure object.

This is a common enterprise migration scenario.

---

# 17. Why We Use `terraform state list`

```bash
terraform state list
```

shows the resources Terraform currently believes it manages.

Example:

```text
azurerm_resource_group.tfstate
azurerm_storage_account.tfstate
azurerm_storage_container.tfstate
azurerm_role_assignment.github_tfstate[0]
```

Use it to answer:

- Did import work?
- Did backend migration preserve the state?
- Does Terraform still track the expected resources?
- Is anything missing from state?

---

# 18. Why We Run `terraform validate`

```bash
terraform validate
```

checks whether the Terraform configuration is structurally valid.

It catches problems such as:

- undeclared variables
- invalid references
- unsupported arguments
- malformed HCL
- provider schema errors

Expected:

```text
Success! The configuration is valid.
```

---

# 19. Why We Run `terraform plan`

`terraform plan` compares:

```text
Terraform Configuration
         |
         v
Terraform State
         |
         v
Actual Azure Infrastructure
```

Common indicators:

```text
+   create
~   update in place
-   destroy
-/+ replace
```

The ideal stable result is:

```text
No changes. Your infrastructure matches the configuration.
```

or:

```text
Plan: 0 to add, 0 to change, 0 to destroy.
```

That means:

```text
Code
=
State
=
Azure
```

A surprise `-/+ replace` on critical infrastructure such as the Terraform state Storage Account is a stop condition and should be investigated before applying.

---

# 20. Why We Validate With Azure CLI

Terraform gives Terraform's view.

Azure CLI gives Azure's direct view.

```text
Terraform View
      |
      +------ must agree ------+
                               |
Azure CLI View ----------------+
```

CLI validation is useful for:

- existence checks
- provisioning state
- role assignments
- Storage Account settings
- Blob state
- Entra identity details
- repeatable troubleshooting

---

# 21. Why We Also Validate in Azure Portal

Azure Portal provides visual confirmation of:

- resource hierarchy
- IAM assignments
- Storage Account configuration
- networking
- Blob containers
- federated credentials
- Entra applications
- Enterprise Applications

CLI is best for repeatability and automation.

Portal is useful for visual operations and manual troubleshooting.

Production engineers should know both.

---

# 22. Why `.terraform.lock.hcl` Is Committed

Terraform providers are software dependencies.

Without a lock file:

```text
Developer Mac
  |
  +-- provider version A

GitHub Actions
  |
  +-- provider version B
```

Different versions can behave differently.

Commit:

```text
.terraform.lock.hcl
```

Do not commit:

```text
.terraform/
```

The lock file supports reproducible provider selection.

---

# 23. Why `terraform.tfvars` Is Ignored

A local `terraform.tfvars` file commonly contains environment-specific values.

Use:

```text
terraform.tfvars
```

for local values.

Commit:

```text
terraform.tfvars.example
```

with placeholders.

Example:

```hcl
location                     = "eastus"
tfstate_resource_group_name  = "mqgen-tfstate-rg"
tfstate_storage_account_name = "<TFSTATE_STORAGE_ACCOUNT_NAME>"
tfstate_container_name       = "tfstate"
```

This documents required variables without exposing environment-specific values.

---

# 24. Why Terraform State Is Ignored by Git

Do not commit:

```text
terraform.tfstate
terraform.tfstate.backup
*.tfstate
*.tfstate.*
```

State can contain:

- resource IDs
- infrastructure metadata
- outputs
- provider information
- potentially sensitive values

Use:

```text
Git
→ Terraform source code

Azure Blob
→ Terraform state
```

---

# 25. Why `.terraform/` Is Ignored

Terraform generates:

```text
.terraform/
```

during:

```bash
terraform init
```

It contains local working data and should be recreated on each workstation or CI runner.

Therefore:

```text
IGNORE:
.terraform/
```

---

# 26. Why Terraform Plan Files Are Ignored

A saved plan may be generated with:

```bash
terraform plan -out=tfplan
```

Plan files are execution artifacts and should not normally be committed.

Ignore:

```text
*.tfplan
tfplan
```

---

# 27. Why We Scan Git Before Committing

Infrastructure repositories can accidentally expose credentials.

Common risks include:

- client secrets
- passwords
- PATs
- private keys
- Storage Account keys
- SAS tokens
- API keys
- local `.tfvars`

Useful checks:

```bash
git status --short --ignored
```

```bash
git diff --cached --name-only
```

```bash
git diff --cached
```

The rule is:

```text
Source code and documentation
          |
          v
Git

Secrets and local state
          |
          X
          |
       Not Git
```

---

# 28. Why We Run `git diff --cached --check`

```bash
git diff --cached --check
```

detects staged whitespace problems such as trailing whitespace.

Expected result:

```text
No output
```

This is repository-quality validation and is useful before CI/CD checks.

---

# 29. Why We Use Feature Branches and Pull Requests

Preferred infrastructure workflow:

```text
Feature Branch
      |
      v
Pull Request
      |
      v
Automated Validation
      |
      v
Peer Review
      |
      v
Approval
      |
      v
Merge
```

Benefits:

- audit history
- peer review
- easier rollback
- CI/CD checks
- reduced production risk
- separation of duties

---

# 30. Why We Test OIDC Before Terraform Deployment

Do not debug all layers simultaneously.

A full deployment can fail in:

```text
GitHub
OIDC
Microsoft Entra
Azure RBAC
Terraform backend
Terraform provider
Networking
Databricks
Application resources
```

Validate progressively:

```text
1. GitHub Environment
      |
      v
2. OIDC Token
      |
      v
3. Azure Login
      |
      v
4. Azure Subscription Access
      |
      v
5. Terraform State Access
      |
      v
6. terraform init
      |
      v
7. terraform validate
      |
      v
8. terraform plan
      |
      v
9. terraform apply
```

This isolates failures and simplifies troubleshooting.

---

# 31. End-to-End Production Use Case

Assume the platform is already running and an engineer needs to modify infrastructure.

```text
Engineer
   |
   v
Modify Terraform
   |
   v
Feature Branch
   |
   v
Pull Request
   |
   +-- terraform fmt
   +-- terraform validate
   +-- terraform plan
   |
   v
Review / Approval
   |
   v
Merge to main
   |
   v
GitHub Actions
   |
   v
Request GitHub OIDC Token
   |
   v
Microsoft Entra Validates Federation
   |
   v
Azure Issues Short-Lived Token
   |
   v
Terraform Accesses Remote State
   |
   v
Terraform Compares Code + State + Azure
   |
   v
Terraform Applies Approved Changes
   |
   v
Remote State Updated
```

No engineer needs to share:

```text
Azure password
Azure client secret
Storage Account key
terraform.tfstate file
```

---

# 32. What the Bootstrap Layer Manages

Typical bootstrap structure:

```text
infra/bootstrap/
├── backend.tf
├── main.tf
├── outputs.tf
├── providers.tf
├── variables.tf
├── versions.tf
├── terraform.tfvars.example
└── .terraform.lock.hcl
```

Typical responsibilities:

```text
Terraform State Resource Group
Terraform State Storage Account
tfstate Blob Container
State Access RBAC
```

---

# 33. What the Bootstrap Layer Does Not Manage

The bootstrap layer should not contain the entire application platform.

Examples of later infrastructure:

```text
VNet
Databricks public subnet
Databricks private subnet
NSGs
NAT Gateway
Public egress IP
Azure Databricks workspace
ADLS Gen2
Key Vault
Unity Catalog resources
Databricks compute
application data infrastructure
```

Recommended structure:

```text
infra/
├── bootstrap/
└── environments/
    └── dev/
```

---

# 34. Recommended State Separation

```text
tfstate
├── bootstrap.terraform.tfstate
└── dev.terraform.tfstate
```

Later:

```text
tfstate
├── bootstrap.terraform.tfstate
├── dev.terraform.tfstate
├── test.terraform.tfstate
└── prod.terraform.tfstate
```

Larger enterprises may use separate Storage Accounts or subscriptions for stronger isolation.

---

# 35. Pre-Platform Validation Checklist

Do not begin the main platform deployment until the following are validated.

```text
[ ] GitHub environment exists
[ ] Microsoft Entra automation application exists
[ ] Service Principal exists
[ ] Federated credential exists
[ ] Federated subject matches the intended repository/environment
[ ] No Azure client secret is required
[ ] Terraform state Resource Group exists
[ ] Terraform state Storage Account exists
[ ] tfstate container exists
[ ] Storage Account security configuration is validated
[ ] GitHub Service Principal has required state RBAC
[ ] Terraform bootstrap state contains expected resources
[ ] Remote bootstrap state is stored in Azure Blob
[ ] terraform validate succeeds
[ ] terraform plan returns no unexpected changes
[ ] local tfvars are ignored
[ ] local Terraform state is ignored
[ ] .terraform directory is ignored
[ ] plan files are ignored
[ ] .terraform.lock.hcl is committed
[ ] staged Git changes contain no credentials
[ ] GitHub OIDC dry-run authentication succeeds
[ ] GitHub workflow can access the Terraform state backend
```

---

# 36. Validation Commands

## Verify Azure CLI Context

```bash
az account show \
  --query "{Subscription:name,SubscriptionId:id,TenantId:tenantId,User:user.name}" \
  --output table
```

## Verify Terraform State Resource Group

```bash
az group show \
  --name mqgen-tfstate-rg \
  --query "{Name:name,Location:location,ProvisioningState:properties.provisioningState}" \
  --output table
```

## Verify Storage Account

```bash
az storage account show \
  --name "<TFSTATE_STORAGE_ACCOUNT_NAME>" \
  --resource-group mqgen-tfstate-rg \
  --query "{
      Name:name,
      ResourceGroup:resourceGroup,
      Location:location,
      SKU:sku.name,
      HTTPS:enableHttpsTrafficOnly,
      TLS:minimumTlsVersion,
      PublicBlobAccess:allowBlobPublicAccess,
      SharedKeyAccess:allowSharedKeyAccess,
      ProvisioningState:provisioningState
  }" \
  --output table
```

## Verify Blob Container

```bash
az storage container show \
  --name tfstate \
  --account-name "<TFSTATE_STORAGE_ACCOUNT_NAME>" \
  --auth-mode login \
  --query "{Name:name,PublicAccess:properties.publicAccess}" \
  --output table
```

## Verify Remote State Blob

```bash
az storage blob list \
  --account-name "<TFSTATE_STORAGE_ACCOUNT_NAME>" \
  --container-name tfstate \
  --auth-mode login \
  --query "[].{StateFile:name,Size:properties.contentLength}" \
  --output table
```

Expected bootstrap state:

```text
bootstrap.terraform.tfstate
```

## Verify Terraform-Managed Resources

```bash
terraform state list
```

## Validate Terraform Configuration

```bash
terraform validate
```

## Check for Drift

```bash
terraform plan
```

Expected stable result:

```text
No changes. Your infrastructure matches the configuration.
```

---

# 37. Azure Portal Validation

## Terraform State Resource Group

```text
Azure Portal
→ Resource groups
→ mqgen-tfstate-rg
```

Verify:

- Resource Group exists
- correct Azure region
- expected Storage Account exists

## Terraform State Storage Account

```text
Azure Portal
→ Resource groups
→ mqgen-tfstate-rg
→ <Terraform State Storage Account>
```

Review:

```text
Overview
Configuration
Networking
Data storage → Containers
Access control (IAM)
```

## Terraform State Container

```text
Storage Account
→ Data storage
→ Containers
→ tfstate
```

Verify expected state blobs.

## Microsoft Entra Application

```text
Azure Portal
→ Microsoft Entra ID
→ App registrations
→ mqgen-github-terraform-dev
```

Review:

```text
Overview
Certificates & secrets
Federated credentials
```

## Service Principal / Enterprise Application

```text
Azure Portal
→ Microsoft Entra ID
→ Enterprise applications
→ mqgen-github-terraform-dev
```

This is the service principal representation used for Azure RBAC.

## RBAC

Navigate to the state container or Storage Account:

```text
Access control (IAM)
→ Role assignments
```

Verify the GitHub Terraform identity has the intended Blob data role at the intended scope.

---

# 38. Production Troubleshooting Model

Troubleshoot layer by layer:

```text
Layer 1  Git / Branch / PR
Layer 2  GitHub Environment
Layer 3  GitHub OIDC Token Permission
Layer 4  Microsoft Entra Federated Credential
Layer 5  Azure Authentication
Layer 6  Azure RBAC
Layer 7  Terraform Backend
Layer 8  Terraform Provider
Layer 9  Terraform Configuration
Layer 10 Azure Resource Deployment
```

Do not create a client secret just because OIDC authentication fails.

Check:

```text
Repository name
Repository owner
GitHub environment
Federated subject
Issuer
Audience
Client ID
Tenant ID
id-token: write
Service Principal
Azure RBAC
Backend access
```

---

# 39. Final Principle

The bootstrap phase creates the control plane required for safe infrastructure delivery.

```text
IDENTITY
Who is deploying?

       +

TRUST
Why should Azure trust the deployment source?

       +

AUTHORIZATION
What is the deployment identity allowed to do?

       +

STATE
What infrastructure does Terraform already manage?

       +

VERSION CONTROL
What change is being proposed?

       +

REVIEW
Who approved the change?

       +

AUTOMATION
How is the change deployed consistently?

       =

PRODUCTION-READY INFRASTRUCTURE DELIVERY
```

---

# 40. Next Phase

After all bootstrap checks pass:

```text
1. Push bootstrap code to the feature branch
2. Create a Pull Request
3. Review Terraform and documentation changes
4. Merge to main
5. Pull main locally
6. Re-run terraform init
7. Re-run terraform validate
8. Re-run terraform plan
9. Confirm no unexpected changes
10. Run GitHub OIDC dry authentication workflow
11. Validate Azure Blob state access from GitHub Actions
12. Create infra/environments/dev/
13. Implement the actual Azure Databricks platform
14. Add Terraform plan/apply CI/CD
15. Introduce controlled environment promotion
```

The development platform should only be created after the bootstrap layer and OIDC authentication path are fully validated.
