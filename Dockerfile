# 课程网站：用 Caddy 托管 docsify 静态文档（Railway 会注入 PORT）
FROM caddy:2.8-alpine
WORKDIR /srv
COPY index.html _sidebar.md README.md .nojekyll ./
COPY docs ./docs
COPY src ./src
COPY solutions ./solutions
COPY test ./test
COPY script ./script
CMD caddy file-server --root /srv --listen :${PORT:-8080}
