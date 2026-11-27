#!/bin/sh
# ==============================================================================
# netadmin.sh - Ferramenta de diagnostico e auditoria de servidores Linux
# ==============================================================================
# Descricao:
#   Utilitario de linha de comando em Shell Script (POSIX sh) para automacao
#   de verificacoes de rede, conectividade, servicos/portas locais, analise
#   de logs HTTP e geracao de relatorios de auditoria.
#
# Uso:
#   ./netadmin.sh [OPCOES]
#   Execute ./netadmin.sh -h para visualizar todas as opcoes e exemplos.
# ==============================================================================

# ------------------------------------------------------------------------------
# Variaveis globais de configuracao e estado
# ------------------------------------------------------------------------------
SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

OPT_INFO=0
OPT_PING=0
OPT_PING_FILE=0
OPT_SERVICES=0
OPT_PORTS=0
OPT_LOG=0
OPT_OUTPUT=0
VERBOSE=0

PING_TARGET=""
PING_FILE=""
CHECK_PORTS=""
LOG_FILE=""
OUTPUT_FILE=""

TMP_DIR=""
CHECKS_RUN=""
PROBLEMS_COUNT=0
PROBLEMS_FILE=""
MODULES_OUT=""
EXIT_CODE=0

# ------------------------------------------------------------------------------
# Tratamento de arquivos temporarios e sinais (trap)
# ------------------------------------------------------------------------------
init_temp() {
    TMP_DIR=$(mktemp -d 2>/dev/null)
    if [ -z "$TMP_DIR" ] || [ ! -d "$TMP_DIR" ]; then
        TMP_DIR="/tmp/netadmin.$$"
        mkdir -p "$TMP_DIR" || {
            printf 'Erro: nao foi possivel criar diretorio temporario.\n' >&2
            exit 1
        }
    fi
    PROBLEMS_FILE="$TMP_DIR/problems.txt"
    MODULES_OUT="$TMP_DIR/modules.out"
    : > "$PROBLEMS_FILE"
    : > "$MODULES_OUT"
}

cleanup() {
    if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}

on_interrupt() {
    printf '\nExecucao interrompida. Removendo arquivos temporarios...\n' >&2
    cleanup
    exit 130
}

trap cleanup EXIT
trap on_interrupt INT TERM

# ------------------------------------------------------------------------------
# Funcoes utilitarias de log, erro, validacao e registro de problemas
# ------------------------------------------------------------------------------
log_error() {
    printf 'Erro: %s\n' "$1" >&2
}

error_exit() {
    log_error "$1"
    exit 1
}

check_command() {
    cmd_name="$1"
    if ! command -v "$cmd_name" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}

add_check_name() {
    name="$1"
    if [ -z "$CHECKS_RUN" ]; then
        CHECKS_RUN="$name"
    else
        CHECKS_RUN="$CHECKS_RUN, $name"
    fi
}

add_problem() {
    msg="$1"
    PROBLEMS_COUNT=$((PROBLEMS_COUNT + 1))
    printf '%s\n' "$msg" >> "$PROBLEMS_FILE"
}

is_positive_int() {
    case "$1" in
        ''|*[!0-9]*)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

