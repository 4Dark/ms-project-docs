
#!/bin/bash

# 定义要清理的端口
PORTS=(8281 8080 3000)

echo "=== 1. 开始清理旧进程 ==="
for port in "${PORTS[@]}"; do
  pid=$(lsof -t -i:$port)
  if [ -n "$pid" ]; then
    echo "端口 $port 被进程 $pid 占用，正在停止..."
    kill -9 $pid
  else
    echo "端口 $port 未被占用。"
  fi
done

echo "=== 2. 载入环境配置 ==="
source ~/.zshrc

echo "=== 3. 启动 ms-java-gateway (端口: 8281) ==="
cd /Users/pei/projects/ms-java-gateway && \
nohup env ENV_TYPE=dev \
  NACOS_SERVER_ADDR=tao-lan.122577.xyz:18848 \
  NACOS_USERNAME=nacos \
  NACOS_NAMESPACE=local \
  NACOS_PASSWORD=Qq062525 \
  mvn spring-boot:run -Dspring-boot.run.jvmArguments="-Xmx256m -Xms256m -XX:MaxMetaspaceSize=128m -XX:+UseG1GC -Dnacos.remote.client.grpc.timeout=10000 -Dnacos.remote.client.grpc.server.check.timeout=10000 -Dcom.alibaba.nacos.client.config.request.timeout=10000" > gateway_run.log 2>&1 &

echo "=== 4. 启动 ms-java-biz (端口: 8080) ==="
cd /Users/pei/projects/ms-java-biz && \
nohup env ENV_TYPE=dev \
  NACOS_SERVER_ADDR=tao-lan.122577.xyz:18848 \
  NACOS_USERNAME=nacos \
  NACOS_NAMESPACE=local \
  NACOS_PASSWORD=Qq062525 \
  mvn spring-boot:run -Dspring-boot.run.jvmArguments="-Dnacos.remote.client.grpc.timeout=10000 -Dnacos.remote.client.grpc.server.check.timeout=10000 -Dcom.alibaba.nacos.client.config.request.timeout=10000 -Dai-dev.integration.mode=ADAPTER" > biz_run.log 2>&1 &

echo "=== 5. 启动 ms-ng-view (端口: 3000) ==="
cd /Users/pei/projects/ms-ng-view && \
nohup npm run dev > ng_run.log 2>&1 &

echo "=== 重启指令已全部发送，正在后台初始化... ==="
echo "可以通过 'lsof -i :8281,8080,3000' 观察端口是否成功监听。"
