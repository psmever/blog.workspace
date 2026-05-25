#!/usr/bin/env bash
set -Eeuo pipefail

: "${BLOG_AWS_REGION:=ap-northeast-2}"
: "${BLOG_AWS_PROFILE:=}"
: "${BLOG_VPC_ID:=vpc-0e6897ef9a0a75951}"
: "${BLOG_SUBNET_ID:=}"
: "${BLOG_SSH_CIDR:=}"
: "${BLOG_AMI_ID:=ami-0fc2b553b2bbfaee0}"
: "${BLOG_INSTANCE_TYPE:=t3.medium}"
: "${BLOG_KEY_NAME:=jaubi-prod-app}"
: "${BLOG_SG_NAME:=jaubi-prod-app-sg}"
: "${BLOG_INSTANCE_NAME:=jaubi-prod-app-01}"
: "${BLOG_EIP_NAME:=jaubi-prod-eip-01}"
: "${BLOG_ROOT_DEVICE_NAME:=/dev/sda1}"
: "${BLOG_ROOT_VOLUME_SIZE:=40}"
: "${BLOG_DATA_DEVICE_NAME:=/dev/sdb}"
: "${BLOG_DATA_VOLUME_SIZE:=80}"
: "${BLOG_ALLOCATE_EIP:=1}"

TMP_DIR=""
AWS_CMD=(aws)

timestamp() {
    date "+%Y-%m-%d %H:%M:%S %Z"
}

log() {
    printf '[%s] %s\n' "$(timestamp)" "$*" >&2
}

die() {
    log "ERROR: $*"
    exit 1
}

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

usage() {
    cat <<'EOF'
사용법:
  BLOG_SUBNET_ID=subnet-xxxxxxxx ./scripts/aws/create-prod-app-ec2.sh

선택 환경변수:
  BLOG_AWS_PROFILE       AWS CLI profile
  BLOG_AWS_REGION        AWS region (기본값: ap-northeast-2)
  BLOG_VPC_ID            대상 VPC ID
  BLOG_SUBNET_ID         대상 subnet ID (필수)
  BLOG_SSH_CIDR          SSH 허용 CIDR, 비우면 현재 공인 IP/32 자동 감지
  BLOG_AMI_ID            AMI ID
  BLOG_INSTANCE_TYPE     EC2 instance type
  BLOG_KEY_NAME          EC2 key pair 이름
  BLOG_SG_NAME           보안 그룹 이름
  BLOG_INSTANCE_NAME     EC2 Name 태그
  BLOG_EIP_NAME          Elastic IP Name 태그
  BLOG_ROOT_VOLUME_SIZE  루트 볼륨 크기 GiB
  BLOG_DATA_VOLUME_SIZE  데이터 볼륨 크기 GiB
  BLOG_ALLOCATE_EIP      1이면 EIP 생성/연결, 0이면 생략

예시:
  BLOG_SUBNET_ID=subnet-0123456789abcdef0 ./scripts/aws/create-prod-app-ec2.sh
  BLOG_SUBNET_ID=subnet-0123456789abcdef0 BLOG_SSH_CIDR=YOUR_PUBLIC_IP/32 ./scripts/aws/create-prod-app-ec2.sh
EOF
}

require_commands() {
    local command_name

    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || die "필수 명령이 없습니다: $command_name"
    done
}

aws_cli() {
    "${AWS_CMD[@]}" "$@"
}

normalize_optional_text() {
    local value=$1

    if [ "$value" = "None" ] || [ "$value" = "null" ]; then
        printf '\n'
        return
    fi

    printf '%s\n' "$value"
}

