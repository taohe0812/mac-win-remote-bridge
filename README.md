# Mac-Windows 远程开发桥接方案

通过 FRP 内网穿透 + SSH，实现 Mac 上的 Claude Code 远程操控 Windows 主机执行命令、完成开发任务。

## 架构概览

```
┌──────────────┐         ┌──────────────────┐         ┌──────────────┐
│   Mac        │  SSH    │  Linux ECS       │  反向   │  Windows 10  │
│ (Claude Code)├────────►│  (公网 IP)       │◄────────┤  (内网)      │
│              │ :6022   │  FRP Server :7000│  隧道   │  FRP Client  │
└──────────────┘         └──────────────────┘         │  OpenSSH :22 │
                                                      └──────────────┘
```

**核心思路**：Mac 和 Windows 不在同一局域网，无法直连。借助一台有公网 IP 的 Linux ECS 做中转——Windows 通过 FRP 把本地 SSH 端口反向映射到 ECS 的 6022 端口，Mac 连接 ECS 的 6022 即可穿透到 Windows。

## 前置条件

| 机器 | 要求 |
|------|------|
| Mac | 已安装 SSH 客户端（macOS 自带） |
| Windows | Windows 10/11，管理员账户 |
| Linux ECS | 阿里云 ECS，有公网 IP，可 SSH 登录 |

## 部署步骤

### 第一步：ECS 部署 FRP Server

SSH 登录 ECS 后执行：

```bash
# 下载安装 FRP
cd /tmp
wget https://ghfast.top/https://github.com/fatedier/frp/releases/download/v0.61.1/frp_0.61.1_linux_amd64.tar.gz
tar -xzf frp_0.61.1_linux_amd64.tar.gz
mkdir -p /usr/local/frp
cp frp_0.61.1_linux_amd64/frps /usr/local/frp/
chmod +x /usr/local/frp/frps
```

编写配置文件 `/usr/local/frp/frps.toml`：

```toml
bindPort = 7000
auth.method = "token"
auth.token = "your_strong_token_here"
```

> 请将 `auth.token` 替换为你自己的强密码。

注册为系统服务：

```bash
cat > /etc/systemd/system/frps.service << 'EOF'
[Unit]
Description=FRP Server
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/frp/frps -c /usr/local/frp/frps.toml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now frps
```

验证运行状态：

```bash
systemctl status frps
ss -tlnp | grep 7000   # 应看到 7000 端口在监听
```

### 第二步：阿里云安全组放行端口

登录 [阿里云控制台](https://ecs.console.aliyun.com/) → 对应 ECS 实例 → 安全组 → 添加入方向规则：

| 端口范围 | 协议 | 授权对象 | 说明 |
|----------|------|----------|------|
| 7000/7000 | TCP | 0.0.0.0/0 | FRP 通信端口 |
| 6022/6022 | TCP | 0.0.0.0/0 | SSH 转发端口 |

> **安全建议**：生产环境中，授权对象建议限制为你的出口 IP，而非 `0.0.0.0/0`。

### 第三步：Windows 运行安装脚本

1. 将 `setup_windows_frp.ps1` 拷贝到 Windows 上
2. **右键 PowerShell → 以管理员身份运行**
3. 执行：

```powershell
Set-ExecutionPolicy RemoteSigned -Force
.\setup_windows_frp.ps1
```

脚本自动完成以下操作：
- 安装并启动 OpenSSH Server
- 设置默认 Shell 为 PowerShell
- 下载并安装 FRP Client
- 写入 FRP 配置（连接到你的 ECS）
- 注册 FRP Client 为 Windows 系统服务
- 配置 Mac 公钥免密登录

> **注意**：使用前需修改脚本中的 `serverAddr` 和 `auth.token`，与 ECS 上的 FRP Server 配置保持一致。

### 第四步：Mac 配置 SSH

编辑 `~/.ssh/config`，添加：

```
Host windev
    HostName <ECS公网IP>
    Port 6022
    User Administrator
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

## 验证连通性

```bash
# 从 Mac 执行
ssh windev "hostname"
# 应返回 Windows 主机名

ssh windev "systeminfo | findstr /B /C:'OS Name'"
# 应返回 Windows 版本信息

ssh windev "dir C:\"
# 应返回 C 盘目录列表
```

## Claude Code 使用方式

连通后，在 Mac 上的 Claude Code 中即可通过 SSH 远程操控 Windows：

```bash
# 执行单条命令
ssh windev "命令"

# 示例：查看 Node.js 版本
ssh windev "node --version"

# 示例：运行项目构建
ssh windev "cd C:\Projects\myapp && npm run build"

# 示例：查看进程
ssh windev "tasklist | findstr python"

# 示例：Git 操作
ssh windev "cd C:\Projects\myapp && git status"
```

## 运维管理

### 查看服务状态

```bash
# ECS 上查看 FRP Server 状态
systemctl status frps

# Windows 上查看 FRP Client 状态（PowerShell 管理员）
Get-Service frpc

# Windows 上查看 OpenSSH 状态
Get-Service sshd
```

### 重启服务

```bash
# ECS
systemctl restart frps

# Windows（PowerShell 管理员）
Restart-Service frpc
Restart-Service sshd
```

### 查看日志

```bash
# ECS 上查看 FRP Server 日志
journalctl -u frps -f

# Windows 上查看 FRP Client 日志
Get-EventLog -LogName Application -Source frpc -Newest 20
```

## 故障排查

| 症状 | 排查方向 |
|------|----------|
| Mac 连不上 `windev` | 1. 检查安全组是否放行 6022<br>2. `ssh ecs-relay` 看 ECS 是否可达<br>3. ECS 上 `ss -tlnp \| grep 6022` 看端口是否在监听 |
| ECS 6022 没监听 | Windows FRP Client 未连上。检查 Windows 上 `Get-Service frpc` 是否运行 |
| FRP Client 启动失败 | 1. 检查 token 是否与 Server 一致<br>2. 检查 ECS 安全组是否放行 7000<br>3. 手动运行 `C:\frp\frpc.exe -c C:\frp\frpc.toml` 看错误信息 |
| SSH 连上但命令超时 | Windows 防火墙可能阻止了 22 端口，检查入站规则 |
| 密钥认证失败 | 检查 `C:\ProgramData\ssh\administrators_authorized_keys` 权限，只允许 Administrators 和 SYSTEM |

## 安全建议

1. **修改默认端口**：FRP 的 7000 和 SSH 转发的 6022 可改为非常用端口
2. **限制来源 IP**：安全组中将 `0.0.0.0/0` 改为你 Mac 的出口 IP
3. **使用密钥认证**：已配置，建议在 Windows 的 `sshd_config` 中关闭密码认证
4. **定期更新 FRP**：关注 [FRP releases](https://github.com/fatedier/frp/releases) 获取安全更新
5. **启用 FRP TLS**：在 `frps.toml` 中添加 TLS 加密通信

## 文件说明

```
.
├── README.md                  # 本操作手册
├── setup_windows_frp.ps1      # Windows 一键安装脚本
├── configs/
│   ├── frps.toml.example      # FRP Server 配置模板
│   ├── frpc.toml.example      # FRP Client 配置模板
│   └── ssh_config.example     # Mac SSH config 模板
└── docs/
    └── architecture.md        # 架构设计说明（可选）
```
