param(
  [string]$ProjectId = $(if ([string]::IsNullOrWhiteSpace($env:PROJECT_ID)) { 'fleteapp-8d8f7' } else { $env:PROJECT_ID }),
  [string]$BillingAccountId = $(if ([string]::IsNullOrWhiteSpace($env:BILLING_ACCOUNT_ID)) { '019B89-19CC39-7DBA4E' } else { $env:BILLING_ACCOUNT_ID }),
  [string]$Region = $(if ([string]::IsNullOrWhiteSpace($env:REGION)) { 'us-central1' } else { $env:REGION }),
  [string]$BudgetAmount = $env:BUDGET_AMOUNT,
  [string]$DisplayName = $(if ([string]::IsNullOrWhiteSpace($env:BUDGET_DISPLAY_NAME)) { 'Muvv emergency billing stop' } else { $env:BUDGET_DISPLAY_NAME }),
  [string]$TopicId = $(if ([string]::IsNullOrWhiteSpace($env:BUDGET_TOPIC_ID)) { 'muvv-budget-alerts' } else { $env:BUDGET_TOPIC_ID }),
  [string]$FunctionName = $(if ([string]::IsNullOrWhiteSpace($env:BUDGET_FUNCTION_NAME)) { 'muvv-stop-billing' } else { $env:BUDGET_FUNCTION_NAME }),
  [switch]$ConfirmDisableBillingWhenBudgetReached
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$functionDir = Join-Path $repoRoot 'infra\billing-cap-function'

function Get-GcloudCli {
  $command = Get-Command gcloud -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $default = Join-Path $env:LOCALAPPDATA 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'
  if (Test-Path $default) {
    return $default
  }

  throw 'No se encontro gcloud. Abre una nueva PowerShell despues de instalar Google Cloud SDK, o revisa la instalacion.'
}

function Invoke-Gcloud {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
  & $gcloud @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Fallo gcloud $($Arguments -join ' ')"
  }
}

if ([string]::IsNullOrWhiteSpace($BudgetAmount)) {
  throw 'Indica -BudgetAmount. Ejemplos: -BudgetAmount 5000CLP o -BudgetAmount 5USD.'
}

if (-not $ConfirmDisableBillingWhenBudgetReached) {
  throw 'Este script configura un apagado real de billing. Vuelve a ejecutarlo con -ConfirmDisableBillingWhenBudgetReached cuando estes seguro.'
}

if (-not (Test-Path $functionDir)) {
  throw "No existe la carpeta de funcion: $functionDir"
}

$gcloud = Get-GcloudCli
$topicPath = "projects/$ProjectId/topics/$TopicId"

Write-Host "Configurando freno de presupuesto para $ProjectId"
Write-Host "Billing account: $BillingAccountId"
Write-Host "Presupuesto: $BudgetAmount"
Write-Host "Topic Pub/Sub: $topicPath"
Write-Host "Funcion: $FunctionName en $Region"
Write-Host ""
Write-Host 'ADVERTENCIA: al alcanzar el presupuesto, se desactiva billing del proyecto y los servicios pueden detenerse.'

Invoke-Gcloud services enable `
  billingbudgets.googleapis.com `
  cloudbilling.googleapis.com `
  cloudbuild.googleapis.com `
  cloudfunctions.googleapis.com `
  eventarc.googleapis.com `
  run.googleapis.com `
  pubsub.googleapis.com `
  artifactregistry.googleapis.com `
  --project $ProjectId

$existingTopic = & $gcloud pubsub topics list `
  --project $ProjectId `
  --filter "name:$topicPath" `
  --format 'value(name)'
if ([string]::IsNullOrWhiteSpace($existingTopic)) {
  Write-Host "Creando topic $TopicId..."
  Invoke-Gcloud pubsub topics create $TopicId --project $ProjectId
} else {
  Write-Host "Topic ya existe: $TopicId"
}

Write-Host "Desplegando funcion de freno..."
Invoke-Gcloud functions deploy $FunctionName `
  --gen2 `
  --runtime nodejs22 `
  --region $Region `
  --trigger-topic $TopicId `
  --entry-point stopBilling `
  --set-env-vars "GOOGLE_CLOUD_PROJECT=$ProjectId" `
  --source $functionDir `
  --project $ProjectId `
  --quiet

$functionServiceAccount = & $gcloud functions describe $FunctionName `
  --region $Region `
  --project $ProjectId `
  --format 'value(serviceConfig.serviceAccountEmail)'
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($functionServiceAccount)) {
  throw 'No se pudo obtener el service account de la funcion.'
}

Write-Host "Service account de funcion: $functionServiceAccount"
Write-Host 'Otorgando permiso para desactivar billing si se alcanza el presupuesto...'
Invoke-Gcloud billing accounts add-iam-policy-binding $BillingAccountId `
  --member "serviceAccount:$functionServiceAccount" `
  --role roles/billing.admin `
  --quiet

$budgetsJson = & $gcloud billing budgets list --billing-account $BillingAccountId --format json
if ($LASTEXITCODE -ne 0) {
  throw 'No se pudo listar presupuestos.'
}

$budgets = @()
if (-not [string]::IsNullOrWhiteSpace($budgetsJson)) {
  $parsedBudgets = $budgetsJson | ConvertFrom-Json
  foreach ($budget in $parsedBudgets) {
    $budgets += $budget
  }
}

$matchingBudgets = @($budgets | Where-Object { [string]$_.displayName -eq [string]$DisplayName })
$existingBudget = if ($matchingBudgets.Count -gt 0) { $matchingBudgets[0] } else { $null }

if ($existingBudget -and $existingBudget.name) {
  Write-Host "Actualizando presupuesto existente: $($existingBudget.name)"
  Invoke-Gcloud billing budgets update $existingBudget.name `
    --display-name $DisplayName `
    --budget-amount $BudgetAmount `
    --filter-projects "projects/$ProjectId" `
    --credit-types-treatment include-all-credits `
    --notifications-rule-pubsub-topic $topicPath `
    --clear-threshold-rules `
    --add-threshold-rule 'percent=0.50,basis=current-spend' `
    --add-threshold-rule 'percent=0.80,basis=current-spend' `
    --add-threshold-rule 'percent=1.00,basis=current-spend'
} else {
  Write-Host "Creando presupuesto nuevo: $DisplayName"
  Invoke-Gcloud billing budgets create `
    --billing-account $BillingAccountId `
    --display-name $DisplayName `
    --budget-amount $BudgetAmount `
    --filter-projects "projects/$ProjectId" `
    --credit-types-treatment include-all-credits `
    --notifications-rule-pubsub-topic $topicPath `
    --threshold-rule 'percent=0.50,basis=current-spend' `
    --threshold-rule 'percent=0.80,basis=current-spend' `
    --threshold-rule 'percent=1.00,basis=current-spend'
}

Write-Host ""
Write-Host 'Freno configurado.'
Write-Host "Cuando el costo reportado llegue a $BudgetAmount, la funcion intentara desactivar billing del proyecto."
Write-Host 'Esto no es instantaneo: Google puede reportar costos con retraso, asi que deja margen bajo tu limite real.'
