#!/bin/bash

# Termux AstrBot Pro 安装脚本
# GitHub: https://github.com/xiewoc/astrbot_termux_installer
# 基于原脚本增强版

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # 无颜色

# 配置变量
TERMUX_HOME="$HOME"
PROOT_DISTRO_DIR="$TERMUX_HOME/.proot-distro"
DEFAULT_DISTRO="ubuntu"
DEFAULT_VERSION="20.04"
ASTROBOT_REPO="https://github.com/AstrBotDevs/AstrBot.git"
INSTALLER_REPO="https://github.com/xiewoc/astrbot_termux_installer.git"
PROXY_SITES=(
    "https://ghproxy.com/"
    "https://ghproxy.net/"
    "https://mirror.ghproxy.com/"
    "https://github.moeyy.xyz/"
)
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 进度动画
show_spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 显示Logo
show_logo() {
    clear
    echo -e "${CYAN}"
    cat << "LOGO"
    █████╗ ███████╗████████╗██████╗ ██████╗  ██████╗ ████████╗
   ██╔══██╗██╔════╝╚══██╔══╝██╔══██╗██╔══██╗██╔═══██╗╚══██╔══╝
   ███████║███████╗   ██║   ██████╔╝██████╔╝██║   ██║   ██║   
   ██╔══██║╚════██║   ██║   ██╔══██╗██╔══██╗██║   ██║   ██║   
   ██║  ██║███████║   ██║   ██║  ██║██████╔╝╚██████╔╝   ██║   
   ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═════╝  ╚═════╝    ╚═╝   
LOGO
    echo -e "${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${WHITE}    Termux AstrBot 专业安装脚本         ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "${YELLOW}版本: 2.0 | GitHub: xiewoc/astrbot_termux_installer${NC}"
    echo
}

# 日志系统
setup_logging() {
    LOG_DIR="$TERMUX_HOME/.astrbot_logs"
    INSTALL_LOG="$LOG_DIR/install_$(date +%Y%m%d_%H%M%S).log"
    mkdir -p "$LOG_DIR"
    
    # 清理旧日志（保留最近7天）
    find "$LOG_DIR" -name "install_*.log" -mtime +7 -delete 2>/dev/null
}

log() {
    local level="INFO"
    local color=$BLUE
    local message="$1"
    
    echo -e "${color}[$(date '+%H:%M:%S')] $message${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$INSTALL_LOG"
}

success() {
    echo -e "${GREEN}[✓] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1" >> "$INSTALL_LOG"
}

warning() {
    echo -e "${YELLOW}[!] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1" >> "$INSTALL_LOG"
}

error() {
    echo -e "${RED}[✗] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$INSTALL_LOG"
    exit 1
}

# 检查依赖
check_dependencies() {
    log "检查系统依赖..."
    
    # 检查是否在Termux中
    if ! command -v termux-setup-storage >/dev/null 2>&1; then
        warning "可能不在Termux环境中运行"
        read -p "是否继续？(y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] || error "请在Termux中运行此脚本"
    fi
    
    # 检查存储权限
    if [ ! -w "$TERMUX_HOME" ]; then
        warning "存储权限可能受限"
        echo "建议运行: termux-setup-storage"
        read -p "现在运行？(Y/n): " -n 1 -r
        echo
        [[ ! $REPLY =~ ^[Nn]$ ]] && termux-setup-storage
    fi
    
    success "基础检查完成"
}

# 网络检测
check_network() {
    log "检测网络连接..."
    
    local test_sites=(
        "https://github.com"
        "https://pypi.org"
        "https://mirrors.tuna.tsinghua.edu.cn"
    )
    
    local has_connection=false
    
    for site in "${test_sites[@]}"; do
        if curl -s --connect-timeout 5 "$site" >/dev/null 2>&1; then
            log "可访问: $(echo "$site" | cut -d'/' -f3)"
            has_connection=true
            break
        fi
    done
    
    if [ "$has_connection" = false ]; then
        warning "网络连接异常，将使用代理"
        return 1
    fi
    
    return 0
}

