# Placeholder for DigitalOcean’s “Connect repository” scanner only.
# Do not use this as your production app — deploy using app.yaml at the repo root.
FROM nginx:alpine
RUN echo '<!doctype html><title>rloko</title><p>Deploy with app.yaml in this repository.</p>' \
  > /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
