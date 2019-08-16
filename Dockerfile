FROM xrally/xrally-openstack:0.11.2

SHELL ["/bin/bash", "-xec"]

USER root

RUN apt-get update; apt-get install -y iputils-ping curl wget

WORKDIR /var/lib/

RUN mkdir -p cvp-configuration

RUN git clone http://gerrit.mcp.mirantis.com/packaging/sources/tempest && \
    pushd tempest; git checkout mcp/queens; pip install -r requirements.txt; \
    popd;

RUN git clone http://gerrit.mcp.mirantis.com/packaging/sources/heat-tempest-plugin && \
    pushd heat-tempest-plugin; git checkout mcp/queens; pip install -r requirements.txt; \
    popd;

RUN pip install --force-reinstall python-cinderclient==3.2.0 python-glanceclient==2.11

RUN git clone http://gerrit.mcp.mirantis.com/packaging/sources/designate-tempest-plugin && \
    pushd designate-tempest-plugin; git checkout mcp/queens; pip install -r requirements.txt; \
    popd;

RUN git clone https://github.com/openstack/neutron-lbaas && \
    pushd neutron-lbaas; git checkout stable/queens; pip install -r requirements.txt; \
    popd;

RUN git clone http://gerrit.mcp.mirantis.com/packaging/sources/telemetry-tempest-plugin && \
    pushd telemetry-tempest-plugin; git checkout mcp/queens; pip install -r requirements.txt; \
    popd;

RUN sed -i 's/uuid4())/uuid4()).replace("-","")/g' /usr/local/lib/python2.7/dist-packages/rally/plugins/openstack/scenarios/keystone/utils.py
RUN sed -i 's/uuid4())/uuid4()).replace("-","")/g' /usr/local/lib/python2.7/dist-packages/rally/plugins/openstack/context/keystone/users.py

COPY rally/ /var/lib/cvp-configuration/rally
COPY tempest/ /var/lib/cvp-configuration/tempest
COPY cleanup.sh  /var/lib/cvp-configuration/cleanup.sh
COPY configure.sh /var/lib/cvp-configuration/configure.sh

WORKDIR /home/rally

ENTRYPOINT ["/bin/bash"]