# 获取最佳代理
get_best_proxy() {
    log "测试代理速度..."
    
    local fastest_proxy=""
    local fastest_time=999
    
    for proxy in "${PROXY_SITES[@]}"; do
        local test_url="${proxy}https://github.com"
        local start_time=$(date +%s%3N)
        
        if curl -s --connect-timeout 3 "$test_url" >/dev/null 2>&1; then
            local end_time=$(date +%s%3N)
            local duration=$((end_time - start_time))
            
            if [ $duration -lt $fastest_time ]; then
                fastest_time=$duration
                fastest_proxy=$proxy
            fi
            log "代理 $proxy 响应时间: ${duration}ms"
        fi
    done
    
    if [ -n "$fastest_proxy" ]; then
        log "选择最快代理: $fastest_proxy"
        export SELECTED_PROXY="$fastest_proxy"
    else
        warning "所有代理都不可用"
        export SELECTED_PROXY=""
    fi
}

# 更新系统
update_system() {
    log "更新Termux系统..."
    
    echo "更新步骤:"
    echo "1. 更新软件包列表"
    echo "2. 升级已安装的包"
    echo "3. 安装必要工具"
    echo
    
    # 更新包列表
    if ! pkg update -y >/dev/null 2>&1; then
        warning "更新包列表失败，尝试继续..."
    fi
    
    # 升级包
    log "升级系统包..."
    pkg upgrade -y >/dev/null 2>&1 &
    show_spinner
    
    # 安装基础工具
    local base_packages=("proot-distro" "git" "wget" "curl" "python" "python-pip" "nano" "screen" "termux-api")
    
    for pkg_name in "${base_packages[@]}"; do
        if ! pkg list-installed | grep -q "$pkg_name"; then
            log "安装 $pkg_name..."
            pkg install -y "$pkg_name" >/dev/null 2>&1 &
            show_spinner
        fi
    done
    
    success "系统更新完成"
}

# 选择Linux发行版
select_distro() {
    echo -e "${CYAN}选择Linux发行版:${NC}"
    echo "1) Ubuntu 20.04 (推荐，兼容性好)"
    echo "2) Ubuntu 22.04 (较新版本)"
    echo "3) Debian 11 (稳定版)"
    echo "4) Alpine Linux (极简，资源占用少)"
    echo "5) Arch Linux (滚动更新，适合高级用户)"
    echo
    
    local choice
    read -p "请选择 (1-5): " choice
    
    case $choice in
        1)
            DISTRO_NAME="ubuntu"
            DISTRO_VERSION="20.04"
            ;;
        2)
            DISTRO_NAME="ubuntu"
            DISTRO_VERSION="22.04"
            ;;
        3)
            DISTRO_NAME="debian"
            DISTRO_VERSION="bullseye"
            ;;
        4)
            DISTRO_NAME="alpine"
            DISTRO_VERSION="latest"
            ;;
        5)
            DISTRO_NAME="archlinux"
            DISTRO_VERSION="latest"
            ;;
        *)
            DISTRO_NAME="ubuntu"
            DISTRO_VERSION="20.04"
            log "使用默认: Ubuntu 20.04"
            ;;
    esac
    
    # 显示选择信息
    echo
    echo -e "${GREEN}已选择: $DISTRO_NAME $DISTRO_VERSION${NC}"
    echo "所需空间: 约 200-500MB"
    echo "安装时间: 约 5-15分钟（取决于网络）"
    echo
    
    read -p "是否继续？(Y/n): " -n 1 -r
    echo
    [[ $REPLY =~ ^[Nn]$ ]] && exit 0
}

