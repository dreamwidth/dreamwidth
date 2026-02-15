#!/usr/bin/env bash
# import.sh - Import all existing AWS resources into Terraform state
#
# Run from the terraform/ directory after running: terraform init
#
# Usage: bash import.sh

set -euo pipefail

ACCOUNT_ID="194396987458"
REGION="us-east-1"
CLUSTER="dreamwidth"
VPC_ID="vpc-dd5972b9"

echo "=== Terraform Import Script ==="
echo "Account: ${ACCOUNT_ID}"
echo "Region:  ${REGION}"
echo "Cluster: ${CLUSTER}"
echo ""

# =============================================================================
# Helper function
# =============================================================================

import_resource() {
    local addr="$1"
    local id="$2"
    # Skip if already in state
    if terraform state show "${addr}" &>/dev/null; then
        echo "Skipping ${addr} (already imported)"
        return 0
    fi
    echo "Importing ${addr}..."
    terraform import "${addr}" "${id}"
    echo ""
}

# =============================================================================
# ECS Cluster
# =============================================================================

echo "--- ECS Cluster ---"
import_resource "aws_ecs_cluster.dreamwidth" "dreamwidth"

# =============================================================================
# IAM Roles
# =============================================================================

echo "--- IAM Roles ---"
import_resource "aws_iam_role.task_role" "dreamwidth-ecsTaskRole"
import_resource "aws_iam_role.execution_role" "dreamwidth-ecsTaskExecutionRole"

# =============================================================================
# Security Groups
# =============================================================================

echo "--- Security Groups ---"
import_resource "aws_security_group.workers" "sg-051da131f4bd2f503"
import_resource "aws_security_group.webs" "sg-04d6101ec5cf7281b"
import_resource "aws_security_group.proxies" "sg-0783b94b3e412943e"
import_resource "aws_security_group.alb" "sg-0609957b"

# =============================================================================
# Application Load Balancers
# =============================================================================

echo "--- Load Balancers ---"
echo "Looking up ALB ARNs..."

PROD_LB_ARN=$(aws elbv2 describe-load-balancers --names "dw-prod" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "  dw-prod ARN: ${PROD_LB_ARN}"

PROXY_LB_ARN=$(aws elbv2 describe-load-balancers --names "dw-proxy" \
    --query 'LoadBalancers[0].LoadBalancerArn' --output text)
echo "  dw-proxy ARN: ${PROXY_LB_ARN}"

import_resource "aws_lb.prod" "${PROD_LB_ARN}"
import_resource "aws_lb.proxy" "${PROXY_LB_ARN}"

# =============================================================================
# Target Groups - Web Services
# =============================================================================

echo "--- Target Groups ---"

declare -A TG_NAMES=(
    ["web_stable"]="web-stable-tg"
    ["web_stable_2"]="web-stable-2-tg"
    ["web_canary"]="web-canary-tg"
    ["web_canary_2"]="web-canary-2-tg"
    ["web_shop"]="web-shop-tg"
    ["web_shop_2"]="web-shop-2-tg"
    ["web_unauthenticated"]="web-unauthenticated-tg"
    ["web_unauthenticated_2"]="web-unauthenticated-2-tg"
    ["proxy"]="proxy-stable-tg"
    ["dw_maint"]="dw-maint"
    ["dw_stats"]="dw-stats"
    ["ghi_assist"]="ghi-assist"
    ["dw_embedded"]="dw-embedded"
)

declare -A TG_ARNS

for tf_name in "${!TG_NAMES[@]}"; do
    aws_name="${TG_NAMES[$tf_name]}"
    echo "Looking up target group: ${aws_name}..."
    arn=$(aws elbv2 describe-target-groups --names "${aws_name}" \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    TG_ARNS["${tf_name}"]="${arn}"
    import_resource "aws_lb_target_group.${tf_name}" "${arn}"
done

# =============================================================================
# Listeners
# =============================================================================

echo "--- Listeners ---"

# Prod ALB listeners
echo "Looking up listeners for dw-prod..."
PROD_LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "${PROD_LB_ARN}" \
    --query 'Listeners[*].[Port,ListenerArn]' --output text)

PROD_443_LISTENER_ARN=""
PROD_80_LISTENER_ARN=""

while IFS=$'\t' read -r port arn; do
    case "${port}" in
        443)
            PROD_443_LISTENER_ARN="${arn}"
            echo "  Prod HTTPS (443): ${arn}"
            ;;
        80)
            PROD_80_LISTENER_ARN="${arn}"
            echo "  Prod HTTP (80): ${arn}"
            ;;
    esac
