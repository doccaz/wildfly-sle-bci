# Pinned to 21: openjdk:latest is Java 25, which dropped java.security.Policy
# and crashes jboss-modules in WildFly 32 (UnsupportedOperationException).
FROM registry.suse.com/bci/openjdk:21

LABEL maintainer="erico.mendonca@suse.com"

ENV WILDFLY_VERSION=32.0.0.Final \
    JBOSS_HOME=/opt/wildfly

RUN groupadd -g 101 wildfly \
    && useradd -u 101 -g wildfly -m -d /opt/wildfly -s /sbin/nologin wildfly \
    && curl -fL -o /tmp/wildfly.tar.gz \
         https://github.com/wildfly/wildfly/releases/download/${WILDFLY_VERSION}/wildfly-${WILDFLY_VERSION}.tar.gz \
    && tar xzf /tmp/wildfly.tar.gz -C /opt \
    && rm -rf ${JBOSS_HOME} \
    && mv /opt/wildfly-${WILDFLY_VERSION} ${JBOSS_HOME} \
    && rm -f /tmp/wildfly.tar.gz \
    && chown -R wildfly:wildfly ${JBOSS_HOME}

COPY --chown=wildfly:wildfly deployments/ ${JBOSS_HOME}/standalone/deployments/

USER wildfly
WORKDIR ${JBOSS_HOME}

EXPOSE 8080 9990

CMD ["bin/standalone.sh", "-c", "standalone.xml", "-b", "0.0.0.0", "-bmanagement", "0.0.0.0"]
