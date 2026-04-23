#!/bin/sh
set -e

# 不存在则创建 /app/config 目录，并将 /data 目录下的内容复制到 /app/config
if [ ! -f /app/config/.initialized ]; then
  cp -r /data/* /app/config/
  touch /app/config/.initialized
fi

if [ -f /root/.warp_parse/admin_api.token ]; then
  chmod 600 /root/.warp_parse/admin_api.token
fi

wparse deamon --work-root /app/config 