done <<< "${PROD_LISTENERS}"

import_resource "aws_lb_listener.r_51c219f8069621b6_443" "${PROD_443_LISTENER_ARN}"
import_resource "aws_lb_listener.r_51c219f8069621b6_80" "${PROD_80_LISTENER_ARN}"

# Proxy ALB listeners
echo "Looking up listeners for dw-proxy..."
PROXY_LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "${PROXY_LB_ARN}" \
    --query 'Listeners[*].[Port,ListenerArn]' --output text)

PROXY_443_LISTENER_ARN=""
PROXY_80_LISTENER_ARN=""

while IFS=$'\t' read -r port arn; do
    case "${port}" in
        443)
            PROXY_443_LISTENER_ARN="${arn}"
            echo "  Proxy HTTPS (443): ${arn}"
            ;;
        80)
            PROXY_80_LISTENER_ARN="${arn}"
            echo "  Proxy HTTP (80): ${arn}"
            ;;
    esac
done <<< "${PROXY_LISTENERS}"

import_resource "aws_lb_listener.r_35f0700031428f07_443" "${PROXY_443_LISTENER_ARN}"
import_resource "aws_lb_listener.r_35f0700031428f07_80" "${PROXY_80_LISTENER_ARN}"

# =============================================================================
# Listener Rules
# =============================================================================

echo "--- Listener Rules ---"

# Prod ALB HTTPS (443) listener rules
echo "Looking up rules for prod HTTPS listener..."
PROD_443_RULES=$(aws elbv2 describe-rules --listener-arn "${PROD_443_LISTENER_ARN}" \
    --query 'Rules[*].[Priority,RuleArn]' --output text)

declare -A RULE_ARNS

while IFS=$'\t' read -r priority arn; do
    RULE_ARNS["443_${priority}"]="${arn}"
done <<< "${PROD_443_RULES}"

