#!/usr/bin/env bash
# =============================================================================
# delete-cluster.sh - 删除 Multipass 集群并清理宿主机数据目录
# =============================================================================
# 用法:
#   ./delete-cluster.sh [选项]
#
# 选项:
#   -p, --prefix  <前缀>    节点名称前缀（默认: node）
#   -n, --nodes   <数量>    节点数量（默认: 自动检测）
#   -y, --yes               跳过确认提示，直接删除
#   -h, --help              显示帮助信息
#
# 说明:
#   1. 自动卸载所有节点的 multipass mount 挂载
#   2. 删除并清除所有节点（multipass delete --purge）
#   3. 清理宿主机数据目录 ~/.multipass-data/<prefix>/
#
# 示例:
#   ./delete-cluster.sh                    # 删除默认前缀 node 的集群
#   ./delete-cluster.sh -p master          # 删除前缀为 master 的集群
#   ./delete-cluster.sh -p node -y        # 跳过确认直接删除
# =============================================================================

set -euo pipefail

# ─── 颜色定义 ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── 默认参数 ────────────────────────────────────────────────────────────────
NAME_PREFIX="node"
NODE_COUNT=""       # 空表示自动检测
AUTO_YES=false
DATA_BASE_DIR="${HOME}/.multipass-data"

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

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--prefix)  NAME_PREFIX="$2"; shift 2 ;;
            -n|--nodes)   NODE_COUNT="$2";  shift 2 ;;
            -y|--yes)     AUTO_YES=true;    shift ;;
            -h|--help)    show_help ;;
            *) log_error "未知参数: $1"; show_help ;;
        esac
    done
}

# 自动检测集群节点
detect_nodes() {
    local prefix="$1"
    local nodes=()

    # 从 multipass list 中找到匹配前缀的节点
    while IFS= read -r line; do
        local name
        name=$(echo "$line" | awk '{print $1}')
        if [[ "$name" == "${prefix}"* ]]; then
            nodes+=("$name")
        fi
    done < <(multipass list --format csv 2>/dev/null | tail -n +2)

    echo "${nodes[@]}"
}

# 卸载数据盘挂载
unmount_data_disks() {
    local node_names=("$@")

    log_step "卸载数据盘挂载"
    for name in "${node_names[@]}"; do
        log_info "卸载节点 ${CYAN}${name}${NC} 的挂载..."
        multipass umount "${name}" 2>/dev/null && \
            log_success "节点 ${name} 挂载已卸载" || \
            log_warn "节点 ${name} 无挂载或卸载失败（忽略）"
    done
}

# 删除集群节点
delete_nodes() {
    local node_names=("$@")

    log_step "删除集群节点"
    for name in "${node_names[@]}"; do
        log_info "删除节点: ${CYAN}${name}${NC}"
        multipass delete "$name" --purge 2>/dev/null && \
            log_success "节点 ${name} 已删除" || \
            log_warn "节点 ${name} 删除失败（可能已不存在）"
    done
}

# 清理宿主机数据目录
cleanup_host_data() {
    local host_dir="${DATA_BASE_DIR}/${NAME_PREFIX}"

    log_step "清理宿主机数据目录"
    if [[ -d "$host_dir" ]]; then
        log_info "清理目录: ${CYAN}${host_dir}${NC}"
        rm -rf "$host_dir"
        log_success "宿主机数据目录已清理: ${host_dir}"
    else
        log_info "宿主机数据目录不存在，跳过: ${host_dir}"
    fi
}

# ─── 主流程 ──────────────────────────────────────────────────────────────────
main() {
    parse_args "$@"

    echo -e "${BOLD}${RED}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║   Multipass 集群删除工具              ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    # 检查 multipass
    if ! command -v multipass &>/dev/null; then
        log_error "未找到 multipass 命令"
        exit 1
    fi

    # 检测节点列表
    local node_names=()
    if [[ -n "$NODE_COUNT" ]]; then
        # 按数量生成节点名
        for i in $(seq 1 "$NODE_COUNT"); do
            node_names+=("${NAME_PREFIX}${i}")
        done
    else
        # 自动检测
        read -ra node_names <<< "$(detect_nodes "$NAME_PREFIX")"
    fi

    if [[ ${#node_names[@]} -eq 0 ]]; then
        log_warn "未找到前缀为 '${NAME_PREFIX}' 的节点"
        # 仍然尝试清理宿主机数据目录
        cleanup_host_data
        exit 0
    fi

    log_info "将删除以下节点: ${CYAN}${node_names[*]}${NC}"
    local host_dir="${DATA_BASE_DIR}/${NAME_PREFIX}"
    if [[ -d "$host_dir" ]]; then
        log_info "将清理宿主机数据目录: ${CYAN}${host_dir}${NC}"
    fi

    # 确认提示
    if [[ "$AUTO_YES" != "true" ]]; then
        echo ""
        echo -e "${RED}${BOLD}警告：此操作不可逆，将永久删除以上节点及数据！${NC}"
        echo -ne "${YELLOW}确认删除？[y/N]${NC} "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            log_info "操作已取消"
            exit 0
        fi
    fi

    # 1. 卸载数据盘
    unmount_data_disks "${node_names[@]}"

    # 2. 删除节点
    delete_nodes "${node_names[@]}"

    # 3. 清理宿主机数据目录
    cleanup_host_data

    echo ""
    echo -e "${GREEN}${BOLD}✓ 集群已完全删除${NC}"
    echo ""
}

main "$@"
