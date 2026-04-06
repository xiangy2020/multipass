#!/usr/bin/env bash
# =============================================================================
# create-cluster.sh - 使用 Multipass 一键创建多节点集群
# =============================================================================
# 用法:
#   ./create-cluster.sh [选项]
#
# 选项:
#   -n, --nodes      <数量>    节点数量（默认: 3）
#   -i, --image      <镜像>    使用的镜像（默认: centos:9）
#   -p, --prefix     <前缀>    节点名称前缀（默认: node）
#   -c, --cpus       <核数>    每个节点的 CPU 核数（默认: 2）
#   -m, --memory     <内存>    每个节点的内存大小（默认: 2G）
#   -d, --disk       <磁盘>    每个节点的系统盘大小（默认: 20G）
#   -e, --extra-disk <磁盘>    每个节点额外挂载的数据盘大小（如: 50G），不指定则不挂载
#                              数据盘将格式化为 xfs，开机自动挂载
#   -t, --mount-path <路径>    数据盘挂载目录（默认: /data），需以 / 开头
#   -k, --k8s                 安装 k3s 轻量级 Kubernetes 集群
#   -h, --help                显示帮助信息
#
# 示例:
#   ./create-cluster.sh                                    # 创建 3 节点 CentOS 9 集群
#   ./create-cluster.sh -n 5 -i ubuntu:22.04              # 创建 5 节点 Ubuntu 集群
#   ./create-cluster.sh -n 3 -i centos:8 -k               # 创建 3 节点 CentOS 8 k3s 集群
#   ./create-cluster.sh -p master -n 1 -c 4 -m 4G        # 创建单个 master 节点
#   ./create-cluster.sh -n 3 -e 50G                       # 创建 3 节点集群，每节点额外挂载 50G 数据盘到 /data
#   ./create-cluster.sh -n 3 -e 50G -t /mnt/data         # 挂载到自定义目录 /mnt/data
# =============================================================================

set -euo pipefail

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ─── 默认参数 ────────────────────────────────────────────────────────────────
NODE_COUNT=3
IMAGE="centos:9"
NAME_PREFIX="node"
CPUS=2
MEMORY="2G"
DISK="20G"
EXTRA_DISK=""       # 额外数据盘大小，空字符串表示不挂载
MOUNT_PATH="/data"  # 数据盘挂载目录
INSTALL_K3S=false

# ─── 工具函数 ────────────────────────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BLUE}${BOLD}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}${BOLD}✓${NC} $*"; }

# 显示帮助信息
show_help() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

