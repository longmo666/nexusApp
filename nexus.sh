#!/bin/bash

# Nexus服务管理器脚本
APP_DIR="/root/nexusApp"
CONFIG_FILE="$APP_DIR/nexus_server.txt"
NEW_ADDRESS="0x123abc..."  # 默认地址

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "错误：此脚本必须使用root权限运行"
        exit 1
    fi
}

# 检查依赖命令是否存在
check_dependencies() {
    command -v git >/dev/null 2>&1 || {
        echo "需要安装git..."
        apt-get update
        apt-get install -y git
    }
    command -v systemctl >/dev/null 2>&1 || {
        echo "错误：systemd未安装"
        exit 1
    }
}

# 下载和配置
download_and_configure() {
    echo "正在设置Nexus应用..."
    check_root
    check_dependencies
    
    # 克隆或更新仓库
    if [ -d "$APP_DIR/.git" ]; then
        echo "检测到现有仓库，更新中..."
        (cd "$APP_DIR" && git pull)
    else
        rm -rf "$APP_DIR" 2>/dev/null
        echo "正在克隆仓库..."
        git clone http://github.com/szvone/nexusApp.git "$APP_DIR"
    fi
    
    # 设置新地址（如果已提供）
    read -p "请输入您的新地址（当前: $NEW_ADDRESS）: " user_input
    if [ -n "$user_input" ]; then
        NEW_ADDRESS="$user_input"
    fi
    
    # 更新配置文件
    if [ -f "$CONFIG_FILE" ]; then
        sed -i "s/^address: .*/address: ${NEW_ADDRESS}/" "$CONFIG_FILE"
        echo "地址已更新为: $NEW_ADDRESS"
    else
        echo "address: $NEW_ADDRESS" > "$CONFIG_FILE"
        echo "创建配置文件并设置地址: $NEW_ADDRESS"
    fi
    
    # 创建服务文件
    echo "正在创建服务文件..."
    
    # 服务端服务
    cat > /etc/systemd/system/nexus_server.service <<EOF
[Unit]
Description=Nexus Server
After=network.target

[Service]
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/nexus_server
Restart=always
RestartSec=10
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=nexus_server

[Install]
WantedBy=multi-user.target
EOF

    # 客户端服务（创建5个）
    for i in {1..5}; do
        cat > /etc/systemd/system/nexus_client_$i.service <<EOF
[Unit]
Description=Nexus Client $i
After=network.target nexus_server.service

[Service]
User=root
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/nexus_client
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    done

    # 设置执行权限
    chmod +x $APP_DIR/nexus_server $APP_DIR/nexus_client 2>/dev/null
    echo "已设置执行权限"

    # 重载systemd
    systemctl daemon-reload
    echo "Systemd配置已重载"
}

# 启动服务
start_services() {
    echo "正在启动服务..."
    systemctl start nexus_server
    for i in {1..5}; do
        systemctl start nexus_client_$i
    done
    systemctl enable nexus_server nexus_client_{1..5} >/dev/null 2>&1
    echo "服务已启动并启用开机自启"
}

# 停止服务
stop_services() {
    echo "正在停止服务..."
    for i in {1..5}; do
        systemctl stop nexus_client_$i 2>/dev/null
    done
    systemctl stop nexus_server 2>/dev/null
    echo "服务已停止"
}

# 更换地址
change_address() {
    read -p "请输入新地址: " NEW_ADDRESS
    if [ -z "$NEW_ADDRESS" ]; then
        echo "地址不能为空!"
        return
    fi
    
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "配置文件不存在! 请先运行设置"
        return
    fi
    
    # 检查服务是否运行
    is_running=$(systemctl is-active nexus_server)
    needs_restart=0
    if [ "$is_running" = "active" ]; then
        needs_restart=1
        stop_services
    fi
    
    # 更新配置文件
    sed -i "s/^address: .*/address: ${NEW_ADDRESS}/" "$CONFIG_FILE"
    echo "地址已更新为: $NEW_ADDRESS"
    
    # 如果需要则重启服务
    if [ "$needs_restart" -eq 1 ]; then
        start_services
    fi
}

# 查看服务端日志
show_logs() {
    journalctl -u nexus_server -f -n 100
}

# 状态检查
check_status() {
    echo "服务状态:"
    echo "------------------------------------------------"
    printf "%-20s %s\n" "服务名称" "状态"
    printf "%-20s %s\n" "-------------------" "-----------------"
    
    systemctl status nexus_server --no-pager | awk '/
        Loaded:/ {printf "%-20s %s\n", $1, "Loaded: " $4 $5}
        Active:/ {printf "%-20s %s\n", "", "Active: " $2 $3 $4 $5 $6}'
    
    for i in {1..5}; do
        systemctl status nexus_client_$i --no-pager | awk '/
            Loaded:/ {service="nexus_client_'$i'"; printf "%-20s %s\n", service, "Loaded: " $4 $5}
            Active:/ {printf "%-20s %s\n", "", "Active: " $2 $3 $4 $5 $6}'
    done
}

# 卸载
uninstall() {
    echo "正在卸载Nexus服务..."
    stop_services
    
    # 禁用并移除服务文件
    for i in {1..5}; do
        systemctl disable nexus_client_$i 2>/dev/null
        rm -f /etc/systemd/system/nexus_client_$i.service
    done
    
    systemctl disable nexus_server 2>/dev/null
    rm -f /etc/systemd/system/nexus_server.service
    systemctl daemon-reload
    
    # 保留应用目录但可配置清除
    read -p "是否删除应用目录? ($APP_DIR) [y/N]: " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        rm -rf "$APP_DIR"
    fi
    
    echo "卸载完成"
}

# 菜单界面
show_menu() {
    clear
    echo "================================================"
    echo "          Nexus 服务管理器 v1.0"
    echo "================================================"
    echo "  1) 下载并配置服务"
    echo "  2) 启动所有服务"
    echo "  3) 停止所有服务"
    echo "  4) 更换服务器地址"
    echo "  5) 查看服务端日志"
    echo "  6) 检查服务状态"
    echo "  7) 卸载服务"
    echo "  8) 退出"
    echo "================================================"
    
    current_address=$(grep '^address:' "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f2)
    [ -z "$current_address" ] && current_address="未设置"
    echo "当前地址: $current_address"
    echo "================================================"
    
    read -p "请选择操作 [1-8]: " choice
    case $choice in
        1) download_and_configure;;
        2) start_services;;
        3) stop_services;;
        4) change_address;;
        5) show_logs;;
        6) check_status;;
        7) uninstall;;
        8) exit 0;;
        *) echo "无效选择";;
    esac
    
    read -p "按回车键继续..."
}

# 主程序
if [ $# -eq 0 ]; then
    while true; do
        show_menu
    done
else
    case $1 in
        setup) download_and_configure;;
        start) start_services;;
        stop) stop_services;;
        change) change_address;;
        logs) show_logs;;
        status) check_status;;
        uninstall) uninstall;;
        *)
            echo "使用方式: $0 {setup|start|stop|change|logs|status|uninstall}"
            exit 1;;
    esac
fi
