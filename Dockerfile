FROM xrally/xrally-openstack:0.10.1

SHELL ["/bin/bash", "-xec"]

USER root

RUN apt-get update; apt-get install -y iputils-ping curl wget

WORKDIR /var/lib/

RUN mkdir -p cvp-configuration

RUN git clone https://github.com/openstack/tempest && \
    pushd tempest; git checkout 17.2.0; pip install -r requirements.txt; \
    popd;

RUN git clone https://github.com/openstack/heat-tempest-plugin && \
    pushd heat-tempest-plugin; git checkout 12b770e923060f5ef41358c37390a25be56634f0; pip install -r requirements.txt; \
    popd;

RUN pip install --force-reinstall python-cinderclient==3.2.0

RUN git clone https://github.com/openstack/designate-tempest-plugin && \
    pushd designate-tempest-plugin; git checkout 0.5.0; git cherry-pick fd1eb9bbbcb721b4f8e7021219b5bdbd7c104ccb; pip install -r requirements.txt; \
    popd;

RUN git clone https://github.com/openstack/neutron-lbaas && \
    pushd neutron-lbaas; git checkout stable/pike; pip install -r requirements.txt; \
    popd;

COPY rally/ /var/lib/cvp-configuration/rally
COPY tempest/ /var/lib/cvp-configuration/tempest
COPY cleanup.sh  /var/lib/cvp-configuration/cleanup.sh
COPY configure.sh /var/lib/cvp-configuration/configure.sh

WORKDIR /home/rally

ENTRYPOINT ["/bin/bash"]
