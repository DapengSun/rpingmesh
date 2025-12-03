# 1. 复制到系统 PATH 目录（任意一个即可）
sudo cp docker-compose-linux-aarch64 /usr/local/bin/docker-compose

# 2. 赋可执行权限
sudo chmod +x /usr/local/bin/docker-compose

# 3. 可选：再做个软链，确保能被任意位置调用
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# 4. 验证
docker-compose version
