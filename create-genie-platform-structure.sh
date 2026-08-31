#!/usr/bin/env bash
set -euo pipefail

# Genie Insurance Platform - enterprise repository scaffold
#
# Usage:
#   ./create-genie-platform-structure.sh
#   ./create-genie-platform-structure.sh /path/to/genie-insurance-platform
#
# Behavior:
#   - Creates directories only; it does not delete or overwrite source files.
#   - Adds .gitkeep files to leaf directories so Git can track the empty structure.

ROOT_DIR="${1:-genie-insurance-platform}"

echo "Creating repository structure under: ${ROOT_DIR}"

directories=(
  ".github/workflows"
  ".github/ISSUE_TEMPLATE"

  "docs/00-overview/images"
  "docs/01-local-development"
  "docs/02-terraform-bootstrap"
  "docs/03-platform-foundation"
  "docs/04-databricks"
  "docs/05-data-engineering"
  "docs/06-ai-ml-genie"
  "docs/07-platform-engineering"
  "docs/08-security-governance"
  "docs/09-observability-sre"
  "docs/10-runbooks"
  "docs/11-adr"

  "scripts/local"
  "scripts/bootstrap"
  "scripts/deployment"
  "scripts/validation"
  "scripts/operations"
  "scripts/utilities"

  "infra/bootstrap"
  "infra/modules/resource-group"
  "infra/modules/networking"
  "infra/modules/storage"
  "infra/modules/key-vault"
  "infra/modules/databricks"
  "infra/modules/aks"
  "infra/modules/monitoring"
  "infra/modules/private-endpoint"
  "infra/modules/identity-rbac"
  "infra/environments/dev"
  "infra/environments/test"
  "infra/environments/stage"
  "infra/environments/prod"

  "databricks/src/bronze"
  "databricks/src/silver"
  "databricks/src/gold"
  "databricks/src/shared"
  "databricks/src/data_quality"
  "databricks/resources"
  "databricks/jobs"
  "databricks/sql/ddl"
  "databricks/sql/dml"
  "databricks/sql/queries"
  "databricks/tests/unit"
  "databricks/tests/integration"

  "data/contracts"
  "data/schemas"
  "data/samples"
  "data/reference"

  "orchestration/airflow/dags"
  "orchestration/airflow/plugins"
  "orchestration/airflow/tests"

  "streaming/kafka/producers"
  "streaming/kafka/consumers"
  "streaming/kafka/schemas"
  "streaming/kafka/config"

  "applications/api/src"
  "applications/api/tests"
  "applications/agents/src"
  "applications/agents/tests"
  "applications/ui/src"
  "applications/ui/tests"

  "mlops/training"
  "mlops/feature-engineering"
  "mlops/model-registry"
  "mlops/deployment"
  "mlops/inference"
  "mlops/evaluation"

  "observability/dashboards"
  "observability/alerts"
  "observability/slo"
  "observability/queries"
  "observability/runbooks"

  "security/policies"
  "security/rbac"
  "security/scanning"
  "security/threat-models"

  "tests/unit"
  "tests/integration"
  "tests/e2e"
  "tests/infrastructure"
  "tests/security"
  "tests/performance"
  "tests/smoke"
  "tests/fixtures"

  "config/dev"
  "config/test"
  "config/stage"
  "config/prod"

  "samples/notebooks"
  "samples/payloads"
  "samples/configuration"
)

mkdir -p "${ROOT_DIR}"

for dir in "${directories[@]}"; do
  mkdir -p "${ROOT_DIR}/${dir}"
done

# Git does not track empty directories. Add .gitkeep only to leaf directories.
for dir in "${directories[@]}"; do
  full_path="${ROOT_DIR}/${dir}"

  has_child=false
  for other in "${directories[@]}"; do
    if [[ "${other}" == "${dir}/"* ]]; then
      has_child=true
      break
    fi
  done

  if [[ "${has_child}" == false ]]; then
    touch "${full_path}/.gitkeep"
  fi
done

echo
echo "Repository scaffold created successfully."
echo
echo "Directory tree:"
if command -v tree >/dev/null 2>&1; then
  tree -a -I '.git'
else
  find "${ROOT_DIR}" -type d | sort
fi

echo
echo "Next steps:"
echo "  cd \"${ROOT_DIR}\""
echo "  git status"
echo "  git add ."
echo "  git commit -m \"chore: create enterprise repository scaffold\""
