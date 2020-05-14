FROM alpine:latest

COPY rollback/restore_efs.sh /

USER root
RUN mkdir -p /mnt/efs_drive && \
    ln -s /bitnami/wordpress /mnt/efs_drive/public
RUN chmod +x /restore_efs.sh
RUN adduser --disabled-password --no-create-home --uid 1001 bitnami

ENTRYPOINT [ "/restore_efs.sh" ]