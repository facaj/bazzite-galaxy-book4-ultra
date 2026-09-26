# Comandos do Samsung Galaxy Book4 Ultra (bazzite-galaxy-book4-ultra)

# Inscreve no MOK a chave que assinou os drivers da câmera e dos alto-falantes (Secure Boot)
[group('Galaxy Book')]
galaxybook-enroll-key:
    #!/usr/bin/bash
    set -euo pipefail
    cert=/usr/share/galaxybook-bazzite/galaxybook-mok.der
    if [[ ! -r "${cert}" ]]; then
        echo "Esta imagem foi gerada sem chave de assinatura: não há o que inscrever."
        echo "Com Secure Boot ativo, os módulos ov02c10 e MAX98390 não vão carregar."
        exit 1
    fi
    if mokutil --test-key "${cert}" 2>&1 | grep -q "already enrolled"; then
        echo "A chave do Galaxy Book já está inscrita no MOK."
        exit 0
    fi
    echo "Defina uma senha temporária. Ela será pedida uma única vez na tela azul"
    echo "do MOK no próximo boot: escolha 'Enroll MOK' > 'Continue' > 'Yes'."
    sudo mokutil --import "${cert}"
    echo "Pronto. Reinicie o notebook para concluir a inscrição."

# Mostra o estado da câmera, dos alto-falantes, da digital e da NVIDIA
[group('Galaxy Book')]
galaxybook-status:
    #!/usr/bin/bash
    echo "== Imagem / kernel"
    rpm-ostree status --booted | sed -n '1,6p'
    uname -r
    echo; echo "== Secure Boot"
    mokutil --sb-state 2>/dev/null || echo "mokutil indisponível"
    if [[ -r /usr/share/galaxybook-bazzite/galaxybook-mok.der ]]; then
        mokutil --test-key /usr/share/galaxybook-bazzite/galaxybook-mok.der 2>&1 || true
    fi
    echo; echo "== Câmera (ov02c10)"
    modinfo -n ov02c10
    lsmod | grep -E '^ov02c10' || echo "ov02c10 não carregado"
    journalctl -b -k --no-pager | grep -i ov02c10 | tail -n 5
    cam -l 2>/dev/null | head -n 5
    echo; echo "== Alto-falantes (MAX98390)"
    modinfo -n snd-hda-scodec-max98390
    lsmod | grep -E '^snd_hda_scodec_max98390' || echo "MAX98390 não carregado"
    systemctl --no-pager --lines=0 status max98390-hda-i2c-setup.service || true
    echo; echo "== Leitor de digital"
    lsusb | grep -i '1c7a:05a1' || echo "sensor 1c7a:05a1 não encontrado"
    fprintd-list "${USER}" 2>/dev/null || true
    echo; echo "== NVIDIA"
    lsmod | grep -E '^nvidia' || echo "módulos NVIDIA não carregados"
