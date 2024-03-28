VERSION 0.8
FROM scratch

docker-product-base:
    FROM DOCKERFILE -f ./Dockerfile ./
    ARG EARTHLY_TARGET_TAG_DOCKER
    ARG IMAGE_TAG=$EARTHLY_TARGET_TAG_DOCKER
    SAVE IMAGE --cache-from deskpro/docker-product-base:main deskpro/docker-product-base:$IMAGE_TAG
