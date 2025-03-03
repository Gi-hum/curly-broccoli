#!/bin/bash

# 配置文件路径
VSFTPD_CONF="/etc/vsftpd/vsftpd.conf"
PAM_CONF="/etc/pam.d/vsftpd-virtual"
USER_DB="/etc/vsftpd/virtual_users.db"
USER_LIST="/etc/vsftpd/virtual_users.txt"
FTP_ROOT="/data/hyk"

# 安装 vsftpd 和相关工具
install_vsftpd() {
    echo "🔧 安装 vsftpd..."
    yum install -y vsftpd db4 db4-utils

    mkdir -p /etc/vsftpd/vusers

    # 配置 vsftpd	
    cat > "$VSFTPD_CONF" <<EOF
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
xferlog_enable=YES
connect_from_port_20=YES
ftpd_banner=Welcome to FTP Server
chroot_local_user=YES
allow_writeable_chroot=YES
listen=YES
listen_ipv6=NO
pam_service_name=vsftpd-virtual
user_sub_token=\$USER
local_root=$FTP_ROOT/\$USER
virtual_use_local_privs=YES
guest_enable=YES
guest_username=ftpuser
user_config_dir=/etc/vsftpd/vusers
anon_world_readable_only=NO
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
EOF

    # 创建 vsftpd 运行用户
    useradd -d /dev/null -s /sbin/nologin ftpuser

    # 配置 PAM 认证
    cat > "$PAM_CONF" <<EOF
auth required pam_userdb.so db=/etc/vsftpd/virtual_users
account required pam_userdb.so db=/etc/vsftpd/virtual_users
EOF

    systemctl restart vsftpd
    systemctl enable vsftpd
    echo "✅ vsftpd 安装完成！"
}

# 添加 FTP 用户
add_ftp_user() {
    echo "请输入 FTP 虚拟用户名:"
    read -r ftp_username

    # 检查用户是否已经存在
    if grep -q "$ftp_username" "$USER_LIST"; then
        echo "❌ 用户 $ftp_username 已经存在！"
        return
    fi

    echo "请输入 FTP 用户密码:"
    read -s ftp_password
    echo "请输入 FTP 目录名称 (默认路径 $FTP_ROOT/):"
    read -r ftp_dir_name

    ftp_dir="$FTP_ROOT/$ftp_dir_name"
    mkdir -p "$ftp_dir"
    chown -R ftpuser:ftpuser "$ftp_dir"
    chmod 755 "$ftp_dir"

    # 添加用户到 user_list
    echo "$ftp_username" >> "$USER_LIST"
    echo "$ftp_password" >> "$USER_LIST"

    # 生成 db4 数据库文件
    db_load -T -t hash -f "$USER_LIST" "$USER_DB"
    chmod 600 "$USER_DB" "$USER_LIST"

    # 创建用户配置
    cat > "/etc/vsftpd/vusers/$ftp_username" <<EOF
local_root=$ftp_dir
write_enable=YES
anon_world_readable_only=NO
anon_upload_enable=YES
anon_mkdir_write_enable=YES
anon_other_write_enable=YES
EOF

    systemctl restart vsftpd
    echo "✅ 用户 $ftp_username 已创建，FTP 目录：$ftp_dir"
}

# 删除 FTP 用户
delete_ftp_user() {
    if [[ ! -s "$USER_LIST" ]]; then
        echo "⚠️ 当前没有 FTP 用户！"
        return
    fi

    echo "📂 当前 FTP 用户列表："
    awk 'NR%2==1 {print int((NR+1)/2)". "$0}' "$USER_LIST"

    echo "请输入要删除的用户编号:"
    read -r user_num

    user_num=$((user_num * 2 - 1))
    ftp_username=$(sed -n "${user_num}p" "$USER_LIST")

    if [[ -z "$ftp_username" ]]; then
        echo "❌ 选择的用户不存在！"
        return
    fi

    # 查找用户目录（从 vusers 配置文件中读取 local_root）
    user_config="/etc/vsftpd/vusers/$ftp_username"
    if [[ -f "$user_config" ]]; then
        ftp_user_dir=$(grep "local_root=" "$user_config" | cut -d= -f2)
    fi

    # 删除用户信息
    sed -i -e "${user_num}d" -e "$((user_num + 1))d" "$USER_LIST"
    db_load -T -t hash -f "$USER_LIST" "$USER_DB"
    rm -f "$user_config"

    # 删除 FTP 用户目录
    if [[ -d "$ftp_user_dir" ]]; then
        rm -rf "$ftp_user_dir"
        echo "🗑️ 用户目录 $ftp_user_dir 已删除！"
    else
        echo "⚠️ 未找到用户目录，可能已被手动删除。"
    fi

    systemctl restart vsftpd
    echo "✅ 用户 $ftp_username 已删除！"
}

# 查看 FTP 用户
list_ftp_users() {
    if [[ ! -s "$USER_LIST" ]]; then
        echo "📂 当前没有 FTP 用户！"
    else
        echo "📂 当前 FTP 用户列表："
        awk 'NR%2==1 {print int((NR+1)/2)". "$0}' "$USER_LIST" | sed '/^$/d'
    fi
}

# 主菜单
while true; do
    echo "=============================="
    echo "    📌 vsftpd 管理脚本"
    echo "=============================="
    echo "1. 安装 vsftpd"
    echo "2. 添加 FTP 用户"
    echo "3. 删除 FTP 用户"
    echo "4. 查看 FTP 用户"
    echo "5. 退出"
    echo "=============================="
    read -rp "请选择操作 (1-5): " choice

    case $choice in
        1) install_vsftpd ;;
        2) add_ftp_user ;;
        3) delete_ftp_user ;;
        4) list_ftp_users ;;
        5) echo "🔚 退出脚本"; exit 0 ;;
        *) echo "❌ 选择错误，请输入 1-5" ;;
    esac
done