# 安装proot发行版
install_proot_distro() {
    log "安装 $DISTRO_NAME $DISTRO_VERSION..."
    
    # 检查是否已安装
    if proot-distro list 2>/dev/null | grep -q "^$DISTRO_NAME\$"; then
        warning "$DISTRO_NAME 已安装"
        
        echo "请选择:"
        echo "1) 重新安装（删除旧版）"
        echo "2) 使用现有版本"
        echo "3) 查看发行版信息"
        
        read -p "选择 (1-3): " choice
        case $choice in
            1)
                log "删除旧版本..."
                proot-distro remove "$DISTRO_NAME" || warning "删除失败，继续安装"
                ;;
            2)
                success "使用现有版本"
                return 0
                ;;
            3)
                proot-distro list
                read -p "按回车键继续..." -n 1
                return 1
                ;;
        esac
    fi
    
    # 显示进度信息
    echo
    echo -e "${YELLOW}开始下载 $DISTRO_NAME 镜像...${NC}"
    echo "这可能需要一些时间，请耐心等待"
    echo "网络状态会影响下载速度"
    echo
    
    # 开始安装
    if proot-distro install "$DISTRO_NAME"; then
        success "$DISTRO_NAME 安装成功！"
        
        # 显示磁盘使用情况
        echo
        log "磁盘使用情况:"
        du -sh "$PROOT_DISTRO_DIR/installed-rootfs/$DISTRO_NAME"
    else
        error "安装 $DISTRO_NAME 失败"
    fi
}

# 基础配置
basic_config() {
    log "配置 $DISTRO_NAME 基础环境..."
    
    proot-distro login "$DISTRO_NAME" -- bash -c "
        # 更新系统
        echo '更新系统包...'
        apt update && apt upgrade -y 2>/dev/null
        
        # 安装基础工具
        echo '安装基础工具...'
        apt install -y sudo wget curl git vim nano htop 2>/dev/null
        
        # 设置时区
        echo '设置时区为 Asia/Shanghai...'
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        
        # 创建用户目录
        echo '创建用户目录...'
        mkdir -p ~/projects ~/downloads ~/logs
        
        echo '基础配置完成！'
    " || warning "部分配置失败，但不影响主要功能"
    
    success "基础配置完成"
}

# 创建启动脚本
create_launcher() {
    log "创建启动脚本..."
    
    local launcher="$TERMUX_HOME/astrbot_launcher.sh"
    
    cat > "$launcher" << EOF
#!/bin/bash
# AstrBot 启动器 v2.0

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "\${GREEN}"
    echo "   ╔═══════════════════════════════════════╗"
    echo "   ║        AstrBot 启动管理器            ║"
    echo "   ╚═══════════════════════════════════════╝"
    echo -e "\${NC}"
}

