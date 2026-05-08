FROM node:20-alpine
WORKDIR /usr/src/app

RUN apk add --no-cache tzdata
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
 && echo $TZ > /etc/timezone

ENV HUSKY=0 \
    COREPACK_HOME=/usr/local/share/corepack \
    YARN_NODE_LINKER=node-modules

RUN corepack enable && corepack prepare yarn@4.14.1 --activate

RUN mkdir -p /usr/src/app/node_modules /usr/src/app/.next /home/node/.cache/yarn \
 && mkdir -p /usr/local/share/corepack \
 && chown -R node:node /usr/src/app /usr/local/share/corepack /home/node/.cache

USER node
EXPOSE 3000
