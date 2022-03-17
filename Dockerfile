FROM debian:latest

# Install Packages
RUN apt-get update -y; \
    apt-get upgrade -y; \
    apt-get install nano jq openssh-server lsb-release gnupg curl software-properties-common apache2-utils zip -y; \ 
    apt-get install python3 python3-pip python3-venv wget openvpn sshpass iputils-ping sudo -y; \
    apt-get install firefox-esr libx11-xcb1 libdbus-glib-1-2 -y

ENV FIREFOX_VER 90.0
 
# Add latest FireFox
RUN set -x \
   && curl -sSLO https://download-installer.cdn.mozilla.net/pub/firefox/releases/${FIREFOX_VER}/linux-x86_64/en-US/firefox-${FIREFOX_VER}.tar.bz2 \
   && tar -jxf firefox-* \
   && mv firefox /opt/ \
   && chmod 755 /opt/firefox \
   && chmod 755 /opt/firefox/firefox

# Install Selenium Firefox Webdriver to /usr/local/bin 

RUN curl -LO https://github.com/mozilla/geckodriver/releases/download/v0.30.0/geckodriver-v0.30.0-linux64.tar.gz; \
    tar -zxvf geckodriver-v0.30.0-linux64.tar.gz -C /usr/local/bin; \
    rm ./geckodriver-v0.30.0-linux64.tar.gz

# Install Packer and Terraform
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -; \
    apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"; \
    apt-get update; \ 
    apt-get install packer terraform

# Vault CLI
RUN wget --quiet https://releases.hashicorp.com/vault/1.8.4/vault_1.8.4_linux_amd64.zip \
  && unzip vault_1.8.4_linux_amd64.zip -d /usr/bin/ \
  && rm vault_1.8.4_linux_amd64.zip

RUN adduser --disabled-password --gecos '' hetzner
RUN adduser hetzner sudo
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN mkdir -p /home/hetzner/.ssh /home/hetzner/.config/packer/plugins; \
    mkdir -p /home/hetzner/ansible /home/hetzner/terraform /home/hetzner/packer /opt/venv /etc/ansible

# Install custom Packer Plugin
RUN curl -LO https://github.com/ThorstenHeck/packer-plugin-hcloud/releases/download/v1.2.0/packer-plugin-hcloud_v1.2.0_x5.0_linux_amd64.zip; \
    unzip packer-plugin-hcloud_v1.2.0_x5.0_linux_amd64.zip -d home/hetzner/.config/packer/plugins; \
    mv home/hetzner/.config/packer/plugins/packer-plugin-hcloud_v1.2.0_x5.0_linux_amd64 home/hetzner/.config/packer/plugins/packer-plugin-hcloud; \
    rm ./packer-plugin-hcloud_v1.2.0_x5.0_linux_amd64.zip

RUN echo "Host *\n\tStrictHostKeyChecking no\n" >> /home/hetzner/.ssh/config
WORKDIR /home/hetzner

ENV VIRTUAL_ENV=/opt/venv
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

ADD build/requirements.yml /tmp/requirements.yml
ADD build/ansible.cfg /etc/ansible/ansible.cfg
RUN chmod 644 /etc/ansible/ansible.cfg
RUN python3 -m venv $VIRTUAL_ENV

RUN chown -R hetzner:hetzner /home/hetzner /opt/venv /tmp

USER hetzner

COPY --chown=hetzner hetzner_setup.sh /home/hetzner/hetzner_setup.sh
COPY --chown=hetzner packer /home/hetzner/packer
COPY --chown=hetzner terraform /home/hetzner/terraform
COPY --chown=hetzner ansible /home/hetzner/ansible
COPY --chown=hetzner build /home/hetzner/build

RUN packer -autocomplete-install; \
    terraform -install-autocomplete; \
    pip3 install --upgrade pip; \
    pip3 install ansible lxml selenium requests

RUN ansible-galaxy install -r /tmp/requirements.yml; \
    rm -rf /tmp/*
