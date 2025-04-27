ARG APP_VERSION
ARG BINARY_NAME

FROM alpine:3.18

# 设置工作目录
WORKDIR /app
# 复制二进制文件和配置文件到容器中
COPY ${BINARY_NAME} /app/shoes
COPY config.yaml /app/config.yaml

# 设置可执行权限
RUN chmod +x /app/shoes

# 添加版本标签
LABEL version="${APP_VERSION}"

EXPOSE 5555
# 设置入口点
ENTRYPOINT ["/app/shoes"]
CMD ["/app/config.yaml"]
