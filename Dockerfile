ARG JAVA_TAG=21
FROM registry.suse.com/bci/openjdk:${JAVA_TAG}

LABEL maintainer="erico.mendonca@suse.com"

# WildFly 32.x needs JAVA_TAG=21 or older: its jboss-modules bootstrap calls
# the java.security.Policy API that JDK 24+ removed outright
# (UnsupportedOperationException). WildFly 41+ dropped that call and boots
# fine on newer JDKs. See versions.json for the tested version/JDK pairs.
ARG WILDFLY_VERSION=32.0.0.Final
ENV WILDFLY_VERSION=${WILDFLY_VERSION} \
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