# 检查依赖
check_dependencies() {
    if ! command -v multipass &>/dev/null; then
        log_error "未找到 multipass 命令，请先安装 Multipass"
        log_error "安装文档: https://multipass.run/install"
        exit 1
    fi
    log_info "Multipass 版本: $(multipass version | head -1)"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--nodes)       NODE_COUNT="$2"; shift 2 ;;
            -i|--image)       IMAGE="$2";      shift 2 ;;
            -p|--prefix)      NAME_PREFIX="$2"; shift 2 ;;
            -c|--cpus)        CPUS="$2";       shift 2 ;;
            -m|--memory)      MEMORY="$2";     shift 2 ;;
            -d|--disk)        DISK="$2";       shift 2 ;;
            -e|--extra-disk)  EXTRA_DISK="$2"; shift 2 ;;
            -t|--mount-path)  MOUNT_PATH="$2"; shift 2 ;;
            -k|--k8s)         INSTALL_K3S=true; shift ;;
            -h|--help)        show_help ;;
            *) log_error "未知参数: $1"; show_help ;;
        esac
    done

    # 参数校验
    if ! [[ "$NODE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        log_error "节点数量必须为正整数，当前值: $NODE_COUNT"
        exit 1
    fi
    if ! [[ "$CPUS" =~ ^[1-9][0-9]*$ ]]; then
        log_error "CPU 核数必须为正整数，当前值: $CPUS"
        exit 1
    fi
    if [[ -n "$EXTRA_DISK" ]] && ! [[ "$EXTRA_DISK" =~ ^[1-9][0-9]*[KMGkmg]?$ ]]; then
        log_error "额外数据盘大小格式不正确，示例: 50G、100G、512M"
        exit 1
    fi
    if [[ -n "$EXTRA_DISK" && "$MOUNT_PATH" != /* ]]; then
        log_error "挂载目录必须以 / 开头，当前值: $MOUNT_PATH"
        exit 1
    fi
}

# 生成节点名称列表
get_node_names() {
    local names=()
    for i in $(seq 1 "$NODE_COUNT"); do
        names+=("${NAME_PREFIX}${i}")
    done
    echo "${names[@]}"
}

# 检查节点是否已存在
check_existing_nodes() {
    local names=("$@")
    local existing=()
    for name in "${names[@]}"; do
        if multipass info "$name" &>/dev/null; then
            existing+=("$name")
        fi
    done
    if [[ ${#existing[@]} -gt 0 ]]; then
        log_warn "以下节点已存在: ${existing[*]}"
        echo -ne "${YELLOW}是否删除已有节点并重新创建？[y/N]${NC} "
        read -r answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            for name in "${existing[@]}"; do
                log_info "删除节点: $name"
                multipass delete "$name" --purge 2>/dev/null || true
            done
        else
            log_error "操作已取消"
            exit 1
        fi
    fi
}

# 生成 cloud-init 配置（注入 SSH 密钥互信 + 主机名解析 + 可选数据盘）
generate_cloud_init() {
    local node_names=("$@")
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # 生成集群共享 SSH 密钥对（用于节点间免密登录）
    local ssh_key_file="${tmp_dir}/cluster_rsa"
    ssh-keygen -t rsa -b 2048 -f "$ssh_key_file" -N "" -C "multipass-cluster" -q
    local pub_key
    pub_key=$(cat "${ssh_key_file}.pub")
    local priv_key
    priv_key=$(cat "${ssh_key_file}")

    # 将数据盘大小转换为 MB 数值（供 dd 使用）
    local extra_disk_mb=0
    if [[ -n "$EXTRA_DISK" ]]; then
        local size_num size_unit
        size_num=$(echo "$EXTRA_DISK" | sed 's/[KMGkmg]$//')
        size_unit=$(echo "$EXTRA_DISK" | grep -oE '[KMGkmg]$' | tr '[:lower:]' '[:upper:]')
        case "$size_unit" in
            G) extra_disk_mb=$((size_num * 1024)) ;;
            M) extra_disk_mb=$((size_num)) ;;
            K) extra_disk_mb=$((size_num / 1024)) ;;
            *) extra_disk_mb=$((size_num / 1024 / 1024)) ;;  # 纯字节
        esac
    fi

    # 为每个节点生成 cloud-init 配置
    for name in "${node_names[@]}"; do
        local cloud_init_file="${tmp_dir}/cloud-init-${name}.yaml"

        # 构建额外数据盘的 runcmd 片段
        local extra_disk_cmds=""
        if [[ -n "$EXTRA_DISK" && $extra_disk_mb -gt 0 ]]; then
            extra_disk_cmds="
  # ── 创建并挂载额外数据盘（${EXTRA_DISK}）──
  - echo '==> 创建数据盘镜像文件 /data-disk.img (${EXTRA_DISK})'
  - dd if=/dev/zero of=/data-disk.img bs=1M count=${extra_disk_mb} status=none
  - echo '==> 格式化数据盘为 xfs'
  - mkfs.xfs -f /data-disk.img
  - mkdir -p ${MOUNT_PATH}
  - echo '==> 写入 fstab 实现开机自动挂载'
  - echo '/data-disk.img ${MOUNT_PATH} xfs loop,defaults 0 0' >> /etc/fstab
  - echo '==> 挂载数据盘到 ${MOUNT_PATH}'
  - mount ${MOUNT_PATH}
  - echo '==> 数据盘挂载完成'"
        fi

        cat > "$cloud_init_file" <<YAML
#cloud-config
# Multipass 集群节点 cloud-init 配置 - ${name}

# 磁盘自动扩容
growpart:
  mode: auto
  devices: ["/"]
  ignore_growroot_disabled: false

# 主机名解析（集群内所有节点）
manage_etc_hosts: true

# 用户配置
users:
  - default

# 启用 SSH 密码认证
ssh_pwauth: true

# 设置密码
chpasswd:
  expire: false
  list:
    - root:root
    - centos:centos
    - ubuntu:ubuntu

# 写入集群 SSH 密钥和配置
write_files:
  - path: /root/.ssh/cluster_rsa
    content: |
$(echo "$priv_key" | sed 's/^/      /')
    permissions: '0600'
    owner: root:root
  - path: /root/.ssh/cluster_rsa.pub
    content: |
      ${pub_key}
    permissions: '0644'
    owner: root:root
  - path: /etc/ssh/sshd_config.d/99-multipass-cluster.conf
    content: |
      # Multipass 集群 SSH 配置
      PermitRootLogin yes
      PasswordAuthentication yes
    permissions: '0600'

# 初始化命令
runcmd:
  # 将集群公钥加入 authorized_keys（节点间免密登录）
  - mkdir -p /root/.ssh
  - chmod 700 /root/.ssh
  - echo "${pub_key}" >> /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
  # 配置 SSH 客户端（跳过主机验证，使用集群密钥）
  - |
    cat > /root/.ssh/config << 'EOF'
    Host ${NAME_PREFIX}*
      StrictHostKeyChecking no
      UserKnownHostsFile /dev/null
      IdentityFile /root/.ssh/cluster_rsa
      User root
    EOF
  - chmod 600 /root/.ssh/config
  # 重启 SSH 服务
  - systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true${extra_disk_cmds}
YAML
    done

    echo "$tmp_dir"
}

# 并行启动所有节点
# 用法: launch_nodes <tmp_dir> <node1> <node2> ...
launch_nodes() {
    local tmp_dir="$1"
    shift
    local node_names=("$@")

    log_step "启动 ${#node_names[@]} 个节点（并行创建）"
    local disk_info="系统盘: ${DISK}"
    [[ -n "$EXTRA_DISK" ]] && disk_info+=" | 数据盘: ${EXTRA_DISK} (挂载至 ${MOUNT_PATH})"
    log_info "镜像: ${IMAGE} | CPU: ${CPUS} 核 | 内存: ${MEMORY} | ${disk_info}"

    local pids=()
    local log_files=()

    for name in "${node_names[@]}"; do
        local cloud_init_file="${tmp_dir}/cloud-init-${name}.yaml"
        local log_file="${tmp_dir}/launch-${name}.log"
        log_files+=("$log_file")

        log_info "启动节点: ${CYAN}${name}${NC}"
        multipass launch "$IMAGE" \
            --name "$name" \
            --cpus "$CPUS" \
            --memory "$MEMORY" \
            --disk "$DISK" \
            --cloud-init "$cloud_init_file" \
            > "$log_file" 2>&1 &
        pids+=($!)
    done

    # 等待所有节点启动完成
    local failed=0
    for i in "${!pids[@]}"; do
        local pid="${pids[$i]}"
        local name="${node_names[$i]}"
        local log_file="${log_files[$i]}"

        if wait "$pid"; then
            log_success "节点 ${CYAN}${name}${NC} 启动成功"
        else
            log_error "节点 ${name} 启动失败，日志如下:"
            cat "$log_file" >&2
            ((failed++)) || true
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_error "${failed} 个节点启动失败"
        return 1
    fi
}

# 获取所有节点的 IP 地址
get_node_ips() {
    local node_names=("$@")
    local ip_file
    ip_file=$(mktemp)

    log_step "获取节点 IP 地址" >&2
    for name in "${node_names[@]}"; do
        local ip=""
        # 等待 IP 分配（最多重试 30 次）
        local retry
        for retry in $(seq 1 30); do
            ip=$(multipass info "$name" --format csv 2>/dev/null \
                | awk -F',' 'NR>1 {print $3}' | head -1 | tr -d ' ')
            if [[ -n "$ip" && "$ip" != "-" ]]; then
                break
            fi
            sleep 2
        done
        if [[ -z "$ip" || "$ip" == "-" ]]; then
            log_warn "无法获取节点 ${name} 的 IP 地址" >&2
            ip="<unknown>"
        fi
        # 直接写入临时文件（避免 bash 3.x 不支持的关联数组）
        echo "${name}=${ip}" >> "$ip_file"
        log_info "节点 ${CYAN}${name}${NC}: ${ip}" >&2
    done

    echo "$ip_file"
}

# 配置节点间 /etc/hosts 互相解析
configure_hosts() {
    local ip_file="$1"
    shift
    local node_names=("$@")

    log_step "配置节点间主机名解析 (/etc/hosts)"

    # 构建 hosts 条目
    local hosts_entries=""
    while IFS='=' read -r name ip; do
        if [[ "$ip" != "<unknown>" ]]; then
            hosts_entries+="${ip} ${name}\n"
        fi
    done < "$ip_file"

    if [[ -z "$hosts_entries" ]]; then
        log_warn "无法获取节点 IP，跳过 hosts 配置"
        return
    fi

    # 向每个节点注入 hosts 条目
    for name in "${node_names[@]}"; do
        log_info "配置节点 ${CYAN}${name}${NC} 的 /etc/hosts"
        multipass exec "$name" -- sudo bash -c "
            # 删除旧的集群条目（如果存在）
            grep -v '# multipass-cluster' /etc/hosts > /tmp/hosts.tmp && mv /tmp/hosts.tmp /etc/hosts
            # 追加新的集群条目
            printf '\n# multipass-cluster-start\n${hosts_entries}# multipass-cluster-end\n' >> /etc/hosts
        " || log_warn "节点 ${name} hosts 配置失败（可能需要手动配置）"
    done
    log_success "主机名解析配置完成"
}

# 安装 k3s 集群（可选）
install_k3s() {
    local ip_file="$1"
    shift
    local node_names=("$@")
    local master_name="${node_names[0]}"

    log_step "安装 k3s 轻量级 Kubernetes 集群"
    log_info "Master 节点: ${CYAN}${master_name}${NC}"

    # 获取 master IP
    local master_ip
    master_ip=$(grep "^${master_name}=" "$ip_file" | cut -d'=' -f2)
    if [[ -z "$master_ip" || "$master_ip" == "<unknown>" ]]; then
        log_error "无法获取 master 节点 IP，跳过 k3s 安装"
        return 1
    fi

    # 在 master 节点安装 k3s server
    log_info "在 master 节点安装 k3s server..."
    multipass exec "$master_name" -- bash -c "
        curl -sfL https://get.k3s.io | sh -s - server \
            --write-kubeconfig-mode 644 \
            --node-name ${master_name}
    " || { log_error "k3s server 安装失败"; return 1; }

    # 获取 k3s token
    local k3s_token
    k3s_token=$(multipass exec "$master_name" -- cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
    if [[ -z "$k3s_token" ]]; then
        log_error "无法获取 k3s token"
        return 1
    fi
    log_success "k3s server 安装完成，token 已获取"

    # 在 worker 节点安装 k3s agent
    for i in $(seq 1 $((${#node_names[@]} - 1))); do
        local worker_name="${node_names[$i]}"
        log_info "在 worker 节点 ${CYAN}${worker_name}${NC} 安装 k3s agent..."
        multipass exec "$worker_name" -- bash -c "
            curl -sfL https://get.k3s.io | K3S_URL=https://${master_ip}:6443 \
                K3S_TOKEN=${k3s_token} \
                sh -s - agent --node-name ${worker_name}
        " || log_warn "节点 ${worker_name} k3s agent 安装失败"
    done

    # 等待节点就绪
    log_info "等待所有节点加入集群..."
    sleep 10
    multipass exec "$master_name" -- kubectl get nodes 2>/dev/null || true
    log_success "k3s 集群安装完成"
    log_info "使用以下命令查看集群状态:"
    echo -e "  ${CYAN}multipass exec ${master_name} -- kubectl get nodes${NC}"
}

# 打印集群摘要
print_summary() {
    local ip_file="$1"
    shift
    local node_names=("$@")

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║           集群创建完成 / Cluster Ready               ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}节点信息:${NC}"
    printf "  %-20s %-18s %s\n" "节点名称" "IP 地址" "状态"
    printf "  %-20s %-18s %s\n" "────────────────────" "──────────────────" "────"
    while IFS='=' read -r name ip; do
        local status
        status=$(multipass info "$name" --format csv 2>/dev/null \
            | awk -F',' 'NR>1 {print $2}' | head -1 | tr -d ' ')
        printf "  %-20s %-18s %s\n" "$name" "$ip" "${status:-unknown}"
    done < "$ip_file"

    echo ""
    echo -e "${BOLD}常用命令:${NC}"
    echo -e "  登录节点:    ${CYAN}multipass shell ${node_names[0]}${NC}"
    echo -e "  查看所有节点: ${CYAN}multipass list${NC}"
    echo -e "  停止集群:    ${CYAN}multipass stop ${node_names[*]}${NC}"
    echo -e "  删除集群:    ${CYAN}multipass delete ${node_names[*]} --purge${NC}"
    if [[ -n "$EXTRA_DISK" ]]; then
        echo -e "  查看数据盘:   ${CYAN}multipass exec ${node_names[0]} -- df -h ${MOUNT_PATH}${NC}"
    fi
    if [[ "$INSTALL_K3S" == "true" ]]; then
        echo -e "  查看 k8s 节点: ${CYAN}multipass exec ${node_names[0]} -- kubectl get nodes${NC}"
    fi
    echo ""
}

# ─── 主流程 ──────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║   Multipass 多节点集群创建工具        ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    log_info "配置: ${NODE_COUNT} 个节点 | 镜像: ${IMAGE} | 前缀: ${NAME_PREFIX}"
    local disk_summary="系统盘: ${DISK}"
    [[ -n "$EXTRA_DISK" ]] && disk_summary+=" | 数据盘: ${EXTRA_DISK} → ${MOUNT_PATH}"
    log_info "资源: ${CPUS} CPU | ${MEMORY} 内存 | ${disk_summary}"
    [[ "$INSTALL_K3S" == "true" ]] && log_info "将安装 k3s Kubernetes 集群"

    # 1. 检查依赖
    check_dependencies

    # 2. 生成节点名称
    read -ra NODE_NAMES <<< "$(get_node_names)"

    # 3. 检查已有节点
    check_existing_nodes "${NODE_NAMES[@]}"

    # 4. 生成 cloud-init 配置
    log_step "生成 cloud-init 配置"
    local TMP_DIR
    TMP_DIR=$(generate_cloud_init "${NODE_NAMES[@]}")
    log_success "cloud-init 配置已生成: ${TMP_DIR}"

    # 5. 并行启动所有节点
    launch_nodes "$TMP_DIR" "${NODE_NAMES[@]}"

    # 6. 获取节点 IP
    local IP_FILE
    IP_FILE=$(get_node_ips "${NODE_NAMES[@]}")

    # 7. 配置节点间 hosts 解析
    configure_hosts "$IP_FILE" "${NODE_NAMES[@]}"

    # 8. 可选：安装 k3s
    if [[ "$INSTALL_K3S" == "true" ]]; then
        install_k3s "$IP_FILE" "${NODE_NAMES[@]}"
    fi

    # 9. 打印摘要
    print_summary "$IP_FILE" "${NODE_NAMES[@]}"

    # 清理临时文件
    rm -rf "$TMP_DIR" "$IP_FILE"
}

main "$@"