start_astrobot() {
    echo -e "\${BLUE}[信息] 启动 AstrBot...\${NC}"
    
    proot-distro login $DISTRO_NAME -- bash -c "
        cd ~
        
        if [ ! -d \"AstrBot\" ]; then
            echo -e '\${RED}[错误] 未找到 AstrBot 目录\${NC}'
            echo '请先运行安装脚本: ./install_astrobot.sh'
            exit 1
        fi
        
        cd AstrBot
        
        # 检查环境
        if [ -f \"pyproject.toml\" ] && command -v uv >/dev/null 2>&1; then
            echo -e '\${GREEN}[信息] 使用 UV 启动...\${NC}'
            export UV_DEFAULT_INDEX=\"https://pypi.tuna.tsinghua.edu.cn/simple\"
            uv run main.py
        elif [ -d \"venv\" ]; then
            echo -e '\${GREEN}[信息] 使用虚拟环境...\${NC}'
            source venv/bin/activate
            python main.py
        elif command -v python3 >/dev/null 2>&1; then
            echo -e '\${GREEN}[信息] 使用 Python3...\${NC}'
            python3 main.py
        else
            echo -e '\${RED}[错误] 未找到 Python 环境\${NC}'
            exit 1
        fi
    "
}

start_with_screen() {
    echo -e "\${BLUE}[信息] 在 Screen 中启动...\${NC}"
    
    SESSION_NAME="astrobot_\$(date +%s)"
    
    proot-distro login $DISTRO_NAME -- bash -c "
        cd ~/AstrBot 2>/dev/null || { echo '目录不存在'; exit 1; }
        
        # 创建 screen 会话
        screen -dmS \$SESSION_NAME bash -c '
            if [ -f \"pyproject.toml\" ] && command -v uv >/dev/null 2>&1; then
                export UV_DEFAULT_INDEX=\"https://pypi.tuna.tsinghua.edu.cn/simple\"
                uv run main.py
            elif [ -d \"venv\" ]; then
                source venv/bin/activate
                python main.py
            else
                python3 main.py
            fi
        '
        
        if screen -list | grep -q \$SESSION_NAME; then
            echo -e '\${GREEN}[成功] Screen 会话创建: '\$SESSION_NAME\${NC}
            echo
            echo '命令:'
            echo '  查看会话: screen -list'
            echo '  进入会话: screen -r '\$SESSION_NAME
            echo '  退出会话: Ctrl+A, D'
        else
            echo -e '\${RED}[错误] 创建 Screen 会话失败\${NC}'
        fi
    "
}

update_astrobot() {
    echo -e "\${BLUE}[信息] 更新 AstrBot...\${NC}"
    
    proot-distro login $DISTRO_NAME -- bash -c "
        cd ~/AstrBot 2>/dev/null || { echo '目录不存在'; exit 1; }
        
        if [ -d \".git\" ]; then
            echo '拉取最新代码...'
            git pull
            echo '更新依赖...'
            
            if [ -f \"pyproject.toml\" ] && command -v uv >/dev/null 2>&1; then
                uv sync
            elif [ -d \"venv\" ]; then
                source venv/bin/activate
                pip install -r requirements.txt
            fi
            
            echo -e '\${GREEN}[成功] 更新完成\${NC}'
        else
            echo -e '\${RED}[错误] 不是 Git 仓库\${NC}'
        fi
    "
}

show_logs() {
    echo -e "\${BLUE}[信息] 查看日志...\${NC}"
    
    proot-distro login $DISTRO_NAME -- bash -c "
        echo '=== 最近日志 ==='
        find ~/AstrBot -name \"*.log\" -type f | head -3 | while read log; do
            echo
            echo \"日志文件: \$log\"
            echo \"最后更新: \$(stat -c %y \"\$log\" 2>/dev/null || echo '未知')\"
            echo '最后10行:'
            tail -10 "\$log" 2>/dev/null || echo '无法读取'
            echo
        done
        
        if [ -f \"~/astrobot_install.log\" ]; then
            echo '=== 安装日志 ==='
            tail -20 ~/astrobot_install.log
        fi
    "
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        echo "请选择操作:"
        echo "1) 启动 AstrBot (前台运行)"
        echo "2) 启动 AstrBot (Screen 后台)"
        echo "3) 进入 Linux 终端"
        echo "4) 更新 AstrBot"
        echo "5) 查看日志"
        echo "6) 清理缓存"
        echo "7) 重启服务"
        echo "8) 退出"
        echo
        
        read -p "选择 (1-8): " choice
        
        case \$choice in
            1)
                start_astrobot
                ;;
            2)
                start_with_screen
                ;;
            3)
                echo -e "\${BLUE}[信息] 进入 $DISTRO_NAME...\${NC}"
                proot-distro login $DISTRO_NAME
                ;;
            4)
                update_astrobot
                ;;
            5)
                show_logs
                ;;
            6)
                echo -e "\${BLUE}[信息] 清理缓存...\${NC}"
                proot-distro login $DISTRO_NAME -- bash -c "apt clean && rm -rf /tmp/*"
                echo -e "\${GREEN}[成功] 缓存清理完成\${NC}"
                ;;
            7)
                echo -e "\${YELLOW}[警告] 重启服务...\${NC}"
                pkill -f "astrobot" 2>/dev/null
                sleep 2
                start_with_screen
                ;;
            8)
                echo -e "\${GREEN}[信息] 退出\${NC}"
                exit 0
                ;;
            *)
                echo -e "\${RED}[错误] 无效选择\${NC}"
                ;;
        esac
        
        echo
        read -p "按回车键继续..." -n 1
    done
}

