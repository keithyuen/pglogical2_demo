FROM registry.access.redhat.com/ubi9/ubi

ENV PG_MAJOR=16
ENV PGDATA=/var/lib/pgsql/${PG_MAJOR}/data

RUN dnf -y install --allowerasing dnf-utils curl git make gcc && \
    curl -1sSLf "https://downloads.enterprisedb.com/pdZe6pcnWIgmuqdR7v1L38rG6Z6wJEsY/enterprise/setup.rpm.sh" | bash && \
    dnf -y install postgresql${PG_MAJOR}-server postgresql${PG_MAJOR}-contrib edb-pg${PG_MAJOR}-pg-failover-slots1 edb-pg${PG_MAJOR}-pglogical2 && \
    dnf clean all

RUN mkdir -p ${PGDATA} && \
    mkdir -p /logs && \
    chown -R postgres:postgres /var/lib/pgsql && \
    chown -R postgres:postgres /logs && \
    chmod 700 ${PGDATA}

USER postgres
RUN /usr/pgsql-${PG_MAJOR}/bin/initdb -D ${PGDATA}

COPY --chown=postgres:postgres standby/postgresql.conf ${PGDATA}/
COPY --chown=postgres:postgres shared/pg_hba.conf ${PGDATA}/
COPY --chown=postgres:postgres docker-entrypoint.sh /usr/local/bin/

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["/usr/pgsql-16/bin/postgres", "-D", "/var/lib/pgsql/16/data"]