detect_ssh_cidr() {
    local detected_ip

    if [ -n "$BLOG_SSH_CIDR" ]; then
        return
    fi

    require_commands curl
    detected_ip=$(curl -fsSL https://checkip.amazonaws.com | tr -d '[:space:]')
    [ -n "$detected_ip" ] || die "현재 공인 IP를 감지하지 못했습니다. BLOG_SSH_CIDR을 직접 지정하세요."

    BLOG_SSH_CIDR="${detected_ip}/32"
    log "현재 SSH 허용 CIDR 자동 감지: $BLOG_SSH_CIDR"
}

ensure_required_env() {
    [ -n "$BLOG_SUBNET_ID" ] || {
        usage
        die "BLOG_SUBNET_ID는 필수입니다."
    }
}

configure_aws_cmd() {
    if [ -n "$BLOG_AWS_PROFILE" ]; then
        AWS_CMD+=(--profile "$BLOG_AWS_PROFILE")
    fi

    AWS_CMD+=(--region "$BLOG_AWS_REGION")
}

ensure_no_existing_instance() {
    local instance_id

    instance_id=$(
        aws_cli ec2 describe-instances \
            --filters \
                "Name=tag:Name,Values=${BLOG_INSTANCE_NAME}" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped" \
            --query 'Reservations[].Instances[].InstanceId' \
            --output text
    )
    instance_id=$(normalize_optional_text "$instance_id")

    [ -z "$instance_id" ] || die "같은 Name 태그를 가진 인스턴스가 이미 있습니다: $instance_id"
}

resolve_or_create_security_group() {
    local sg_id

    sg_id=$(
        aws_cli ec2 describe-security-groups \
            --filters \
                "Name=vpc-id,Values=${BLOG_VPC_ID}" \
                "Name=group-name,Values=${BLOG_SG_NAME}" \
            --query 'SecurityGroups[0].GroupId' \
            --output text
    )
    sg_id=$(normalize_optional_text "$sg_id")

    if [ -n "$sg_id" ]; then
        log "기존 보안 그룹 재사용: $sg_id"
        printf '%s\n' "$sg_id"
        return
    fi

    sg_id=$(
        aws_cli ec2 create-security-group \
            --group-name "$BLOG_SG_NAME" \
            --description "jaubi prod app security group" \
            --vpc-id "$BLOG_VPC_ID" \
            --query 'GroupId' \
            --output text
    )

    aws_cli ec2 create-tags \
        --resources "$sg_id" \
        --tags \
            "Key=Name,Value=${BLOG_SG_NAME}" \
            "Key=Project,Value=jaubi" \
            "Key=Environment,Value=prod" \
            "Key=Role,Value=app-sg" >/dev/null

    log "보안 그룹 생성 완료: $sg_id"
    printf '%s\n' "$sg_id"
}

ensure_ingress_rule() {
    local sg_id=$1
    local from_port=$2
    local to_port=$3
    local cidr=$4
    local description=$5
    local output

    if output=$(
        aws_cli ec2 authorize-security-group-ingress \
            --group-id "$sg_id" \
            --ip-permissions "[{\"IpProtocol\":\"tcp\",\"FromPort\":${from_port},\"ToPort\":${to_port},\"IpRanges\":[{\"CidrIp\":\"${cidr}\",\"Description\":\"${description}\"}]}]" \
            2>&1
    ); then
        log "인바운드 규칙 추가: tcp ${from_port}-${to_port} ${cidr}"
        return
    fi

    if printf '%s' "$output" | grep -q 'InvalidPermission.Duplicate'; then
        log "인바운드 규칙 이미 존재: tcp ${from_port}-${to_port} ${cidr}"
        return
    fi

    printf '%s\n' "$output" >&2
    die "보안 그룹 인바운드 규칙 추가에 실패했습니다."
}

build_payload_files() {
    local block_device_file=$1
    local network_file=$2
    local tag_file=$3
    local sg_id=$4

    cat > "$block_device_file" <<EOF
[
  {
    "DeviceName": "${BLOG_ROOT_DEVICE_NAME}",
    "Ebs": {
      "Encrypted": true,
      "DeleteOnTermination": true,
      "Iops": 3000,
      "VolumeSize": ${BLOG_ROOT_VOLUME_SIZE},
      "VolumeType": "gp3",
      "Throughput": 125
    }
  },
  {
    "DeviceName": "${BLOG_DATA_DEVICE_NAME}",
    "Ebs": {
      "Encrypted": true,
      "DeleteOnTermination": false,
      "Iops": 3000,
      "VolumeSize": ${BLOG_DATA_VOLUME_SIZE},
      "VolumeType": "gp3",
      "Throughput": 125
    }
  }
]
EOF

    cat > "$network_file" <<EOF
[
  {
    "AssociatePublicIpAddress": true,
    "DeviceIndex": 0,
    "Groups": [
      "${sg_id}"
    ],
    "SubnetId": "${BLOG_SUBNET_ID}"
  }
]
EOF

    cat > "$tag_file" <<EOF
[
  {
    "ResourceType": "instance",
    "Tags": [
      {"Key": "Name", "Value": "${BLOG_INSTANCE_NAME}"},
      {"Key": "Project", "Value": "jaubi"},
      {"Key": "Environment", "Value": "prod"},
      {"Key": "Role", "Value": "app"}
    ]
  },
  {
    "ResourceType": "volume",
    "Tags": [
      {"Key": "Project", "Value": "jaubi"},
      {"Key": "Environment", "Value": "prod"},
      {"Key": "AttachedTo", "Value": "${BLOG_INSTANCE_NAME}"}
    ]
  },
  {
    "ResourceType": "network-interface",
    "Tags": [
      {"Key": "Project", "Value": "jaubi"},
      {"Key": "Environment", "Value": "prod"},
      {"Key": "AttachedTo", "Value": "${BLOG_INSTANCE_NAME}"}
    ]
  }
]
EOF
}

run_instance() {
    local block_device_file=$1
    local network_file=$2
    local tag_file=$3

    aws_cli ec2 run-instances \
        --image-id "$BLOG_AMI_ID" \
        --instance-type "$BLOG_INSTANCE_TYPE" \
        --key-name "$BLOG_KEY_NAME" \
        --block-device-mappings "file://${block_device_file}" \
        --network-interfaces "file://${network_file}" \
        --credit-specification '{"CpuCredits":"unlimited"}' \
        --tag-specifications "file://${tag_file}" \
        --metadata-options '{"HttpEndpoint":"enabled","HttpPutResponseHopLimit":2,"HttpTokens":"required"}' \
        --private-dns-name-options '{"HostnameType":"ip-name","EnableResourceNameDnsARecord":true,"EnableResourceNameDnsAAAARecord":false}' \
        --count 1 \
        --query 'Instances[0].InstanceId' \
        --output text
}

resolve_or_allocate_eip() {
    local allocation_id
    local attached_instance_id

    allocation_id=$(
        aws_cli ec2 describe-addresses \
            --filters "Name=tag:Name,Values=${BLOG_EIP_NAME}" \
            --query 'Addresses[0].AllocationId' \
            --output text
    )
    allocation_id=$(normalize_optional_text "$allocation_id")

    if [ -z "$allocation_id" ]; then
        allocation_id=$(
            aws_cli ec2 allocate-address \
                --domain vpc \
                --query 'AllocationId' \
                --output text
        )

        aws_cli ec2 create-tags \
            --resources "$allocation_id" \
            --tags \
                "Key=Name,Value=${BLOG_EIP_NAME}" \
                "Key=Project,Value=jaubi" \
                "Key=Environment,Value=prod" \
                "Key=Role,Value=eip" >/dev/null

        log "Elastic IP 생성 완료: $allocation_id"
        printf '%s\n' "$allocation_id"
        return
    fi

    attached_instance_id=$(
        aws_cli ec2 describe-addresses \
            --allocation-ids "$allocation_id" \
            --query 'Addresses[0].InstanceId' \
            --output text
    )
    attached_instance_id=$(normalize_optional_text "$attached_instance_id")

    if [ -n "$attached_instance_id" ]; then
        die "기존 Elastic IP가 다른 인스턴스에 연결되어 있습니다: allocation_id=${allocation_id} instance_id=${attached_instance_id}"
    fi

    log "기존 Elastic IP 재사용: $allocation_id"
    printf '%s\n' "$allocation_id"
}

associate_eip() {
    local instance_id=$1
    local allocation_id=$2
    local current_allocation_id

    current_allocation_id=$(
        aws_cli ec2 describe-instances \
            --instance-ids "$instance_id" \
            --query 'Reservations[0].Instances[0].PublicIpAddress' \
            --output text
    )
    current_allocation_id=$(normalize_optional_text "$current_allocation_id")

    if [ -n "$current_allocation_id" ]; then
        log "현재 인스턴스에 임시 공인 IP가 있습니다. EIP로 교체합니다."
    fi

    aws_cli ec2 associate-address \
        --instance-id "$instance_id" \
        --allocation-id "$allocation_id" >/dev/null

    log "Elastic IP 연결 완료: allocation_id=${allocation_id}"
}

print_summary() {
    local instance_id=$1

    aws_cli ec2 describe-instances \
        --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].{
            InstanceId: InstanceId,
            State: State.Name,
            InstanceType: InstanceType,
            SubnetId: SubnetId,
            PrivateIp: PrivateIpAddress,
            PublicIp: PublicIpAddress,
            PublicDns: PublicDnsName
        }' \
        --output table
}

