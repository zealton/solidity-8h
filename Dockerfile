# 课程网站：用 Caddy 托管静态页面（index.html + assets + Markdown 讲义）（Railway 会注入 PORT）
FROM caddy:2.8-alpine
WORKDIR /srv
COPY index.html README.md ./
COPY assets ./assets
COPY docs ./docs
COPY src ./src
COPY solutions ./solutions
COPY test ./test
COPY script ./script
CMD caddy file-server --root /srv --listen :${PORT:-8080}
