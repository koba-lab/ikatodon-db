#!/bin/bash
# ConoHa スタートアップスクリプト
# PostgreSQL 16 DB サーバー用初期設定

set -e

echo "=== ConoHa Startup Script Started at $(date) ==="

# システムの更新
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# 必要なパッケージのインストール
echo "Installing required packages..."
apt-get install -y \
    curl \
    wget \
    git

# Ansibleのインストール
echo "Installing Ansible..."
apt-get install -y ansible

# mastodonユーザーの作成
echo "Creating mastodon user..."
if ! id "mastodon" &>/dev/null; then
    useradd -m -s /bin/bash mastodon
    usermod -aG sudo mastodon
    echo "mastodon user created successfully"
else
    echo "mastodon user already exists"
fi

# authorized_keysファイルの作成（rootのキーをコピー）
if [ -f /root/.ssh/authorized_keys ]; then
    cp /root/.ssh/authorized_keys $SSH_DIR/authorized_keys
    chmod 600 $SSH_DIR/authorized_keys
    chown mastodon:mastodon $SSH_DIR/authorized_keys
    echo "SSH keys copied to mastodon user"
fi

# sudoersの設定（パスワードなしでsudo実行可能）
echo "mastodon ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/mastodon
chmod 440 /etc/sudoers.d/mastodon

# SSH設定の調整
echo "Configuring SSH daemon..."
SSH_CONFIG="/etc/ssh/sshd_config"

# SSH設定のバックアップ
cp $SSH_CONFIG $SSH_CONFIG.backup

# SSH設定の更新
cat >> $SSH_CONFIG << 'EOF'

# Custom SSH settings for mastodon user
AllowUsers root mastodon
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin yes
EOF

# SSHサービスの再起動
systemctl restart ssh

# ファイアウォールの基本設定
echo "Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow from 192.168.0.0/24 to any port 5432  # PostgreSQL (プライベートネットワーク)

# fail2banの設定
echo "Configuring fail2ban..."
systemctl enable fail2ban
systemctl start fail2ban

# 自動セキュリティ更新の有効化
echo "Enabling automatic security updates..."
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
systemctl enable unattended-upgrades

# 作業ディレクトリの作成
echo "Creating working directories..."
mkdir -p /opt/mastodon
chown mastodon:mastodon /opt/mastodon

# PostgreSQL用ディレクトリの作成
mkdir -p /var/lib/postgresql/16/{data,log}
chown -R 999:999 /var/lib/postgresql/16

# Docker GPGキーとリポジトリの追加
echo "Adding Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# パッケージリストの更新
apt-get update

# Dockerのインストール
echo "Installing Docker..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Dockerサービスの開始と有効化
systemctl start docker
systemctl enable docker

# mastodonユーザーをdockerグループに追加
usermod -aG docker mastodon

# Docker Composeスタンドアロン版のインストール
echo "Installing Docker Compose standalone..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Docker daemon設定
echo "Configuring Docker daemon..."
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "live-restore": true,
  "default-address-pools": [
    {
      "base": "172.17.0.0/12",
      "size": 24
    }
  ]
}
EOF

# Dockerサービスの再起動
systemctl restart docker

# プライベートネットワーク設定用のテンプレート作成
echo "Creating network configuration template..."
cat > /home/mastodon/setup-private-network.sh << 'EOF'
#!/bin/bash
# プライベートネットワーク設定スクリプト
# 使用方法: ./setup-private-network.sh <private_ip> [interface]

PRIVATE_IP="$1"
INTERFACE="${2:-ens4}"

if [ -z "$PRIVATE_IP" ]; then
    echo "Usage: $0 <private_ip> [interface]"
    echo "Example: $0 192.168.0.10 ens4"
    exit 1
fi

echo "Setting up private network..."
echo "IP: $PRIVATE_IP"
echo "Interface: $INTERFACE"

# netplan設定の作成
sudo tee /etc/netplan/11-localnetwork.yaml > /dev/null << NETPLAN_EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      addresses:
        - $PRIVATE_IP/24
      nameservers:
        addresses:
          - 8.8.8.8
          - 8.8.4.4
NETPLAN_EOF

# netplan適用
sudo netplan apply

echo "Private network configuration completed!"
echo "Interface $INTERFACE configured with IP $PRIVATE_IP"
EOF

chmod +x /home/mastodon/setup-private-network.sh
chown mastodon:mastodon /home/mastodon/setup-private-network.sh

# システム情報の表示
echo "Creating system info script..."
cat > /home/mastodon/system-info.sh << 'EOF'
#!/bin/bash
echo "=== ikatodon PostgreSQL 16 DB Server ==="
echo "Server Information:"
echo "  Hostname: $(hostname)"
echo "  OS: $(lsb_release -d | cut -f2)"
echo "  Kernel: $(uname -r)"
echo "  Uptime: $(uptime -p)"
echo ""
echo "Network Information:"
ip addr show | grep -E "inet.*scope global" | awk '{print "  " $NF ": " $2}'
echo ""
echo "Docker Status:"
if systemctl is-active --quiet docker; then
    echo "  Docker: Running"
    echo "  Version: $(docker --version)"
else
    echo "  Docker: Not running"
fi
echo ""
echo "Disk Usage:"
df -h | grep -E "^/dev" | awk '{print "  " $1 ": " $3 "/" $2 " (" $5 " used)"}'
echo ""
echo "Memory Usage:"
free -h | grep Mem | awk '{print "  Memory: " $3 "/" $2 " (" int($3/$2*100) "% used)"}'
echo ""
EOF

chmod +x /home/mastodon/system-info.sh
chown mastodon:mastodon /home/mastodon/system-info.sh

# 初回ログイン時にシステム情報を表示
echo "/home/mastodon/system-info.sh" >> /home/mastodon/.bashrc

# 最終的なシステム情報の表示
echo ""
echo "=== Setup Summary ==="
echo "✓ System packages updated"
echo "✓ Ansible installed"
echo "✓ mastodon user created with sudo privileges"
echo "✓ SSH keys configured"
echo "✓ Docker and Docker Compose installed"
echo "✓ Firewall configured"
echo "✓ Security tools (fail2ban) configured"
echo "✓ Automatic security updates enabled"
echo ""
echo "Next steps:"
echo "1. Configure private network: sudo /home/mastodon/setup-private-network.sh <private_ip>"
echo "2. SSH to server: ssh mastodon@<server_ip>"
echo "3. Run Ansible playbooks from mastodon directory"
echo ""
echo "=== ConoHa Startup Script Completed at $(date) ==="

# 完了通知
wall "ConoHa startup script completed successfully! Server is ready for PostgreSQL 16 setup."
