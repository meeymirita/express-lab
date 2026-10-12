# Образ лабы: Node 24 LTS, как в паспорте лабы (`express_lab_plan.md`)
FROM node:24-alpine
RUN apk add --no-cache bash curl
WORKDIR /work
CMD ["node"]
