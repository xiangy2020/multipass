#!/usr/bin/env bash
# =============================================================================
# create-cluster.sh - 使用 Multipass 一键创建多节点集群
# =============================================================================
# 用法:
#   ./create-cluster.sh [选项]
#
# 选项:
#   -n, --nodes      <数量>    节点数量（默认: 3，与 -N 互斥）
#   -N, --names      <名称>    自定义节点名称，逗号分隔（如: master,worker1,worker2）
#                              指定后 -n/-p 参数无效
#   -i, --image      <镜像>    使用的镜像（默认: centos:9）
#   -p, --prefix     <前缀>    节点名称前缀（默认: node，与 -N 互斥）
#   -c, --cpus       <核数>    每个节点的 CPU 核数（默认: 2）
#   -m, --memory     <内存>    每个节点的内存大小（默认: 2G）
#   -d, --disk       <磁盘>    每个节点的系统盘大小（默认: 20G）
#   -e, --extra-disk [大小]    为每个节点添加独立数据磁盘（独立块设备 /dev/sdb）
#                              可选指定大小（如: 50G），默认 20G
#                              利用 multipass 原生 --extra-disk 参数实现
#                              在虚拟机内格式化为 xfs 后挂载到指定目录
#   -t, --mount-path <路径>    数据盘在虚拟机内的挂载目录（默认: /data），需以 / 开头
#   -k, --k8s                 安装 k3s 轻量级 Kubernetes 集群
#   -T, --tdsql-init          启用 TDSQL 节点初始化（关闭 SELinux/防火墙/NetworkManager，配置时区和 chrony）
#       --ntp-server <地址>   NTP 服务器地址（默认: ntp.aliyun.com，仅 --tdsql-init 时生效）
#   -h, --help                显示帮助信息
#
# 示例:
#   ./create-cluster.sh                                         # 创建 3 节点 CentOS 9 集群
#   ./create-cluster.sh -n 5 -i ubuntu:22.04                   # 创建 5 节点 Ubuntu 集群
#   ./create-cluster.sh -n 3 -i centos:8 -k                    # 创建 3 节点 CentOS 8 k3s 集群
#   ./create-cluster.sh -p master -n 1 -c 4 -m 4G             # 创建单个 master 节点
#   ./create-cluster.sh -N dev-box -c 2 -m 2G -e 50G -t /data1 # 创建单个自定义名称节点
#   ./create-cluster.sh -N master,worker1,worker2 -k           # 创建自定义名称的 k3s 集群
#   ./create-cluster.sh -n 3 -e                                # 创建 3 节点集群，每节点额外数据盘 20G，挂载到 /data
#   ./create-cluster.sh -n 3 -e 50G -t /data1                 # 系统盘 20G + 独立数据盘 50G，挂载到 /data1
#   ./create-cluster.sh -n 3 -T                               # 创建 3 节点集群并执行 TDSQL 初始化
#   ./create-cluster.sh -n 3 -T --ntp-server 192.168.1.100    # 指定 NTP 服务器的 TDSQL 初始化
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
CUSTOM_NAMES=""         # 自定义节点名称列表（逗号分隔），非空时覆盖 NODE_COUNT/NAME_PREFIX
CPUS=2
MEMORY="2G"
DISK="20G"
EXTRA_DISK=false        # 是否添加独立数据磁盘
EXTRA_DISK_SIZE="20G"   # 数据磁盘大小（默认 20G）
MOUNT_PATH="/data"      # 数据磁盘在虚拟机内的挂载目录
INSTALL_K3S=false
TDSQL_INIT=false        # 是否执行 TDSQL 节点初始化
NTP_SERVER="ntp.aliyun.com" # NTP 服务器地址（TDSQL 初始化时使用）

# ─── 工具函数 ────────────────────────────────────────────────────────────────
log_info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()    { echo -e "\n${BLUE}${BOLD}==>${NC}${BOLD} $*${NC}"; }
log_success() { echo -e "${GREEN}${BOLD}✓${NC} $*"; }

