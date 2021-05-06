FROM photon:3.0
  
LABEL authors="renoufa@vmware.com,jaker@vmware.com,dmilov@vmware.com"

ENV TERM linux

WORKDIR /root

# Set terminal. If we don't do this, weird readline things happen.
RUN echo "/usr/bin/pwsh" >> /etc/shells && \
    echo "/bin/pwsh" >> /etc/shells && \
    tdnf install -y wget tar icu powershell git unzip openssh-clients sshpass && \
    wget https://github.com/PowerShell/PowerShell/releases/download/v7.1.1/powershell-7.1.1-linux-x64.tar.gz && \
    tar -xvf /root/powershell-7.1.1-linux-x64.tar.gz -C /usr/lib/powershell && \
    rm /usr/lib/powershell/libssl.so.1.0.0 && \
    rm /usr/lib/powershell/libcrypto.so.1.0.0 && \
    ln -s /usr/lib/libssl.so.1.1 /usr/lib/powershell/libssl.so.1.0.0 && \
    ln -s /usr/lib/libcrypto.so.1.1 /usr/lib/powershell/libcrypto.so.1.0.0 && \
    pwsh -c "Enable-ExperimentalFeature PSDesiredStateConfiguration.InvokeDscResource" && \
    pwsh -c "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module VMware.PowerCLI -RequiredVersion 12.2.0.17538434" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module VMware.vSphereDSC" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module VMware.PSDesiredStateConfiguration" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module VMware.vSphere.SsoAdmin" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module PowerNSX -RequiredVersion 3.0.1174" && \
    pwsh -c "\$ProgressPreference = \"SilentlyContinue\"; Install-Module PowervRA -RequiredVersion 3.6.0" && \
    find / -name "net45" | xargs rm -rf && \
    echo '$ProgressPreference = "SilentlyContinue"' > /root/.config/powershell/Microsoft.PowerShell_profile.ps1 && \
    tdnf erase -y unzip && \
    tdnf clean all

CMD ["/bin/pwsh"]