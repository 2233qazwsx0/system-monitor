# System Monitor · Docker 部署

一键部署，零配置，跨平台。

## 快速开始

```bash
docker run -d \
  --name system-monitor \
  --restart unless-stopped \
  -p 8080:8080 \
  -v /proc:/host/proc:ro \
  -v /sys:/host/sys:ro \
  -v /:/rootfs:ro \
  --cap-add SYS_PTRACE \
  --security-opt seccomp=unconfined \
  ghcr.io/YOUR_USER/system-monitor:latest
```

然后打开 `http://localhost:8080`。

## 为什么需要特权模式

- `--cap-add SYS_PTRACE` + `--security-opt seccomp=unconfined`：允许 psutil 读取完整系统指标
- `-v /proc:/host/proc:ro`：容器内 `/proc` 默认只能看到容器内部

## 端口与数据

- 默认端口 `8080`，通过 `-p <host_port>:8080` 修改
- 数据纯内存运行，不持久化，重启即清

## Docker Compose

```yaml
version: "3.8"
services:
  system-monitor:
    image: ghcr.io/YOUR_USER/system-monitor:latest
    ports:
      - "8080:8080"
    restart: unless-stopped
    volumes:
      - /proc:/proc:ro
      - /sys:/sys:ro
      - /:/rootfs:ro
    cap_add:
      - SYS_PTRACE
    security_opt:
      - seccomp:unconfined
```

```bash
docker compose up -d
```
