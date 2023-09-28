FROM node:20-alpine3.17 as react-build
COPY sca_react/ sca_react/
WORKDIR sca_react/
RUN yarn install --frozen-lockfile
RUN yarn build

# Build mediasoup-worker binary as separate stage to decrease build time
FROM node:20-alpine3.17 as mediasoup-worker-build
RUN apk add --update make python3 py3-pip gcc g++ linux-headers
WORKDIR mediasoup/
RUN yarn add mediasoup@3

FROM node:20-alpine3.17 as nest-build
RUN apk add --update make python3 py3-pip gcc g++ linux-headers
COPY sca_nest/ sca_nest/
WORKDIR sca_nest/
COPY --from=mediasoup-worker-build mediasoup/node_modules/mediasoup/worker/out/Release/mediasoup-worker mediasoup/mediasoup-worker
# Mediasoup will skip worker build if MEDIASOUP_WORKER_BIN specified
RUN MEDIASOUP_WORKER_BIN="mediasoup/mediasoup-worker" yarn install --frozen-lockfile
RUN yarn build
RUN npx prisma generate
RUN npx prisma migrate deploy 

FROM node:20-alpine3.17
WORKDIR sca
COPY --from=nest-build sca_nest/dist/ dist/
COPY --from=nest-build /sca_nest/node_modules/ node_modules/
COPY --from=nest-build /sca_nest/.env .env
COPY --from=nest-build /sca_nest/prisma/ prisma/
COPY --from=react-build /sca_react/dist/ frontend/
COPY --from=mediasoup-worker-build mediasoup/node_modules/mediasoup/worker/out/Release/mediasoup-worker mediasoup/mediasoup-worker
ENV MEDIASOUP_WORKER_BIN="mediasoup/mediasoup-worker"
ENTRYPOINT [ "node", "dist/src/main" ]
