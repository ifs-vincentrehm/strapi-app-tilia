# ARG IMAGE_TAG
# FROM bitnami/wordpress:$IMAGE_TAG
# COPY wordpress-install/setup_wp.sh /docker-entrypoint-init.d/setup.sh
# USER root
# RUN apt-get update && \
#     apt-get install nfs-common dnsutils -y && \
#     mkdir -p /mnt/efs_drive && \
#     ln -s /bitnami/wordpress /mnt/efs_drive/public
# ENV WORDPRESS_SCHEME 'https'
# ENV WORDPRESS_USERNAME 'admin'

# RUN mkdir /bivwak-auto-update-plugin
# COPY wordpress-install/bivwak-auto-update-plugin.php /bivwak-auto-update-plugin/
# COPY wordpress-install/bivwak-auto-update-addons.json /bivwak-auto-update-plugin/
# COPY wordpress-install/bivwak-auto-update-plugin-installer.sh /bivwak-auto-update-plugin/

FROM strapi/base

WORKDIR /my-path

COPY ./application .

RUN yarn install
ENV NODE_ENV production
RUN yarn build

EXPOSE 1337

CMD ["yarn", "start"]