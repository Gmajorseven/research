FROM node:20-alpine

ARG THUNDERHUB_VERSION=v0.15.1

RUN apk add --no-cache git curl ca-certificates

RUN addgroup -g 1002 thunderhub \
    && adduser -u 1002 -G thunderhub -s /bin/sh -D thunderhub

WORKDIR /app

RUN git clone --depth 1 --branch ${THUNDERHUB_VERSION} \
    https://github.com/apotdevin/thunderhub.git /app \
    && chown -R thunderhub:thunderhub /app

USER thunderhub

RUN npm ci \
    && npm run build \
    && npm cache clean --force

EXPOSE 3001

ENV NODE_ENV=production

CMD ["npm", "run", "start"]