validate_port() {
    port="$1"
    if ! is_positive_int "$port"; then
        return 1
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

validate_input_file() {
    file_path="$1"
    label="$2"

    if [ -z "$file_path" ]; then
        log_error "$label: caminho de arquivo nao informado."
        return 1
    fi
    if [ ! -e "$file_path" ]; then
        log_error "$label: arquivo '$file_path' nao existe."
        return 1
    fi
    if [ ! -f "$file_path" ]; then
        log_error "$label: '$file_path' nao e um arquivo regular."
        return 1
    fi
    if [ ! -r "$file_path" ]; then
        log_error "$label: sem permissao de leitura em '$file_path'."
        return 1
    fi
    return 0
}

validate_output_file() {
    out_path="$1"
    if [ -z "$out_path" ]; then
        log_error "Caminho do arquivo de relatorio nao informado."
        return 1
    fi
    if [ -d "$out_path" ]; then
        log_error "O caminho '$out_path' e um diretorio, nao um arquivo."
        return 1
    fi

    out_dir=$(dirname "$out_path")
    if [ ! -d "$out_dir" ]; then
        log_error "O diretorio de saida '$out_dir' nao existe."
        return 1
    fi

    if [ -e "$out_path" ]; then
        if [ ! -w "$out_path" ]; then
            log_error "O arquivo '$out_path' nao pode ser escrito (sem permissao)."
            return 1
        fi
    else
        if [ ! -w "$out_dir" ]; then
            log_error "Sem permissao de escrita no diretorio '$out_dir'."
            return 1
        fi
    fi
    return 0
}

get_hostname_safe() {
    if check_command hostname; then
        hostname 2>/dev/null || printf 'desconhecido\n'
    elif [ -r /etc/hostname ]; then
        cat /etc/hostname 2>/dev/null
    else
        uname -n 2>/dev/null || printf 'desconhecido\n'
    fi
}

get_datetime_safe() {
    if check_command date; then
        date '+%d/%m/%Y %H:%M:%S' 2>/dev/null
    else
        printf 'indisponivel\n'
    fi
}

# ------------------------------------------------------------------------------
# Ajuda de utilizacao (-h)
# ------------------------------------------------------------------------------
show_help() {
    cat <<EOF
NetAdmin v$VERSION - Ferramenta de diagnostico e auditoria de servidores Linux

Uso:
  $SCRIPT_NAME [OPCOES]

Opcoes:
  -i              Exibir informacoes do servidor e das interfaces de rede.
  -p DESTINO      Testar a conectividade com um destino (IP ou dominio).
  -P ARQUIVO      Testar a conectividade com todos os destinos de um arquivo.
  -s              Listar servicos e portas em estado de escuta.
  -c PORTAS       Verificar uma ou mais portas locais (separadas por virgula).
  -l ARQUIVO      Analisar um arquivo de log de acessos HTTP.
  -o ARQUIVO      Salvar os resultados e o historico em um relatorio.
  -v              Ativar o modo detalhado.
  -h              Exibir esta ajuda de utilizacao.

Exemplos:
  $SCRIPT_NAME -i
  $SCRIPT_NAME -i -v
  $SCRIPT_NAME -p 192.168.1.1
  $SCRIPT_NAME -p google.com -v
  $SCRIPT_NAME -P exemplos/destinos.txt
  $SCRIPT_NAME -s -v
  $SCRIPT_NAME -c 22,80,443
  $SCRIPT_NAME -l exemplos/acessos_basico.log -v
  $SCRIPT_NAME -i -s -l exemplos/acessos_basico.log -o auditoria.txt
EOF
}

# ------------------------------------------------------------------------------
# Modulo 1 — Informacoes do servidor e interfaces de rede (-i)
# ------------------------------------------------------------------------------
module_network_info() {
    add_check_name "Informacoes do servidor e interfaces de rede (-i)"

    if ! check_command ip; then
        log_error "Modulo 1: comando 'ip' nao esta instalado no sistema."
        add_problem "Comando 'ip' ausente: verificacao de interfaces e rotas nao executada."
        return 1
    fi

    link_file="$TMP_DIR/ip_link.txt"
    addr_file="$TMP_DIR/ip_addr.txt"
    route_file="$TMP_DIR/ip_route.txt"

    if ! ip link > "$link_file" 2>"$TMP_DIR/ip_link.err"; then
        log_error "Modulo 1: falha ao executar 'ip link': $(cat "$TMP_DIR/ip_link.err")"
        add_problem "Falha ao consultar interfaces via 'ip link'."
        return 1
    fi

    if ! ip address > "$addr_file" 2>"$TMP_DIR/ip_addr.err"; then
        log_error "Modulo 1: falha ao executar 'ip address': $(cat "$TMP_DIR/ip_addr.err")"
        add_problem "Falha ao consultar enderecos via 'ip address'."
        return 1
    fi

    if ! ip route > "$route_file" 2>"$TMP_DIR/ip_route.err"; then
        log_error "Modulo 1: falha ao consultar rotas via 'ip route': $(cat "$TMP_DIR/ip_route.err")"
        add_problem "Falha ao consultar tabela de rotas via 'ip route'."
        return 1
    fi

    srv_host=$(get_hostname_safe)
    srv_date=$(get_datetime_safe)

    if [ "$VERBOSE" -eq 1 ]; then
        srv_os=$(uname -s 2>/dev/null || printf 'Linux')
        srv_kernel=$(uname -r 2>/dev/null || printf 'desconhecido')
        if check_command uptime; then
            srv_uptime=$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/^[[:space:]]*//')
        else
            srv_uptime="indisponivel"
        fi

        printf '=== INFORMACOES DO SERVIDOR (MODO DETALHADO) ===\n\n'
        printf 'INFORMACOES DO SISTEMA\n'
        printf 'Hostname: %s\n' "$srv_host"
        printf 'Data/Horario: %s\n' "$srv_date"
        printf 'Sistema operacional: %s\n' "$srv_os"
        printf 'Kernel: %s\n' "$srv_kernel"
        printf 'Tempo ligado: %s\n\n' "$srv_uptime"
    else
        printf '=== DIAGNOSTICO DE REDE ===\n\n'
        printf 'Servidor: %s\n' "$srv_host"
        printf 'Data/Horario: %s\n\n' "$srv_date"
    fi

    printf 'INTERFACES DE REDE\n\n'

    # Extrair nomes das interfaces de ip link (suporta formato padrao "N: nome: <...>" e simplificado "nome: <...>")
    iface_list="$TMP_DIR/ifaces.txt"
    awk '
        /^[0-9]+:[[:space:]]+[^:]+:/ {
            line = $0
            sub(/^[0-9]+:[[:space:]]+/, "", line)
            sub(/:.*/, "", line)
            sub(/@.*/, "", line)
            print line
            next
        }
        /^[^[:space:]]+:[[:space:]]*</ {
            line = $0
            sub(/:.*/, "", line)
            sub(/@.*/, "", line)
            print line
        }
    ' "$link_file" > "$iface_list"

    total_ifaces=0
    active_ifaces=0
    down_ifaces=0
    no_ipv4_ifaces=0
    attention_count=0
    diag_list="$TMP_DIR/net_diag.txt"
    : > "$diag_list"

    while IFS= read -r iface; do
        [ -z "$iface" ] && continue
        total_ifaces=$((total_ifaces + 1))

        # Extrair bloco da interface em ip link
        iface_link_block=$(awk -v target="$iface" '
            BEGIN { in_blk = 0 }
            /^[0-9]+:[[:space:]]+/ || /^[^[:space:]]+:[[:space:]]*</ {
                name = $0
                sub(/^[0-9]+:[[:space:]]+/, "", name)
                sub(/:.*/, "", name)
                sub(/@.*/, "", name)
                if (name == target) {
                    in_blk = 1
                    print
                    next
                } else if (in_blk == 1) {
                    exit
                }
            }
            in_blk == 1 { print }
        ' "$link_file")

        # Extrair bloco da interface em ip address
        iface_addr_block=$(awk -v target="$iface" '
            BEGIN { in_blk = 0 }
            /^[0-9]+:[[:space:]]+/ || /^[^[:space:]]+:[[:space:]]+/ {
                name = $0
                sub(/^[0-9]+:[[:space:]]+/, "", name)
                sub(/:.*/, "", name)
                sub(/@.*/, "", name)
                if (name == target) {
                    in_blk = 1
                    print
                    next
                } else if (in_blk == 1) {
                    exit
                }
            }
            in_blk == 1 { print }
        ' "$addr_file")

        # Verificar estado (flag UP dentro de <...> ou state UP)
        if printf '%s\n' "$iface_link_block" | grep -qE '<[^>]*UP[^>]*>|state UP'; then
            iface_state="ATIVA"
            active_ifaces=$((active_ifaces + 1))
        else
            iface_state="DESATIVADA"
            down_ifaces=$((down_ifaces + 1))
        fi

        # Extrair MTU
        iface_mtu=$(printf '%s\n' "$iface_link_block" | awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "mtu" && (i + 1) <= NF) {
                        print $(i + 1)
                        exit
                    }
                }
            }
        ')
        [ -z "$iface_mtu" ] && iface_mtu="N/A"

        # Extrair MAC
        iface_mac=$(printf '%s\n' "$iface_link_block" | awk '
            $1 ~ /^link\// { print $2; exit }
        ')
        [ -z "$iface_mac" ] && iface_mac="NAO DISPONIVEL"

        # Extrair IPv4 (suporta linha "inet x.x.x.x/yy" e formato simplificado "iface: x.x.x.x/yy")
        iface_ipv4=$(printf '%s\n' "$iface_addr_block" | awk '
            $1 == "inet" { print $2; exit }
        ')
        if [ -z "$iface_ipv4" ]; then
            iface_ipv4=$(printf '%s\n' "$iface_addr_block" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?' | head -n 1)
        fi

        # Extrair IPv6
        iface_ipv6=$(printf '%s\n' "$iface_addr_block" | awk '
            $1 == "inet6" { print $2; exit }
        ')

        printf '%s\n' "$iface"
        printf '  Estado: %s\n' "$iface_state"

        if [ "$VERBOSE" -eq 1 ]; then
            printf '  Endereco MAC: %s\n' "$iface_mac"
            if [ -n "$iface_ipv4" ]; then
                printf '  IPv4: %s\n' "$iface_ipv4"
            else
                printf '  IPv4: NAO CONFIGURADO\n'
                no_ipv4_ifaces=$((no_ipv4_ifaces + 1))
            fi
            if [ -n "$iface_ipv6" ]; then
                printf '  IPv6: %s\n' "$iface_ipv6"
            else
                printf '  IPv6: NAO CONFIGURADO\n'
            fi
            printf '  MTU: %s\n' "$iface_mtu"
        else
            if [ -n "$iface_ipv4" ]; then
                printf '  Endereco IPv4: %s\n' "$iface_ipv4"
            else
                printf '  Endereco IPv4: NAO CONFIGURADO\n'
                no_ipv4_ifaces=$((no_ipv4_ifaces + 1))
            fi
        fi

        if [ "$iface_state" = "DESATIVADA" ]; then
            printf '  ATENCAO: Interface desativada.\n'
            attention_count=$((attention_count + 1))
            printf 'Interface %s desativada.\n' "$iface" >> "$diag_list"
            add_problem "Interface de rede '$iface' encontra-se desativada."
            if [ -z "$iface_ipv4" ]; then
                printf 'Interface %s sem endereco IPv4.\n' "$iface" >> "$diag_list"
            fi
        elif [ -z "$iface_ipv4" ]; then
            if [ "$VERBOSE" -eq 1 ]; then
                printf '  ATENCAO: Interface sem endereco IPv4.\n'
            else
                printf '  ATENCAO: Interface ativa, mas sem endereco IP configurado.\n'
            fi
            attention_count=$((attention_count + 1))
            printf 'Interface %s sem endereco IPv4.\n' "$iface" >> "$diag_list"
            add_problem "Interface '$iface' esta ativa, porem sem endereco IPv4 configurado."
        fi
        printf '\n'
    done < "$iface_list"

    if [ "$total_ifaces" -eq 0 ]; then
        printf 'Nenhuma interface de rede encontrada.\n\n'
        add_problem "Nenhuma interface de rede foi detectada."
    fi

    # Rotas de rede
    printf 'ROTAS DE REDE\n'
    default_route=$(grep '^default ' "$route_file" | head -n 1)

    if [ "$VERBOSE" -eq 1 ]; then
        if [ -s "$route_file" ]; then
            while IFS= read -r rline; do
                [ -z "$rline" ] && continue
                printf '  %s\n' "$rline"
            done < "$route_file"
        else
            printf '  Nenhuma rota configurada.\n'
        fi
        printf '\n'
    fi

    if [ -n "$default_route" ]; then
        printf 'Rota padrao: %s\n\n' "$default_route"
        default_status="CONFIGURADA"
    else
        if [ "$VERBOSE" -eq 1 ]; then
            printf 'Rota padrao: NAO CONFIGURADA\n\n'
        else
            printf 'Rota padrao: NAO CONFIGURADA\n'
            printf '  ATENCAO: O servidor pode nao conseguir acessar redes externas.\n\n'
        fi
        default_status="NAO CONFIGURADA"
        attention_count=$((attention_count + 1))
        printf 'Rota padrao nao configurada.\n' >> "$diag_list"
        add_problem "Rota padrao nao configurada (possivel perda de acesso a redes externas)."
    fi

    if [ "$VERBOSE" -eq 1 ]; then
        printf 'COMANDOS UTILIZADOS\n'
        printf '  hostname\n'
        printf '  date\n'
        printf '  uname -r\n'
        printf '  uptime\n'
        printf '  ip link\n'
        printf '  ip address\n'
        printf '  ip route\n\n'

        printf 'DIAGNOSTICO\n'
        if [ -s "$diag_list" ]; then
            idx=1
            while IFS= read -r dline; do
                printf '  %d. %s\n' "$idx" "$dline"
                idx=$((idx + 1))
            done < "$diag_list"
        else
            printf '  Nenhum problema identificado nas interfaces ou rotas.\n'
        fi
        printf '\n'
    else
        printf '=== RESUMO DO DIAGNOSTICO ===\n\n'
        printf 'Interfaces encontradas: %d\n' "$total_ifaces"
        printf 'Interfaces ativas: %d\n' "$active_ifaces"
        printf 'Interfaces desativadas: %d\n' "$down_ifaces"
        printf 'Interfaces sem endereco IPv4: %d\n' "$no_ipv4_ifaces"
        printf 'Rota padrao: %s\n\n' "$default_status"

        if [ "$attention_count" -gt 0 ]; then
            printf 'Foram identificadas %d situacoes que merecem atencao.\n\n' "$attention_count"
        else
            printf 'Nenhuma situacao que mereca atencao foi identificada.\n\n'
        fi
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Modulo 2 — Testes de conectividade (-p DESTINO e -P ARQUIVO)
# ------------------------------------------------------------------------------
resolve_destination_ip() {
    dest="$1"
    ping_out_file="$2"

    # Se ja for um IPv4 valido, retorna diretamente
    if printf '%s\n' "$dest" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        printf '%s\n' "$dest"
        return 0
    fi

    # Tenta obter IP resolvido a partir da primeira linha do ping: PING host (1.2.3.4) ...
    resolved=$(head -n 1 "$ping_out_file" 2>/dev/null | sed -n 's/^PING [^(]*(\([^)]*\)).*/\1/p')
    if [ -n "$resolved" ]; then
        printf '%s\n' "$resolved"
        return 0
    fi

    # Fallback via getent se disponivel
    if check_command getent; then
        resolved=$(getent ahostsv4 "$dest" 2>/dev/null | awk 'NR==1 { print $1 }')
        if [ -z "$resolved" ]; then
            resolved=$(getent hosts "$dest" 2>/dev/null | awk 'NR==1 { print $1 }')
        fi
        if [ -n "$resolved" ]; then
            printf '%s\n' "$resolved"
            return 0
        fi
    fi

    printf 'NAO RESOLVIDO\n'
    return 1
}

test_single_destination() {
    target="$1"
    ping_count=4

    if [ -z "$target" ]; then
        log_error "Modulo 2: destino vazio informado."
        add_problem "Destino vazio informado no teste de conectividade."
        return 1
    fi

    case "$target" in
        -*)
            log_error "Modulo 2: destino invalido '$target'."
            add_problem "Destino invalido '$target' informado para teste de conectividade."
            return 1
            ;;
    esac

    if ! check_command ping; then
        log_error "Modulo 2: comando 'ping' nao esta instalado."
        add_problem "Comando 'ping' ausente: teste para '$target' nao executado."
        return 1
    fi

    ping_out="$TMP_DIR/ping_out.txt"
    ping -c "$ping_count" -W 2 "$target" > "$ping_out" 2>&1
    ping_rc=$?

    resolved_ip=$(resolve_destination_ip "$target" "$ping_out")

    # Extrair estatisticas de pacotes (Linux iputils-ping e formatos compativeis)
    stats_line=$(grep -E 'packets transmitted' "$ping_out" | tail -n 1)
    if [ -n "$stats_line" ]; then
        pkt_sent=$(printf '%s\n' "$stats_line" | sed -n 's/^\([0-9][0-9]*\) packets transmitted.*/\1/p')
        pkt_recv=$(printf '%s\n' "$stats_line" | sed -n 's/.*,[[:space:]]*\([0-9][0-9]*\)\( packets\)\{0,1\} received.*/\1/p')
        pkt_loss=$(printf '%s\n' "$stats_line" | sed -n 's/.*,[[:space:]]*\([0-9.][0-9.]*%\) packet loss.*/\1/p')
    else
        pkt_sent="$ping_count"
        pkt_recv=0
        pkt_loss="100%"
    fi

    [ -z "$pkt_sent" ] && pkt_sent="$ping_count"
    [ -z "$pkt_recv" ] && pkt_recv=0
    [ -z "$pkt_loss" ] && pkt_loss="100%"
    pkt_lost=$((pkt_sent - pkt_recv))
    [ "$pkt_lost" -lt 0 ] && pkt_lost=0

    # Extrair RTT min/avg/max
    rtt_line=$(grep -E '(rtt|round-trip)[[:space:]]+min/avg/max' "$ping_out" | tail -n 1)
    if [ -n "$rtt_line" ]; then
        rtt_vals=$(printf '%s\n' "$rtt_line" | sed -n 's/.*=[[:space:]]*\([0-9./]*\).*/\1/p')
        rtt_min=$(printf '%s\n' "$rtt_vals" | cut -d'/' -f1)
        rtt_avg=$(printf '%s\n' "$rtt_vals" | cut -d'/' -f2)
        rtt_max=$(printf '%s\n' "$rtt_vals" | cut -d'/' -f3)
    else
        rtt_min=""
        rtt_avg=""
        rtt_max=""
    fi

    if [ "$ping_rc" -eq 0 ] && [ "$pkt_recv" -gt 0 ]; then
        conn_result="SUCESSO"
    else
        conn_result="FALHA"
        add_problem "Falha de conectividade para o destino '$target' (perda: $pkt_loss)."
    fi

    if [ "$VERBOSE" -eq 1 ]; then
        printf '=== TESTE DE CONECTIVIDADE (MODO DETALHADO) ===\n\n'
        printf 'Destino informado: %s\n' "$target"
        printf 'Endereco IP resolvido: %s\n\n' "$resolved_ip"

        printf 'EXECUCAO DO TESTE\n'
        attempt=1
        while [ "$attempt" -le "$ping_count" ]; do
            seq_line=$(grep -E "icmp_seq=${attempt}[[:space:]]" "$ping_out" | head -n 1)
            if [ -n "$seq_line" ]; then
                resp_time=$(printf '%s\n' "$seq_line" | sed -n 's/.*time=\([0-9.][0-9.]*\).*/\1/p')
                if [ -n "$resp_time" ]; then
                    printf '  Tentativa %d: RESPOSTA - %s ms\n' "$attempt" "$resp_time"
                else
                    printf '  Tentativa %d: RESPOSTA\n' "$attempt"
                fi
            else
                printf '  Tentativa %d: SEM RESPOSTA\n' "$attempt"
            fi
            attempt=$((attempt + 1))
        done
        printf '\n'

        printf 'ESTATISTICAS\n'
        printf '  Pacotes enviados: %s\n' "$pkt_sent"
        printf '  Pacotes recebidos: %s\n' "$pkt_recv"
        printf '  Pacotes perdidos: %s\n' "$pkt_lost"
        printf '  Perda: %s\n' "$pkt_loss"
        if [ -n "$rtt_avg" ]; then
            printf '  Tempo minimo: %s ms\n' "$rtt_min"
            printf '  Tempo medio: %s ms\n' "$rtt_avg"
            printf '  Tempo maximo: %s ms\n' "$rtt_max"
        else
            printf '  Tempo minimo: N/A\n'
            printf '  Tempo medio: N/A\n'
            printf '  Tempo maximo: N/A\n'
        fi
        printf '\nRESULTADO: %s\n' "$conn_result"

        if [ "$conn_result" = "FALHA" ] && [ -s "$ping_out" ]; then
            err_detail=$(grep -ivE '^(PING|---|$|[0-9]+ packets|rtt )' "$ping_out" | head -n 1)
            if [ -n "$err_detail" ]; then
                printf 'Detalhe: %s\n' "$err_detail"
            fi
        fi
        printf '\n'
    else
        printf '=== TESTE DE CONECTIVIDADE ===\n\n'
        printf 'Destino: %s\n' "$target"
        printf 'Resultado: %s\n\n' "$conn_result"
        printf 'Pacotes enviados: %s\n' "$pkt_sent"
        printf 'Pacotes recebidos: %s\n' "$pkt_recv"
        printf 'Perda: %s\n' "$pkt_loss"
        if [ -n "$rtt_avg" ]; then
            printf 'Tempo medio: %s ms\n\n' "$rtt_avg"
        else
            printf 'Tempo medio: N/A\n\n'
        fi
    fi

    if [ "$conn_result" = "SUCESSO" ]; then
        return 0
    fi
    return 1
}

module_ping_single() {
    add_check_name "Teste de conectividade (-p $PING_TARGET)"
    test_single_destination "$PING_TARGET"
    return $?
}

module_ping_file() {
    add_check_name "Teste de conectividade em lote (-P $PING_FILE)"

    if ! validate_input_file "$PING_FILE" "Modulo 2 (-P)"; then
        add_problem "Arquivo de destinos '$PING_FILE' invalido ou inacessivel."
        return 1
    fi

    if [ ! -s "$PING_FILE" ]; then
        log_error "Modulo 2 (-P): arquivo '$PING_FILE' esta vazio."
        add_problem "Arquivo de destinos '$PING_FILE' esta vazio."
        return 1
    fi

    clean_targets="$TMP_DIR/targets_clean.txt"
    # Remove CR (CRLF), linhas em branco e comentarios iniciados com #
    tr -d '\r' < "$PING_FILE" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -vE '^(#|$)' > "$clean_targets"

    if [ ! -s "$clean_targets" ]; then
        log_error "Modulo 2 (-P): nenhum destino valido encontrado em '$PING_FILE'."
        add_problem "Nenhum destino valido encontrado no arquivo '$PING_FILE'."
        return 1
    fi

    batch_total=0
    batch_ok=0
    batch_fail=0

    while IFS= read -r dest_line; do
        [ -z "$dest_line" ] && continue
        batch_total=$((batch_total + 1))
        if test_single_destination "$dest_line"; then
            batch_ok=$((batch_ok + 1))
        else
            batch_fail=$((batch_fail + 1))
        fi
    done < "$clean_targets"

    printf '=== RESUMO DO TESTE EM LOTE ===\n\n'
    printf 'Arquivo: %s\n' "$PING_FILE"
    printf 'Destinos testados: %d\n' "$batch_total"
    printf 'Sucessos: %d\n' "$batch_ok"
    printf 'Falhas: %d\n\n' "$batch_fail"

    if [ "$batch_fail" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Modulo 3 — Verificacao de servicos e portas (-s e -c PORTAS)
# ------------------------------------------------------------------------------
collect_listening_sockets() {
    sockets_file="$1"
    : > "$sockets_file"

    if ! check_command ss; then
        log_error "Modulo 3: comando 'ss' nao esta instalado no sistema."
        add_problem "Comando 'ss' ausente: verificacao de servicos e portas nao executada."
        return 1
    fi

    ss_raw="$TMP_DIR/ss_raw.txt"
    if ! ss -tuln > "$ss_raw" 2>"$TMP_DIR/ss.err"; then
        log_error "Modulo 3: falha ao executar 'ss -tuln': $(cat "$TMP_DIR/ss.err")"
        add_problem "Falha ao consultar sockets locais via 'ss -tuln'."
        return 1
    fi

    # Extrair PROTOCOLO|ENDERECO|PORTA
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        set -- $line
        proto="$1"
        case "$proto" in
            tcp|udp|tcp6|udp6)
                ;;
            *)
                continue
                ;;
        esac

        # Em ss -tuln: Netid State Recv-Q Send-Q Local_Address:Port Peer_Address:Port
        local_ep="$5"
        [ -z "$local_ep" ] && continue

        port=${local_ep##*:}
        addr=${local_ep%:*}

        # Normaliza colchetes IPv6 para exibicao consistente e verifica porta valida
        if ! validate_port "$port"; then
            continue
        fi

        # Normaliza tcp6/udp6 se aparecerem em variantes de ss
        case "$proto" in
            tcp*) proto_norm="tcp" ;;
            udp*) proto_norm="udp" ;;
        esac

        printf '%s|%s|%s\n' "$proto_norm" "$addr" "$port" >> "$sockets_file"
    done < "$ss_raw"

    return 0
}

describe_bind_scope() {
    bind_addr="$1"
    case "$bind_addr" in
        0.0.0.0|'*')
            printf 'Escuta em todas as interfaces IPv4.\n'
            ;;
        '[::]'|'::')
            printf 'Escuta em todas as interfaces IPv6.\n'
            ;;
        127.*|'[::1]'|'::1')
            printf 'Disponivel somente localmente.\n'
            ;;
        *)
            printf 'Escuta no endereco especifico %s.\n' "$bind_addr"
            ;;
    esac
}

