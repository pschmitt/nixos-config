FROM oraclelinux:9

ARG ORACLE_LINUX_VERSION=9

# Update and clean YUM cache
# hadolint ignore=DL3059
RUN yum install -y yum-utils && yum clean all

# Delete all configured yum repos and add our custom YUM repository
RUN rm /etc/yum.repos.d/*.repo && cat <<EOF > /etc/yum.repos.d/oci-x86_64.repo
[oci-aarch64]
name=Oracle OCI Repo (oci-yum.brkn.lol) aarch64
baseurl=https://oci-yum.brkn.lol/repo/OracleLinux/OL${ORACLE_LINUX_VERSION}/oci/included/aarch64/
enabled=1
gpgcheck=0

[oci-x86_64]
name=Oracle OCI Repo (oci-yum.brkn.lol) x86_64
baseurl=https://oci-yum.brkn.lol/repo/OracleLinux/OL${ORACLE_LINUX_VERSION}/oci/included/x86_64/
enabled=1
gpgcheck=0
EOF


ENTRYPOINT ["yumdownloader", "--urls", "oracle-cloud-agent"]
