FROM node:20-alpine
WORKDIR /usr/src/app

RUN apk add --no-cache tzdata
ENV TZ=Asia/Seoul
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
 && echo $TZ > /etc/timezone

RUN corepack enable && corepack prepare yarn@4 --activate

# 의존성 캐시 최적화
COPY package.json yarn.lock ./
RUN yarn install || true

# 소스는 볼륨으로 마운트되므로 빌드 단계 복사는 생략 가능
USER node
EXPOSE 3000
