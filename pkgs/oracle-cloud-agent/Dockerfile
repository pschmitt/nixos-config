FROM oraclelinux:9

ARG ORACLE_LINUX_VERSION=9
ARG YUM_REPO=yum.eu-frankfurt-1.oci.oraclecloud.com
# ARG YUM_REPO=oci-yum.brkn.lol

# Update and clean YUM cache
# hadolint ignore=DL3059
RUN yum install -y yum-utils && yum clean all

# Delete all configured yum repos and add our custom YUM repository
RUN rm /etc/yum.repos.d/*.repo && cat <<EOF > /etc/yum.repos.d/oci-x86_64.repo
[oci-aarch64]
name=Oracle OCI Repo (${YUM_REPO}) aarch64
baseurl=https://${YUM_REPO}/repo/OracleLinux/OL${ORACLE_LINUX_VERSION}/oci/included/aarch64/
enabled=1
gpgcheck=0

[oci-x86_64]
name=Oracle OCI Repo (${YUM_REPO}) x86_64
baseurl=https://${YUM_REPO}/repo/OracleLinux/OL${ORACLE_LINUX_VERSION}/oci/included/x86_64/
enabled=1
gpgcheck=0
EOF


ENTRYPOINT ["yumdownloader", "--urls", "oracle-cloud-agent"]
