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

# # Because installing against already populated database :
# # ENV WORDPRESS_SKIP_INSTALL 'yes'
# USER 1001

FROM node
###################################
# INSTALL TOOLS
###################################
RUN apt-get update && apt-get upgrade && \
  npm install -g typescript@3.6.3 && \
  npm install -g aws-cdk@1.9.0

RUN npx create-strapi-app strapi-colivme
 
EXPOSE 8080