main() {
    local sg_id
    local instance_id
    local allocation_id
    local block_device_file
    local network_file
    local tag_file

    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        usage
        exit 0
    fi

    require_commands aws
    ensure_required_env
    configure_aws_cmd
    detect_ssh_cidr
    ensure_no_existing_instance

    TMP_DIR=$(mktemp -d)
    trap cleanup EXIT
    block_device_file="${TMP_DIR}/block-device-mappings.json"
    network_file="${TMP_DIR}/network-interfaces.json"
    tag_file="${TMP_DIR}/tag-specifications.json"

    sg_id=$(resolve_or_create_security_group)
    ensure_ingress_rule "$sg_id" 22 22 "$BLOG_SSH_CIDR" "ssh current ip"
    ensure_ingress_rule "$sg_id" 80 80 "0.0.0.0/0" "http"
    ensure_ingress_rule "$sg_id" 443 443 "0.0.0.0/0" "https"
    build_payload_files "$block_device_file" "$network_file" "$tag_file" "$sg_id"

    log "EC2 인스턴스 생성 시작: name=${BLOG_INSTANCE_NAME} subnet=${BLOG_SUBNET_ID}"
    instance_id=$(run_instance "$block_device_file" "$network_file" "$tag_file")
    log "인스턴스 생성 완료: $instance_id"

    log "인스턴스 running 대기"
    aws_cli ec2 wait instance-running --instance-ids "$instance_id"

    if [ "$BLOG_ALLOCATE_EIP" = "1" ]; then
        allocation_id=$(resolve_or_allocate_eip)
        associate_eip "$instance_id" "$allocation_id"
    fi

    log "인스턴스 status-ok 대기"
    aws_cli ec2 wait instance-status-ok --instance-ids "$instance_id"

    print_summary "$instance_id"

    log "완료"
    log "다음 단계: ssh -i <pem-path> ubuntu@<PublicIpAddress>"
    log "data 볼륨은 인스턴스 내부에서 lsblk로 실제 디바이스 이름을 확인한 뒤 포맷/마운트하세요."
}

main "$@"
