#!/bin/bash

# 配置
ASTROBOT_PATH="$HOME/AstrBot"
LOG_FILE="$HOME/astrobot_install.log"
GITHUB_REPO="https://github.com/AstrBotDevs/AstrBot.git"
PYTHON_VERSION="3.10"
PROXY_URL="https://gh-proxy.com/"
UV_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"

# Logo
show_logo() {
    echo -e "\033[1;36m"
    cat << "LOGO"
     ___           _______.___________..______      .______     ______   .___________.
    /   \        /       |            ||   _  \    |   _  \   /  __  \  |           |
   /  ^  \      |   (----|  |----`|  |_)  |   |  |_)  | |  |  |  | `---|  |----`
  /  /_\  \      \   \       |  |     |      /    |   _  <  |  |  |  |     |  |
 /  _____  \  .----)  |       |  |     |  |\  \--.||  |_)  | |  `--'  |     |  |
/__/     \__\ |_______/       |__|     | _| `.____||______/   \______/      |__|
LOGO
    echo -e "\033[0m"
    echo "========================================"
    echo "    AstrBot 安装脚本 (proot-distro 版)   "
    echo "========================================"
    echo
}

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 无颜色

# 日志函数
log() {
    echo -e "${BLUE}[信息]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[成功]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}[警告]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[错误]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
    exit 1
}

# 检查是否为proot环境
check_proot() {
    if [ -n "$PROOT_TMP_DIR" ] || [ -f "/etc/proot-distro" ] || grep -q "proot" /proc/self/status 2>/dev/null; then
        log "检测到运行在 proot/proot-distro 环境中"
        return 0
    else
        warning "未检测到 proot 环境，但将继续执行"
        return 1
    fi
}

# 检查网络连接（带重试）
check_internet() {
    log "检查网络连接..."
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s --connect-timeout 10 https://github.com > /dev/null 2>&1; then
            log "网络连接正常"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        warning "网络检查失败 (尝试 $retry_count/$max_retries)"
        
        if [ $retry_count -lt $max_retries ]; then
            sleep 2
        fi
    done
    
    warning "直接连接 GitHub 失败，将尝试使用代理"
    return 1
}

# 安装系统包
install_packages() {
    log "更新软件包列表..."
    apt update >> "$LOG_FILE" 2>&1 || warning "更新软件包列表失败，继续执行..."
    
    log "安装必要的系统包..."
    local packages=("git" "screen" "software-properties-common" "curl" "wget")
    
    for pkg in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            log "正在安装 $pkg..."
            if apt install -y "$pkg" >> "$LOG_FILE" 2>&1; then
                success "已安装 $pkg"
            else
                warning "安装 $pkg 失败，某些功能可能无法使用"
            fi
        else
            log "$pkg 已安装"
        fi
    done
}

# 安装 Python
install_python() {
    log "检查 Python $PYTHON_VERSION 安装..."
    
    if command -v python$PYTHON_VERSION >/dev/null 2>&1; then
        log "Python $PYTHON_VERSION 已安装"
        return 0
    fi
    
    log "添加 deadsnakes PPA 源..."
    if add-apt-repository ppa:deadsnakes/ppa -y >> "$LOG_FILE" 2>&1; then
        log "PPA 添加成功"
    else
        warning "添加 PPA 失败，尝试直接安装"
    fi
    
    log "更新软件包列表..."
    apt update >> "$LOG_FILE" 2>&1
    
    log "安装 Python $PYTHON_VERSION..."
    if apt install -y python$PYTHON_VERSION python$PYTHON_VERSION-venv python$PYTHON_VERSION-dev >> "$LOG_FILE" 2>&1; then
        success "Python $PYTHON_VERSION 安装成功"
    else
        error "安装 Python $PYTHON_VERSION 失败"
    fi
}

# 克隆仓库（带代理支持）
clone_repository() {
    log "克隆 AstrBot 仓库..."
    
    if [ -d "$ASTROBOT_PATH/.git" ]; then
        warning "仓库已存在于 $ASTROBOT_PATH"
        echo "请选择操作："
        echo "  [U] 更新现有仓库"
        echo "  [C] 重新克隆（删除旧版本）"
        echo "  [S] 跳过"
        read -p "请输入选择 (u/c/s): " -n 1 -r
        echo
        case $REPLY in
            [Uu]*)
                cd "$ASTROBOT_PATH" || error "无法进入目录"
                git pull >> "$LOG_FILE" 2>&1 || warning "更新仓库失败"
                success "仓库更新完成"
                return 0
                ;;
            [Cc]*)
                log "删除旧仓库..."
                rm -rf "$ASTROBOT_PATH"
                ;;
            [Ss]*)
                log "跳过仓库克隆/更新"
                return 0
                ;;
        esac
    fi
    
    local clone_success=false
    
    # 先尝试直接克隆
    log "尝试从 GitHub 直接克隆..."
    if git clone "$GITHUB_REPO" "$ASTROBOT_PATH" >> "$LOG_FILE" 2>&1; then
        clone_success=true
    fi
    
    # 如果失败，尝试使用代理
    if [ "$clone_success" = false ]; then
        warning "直接克隆失败，尝试使用代理..."
        if git clone "${PROXY_URL}${GITHUB_REPO}" "$ASTROBOT_PATH" >> "$LOG_FILE" 2>&1; then
            clone_success=true
        fi
    fi
    
    if [ "$clone_success" = true ]; then
        success "仓库克隆成功: $ASTROBOT_PATH"
    else
        error "克隆仓库失败"
    fi
}

# 安装 UV
install_uv() {
    log "检查 UV 是否已安装..."
    
    if command -v uv >/dev/null 2>&1; then
        log "UV 已安装"
        return 0
    fi
    
    log "正在安装 UV..."
    echo "选择安装方法："
    echo "  1) 使用官方安装脚本（推荐）"
    echo "  2) 使用 pip 安装"
    echo "  3) 跳过 UV 安装"
    read -p "请输入选择 (1-3): " uv_choice
    
    case $uv_choice in
        1)
            log "使用官方脚本安装 UV..."
            curl -LsSf https://astral.sh/uv/install.sh | sh >> "$LOG_FILE" 2>&1
            if [ $? -eq 0 ]; then
                success "UV 安装成功"
                # 添加到 PATH
                export PATH="$HOME/.cargo/bin:$PATH"
                export PATH="$HOME/.local/bin:$PATH"
            else
                warning "官方脚本安装失败，尝试 pip 安装"
                pip3 install uv >> "$LOG_FILE" 2>&1 || error "安装 UV 失败"
            fi
            ;;
        2)
            log "使用 pip 安装 UV..."
            pip3 install uv >> "$LOG_FILE" 2>&1 || error "安装 UV 失败"
            success "UV 安装成功"
            ;;
        3)
            warning "跳过 UV 安装"
            return 1
            ;;
        *)
            warning "无效选择，使用官方脚本安装"
            curl -LsSf https://astral.sh/uv/install.sh | sh >> "$LOG_FILE" 2>&1
            ;;
    esac
    
    return 0
}

# 设置 Python 环境
setup_environment() {
    cd "$ASTROBOT_PATH" || error "无法进入 AstrBot 目录"
    
    log "设置 Python 环境..."
    
    echo "选择环境设置方法："
    echo "  1) UV（推荐 - 更快更现代）"
    echo "  2) Python venv（传统虚拟环境）"
    echo "  3) 跳过环境设置"
    read -p "请输入选择 (1-3): " env_choice
    
    case $env_choice in
        1)
            setup_uv_environment
            ;;
        2)
            setup_venv_environment
            ;;
        3)
            warning "跳过环境设置"
            return 0
            ;;
        *)
            warning "无效选择，默认使用 UV"
            setup_uv_environment
            ;;
    esac
}

# 设置 UV 环境
setup_uv_environment() {
    log "设置 UV 环境..."
    
    # 安装 UV（如果需要）
    if ! install_uv; then
        warning "UV 未安装，将使用 venv"
        setup_venv_environment
        return
    fi
    
    log "配置 UV 使用国内镜像源..."
    export UV_DEFAULT_INDEX="$UV_INDEX"
    
    log "使用 UV 同步依赖包..."
    if uv sync >> "$LOG_FILE" 2>&1; then
        success "UV 依赖同步成功"
    else
        error "UV 依赖同步失败"
    fi
}

# 设置传统 venv 环境
setup_venv_environment() {
    log "设置 Python 虚拟环境..."
    
    if [ -d "venv" ]; then
        warning "虚拟环境已存在"
        read -p "重新创建虚拟环境？(y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf venv
        else
            source venv/bin/activate || error "无法激活现有虚拟环境"
            log "使用现有虚拟环境"
            return 0
        fi
    fi
    
    python$PYTHON_VERSION -m venv venv || error "创建虚拟环境失败"
    source venv/bin/activate || error "激活虚拟环境失败"
    
    log "升级 pip 并安装依赖..."
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    
    # 设置 pip 国内源
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple >> "$LOG_FILE" 2>&1
    
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt >> "$LOG_FILE" 2>&1
    else
        warning "未找到 requirements.txt，安装基础依赖"
        pip install requests >> "$LOG_FILE" 2>&1
    fi
    
    success "虚拟环境设置完成"
}

# 运行机器人（带 screen 选项）
run_bot() {
    cd "$ASTROBOT_PATH" || error "无法进入 AstrBot 目录"
    
    echo
    log "Screen 允许您在后台运行机器人并稍后重新连接"
    echo "常用命令："
    echo "  Ctrl+A, D   - 分离当前会话"
    echo "  screen -r   - 重新连接到会话"
    echo "  screen -ls  - 列出所有会话"
    echo
    
    read -p "在 screen 会话中运行？(Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log "在当前终端中运行机器人..."
        
        # 检查并使用正确的环境
        if command -v uv >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
            export UV_DEFAULT_INDEX="$UV_INDEX"
            uv run main.py
        elif [ -d "venv" ]; then
            source venv/bin/activate
            python main.py
        else
            python$PYTHON_VERSION main.py
        fi
    else
        SESSION_NAME="astrobot_$(date +%s)"
        log "在 screen 会话中启动机器人: $SESSION_NAME"
        
        # 创建 screen 会话
        if command -v uv >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
            screen -S "$SESSION_NAME" -dm bash -c "cd '$ASTROBOT_PATH' && export UV_DEFAULT_INDEX='$UV_INDEX' && uv run main.py"
        elif [ -d "venv" ]; then
            screen -S "$SESSION_NAME" -dm bash -c "cd '$ASTROBOT_PATH' && source venv/bin/activate && python main.py"
        else
            screen -S "$SESSION_NAME" -dm bash -c "cd '$ASTROBOT_PATH' && python$PYTHON_VERSION main.py"
        fi
        
        sleep 2
        
        if screen -ls | grep -q "$SESSION_NAME"; then
            success "机器人在 screen 会话中启动: $SESSION_NAME"
            echo
            echo "连接到会话:   ${GREEN}screen -r $SESSION_NAME${NC}"
            echo "列出所有会话: ${GREEN}screen -ls${NC}"
            echo "分离会话:     ${YELLOW}Ctrl+A, D${NC}"
            echo
            log "您也可以稍后使用 'screen -r' 重新连接"
        else
            warning "启动 screen 会话失败，在当前终端运行"
            if command -v uv >/dev/null 2>&1 && [ -f "pyproject.toml" ]; then
                export UV_DEFAULT_INDEX="$UV_INDEX"
                uv run main.py
            elif [ -d "venv" ]; then
                source venv/bin/activate
                python main.py
            else
                python$PYTHON_VERSION main.py
            fi
        fi
    fi
}

# 显示使用说明
show_help() {
    echo
    echo "使用说明："
    echo "  1. 首次安装: 运行此脚本并按提示操作"
    echo "  2. 更新机器人: 脚本会自动检测现有安装并提供更新选项"
    echo "  3. 重新安装: 选择重新克隆选项"
    echo
    echo "环境说明："
    echo "  - UV: 新的 Python 包管理器，速度更快"
    echo "  - venv: 传统的 Python 虚拟环境"
    echo "  - Screen: 允许后台运行，断开 SSH 后仍可保持运行"
    echo
}

# 显示完成信息
show_completion() {
    echo
    echo "========================================"
    success "安装完成！"
    echo "========================================"
    echo
    echo "安装目录: $ASTROBOT_PATH"
    echo "日志文件: $LOG_FILE"
    echo
    
    if [ -d "$ASTROBOT_PATH/venv" ]; then
        echo "激活虚拟环境命令："
        echo "  cd $ASTROBOT_PATH && source venv/bin/activate"
        echo
    fi
    
    echo "手动启动机器人命令："
    if command -v uv >/dev/null 2>&1 && [ -f "$ASTROBOT_PATH/pyproject.toml" ]; then
        echo "  cd $ASTROBOT_PATH && export UV_DEFAULT_INDEX='$UV_INDEX' && uv run main.py"
    elif [ -d "$ASTROBOT_PATH/venv" ]; then
        echo "  cd $ASTROBOT_PATH && source venv/bin/activate && python main.py"
    else
        echo "  cd $ASTROBOT_PATH && python$PYTHON_VERSION main.py"
    fi
    echo
}

# 主安装函数
main() {
    # 显示 Logo
    show_logo
    
    # 创建日志文件
    touch "$LOG_FILE"
    
    log "开始安装 AstrBot..."
    log "日志文件: $LOG_FILE"
    
    # 检查环境
    check_proot
    
    # 检查网络
    if ! check_internet; then
        warning "网络连接不稳定，将继续使用代理尝试"
    fi
    
    # 安装步骤
    cd "$HOME" || error "无法进入主目录"
    install_packages
    install_python
    clone_repository
    setup_environment
    
    # 显示完成信息
    show_completion
    show_help
    
    # 询问是否运行机器人
    read -p "是否立即启动机器人？(Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        run_bot
    else
        log "您可以在准备好后手动启动机器人"
    fi
}

# 运行主函数
main "$@"