module_services_list() {
    add_check_name "Listagem de servicos e portas em escuta (-s)"

    sockets_parsed="$TMP_DIR/sockets_list.txt"
    if ! collect_listening_sockets "$sockets_parsed"; then
        return 1
    fi

    total_sockets=$(wc -l < "$sockets_parsed" | tr -d ' ')
    tcp_count=$(grep -c '^tcp|' "$sockets_parsed" 2>/dev/null)
    [ -z "$tcp_count" ] && tcp_count=0
    udp_count=$(grep -c '^udp|' "$sockets_parsed" 2>/dev/null)
    [ -z "$udp_count" ] && udp_count=0

    if [ "$VERBOSE" -eq 1 ]; then
        printf '=== SERVICOS E PORTAS LOCAIS (MODO DETALHADO) ===\n\n'

        printf 'SOCKETS TCP\n'
        if [ "$tcp_count" -gt 0 ]; then
            printf '%-12s %-20s %s\n' "PROTOCOLO" "ENDERECO LOCAL" "PORTA"
            grep '^tcp|' "$sockets_parsed" | while IFS='|' read -r s_proto s_addr s_port; do
                printf '%-12s %-20s %s\n' "$s_proto" "$s_addr" "$s_port"
            done
        else
            printf '  Nenhum socket TCP em escuta.\n'
        fi
        printf '\n'

        printf 'SOCKETS UDP\n'
        if [ "$udp_count" -gt 0 ]; then
            printf '%-12s %-20s %s\n' "PROTOCOLO" "ENDERECO LOCAL" "PORTA"
            grep '^udp|' "$sockets_parsed" | while IFS='|' read -r s_proto s_addr s_port; do
                printf '%-12s %-20s %s\n' "$s_proto" "$s_addr" "$s_port"
            done
        else
            printf '  Nenhum socket UDP em escuta.\n'
        fi
        printf '\n'

        printf 'DETALHAMENTO\n'
        if [ "$total_sockets" -gt 0 ]; then
            while IFS='|' read -r s_proto s_addr s_port; do
                desc=$(describe_bind_scope "$s_addr")
                printf '  %s:%s (%s) - %s\n' "$s_addr" "$s_port" "$s_proto" "$desc"
            done < "$sockets_parsed"
        else
            printf '  Nenhum socket encontrado.\n'
        fi
        printf '\n'

        printf 'RESUMO\n'
        printf '  Sockets TCP: %d\n' "$tcp_count"
        printf '  Sockets UDP: %d\n' "$udp_count"
        printf '  Total: %d\n\n' "$total_sockets"

        printf 'COMANDO UTILIZADO\n'
        printf '  ss -tuln\n\n'
    else
        printf '=== SERVICOS E PORTAS LOCAIS ===\n\n'
        if [ "$total_sockets" -gt 0 ]; then
            printf '%-12s %-20s %s\n' "PROTOCOLO" "ENDERECO LOCAL" "PORTA"
            while IFS='|' read -r s_proto s_addr s_port; do
                printf '%-12s %-20s %s\n' "$s_proto" "$s_addr" "$s_port"
            done < "$sockets_parsed"
        else
            printf 'Nenhum servico ou porta em escuta encontrado.\n'
        fi
        printf '\nTotal de sockets encontrados: %d\n\n' "$total_sockets"
    fi

    return 0
}

