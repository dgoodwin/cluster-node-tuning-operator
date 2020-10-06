FROM registry.svc.ci.openshift.org/openshift/release:golang-1.15 AS builder
WORKDIR /go/src/github.com/openshift/cluster-node-tuning-operator
COPY . .
RUN make build

FROM centos:7 as tuned
WORKDIR /root
COPY assets /root/assets
RUN INSTALL_PKGS=" \
      gcc git rpm-build make desktop-file-utils patch \
      " && \
    yum install --setopt=tsflags=nodocs -y $INSTALL_PKGS && \
    cd assets/tuned/daemon && \
    LC_COLLATE=C cat ../patches/*.diff | patch -Np1 && \
    make rpm PYTHON=/usr/bin/python && \
    rm -rf /root/rpmbuild/RPMS/noarch/{tuned-gtk*,tuned-utils*,tuned-profiles-compat*} && \
    cd ../stalld && \
    make

FROM centos:7
COPY --from=builder /go/src/github.com/openshift/cluster-node-tuning-operator/_output/cluster-node-tuning-operator /usr/bin/
COPY manifests /manifests
ENV APP_ROOT=/var/lib/tuned
ENV PATH=${APP_ROOT}/bin:${PATH}
ENV HOME=${APP_ROOT}
WORKDIR ${APP_ROOT}
COPY --from=builder /go/src/github.com/openshift/cluster-node-tuning-operator/_output/openshift-tuned /usr/bin/
COPY --from=tuned   /root/assets ${APP_ROOT}
COPY --from=tuned   /root/rpmbuild/RPMS/noarch /root/rpms
RUN INSTALL_PKGS=" \
      socat procps-ng \
      " && \
    mkdir -p /etc/grub.d/ /boot && \
    yum install --setopt=tsflags=nodocs -y $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum --setopt=tsflags=nodocs -y install /root/rpms/*.rpm && \
    find /root/rpms -name \*.rpm -exec basename {} .rpm \; | xargs rpm -e --justdb && \
    cp -a /var/lib/tuned/tuned/stalld/stalld /usr/local/bin && \
    rm -rf /var/lib/tuned/tuned && \
    touch /etc/sysctl.conf && \
    yum clean all && \
    rm -rf /var/cache/yum ~/patches /root/rpms && \
    useradd -r -u 499 cluster-node-tuning-operator
ENTRYPOINT ["/usr/bin/cluster-node-tuning-operator"]
LABEL io.k8s.display-name="OpenShift cluster-node-tuning-operator" \
      io.k8s.description="This is a component of OpenShift and manages the lifecycle of node-level tuning." \
      io.openshift.release.operator=true
