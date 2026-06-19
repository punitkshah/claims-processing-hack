#!/bin/bash
# Deploy Claims Processing API to Azure Container Apps
set -e

echo "🚀 Deploying Claims Processing API to Azure Container Apps"
echo "============================================================"

# Load environment variables
if [ ! -f ../.env ]; then
    echo "❌ Error: .env file not found. Please run Challenge 0 setup first."
    exit 1
fi

source ../.env

# Save current directory and navigate to workspace root for the build context
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# Required variables
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
ACR_NAME="${AZURE_CONTAINER_REGISTRY_NAME}"
ENVIRONMENT_NAME="${CONTAINER_APP_ENVIRONMENT_NAME}"

# Your Container App is PRE-CREATED before the hack, with managed identity and
# RBAC roles already assigned. USERNAME identifies which app is yours.
if [ -z "${USERNAME}" ]; then
    echo "❌ Error: USERNAME is not set in .env. It identifies your pre-created Container App."
    exit 1
fi
APP_NAME="${USERNAME}-app"
IMAGE_NAME="claims-processing-api"
IMAGE_TAG="${USERNAME}"

echo ""
echo "📋 Deployment Configuration:"
echo "   Resource Group: $RESOURCE_GROUP"
echo "   Container Registry: $ACR_NAME"
echo "   Container App Environment: $ENVIRONMENT_NAME"
echo "   App Name: $APP_NAME"
echo ""

# Step 1: Build and push image in the cloud with ACR Tasks (no local Docker required)
echo "🔨 Step 1: Building and pushing image with 'az acr build' (no local Docker needed)..."
cd "$WORKSPACE_ROOT"
az acr build \
   --registry "$ACR_NAME" \
   --image "$IMAGE_NAME:$IMAGE_TAG" \
   --file challenge-4/Dockerfile .
cd "$SCRIPT_DIR"

# Step 2: Verify your PRE-CREATED Container App exists
echo "🔎 Step 2: Verifying your pre-created Container App..."
if ! az containerapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    echo "   ❌ Error: Container App not found: $APP_NAME"
    echo "   The app should have been pre-created for you before the hack."
    echo "   Check that USERNAME in .env matches your assigned app name."
    exit 1
fi
echo "   ✅ Container App exists: $APP_NAME"

# Step 3: Update the pre-created Container App with your new image
# Identity, RBAC roles, env vars and ingress are already configured on the app,
# so attendees only swap in the freshly built image — no role assignment needed.
echo "🚢 Step 3: Updating Container App image..."
# Configure the registry credentials on the app
az containerapp registry set \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --server "$ACR_NAME.azurecr.io" \
    --username "$ACR_USERNAME" \
    --password "$ACR_PASSWORD"

# Then swap in the image
az containerapp update \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --image "$ACR_NAME.azurecr.io/$IMAGE_NAME:$IMAGE_TAG" \
    --cpu 1.0 \
    --memory 2.0Gi \
    --min-replicas 0 \
    --max-replicas 2 \
    --set-env-vars \
        USERNAME="$USERNAME" \
        AI_FOUNDRY_PROJECT_ENDPOINT="$AI_FOUNDRY_PROJECT_ENDPOINT" \
        MODEL_DEPLOYMENT_NAME="$MODEL_DEPLOYMENT_NAME" \
        MISTRAL_DOCUMENT_AI_ENDPOINT="$MISTRAL_DOCUMENT_AI_ENDPOINT" \
        MISTRAL_DOCUMENT_AI_KEY="$MISTRAL_DOCUMENT_AI_KEY" \
        MISTRAL_DOCUMENT_AI_DEPLOYMENT_NAME="$MISTRAL_DOCUMENT_AI_DEPLOYMENT_NAME"

az containerapp ingress enable \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --type external \
  --target-port 8080 \
  --transport auto

# Step 4: Get app URL
echo ""
echo "✅ Deployment Complete!"
echo ""
APP_URL=$(az containerapp show \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query properties.configuration.ingress.fqdn \
    -o tsv)

echo "🌐 Application URL: https://$APP_URL"
echo ""
echo "📊 View logs with:"
echo "   az containerapp logs show --name $APP_NAME --resource-group $RESOURCE_GROUP --follow"
echo ""
echo "🔍 Check status with:"
echo "   az containerapp show --name $APP_NAME --resource-group $RESOURCE_GROUP --query properties.runningStatus"
echo ""