# 显示帮助信息
show_help() {
    sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
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
            -N|--names)       CUSTOM_NAMES="$2"; shift 2 ;;
            -i|--image)       IMAGE="$2";      shift 2 ;;
            -p|--prefix)      NAME_PREFIX="$2"; shift 2 ;;
            -c|--cpus)        CPUS="$2";       shift 2 ;;
            -m|--memory)      MEMORY="$2";     shift 2 ;;
            -d|--disk)        DISK="$2";       shift 2 ;;
            -e|--extra-disk)
                EXTRA_DISK=true
                # 判断下一个参数是否为大小值（如 50G、100G）
                if [[ $# -gt 1 && "$2" =~ ^[1-9][0-9]*[KMGkmg]?$ ]]; then
                    EXTRA_DISK_SIZE="$2"
                    shift 2
                else
                    shift
                fi
                ;;
            -t|--mount-path)  MOUNT_PATH="$2"; shift 2 ;;
            -k|--k8s)         INSTALL_K3S=true; shift ;;
            -T|--tdsql-init)  TDSQL_INIT=true; shift ;;
            --ntp-server)     NTP_SERVER="$2"; shift 2 ;;
            -h|--help)        show_help ;;
            *) log_error "未知参数: $1"; show_help ;;
        esac
    done

    # 参数校验
    if [[ -z "$CUSTOM_NAMES" ]] && ! [[ "$NODE_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        log_error "节点数量必须为正整数，当前值: $NODE_COUNT"
        exit 1
    fi
    if ! [[ "$CPUS" =~ ^[1-9][0-9]*$ ]]; then
        log_error "CPU 核数必须为正整数，当前值: $CPUS"
        exit 1
    fi
    if [[ "$EXTRA_DISK" == "true" && "$MOUNT_PATH" != /* ]]; then
        log_error "挂载目录必须以 / 开头，当前值: $MOUNT_PATH"
        exit 1
    fi
    # 校验自定义名称格式（只允许字母、数字、连字符，且以字母开头）
    if [[ -n "$CUSTOM_NAMES" ]]; then
        IFS=',' read -ra _names <<< "$CUSTOM_NAMES"
        for _n in "${_names[@]}"; do
            _n=$(echo "$_n" | tr -d ' ')
            if ! [[ "$_n" =~ ^[a-zA-Z][a-zA-Z0-9-]*[a-zA-Z0-9]$|^[a-zA-Z]$ ]]; then
                log_error "节点名称 '$_n' 不合法：只允许字母、数字、连字符，且必须以字母开头、以字母或数字结尾"
                exit 1
            fi
        done
    fi
}

# 生成节点名称列表
get_node_names() {
    local names=()
    if [[ -n "$CUSTOM_NAMES" ]]; then
        # 使用自定义名称列表
        IFS=',' read -ra names <<< "$CUSTOM_NAMES"
        # 去除每个名称的首尾空格
        local trimmed=()
        for n in "${names[@]}"; do
            trimmed+=("$(echo "$n" | tr -d ' ')")
        done
        echo "${trimmed[@]}"
    else
        # 使用前缀+序号模式
        for i in $(seq 1 "$NODE_COUNT"); do
            names+=("${NAME_PREFIX}${i}")
        done
        echo "${names[@]}"
    fi
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

# 生成 cloud-init 配置（注入 SSH 密钥互信 + 主机名解析）
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

    # 为每个节点生成 cloud-init 配置
    for name in "${node_names[@]}"; do
        local cloud_init_file="${tmp_dir}/cloud-init-${name}.yaml"

        cat > "$cloud_init_file" <<YAML
#cloud-config
# Multipass 集群节点 cloud-init 配置 - ${name}

# 主机名解析（集群内所有节点）
manage_etc_hosts: true

# 用户配置（新版 cloud-init 语法，兼容 22.2+）
users:
  - name: root
    lock_passwd: false
    hashed_passwd: "\$6\$rounds=4096\$saltsalt\$IxDD3jeSOb5eB1CX5LBsqZFVkJdido3OUILO5Bta47XHX3Do6LksvFyH7YJ0orTHOptflrf3OoDIm/ZgxZt4."
  - default

# 启用 SSH 密码认证
ssh_pwauth: true

# 设置密码（兼容旧版 cloud-init）
chpasswd:
  expire: false
  users:
    - name: root
      password: root
      type: text
    - name: centos
      password: centos
      type: text
    - name: ubuntu
      password: ubuntu
      type: text

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
  # 兜底：确保 root 密码设置成功并解锁（防止 chpasswd 在某些发行版失效）
  - echo 'root:root' | chpasswd
  - passwd -u root 2>/dev/null || true
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
  - systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
YAML

        # 如果启用 TDSQL 初始化，追加初始化命令
        if [[ "$TDSQL_INIT" == "true" ]]; then
            cat >> "$cloud_init_file" <<YAML
  # ── TDSQL 节点初始化 ──────────────────────────────────────────────────────
  # 1. 关闭 SELinux（临时 + 永久）
  - setenforce 0 2>/dev/null || true
  - sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
  # 2. 关闭防火墙
  - systemctl disable firewalld 2>/dev/null || true
  - systemctl stop firewalld 2>/dev/null || true
  # 3. 关闭 NetworkManager
  - systemctl stop NetworkManager 2>/dev/null || true
  - systemctl disable NetworkManager 2>/dev/null || true
  # 4. 设置时区
  - timedatectl set-timezone Asia/Shanghai
  # 5. 关闭 ntpd（若存在）
  - systemctl stop ntpd 2>/dev/null || true
  - systemctl disable ntpd 2>/dev/null || true
  # 6. 安装并配置 chrony
  - yum install -y chrony
  - sed -i 's/^server /#server /' /etc/chrony.conf
  - echo 'server ${NTP_SERVER} iburst' >> /etc/chrony.conf
  - systemctl enable chronyd
  - systemctl restart chronyd
YAML
        fi

        # 如果需要额外数据磁盘，追加格式化+挂载命令
        # multipass --extra-disk 会将额外磁盘挂载为 /dev/sdb（第二块独立磁盘）
        if [[ "$EXTRA_DISK" == "true" ]]; then
            cat >> "$cloud_init_file" <<YAML
  # 格式化并挂载额外数据磁盘（multipass --extra-disk 挂载为 /dev/sdb）
  - |
    set -e
    MOUNT_POINT="${MOUNT_PATH}"
    DATA_DISK="/dev/sdb"
    # 等待磁盘设备就绪
    for i in \$(seq 1 10); do
      [ -b "\${DATA_DISK}" ] && break
      sleep 1
    done
    if [ ! -b "\${DATA_DISK}" ]; then
      echo "ERROR: 数据磁盘 \${DATA_DISK} 未找到" >&2
      exit 1
    fi
    # 格式化为 xfs
    mkfs.xfs -f "\${DATA_DISK}"
    # 创建挂载点
    mkdir -p "\${MOUNT_POINT}"
    # 获取磁盘 UUID
    DISK_UUID=\$(blkid -s UUID -o value "\${DATA_DISK}")
    # 写入 fstab 实现开机自动挂载
    echo "UUID=\${DISK_UUID} \${MOUNT_POINT} xfs defaults 0 0" >> /etc/fstab
    # 挂载
    mount "\${MOUNT_POINT}"
YAML
        fi
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
    if [[ "$EXTRA_DISK" == "true" ]]; then
        disk_info+=" | 数据盘: ${EXTRA_DISK_SIZE}（独立磁盘 /dev/sdb → ${MOUNT_PATH}）"
    fi
    log_info "镜像: ${IMAGE} | CPU: ${CPUS} 核 | 内存: ${MEMORY} | ${disk_info}"

    local pids=()
    local log_files=()

    for name in "${node_names[@]}"; do
        local cloud_init_file="${tmp_dir}/cloud-init-${name}.yaml"
        local log_file="${tmp_dir}/launch-${name}.log"
        log_files+=("$log_file")

        log_info "启动节点: ${CYAN}${name}${NC}"

        # 构建 launch 命令
        local launch_cmd=(
            multipass launch "$IMAGE"
            --name "$name"
            --cpus "$CPUS"
            --memory "$MEMORY"
            --disk "$DISK"
            --cloud-init "$cloud_init_file"
        )
        # 如果有额外磁盘，追加 --extra-disk 参数（利用 multipass 原生多磁盘支持）
        if [[ "$EXTRA_DISK" == "true" ]]; then
            launch_cmd+=(--extra-disk "$EXTRA_DISK_SIZE")
        fi

        "${launch_cmd[@]}" > "$log_file" 2>&1 &
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
    if [[ "$EXTRA_DISK" == "true" ]]; then
        echo -e "  查看数据盘:   ${CYAN}multipass exec ${node_names[0]} -- df -Th ${MOUNT_PATH}${NC}"
        echo -e "  查看磁盘:     ${CYAN}multipass exec ${node_names[0]} -- lsblk${NC}"
        echo -e "  查看磁盘信息: ${CYAN}multipass info ${node_names[0]}${NC}"
    fi
    if [[ "$INSTALL_K3S" == "true" ]]; then
        echo -e "  查看 k8s 节点: ${CYAN}multipass exec ${node_names[0]} -- kubectl get nodes${NC}"
    fi
    if [[ "$TDSQL_INIT" == "true" ]]; then
        echo -e "  验证初始化:   ${CYAN}multipass exec ${node_names[0]} -- cloud-init status${NC}"
        echo -e "  查看初始化日志: ${CYAN}multipass exec ${node_names[0]} -- cat /var/log/cloud-init-output.log${NC}"
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

    # 计算实际节点数量（自定义名称时从名称列表获取）
    local actual_count="$NODE_COUNT"
    local name_desc="前缀: ${NAME_PREFIX}"
    if [[ -n "$CUSTOM_NAMES" ]]; then
        IFS=',' read -ra _tmp_names <<< "$CUSTOM_NAMES"
        actual_count=${#_tmp_names[@]}
        name_desc="名称: ${CUSTOM_NAMES}"
    fi
    log_info "配置: ${actual_count} 个节点 | 镜像: ${IMAGE} | ${name_desc}"
    local disk_summary="系统盘: ${DISK}"
    if [[ "$EXTRA_DISK" == "true" ]]; then
        disk_summary+=" | 数据盘: ${EXTRA_DISK_SIZE}（独立磁盘 /dev/sdb → ${MOUNT_PATH}）"
    fi
    log_info "资源: ${CPUS} CPU | ${MEMORY} 内存 | ${disk_summary}"
    [[ "$INSTALL_K3S" == "true" ]] && log_info "将安装 k3s Kubernetes 集群"
    if [[ "$TDSQL_INIT" == "true" ]]; then
        log_info "TDSQL 初始化: 已启用（NTP: ${NTP_SERVER}）"
    fi

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