# Import HTTPS listener rules by priority
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_3" "${RULE_ARNS[443_3]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_4" "${RULE_ARNS[443_4]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_5" "${RULE_ARNS[443_5]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_45" "${RULE_ARNS[443_45]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_50" "${RULE_ARNS[443_50]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_443_rule_55" "${RULE_ARNS[443_55]}"

# Prod ALB HTTP (80) listener rules
echo "Looking up rules for prod HTTP listener..."
PROD_80_RULES=$(aws elbv2 describe-rules --listener-arn "${PROD_80_LISTENER_ARN}" \
    --query 'Rules[*].[Priority,RuleArn]' --output text)

declare -A RULE_80_ARNS

while IFS=$'\t' read -r priority arn; do
    RULE_80_ARNS["80_${priority}"]="${arn}"
done <<< "${PROD_80_RULES}"

import_resource "aws_lb_listener_rule.r_51c219f8069621b6_80_rule_1" "${RULE_80_ARNS[80_1]}"
import_resource "aws_lb_listener_rule.r_51c219f8069621b6_80_rule_2" "${RULE_80_ARNS[80_2]}"

# =============================================================================
# CloudWatch Log Groups
# =============================================================================

echo "--- CloudWatch Log Groups ---"

# Legacy shared log groups
import_resource "aws_cloudwatch_log_group.worker_legacy" "/dreamwidth/worker"
import_resource "aws_cloudwatch_log_group.web_legacy" "/dreamwidth/web"

# CW Agent log group
import_resource "aws_cloudwatch_log_group.cwagent" "/ecs/ecs-cwagent"

# Proxy log group
import_resource "aws_cloudwatch_log_group.proxy" "/dreamwidth/proxy"

# Per-worker log groups
WORKERS=(
    "birthday-notify"
    "change-poster-id"
    "codebuild-notifier"
    "content-importer"
    "content-importer-lite"
    "content-importer-verify"
    "directory-meta"
    "distribute-invites"
    "dw-esn-cluster-subs"
    "dw-esn-filter-subs"
    "dw-esn-fired-event"
    "dw-esn-process-sub"
    "dw-send-email"
    "dw-sphinx-copier"
    "embeds"
    "expunge-users"
    "import-eraser"
    "import-scheduler"
    "incoming-email"
    "latest-feed"
    "lazy-cleanup"
    "paidstatus"
    "process-privacy"
    "resolve-extacct"
    "schedule-synsuck"
    "shop-creditcard-charge"
    "spellcheck-gm"
    "sphinx-copier"
    "sphinx-search-gm"
    "support-notify"
    "synsuck"
)

for worker in "${WORKERS[@]}"; do
    import_resource "aws_cloudwatch_log_group.worker[\"${worker}\"]" "/dreamwidth/worker/${worker}"
done

# NOTE: Per-web log groups (/dreamwidth/web/canary, /dreamwidth/web/stable, etc.)
# are NOT imported because they do not exist in AWS yet -- they are genuinely new resources.

# =============================================================================
# ECS Task Definitions - Workers
# =============================================================================

echo "--- ECS Task Definitions (Workers) ---"

for worker in "${WORKERS[@]}"; do
    echo "Looking up task definition: worker-${worker}..."
    td_arn=$(aws ecs describe-task-definition --task-definition "worker-${worker}" \
        --query 'taskDefinition.taskDefinitionArn' --output text)
    import_resource "aws_ecs_task_definition.worker[\"${worker}\"]" "${td_arn}"
done

# =============================================================================
# ECS Task Definitions - Web Services
# =============================================================================

echo "--- ECS Task Definitions (Web) ---"

WEB_SERVICES=("canary" "stable" "shop" "unauthenticated")

for svc in "${WEB_SERVICES[@]}"; do
    echo "Looking up task definition: web-${svc}..."
    td_arn=$(aws ecs describe-task-definition --task-definition "web-${svc}" \
        --query 'taskDefinition.taskDefinitionArn' --output text)
    import_resource "aws_ecs_task_definition.web[\"${svc}\"]" "${td_arn}"
done

# =============================================================================
# ECS Task Definition - Proxy
# =============================================================================

echo "--- ECS Task Definition (Proxy) ---"

echo "Looking up task definition: proxy-stable..."
PROXY_TD_ARN=$(aws ecs describe-task-definition --task-definition "proxy-stable" \
    --query 'taskDefinition.taskDefinitionArn' --output text)
import_resource "aws_ecs_task_definition.proxy" "${PROXY_TD_ARN}"

# =============================================================================
# ECS Services - Workers
# =============================================================================

echo "--- ECS Services (Workers) ---"

for worker in "${WORKERS[@]}"; do
    import_resource "aws_ecs_service.worker[\"${worker}\"]" "dreamwidth/worker-${worker}-service"
done

# =============================================================================
# ECS Services - Web
# =============================================================================

echo "--- ECS Services (Web) ---"

for svc in "${WEB_SERVICES[@]}"; do
    import_resource "aws_ecs_service.web[\"${svc}\"]" "dreamwidth/web-${svc}-service"
done

# =============================================================================
# ECS Service - Proxy
# =============================================================================

echo "--- ECS Service (Proxy) ---"
import_resource "aws_ecs_service.proxy" "dreamwidth/proxy-stable-service"

# =============================================================================
# Done
# =============================================================================

echo ""
echo "=== Import complete! ==="
echo ""
echo "Next steps:"
echo "  1. Run 'terraform plan' to check for drift between state and config"
echo "  2. Fix any differences and re-run plan until clean"
echo "  3. Commit the terraform.tfstate file (or configure remote backend)"