module_check_ports() {
    add_check_name "Verificacao de portas especificas (-c $CHECK_PORTS)"

    if [ -z "$CHECK_PORTS" ]; then
        log_error "Modulo 3 (-c): lista de portas nao informada."
        return 1
    fi

    sockets_parsed="$TMP_DIR/sockets_check.txt"
    if ! collect_listening_sockets "$sockets_parsed"; then
        return 1
    fi

    ports_spaced=$(printf '%s\n' "$CHECK_PORTS" | tr ',' ' ')
    found_count=0
    missing_count=0
    invalid_count=0

    if [ "$VERBOSE" -eq 1 ]; then
        printf '=== VERIFICACAO DE PORTAS (MODO DETALHADO) ===\n\n'
    else
        printf '=== VERIFICACAO DE PORTAS ===\n\n'
    fi

    for p in $ports_spaced; do
        if ! validate_port "$p"; then
            printf 'Porta %s: INVALIDA (informe um numero entre 1 e 65535)\n' "$p"
            invalid_count=$((invalid_count + 1))
            add_problem "Porta invalida informada na verificacao: '$p'."
            continue
        fi

        matches="$TMP_DIR/port_matches.txt"
        grep "|${p}$" "$sockets_parsed" > "$matches" 2>/dev/null

        if [ -s "$matches" ]; then
            protos=$(cut -d'|' -f1 "$matches" | tr '[:lower:]' '[:upper:]' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')
            printf 'Porta %s: ABERTA (%s)\n' "$p" "$protos"
            found_count=$((found_count + 1))

            if [ "$VERBOSE" -eq 1 ]; then
                while IFS='|' read -r m_proto m_addr m_port; do
                    m_desc=$(describe_bind_scope "$m_addr")
                    printf '  -> %s %s:%s - %s\n' "$m_proto" "$m_addr" "$m_port" "$m_desc"
                done < "$matches"
            fi
        else
            printf 'Porta %s: NAO ENCONTRADA\n' "$p"
            missing_count=$((missing_count + 1))
            add_problem "Porta local $p nao esta em estado de escuta."
        fi
    done

    printf '\nResumo: %d encontrada(s); %d nao encontrada(s)' "$found_count" "$missing_count"
    if [ "$invalid_count" -gt 0 ]; then
        printf '; %d invalida(s)' "$invalid_count"
    fi
    printf '.\n'

    if [ "$VERBOSE" -eq 1 ]; then
        printf '\nCOMANDO UTILIZADO\n  ss -tuln\n'
    fi
    printf '\n'

    if [ "$invalid_count" -gt 0 ]; then
        return 1
    fi
    return 0
}

# ------------------------------------------------------------------------------
# Modulo 4 — Analise de arquivos de log (-l ARQUIVO)
# ------------------------------------------------------------------------------
module_analyze_log() {
    add_check_name "Analise de arquivo de log (-l $LOG_FILE)"

    if ! validate_input_file "$LOG_FILE" "Modulo 4 (-l)"; then
        add_problem "Arquivo de log '$LOG_FILE' nao pode ser lido ou nao existe."
        return 1
    fi

    if [ ! -s "$LOG_FILE" ]; then
        log_error "Modulo 4 (-l): arquivo de log '$LOG_FILE' esta vazio."
        add_problem "Arquivo de log '$LOG_FILE' esta vazio."
        return 1
    fi

    for req_cmd in grep cut sort uniq wc; do
        if ! check_command "$req_cmd"; then
            log_error "Modulo 4: comando obrigatorio '$req_cmd' nao encontrado."
            add_problem "Comando '$req_cmd' ausente para analise de log."
            return 1
        fi
    done

    clean_log="$TMP_DIR/log_clean.txt"
    valid_log="$TMP_DIR/log_valid.txt"
    statuses_file="$TMP_DIR/log_statuses.txt"
    ips_file="$TMP_DIR/log_ips.txt"
    error_ips_file="$TMP_DIR/log_error_ips.txt"

    # Normaliza quebras CRLF e remove linhas completamente vazias
    tr -d '\r' < "$LOG_FILE" | grep -E '[^[:space:]]' > "$clean_log"
    total_non_empty=$(wc -l < "$clean_log" | tr -d ' ')

    # Filtra linhas no formato padrao de access log HTTP (Apache/Nginx Common/Combined)
    grep -E '^[0-9a-fA-F.:]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+\[[^]]+\][[:space:]]+"[A-Z]+[[:space:]]+[^[:space:]]+[^"]*"[[:space:]]+[1-5][0-9]{2}([[:space:]]|$)' "$clean_log" > "$valid_log"

    valid_count=$(wc -l < "$valid_log" | tr -d ' ')
    invalid_count=$((total_non_empty - valid_count))

    if [ "$valid_count" -eq 0 ]; then
        log_error "Modulo 4 (-l): nenhum registro HTTP valido encontrado em '$LOG_FILE'."
        add_problem "Arquivo de log '$LOG_FILE' nao possui registros HTTP validos."
        return 1
    fi

    # Extrair campos com cut, sed, grep, sort, uniq, wc
    cut -d' ' -f1 "$valid_log" > "$ips_file"
    cut -d'"' -f3 "$valid_log" | sed 's/^[[:space:]]*//' | cut -d' ' -f1 > "$statuses_file"

    # IPs que geraram erros HTTP (4xx e 5xx)
    grep -E '"[[:space:]]+[45][0-9]{2}([[:space:]]|$)' "$valid_log" | cut -d' ' -f1 > "$error_ips_file"

    count_200=$(grep -c '^200$' "$statuses_file" 2>/dev/null)
    [ -z "$count_200" ] && count_200=0
    count_404=$(grep -c '^404$' "$statuses_file" 2>/dev/null)
    [ -z "$count_404" ] && count_404=0
    count_500=$(grep -c '^500$' "$statuses_file" 2>/dev/null)
    [ -z "$count_500" ] && count_500=0

    count_2xx=$(grep -c '^2[0-9][0-9]$' "$statuses_file" 2>/dev/null)
    [ -z "$count_2xx" ] && count_2xx=0
    count_3xx=$(grep -c '^3[0-9][0-9]$' "$statuses_file" 2>/dev/null)
    [ -z "$count_3xx" ] && count_3xx=0
    count_4xx=$(grep -c '^4[0-9][0-9]$' "$statuses_file" 2>/dev/null)
    [ -z "$count_4xx" ] && count_4xx=0
    count_5xx=$(grep -c '^5[0-9][0-9]$' "$statuses_file" 2>/dev/null)
    [ -z "$count_5xx" ] && count_5xx=0
    total_errors=$((count_4xx + count_5xx))

    if [ "$count_4xx" -gt 0 ]; then
        add_problem "Log '$LOG_FILE' apresentou $count_4xx resposta(s) de erro cliente (4xx)."
    fi
    if [ "$count_5xx" -gt 0 ]; then
        add_problem "Log '$LOG_FILE' apresentou $count_5xx resposta(s) de erro servidor (5xx)."
    fi
    if [ "$invalid_count" -gt 0 ]; then
        add_problem "Log '$LOG_FILE' contem $invalid_count linha(s) com formato invalido."
    fi

    if [ "$VERBOSE" -eq 1 ]; then
        methods_file="$TMP_DIR/log_methods.txt"
        resources_file="$TMP_DIR/log_resources.txt"
        times_file="$TMP_DIR/log_times.txt"

        cut -d'"' -f2 "$valid_log" | cut -d' ' -f1 > "$methods_file"
        cut -d'"' -f2 "$valid_log" | cut -d' ' -f2 > "$resources_file"
        cut -d'[' -f2 "$valid_log" | cut -d']' -f1 | cut -d' ' -f1 | cut -d':' -f2-4 > "$times_file"

        pct_2xx=$((count_2xx * 100 / valid_count))
        pct_3xx=$((count_3xx * 100 / valid_count))
        pct_4xx=$((count_4xx * 100 / valid_count))
        pct_5xx=$((count_5xx * 100 / valid_count))

        first_time=$(head -n 1 "$times_file")
        last_time=$(tail -n 1 "$times_file")

        printf '=== ANALISE DE LOG (MODO DETALHADO) ===\n\n'
        printf 'Arquivo: %s\n' "$LOG_FILE"
        printf 'Registros processados: %d\n' "$valid_count"
        printf 'Linhas invalidas: %d\n\n' "$invalid_count"

        printf 'RESPOSTAS HTTP POR CODIGO\n'
        sort "$statuses_file" | uniq -c | sort -k2,2n | while read -r cnt code; do
            printf '  %s: %s\n' "$code" "$cnt"
        done
        printf '\n'

        printf 'CLASSIFICACAO\n'
        printf '  2xx: %d (%d%%)\n' "$count_2xx" "$pct_2xx"
        printf '  3xx: %d (%d%%)\n' "$count_3xx" "$pct_3xx"
        printf '  4xx: %d (%d%%)\n' "$count_4xx" "$pct_4xx"
        printf '  5xx: %d (%d%%)\n\n' "$count_5xx" "$pct_5xx"

        printf 'REQUISICOES POR IP\n'
        sort "$ips_file" | uniq -c | sort -rn | while read -r cnt ip_addr; do
            printf '  %s: %s\n' "$ip_addr" "$cnt"
        done
        printf '\n'

        printf 'REQUISICOES POR RECURSO\n'
        sort "$resources_file" | uniq -c | sort -rn | while read -r cnt res; do
            printf '  %s: %s\n' "$res" "$cnt"
        done
        printf '\n'

        printf 'REQUISICOES POR METODO\n'
        sort "$methods_file" | uniq -c | sort -rn | while read -r cnt meth; do
            printf '  %s: %s\n' "$meth" "$cnt"
        done
        printf '\n'

        printf 'ERROS HTTP\n'
        printf '  Respostas 4xx: %d\n' "$count_4xx"
        printf '  Respostas 5xx: %d\n' "$count_5xx"
        printf '  Total: %d\n\n' "$total_errors"

        printf 'ENDERECOS IP COM MAIS ERROS (4xx/5xx)\n'
        if [ -s "$error_ips_file" ]; then
            sort "$error_ips_file" | uniq -c | sort -rn | while read -r cnt ip_err; do
                printf '  %s: %s\n' "$ip_err" "$cnt"
            done
        else
            printf '  Nenhum erro HTTP registrado.\n'
        fi
        printf '\n'

        printf 'HORARIO\n'
        printf '  Primeira requisicao: %s\n' "$first_time"
        printf '  Ultima requisicao: %s\n\n' "$last_time"
    else
        printf '=================================\n'
        printf '      RELATORIO DE ACESSOS\n'
        printf '=================================\n\n'
        printf 'Arquivo: %s\n' "$LOG_FILE"
        printf 'Total de requisicoes: %d\n' "$valid_count"
        if [ "$invalid_count" -gt 0 ]; then
            printf 'Linhas invalidas ignoradas: %d\n' "$invalid_count"
        fi
        printf '\n'

        printf 'Respostas HTTP:\n'
        printf '  200: %d\n' "$count_200"
        printf '  404: %d\n' "$count_404"
        printf '  500: %d\n\n' "$count_500"

        printf 'Enderecos com mais acessos:\n'
        sort "$ips_file" | uniq -c | sort -rn | head -n 5 | while read -r cnt ip_addr; do
            printf '  %s: %s\n' "$ip_addr" "$cnt"
        done
        printf '\n'

        printf 'Enderecos que geraram mais erros:\n'
        if [ -s "$error_ips_file" ]; then
            sort "$error_ips_file" | uniq -c | sort -rn | head -n 5 | while read -r cnt ip_err; do
                printf '  %s: %s\n' "$ip_err" "$cnt"
            done
        else
            printf '  Nenhum erro HTTP registrado.\n'
        fi
        printf '\n'
    fi

    return 0
}

# ------------------------------------------------------------------------------
# Modulo 5 — Relatorio e historico de execucao (-o ARQUIVO)
# ------------------------------------------------------------------------------
write_report() {
    report_path="$1"
    srv_host=$(get_hostname_safe)
    srv_date=$(get_datetime_safe)

    if [ "$VERBOSE" -eq 1 ]; then
        mode_label="Detalhado (-v)"
    else
        mode_label="Normal"
    fi

    {
        printf '=================================================================\n'
        printf '                RELATORIO DE AUDITORIA - NETADMIN\n'
        printf '=================================================================\n'
        printf 'Data e horario da execucao: %s\n' "$srv_date"
        printf 'Nome do servidor: %s\n' "$srv_host"
        printf 'Modo de execucao: %s\n' "$mode_label"
        printf 'Verificacoes realizadas: %s\n' "$CHECKS_RUN"
        printf '=================================================================\n\n'

        cat "$MODULES_OUT"

        printf '=================================================================\n'
        printf '                    PROBLEMAS IDENTIFICADOS\n'
        printf '=================================================================\n'
        if [ "$PROBLEMS_COUNT" -gt 0 ] && [ -s "$PROBLEMS_FILE" ]; then
            p_idx=1
            while IFS= read -r p_line; do
                [ -z "$p_line" ] && continue
                printf '%d. %s\n' "$p_idx" "$p_line"
                p_idx=$((p_idx + 1))
            done < "$PROBLEMS_FILE"
        else
            printf 'Nenhum problema identificado durante a auditoria.\n'
        fi
        printf '=================================================================\n'
    } > "$report_path"

    if [ $? -ne 0 ]; then
        log_error "Modulo 5: falha ao gravar relatorio em '$report_path'."
        return 1
    fi

    printf 'Relatorio salvo com sucesso em: %s\n' "$report_path"
    return 0
}

# ------------------------------------------------------------------------------
# Funcao principal
# ------------------------------------------------------------------------------
main() {
    if [ "$#" -eq 0 ]; then
        show_help
        exit 0
    fi

    while getopts ":ip:P:sc:l:o:vh" opt; do
        case "$opt" in
            i)
                OPT_INFO=1
                ;;
            p)
                OPT_PING=1
                PING_TARGET="$OPTARG"
                ;;
            P)
                OPT_PING_FILE=1
                PING_FILE="$OPTARG"
                ;;
            s)
                OPT_SERVICES=1
                ;;
            c)
                OPT_PORTS=1
                CHECK_PORTS="$OPTARG"
                ;;
            l)
                OPT_LOG=1
                LOG_FILE="$OPTARG"
                ;;
            o)
                OPT_OUTPUT=1
                OUTPUT_FILE="$OPTARG"
                ;;
            v)
                VERBOSE=1
                ;;
            h)
                show_help
                exit 0
                ;;
            :)
                error_exit "A opcao '-$OPTARG' exige um argumento. Use -h para ajuda."
                ;;
            \?)
                error_exit "Opcao invalida: '-$OPTARG'. Use -h para ajuda."
                ;;
        esac
    done

    shift $((OPTIND - 1))

    # Verifica se restaram argumentos posicionais nao esperados
    if [ "$#" -gt 0 ]; then
        error_exit "Argumento posicional nao reconhecido: '$1'. Use -h para consultar a sintaxe."
    fi

    # Se apenas -o foi informado sem nenhum modulo, executa auditoria padrao (-i e -s)
    if [ "$OPT_INFO" -eq 0 ] && [ "$OPT_PING" -eq 0 ] && [ "$OPT_PING_FILE" -eq 0 ] && \
       [ "$OPT_SERVICES" -eq 0 ] && [ "$OPT_PORTS" -eq 0 ] && [ "$OPT_LOG" -eq 0 ]; then
        if [ "$OPT_OUTPUT" -eq 1 ]; then
            printf 'Aviso: nenhuma verificacao especifica informada; executando auditoria padrao (-i e -s).\n\n'
            OPT_INFO=1
            OPT_SERVICES=1
        else
            error_exit "Nenhuma operacao selecionada. Informe -i, -p, -P, -s, -c ou -l (use -h para ajuda)."
        fi
    fi

    # Valida arquivo de saida antecipadamente se -o foi informado
    if [ "$OPT_OUTPUT" -eq 1 ]; then
        if ! validate_output_file "$OUTPUT_FILE"; then
            exit 1
        fi
    fi

    init_temp

    run_module() {
        mod_fn="$1"
        mod_buf="$TMP_DIR/current_module.out"
        : > "$mod_buf"

        "$mod_fn" > "$mod_buf"
        mod_rc=$?

        if [ -s "$mod_buf" ]; then
            cat "$mod_buf"
            if [ "$OPT_OUTPUT" -eq 1 ]; then
                cat "$mod_buf" >> "$MODULES_OUT"
            fi
        fi

        if [ "$mod_rc" -ne 0 ]; then
            EXIT_CODE=1
        fi
    }

    if [ "$OPT_INFO" -eq 1 ]; then
        run_module module_network_info
    fi

    if [ "$OPT_PING" -eq 1 ]; then
        run_module module_ping_single
    fi

    if [ "$OPT_PING_FILE" -eq 1 ]; then
        run_module module_ping_file
    fi

    if [ "$OPT_SERVICES" -eq 1 ]; then
        run_module module_services_list
    fi

    if [ "$OPT_PORTS" -eq 1 ]; then
        run_module module_check_ports
    fi

    if [ "$OPT_LOG" -eq 1 ]; then
        run_module module_analyze_log
    fi

    if [ "$OPT_OUTPUT" -eq 1 ]; then
        if ! write_report "$OUTPUT_FILE"; then
            EXIT_CODE=1
        fi
    fi

    exit "$EXIT_CODE"
}

main "$@"
