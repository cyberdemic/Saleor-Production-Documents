FROM node:10 as builder
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
ARG API_URI
ARG SENTRY_DSN
ARG SENTRY_APM
ARG DEMO_MODE
ARG GTM_ID
ENV API_URI ${API_URI:-https://example.com/gqlapi/graphql/}
RUN API_URI=${API_URI} npm run build


FROM nginx:1.19.2-alpine
WORKDIR /app
COPY ./nginx/default.conf /etc/nginx/conf.d/default.conf
RUN chown -R nginx:nginx /app && chmod -R 755 /app && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid && \
    touch /var/log/error.log && \
    chown -R nginx:nginx /var/log/error.log
USER nginx
COPY --from=builder /app/dist/ /app/
