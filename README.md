# docker-shoes

为 [cfal/shoes](https://github.com/cfal/shoes) 编译macos/win/linux 可执行文件，以及 docker for Alpine

# 使用说明

配置文件示例见 [cfal/shoes/example] (https://github.com/cfal/shoes/tree/master/examples)

此处介绍与nginx配合使用的几项设置，示例详见本仓库[example_for_nginx](https://github.com/lekai63/docker-shoes/tree/master/example_for_nginx)

## nginx（server） + shoes（server） + mihomo/clash（client）

### docker compose

以下compose 供参考

```yml
services:
  nginx-ui:
    image: uozi/nginx-ui
    container_name: nginx-ui
    restart: always
    tty: true
    stdin_open: true
    environment:
      - TZ=Asia/Shanghai
      # 预定义用户
      - NGINX_UI_PREDEFINED_USER_NAME=yourname
      - NGINX_UI_PREDEFINED_USER_PASSWORD=yourpasswd
      # 配置
      - NGINX_UI_CERT_RENEWAL_INTERVAL=70 # 证书签发的时间间隔，默认7
      - NGINX_UI_CERT_EMAIL=yourname@yourmail.com
      # 设置webauth后才能支持passkey
      - NGINX_UI_WEBAUTHN_RP_DISPLAY_NAME=yourname
      - NGINX_UI_WEBAUTHN_RPID=nginx.example.com
      - NGINX_UI_WEBAUTHN_RP_ORIGINS=https://nginx.example.com

    volumes:
      - ./data/nginx:/etc/nginx
      - ./data/nginx-ui:/etc/nginx-ui
      - ./data/www/static:/var/www/static
    ports:
      - "80:80"
      - "443:443"
    networks:
      - docker_default

  shoes:
    image: lekai63/shoes:v0.1.3
    container_name: shoes
    # nginx docker 直接转发到 shoes docker，在shoes docker中可不暴露ports到主机
    #ports:
    #    - "5555:5555"
    volumes:
      - ./data/shoes/server.yaml:/app/config.yaml
    restart: unless-stopped
```

### nginx

监听443端口，根据域名（host）不同，分流至不同的后端docker。使用nginx-ui管理及自动签发证书，新增shoes.example.com 分流至 ws+ss/vmess.

若你本来使用xray回落或nginx stream分流，请根据自身情况调整。

主要配置如下

```
map $http_upgrade $connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    # 监听的域名
    server_name shoes.example.com;
    # 使用的证书，注意修改为自己的证书！
    ssl_certificate /etc/nginx/ssl/shoes.example.com_2048/fullchain.cer;
    ssl_certificate_key /etc/nginx/ssl/shoes.example.com_2048/private.key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;


    # 匹配/vv 或 /ss 。如果只需要匹配一个，可以写  location /vv
   location ~ ^/(vv|ss)$ {

      if ($http_upgrade != "websocket") {
            return 404;
        }

    # 确保 WebSocket upgrade
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";

    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Server $host;
    proxy_set_header Forwarded $proxy_add_forwarded;

    # 超时设置，可以不要
    proxy_connect_timeout 60s;
    proxy_read_timeout 60s;
    proxy_send_timeout 60s;

    # 如果你的nginx运行在docker中，转发到shoes docker 的5555端口（确保两个容器在同一个docker network下，shoes对应docker中的container_name）

    proxy_pass http://shoes:5555;
    # 如果你的nginx直接运行，可以按如下方式配置，注意shoes端口需映射到主机
    # proxy_pass http://127.0.0.1:5555;

    }
}

```

### shoes(server)

服务端使用shoes，轻量。

**注意配置中的以下字段，没有写host可能导致nginx分流过来，但服务端shoes auth不通过**

```
matching_headers:
  host: "shoes.example.com" # 添加 host 以便nginx分流
```

你也可以增加额外的header，要求client和server一致

完整配置

```yml
- address: 0.0.0.0:5555
  transport: tcp
  protocol:
    type: ws
    targets:
      # 监听vmess，clash-verge可以连接到/vv
      - matching_path: /vv
        matching_headers:
          host: "shoes.example.com" # 添加 host 以便nginx分流
        protocol:
          type: vmess
          cipher: any
          user_id: 2b8798ff-8b47-452e-8051-8c775616b85b # 注意与client一致

      # 监听ss，使用shoes作为客户端可以连接到/ss，但clash-verge似乎不能连接到/ss
      - matching_path: /ss
        matching_headers:
          host: "shoes.example.com" # 添加 host
        protocol:
          type: shadowsocks
          cipher: 2022-blake3-aes-256-gcm
          # 密码生成命令 openssl rand -base64 32
          # 最后的32表示密码位数，如果你用2022-blake3-aes-123-gcm，则命令为openssl rand -base64 16
          password: L5w9Lh/hBZjnIhhPB/suDnXR/MRl+OW1MfCpyxEFn3Q=
  rules:
    - mask: 0.0.0.0/0
      action: allow
      # Direct connection, don't forward requests through another proxy.
      client_proxy: direct
```

### mihomo（client）

客户端内核使用mihomo（clash meta），使用clash-verge作为UI

配置文件中增加一个proxy

```yml
proxies:
  - name: shoes_vmess
    type: vmess
    server: 1.2.3.4
    port: 443
    udp: false
    uuid: 2b8798ff-8b47-452e-8051-8c775616b85b
    alterId: 0
    cipher: auto
    tls: true
    servername: shoes.example.com
    alpn:
      - h2
      - http/1.1
    network: ws
    ws-opts:
      path: /vv
      headers:
        Host: "shoes.example.com" # 注意host与server端一致
      v2ray-http-upgrade: false
      v2ray-http-upgrade-fast-open: false
```

如需使用shoes作为client，可参考本仓库 [example_for_nginx/client.yaml]
