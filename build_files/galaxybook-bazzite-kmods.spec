# Empacota os módulos já compilados por build-kmods.sh. Não é para uso fora
# do build da imagem: depende dos arquivos em /usr/lib/modules do estágio kmods.
%global debug_package %{nil}
# Não deixar o rpmbuild mexer nos .ko (strip apagaria a assinatura)
%global __os_install_post %{nil}

Name:           galaxybook-bazzite-kmods
Version:        1.0.0
Release:        1%{?dist}
Summary:        Módulos ov02c10 e MAX98390 pré-compilados para o kernel do Bazzite
License:        GPL-2.0-only
ExclusiveArch:  x86_64

# O Bazzite não tem akmods funcional; este pacote ocupa o lugar dos akmods
# para satisfazer galaxybook-camera e galaxybook-setup.
Provides:       akmod-galaxybook-ov02c10 = %{ov02c10_evr}
Provides:       kmod-galaxybook-ov02c10 = %{ov02c10_evr}
Provides:       akmod-galaxybook-max98390 = %{max98390_evr}
Provides:       kmod-galaxybook-max98390 = %{max98390_evr}
Requires:       galaxybook-ov02c10-kmod-common
Requires:       galaxybook-max98390-kmod-common

%description
Módulos ov02c10 (câmera) e MAX98390 (alto-falantes) compilados na hora do
build da imagem contra o kernel %{kernel_version}.

%install
for dir in /usr/lib/modules/%{kernel_version}/extra/galaxybook-*; do
  mkdir -p %{buildroot}/usr/lib/modules/%{kernel_version}/extra
  cp -a "$dir" %{buildroot}/usr/lib/modules/%{kernel_version}/extra/
done

%post
/usr/sbin/depmod -a %{kernel_version} || :

%postun
/usr/sbin/depmod -a %{kernel_version} || :

%files
/usr/lib/modules/%{kernel_version}/extra/galaxybook-*