# 启动主菜单
main_menu
EOF
    
    chmod +x "$launcher"
    success "启动器创建完成: $launcher"
}

# 安装AstrBot
install_astrobot() {
    log "安装 AstrBot 机器人..."
    
    echo
    echo "安装选项:"
    echo "1) 自动安装 (推荐)"
    echo "2) 手动安装"
    echo "3) 从备份恢复"
    echo
    
    read -p "选择安装方式 (1-3): " install_method
    
    case $install_method in
        1)
            auto_install_astrobot
            ;;
        2)
            manual_install_astrobot
            ;;
        3)
            restore_backup
            ;;
        *)
            auto_install_astrobot
            ;;
    esac
}

# 自动安装
auto_install_astrobot() {
    log "开始自动安装 AstrBot..."
    
    proot-distro login "$DISTRO_NAME" -- bash -c "
        echo '=== AstrBot 自动安装 ==='
        echo
        cd ~
        
        # 克隆仓库
        if [ ! -d \"AstrBot\" ]; then
            echo '克隆 AstrBot 仓库...'
            
            # 尝试直接克隆
            if git clone '$ASTROBOT_REPO' AstrBot; then
                echo '克隆成功'
            else
                echo '克隆失败，尝试使用代理...'
                
                # 尝试多个代理
                for proxy in '${PROXY_SITES[@]}'; do
                    echo \"尝试代理: \$proxy\"
                    if git clone \"\${proxy}$ASTROBOT_REPO\" AstrBot; then
                        echo \"使用代理 \$proxy 克隆成功\"
                        break
                    fi
                done
                
                if [ ! -d \"AstrBot\" ]; then
                    echo '所有克隆尝试都失败'
                    exit 1
                fi
            fi
        else
            echo 'AstrBot 目录已存在'
            cd AstrBot
            git pull || echo '更新失败，使用现有版本'
        fi
        
        cd ~/AstrBot
        
        # 安装Python依赖
        echo
        echo '安装Python依赖...'
        
        # 检查Python版本
        if command -v python3.10 >/dev/null 2>&1; then
            PYTHON_CMD='python3.10'
        elif command -v python3 >/dev/null 2>&1; then
            PYTHON_CMD='python3'
        else
            echo '安装 Python3.10...'
            apt update
            apt install -y python3.10 python3.10-venv
            PYTHON_CMD='python3.10'
        fi
        
        # 选择安装方式
        echo
        echo '选择安装方式:'
        echo '1) UV (快速安装，推荐)'
        echo '2) venv (传统虚拟环境)'
        echo '3) 系统环境 (不推荐)'
        read -p '选择 (1-3): ' install_choice
        
        case \$install_choice in
            1)
                install_with_uv
                ;;
            2)
                install_with_venv
                ;;
            3)
                install_system_wide
                ;;
            *)
                install_with_uv
                ;;
        esac
        
        echo
        echo '=== 安装完成 ==='
        echo '启动命令: ./astrbot_launcher.sh'
        echo '目录位置: ~/AstrBot'
    "
}

# 使用UV安装
install_with_uv() {
    cat << 'EOF'
    echo '使用 UV 安装...'
    
    # 安装 UV
    if ! command -v uv >/dev/null 2>&1; then
        echo '安装 UV...'
        curl -LsSf https://astral.sh/uv/install.sh | sh
        export PATH="$HOME/.cargo/bin:$PATH"
    fi
    
    # 设置镜像源
    export UV_DEFAULT_INDEX="https://pypi.tuna.tsinghua.edu.cn/simple"
    
    # 同步依赖
    uv sync
    
    echo 'UV 安装完成'
EOF
}

