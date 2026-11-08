ARG WEB_BASE_IMAGE=nginx:alpine
FROM ${WEB_BASE_IMAGE}

# Copy custom nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy Flutter web build output
RUN rm -rf /usr/share/nginx/html/*
COPY build/web /usr/share/nginx/html

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
