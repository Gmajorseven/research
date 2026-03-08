FROM node:20-alpine

ARG THUNDERHUB_VERSION=v0.13.31

RUN apk add --no-cache git curl ca-certificates

RUN addgroup -g 1002 thunderhub \
    && adduser -u 1002 -G thunderhub -s /bin/sh -D thunderhub

WORKDIR /app

RUN git clone --depth 1 --branch ${THUNDERHUB_VERSION} \
    https://github.com/apotdevin/thunderhub.git /app \
    && chown -R thunderhub:thunderhub /app

USER thunderhub

# Ignore TypeScript errors caused by @types/react@18 incompatibility with styled-modal-provider
RUN sed -i 's/module.exports = {/module.exports = { typescript: { ignoreBuildErrors: true },/' src/client/next.config.js

RUN yarn install \
    && yarn build \
    && yarn cache clean

EXPOSE 3000

ENV NODE_ENV=production

CMD ["yarn", "start"]