# 使用venv安装
install_with_venv() {
    cat << 'EOF'
    echo '使用 venv 安装...'
    
    # 创建虚拟环境
    python3 -m venv venv
    source venv/bin/activate
    
    # 设置pip镜像
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    
    # 安装依赖
    if [ -f "requirements.txt" ]; then
        pip install -r requirements.txt
    else
        pip install requests
    fi
    
    echo 'venv 安装完成'
EOF
}

# 系统级安装
install_system_wide() {
    cat << 'EOF'
    echo '系统级安装...'
    
    # 更新pip
    pip3 install --upgrade pip
    
    # 设置镜像
    pip3 config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple
    
    # 安装依赖
    if [ -f "requirements.txt" ]; then
        pip3 install -r requirements.txt
    fi
    
    echo '系统级安装完成'
EOF
}

# 完成安装
finish_installation() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${WHITE}       安装完成！                      ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${CYAN}重要信息:${NC}"
    echo "  📂 Linux 系统: $DISTRO_NAME $DISTRO_VERSION"
    echo "  📂 AstrBot 目录: ~/AstrBot (在Linux内)"
    echo "  📄 启动器: ./astrbot_launcher.sh"
    echo "  📄 日志目录: ~/.astrbot_logs"
    echo
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  启动机器人: ./astrbot_launcher.sh"
    echo "  进入Linux: proot-distro login $DISTRO_NAME"
    echo "  查看日志: tail -f ~/.astrbot_logs/*.log"
    echo
    echo -e "${MAGENTA}Screen 使用指南:${NC}"
    echo "  创建会话: screen -S astrobot"
    echo "  分离会话: Ctrl+A, D"
    echo "  恢复会话: screen -r astrobot"
    echo "  列出会话: screen -ls"
    echo "  结束会话: screen -X -S astrobot quit"
    echo
    echo -e "${BLUE}注意事项:${NC}"
    echo "  1. 确保Termux有存储权限"
    echo "  2. 建议使用Screen保持后台运行"
    echo "  3. 定期备份重要数据"
    echo "  4. 网络问题可尝试切换代理"
    echo
    
    # 创建快捷命令
    cat > "$TERMUX_HOME/.bash_aliases" << ALIASES
# AstrBot 别名
alias astrobot='./astrbot_launcher.sh'
alias astro-logs='tail -f ~/.astrbot_logs/*.log'
alias astro-linux='proot-distro login $DISTRO_NAME'
alias astro-update='cd ~ && ./install_termux_astrobot.sh'
alias astro-status='ps aux | grep -i astrobot'
ALIASES
    
    echo -e "${GREEN}快捷命令已添加到 ~/.bash_aliases${NC}"
    echo "重新打开终端或运行: source ~/.bash_aliases"
    echo
    
    # 询问是否启动
    read -p "是否现在启动机器人？(Y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
        echo "启动机器人..."
        sleep 2
        cd "$TERMUX_HOME" && ./astrbot_launcher.sh
    else
        echo -e "${GREEN}安装完成！使用 ./astrbot_launcher.sh 启动机器人${NC}"
    fi
}

# 主函数
main() {
    # 设置日志
    setup_logging
    
    # 显示Logo
    show_logo
    
    # 检查依赖
    check_dependencies
    
    # 网络检测
    if ! check_network; then
        get_best_proxy
    fi
    
    # 更新系统
    update_system
    
    # 选择发行版
    select_distro
    
    # 安装proot
    install_proot_distro
    
    # 基础配置
    basic_config
    
    # 创建启动器
    create_launcher
    
    # 安装AstrBot
    install_astrobot
    
    # 完成安装
    finish_installation
}

# 异常处理
trap 'echo -e "${RED}[错误] 脚本异常退出${NC}"; exit 1' ERR

# 运行主函数
main "$@"
