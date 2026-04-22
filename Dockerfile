# This file is only so DigitalOcean’s “Connect repository” step finds a supported
# file at the monorepo root. The real deployment is defined in `app.yaml` (and
# `.do/app.yaml`, same content): two services built from `rloco-backend` and
# `rloco-frontend`. After the app exists, remove this component if the UI added a
# useless “web” service from this Dockerfile, or create the app from the app spec
# directly (skip autodetect). This image is a harmless placeholder.
FROM nginx:alpine
RUN echo '<!doctype html><title>rloko</title><p>Use the app spec in this repo (app.yaml).</p>' \
  > /usr/share/nginx/html/index.html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
