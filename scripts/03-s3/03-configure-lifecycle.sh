#!/bin/bash
# =============================================================================
# 03-configure-lifecycle.sh - 配置 S3 生命周期规则
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-init.sh"

init

# -----------------------------------------------------------------------------
# 生成生命周期配置
# -----------------------------------------------------------------------------
generate_lifecycle_config() {
    cat << 'EOF'
{
  "Rules": [
    {
      "ID": "CleanupTempFiles",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "temp/"
      },
      "Expiration": {
        "Days": 7
      }
    },
    {
      "ID": "TransitionTrainingModels",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "models/training/"
      },
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        }
      ]
    },
    {
      "ID": "TransitionArchivedNotebooks",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "notebooks/archived/"
      },
      "Transitions": [
        {
          "Days": 60,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 180,
          "StorageClass": "GLACIER"
        }
      ]
    },
    {
      "ID": "CleanupOldPredictions",
      "Status": "Enabled",
      "Filter": {
        "Prefix": "outputs/predictions/"
      },
      "Expiration": {
        "Days": 90
      }
    },
    {
      "ID": "CleanupNoncurrentVersions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 90
      }
    },
    {
      "ID": "CleanupDeleteMarkers",
      "Status": "Enabled",
      "Filter": {},
      "Expiration": {
        "ExpiredObjectDeleteMarker": true
      }
    },
    {
      "ID": "CleanupIncompleteUploads",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 生成共享 Bucket 生命周期配置 (简化版)
# -----------------------------------------------------------------------------
generate_shared_lifecycle_config() {
    cat << 'EOF'
{
  "Rules": [
    {
      "ID": "CleanupNoncurrentVersions",
      "Status": "Enabled",
      "Filter": {},
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 180
      }
    },
    {
      "ID": "CleanupIncompleteUploads",
      "Status": "Enabled",
      "Filter": {},
      "AbortIncompleteMultipartUpload": {
        "DaysAfterInitiation": 7
      }
    }
  ]
}
EOF
}

# -----------------------------------------------------------------------------
# 应用生命周期配置
# -----------------------------------------------------------------------------
apply_lifecycle_config() {
    local bucket_name=$1
    local config=$2
    local config_file="${SCRIPT_DIR}/${OUTPUT_DIR}/lifecycle-${bucket_name}.json"
    
    log_info "Applying lifecycle rules to bucket: $bucket_name"
    
    echo "$config" > "$config_file"
    
    aws s3api put-bucket-lifecycle-configuration \
        --bucket "$bucket_name" \
        --lifecycle-configuration "file://${config_file}" \
        --region "$AWS_REGION"
    
    log_success "Lifecycle rules applied to $bucket_name"
}

# -----------------------------------------------------------------------------
# 主函数
# -----------------------------------------------------------------------------
main() {
    echo ""
    echo "=============================================="
    echo " Configuring S3 Lifecycle Rules"
    echo "=============================================="
    echo ""
    
    if [[ "${ENABLE_LIFECYCLE_RULES}" != "true" ]]; then
        log_warn "Lifecycle rules disabled (ENABLE_LIFECYCLE_RULES != true)"
        exit 0
    fi
    
    local lifecycle_config=$(generate_lifecycle_config)
    local shared_lifecycle_config=$(generate_shared_lifecycle_config)
    
    # 1. 配置项目 Bucket 生命周期
    for team in $TEAMS; do
        log_info "Configuring lifecycle for team: $team"
        
        local projects=$(get_projects_for_team "$team")
        for project in $projects; do
            local bucket_name=$(get_bucket_name "$team" "$project")
            
            if ! aws s3api head-bucket --bucket "$bucket_name" --region "$AWS_REGION" 2>/dev/null; then
                log_warn "Bucket $bucket_name does not exist, skipping..."
                continue
            fi
            
            apply_lifecycle_config "$bucket_name" "$lifecycle_config"
        done
    done
    
    # 2. 配置共享 Bucket 生命周期
    if [[ "${CREATE_SHARED_BUCKET}" == "true" ]]; then
        local shared_bucket=$(get_shared_bucket_name)
        
        if aws s3api head-bucket --bucket "$shared_bucket" --region "$AWS_REGION" 2>/dev/null; then
            apply_lifecycle_config "$shared_bucket" "$shared_lifecycle_config"
        fi
    fi
    
    echo ""
    log_success "All lifecycle rules configured!"
    echo ""
    echo "Lifecycle Rules Summary:"
    echo "  - temp/* : Delete after 7 days"
    echo "  - models/training/* : Move to IA after 30 days"
    echo "  - notebooks/archived/* : Move to IA (60d), Glacier (180d)"
    echo "  - outputs/predictions/* : Delete after 90 days"
    echo "  - Non-current versions : Delete after 90 days"
    echo "  - Incomplete uploads : Abort after 7 days"
}

main
