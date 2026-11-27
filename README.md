# NetAdmin (`netadmin.sh`)

Ferramenta de diagnóstico e auditoria de servidores Linux desenvolvida em **Shell Script (POSIX `sh`)** para a disciplina de **Sistemas Operacionais Abertos** (IFRN — Campus Canguaretama).

---

## Visão Geral

O `netadmin.sh` reúne em uma única interface de linha de comando verificações essenciais de infraestrutura Linux, com suporte a modo normal, modo detalhado (`-v`), tratamento de erros, limpeza automática de arquivos temporários (`trap`) e exportação de relatórios de auditoria (`-o`).

---

## Opções Disponíveis

| Opção | Argumento | Finalidade |
| :--- | :--- | :--- |
| `-i` | — | Exibir informações do servidor, interfaces de rede e rotas. |
| `-p` | `DESTINO` | Testar a conectividade com um destino (IP ou domínio). |
| `-P` | `ARQUIVO` | Testar a conectividade com todos os destinos listados em um arquivo. |
| `-s` | — | Listar serviços e portas em estado de escuta (`ss -tuln`). |
| `-c` | `PORTAS` | Verificar uma ou mais portas locais específicas (separadas por vírgula). |
| `-l` | `ARQUIVO` | Analisar um arquivo de log HTTP (`access.log`). |
| `-o` | `ARQUIVO` | Salvar os resultados, metadados e problemas em um relatório. |
| `-v` | — | Ativar o modo detalhado. |
| `-h` | — | Exibir a ajuda de utilização. |

---

## Módulos Implementados

1. **Módulo 1 — Informações do servidor e interfaces de rede (`-i`)**
   - Apresenta hostname, data/horário, estado de cada interface (`ATIVA` / `DESATIVADA`), endereços IPv4 configurados e status da rota padrão.
   - Destaca automaticamente interfaces desativadas, interfaces ativas sem IPv4 e ausência de rota padrão.
   - No modo detalhado (`-v`), inclui sistema operacional, versão do kernel, tempo ligado (`uptime`), MAC, IPv6, MTU, tabela completa de rotas, comandos utilizados e lista numerada de diagnósticos.

2. **Módulo 2 — Testes de conectividade (`-p` e `-P`)**
   - Executa testes via `ping` (4 pacotes) para um destino único ou uma lista em arquivo (ignorando linhas vazias e comentários `#`).
   - Interpreta pacotes enviados, recebidos, perda (%) e latência média.
   - No modo detalhado (`-v`), exibe o IP resolvido, resultado de cada tentativa e tempos mínimo/médio/máximo.

3. **Módulo 3 — Verificação de serviços e portas (`-s` e `-c`)**
   - Lista sockets TCP/UDP em escuta usando `ss -tuln`.
   - No modo detalhado (`-v`), separa sockets TCP e UDP e indica se cada porta escuta em todas as interfaces ou apenas localmente (`127.0.0.1` / `::1`).
   - Com `-c PORTA1,PORTA2,...`, valida cada porta (1–65535) e informa se está `ABERTA` (com protocolos) ou `NAO ENCONTRADA`.

4. **Módulo 4 — Análise de arquivos de log (`-l`)**
   - Processa logs no formato padrão Apache/Nginx utilizando `grep`, `cut`, `sort`, `uniq` e `wc`.
   - Exibe total de requisições, contagens de códigos HTTP (`200`, `404`, `500`), IPs que mais acessaram e IPs que geraram mais erros (`4xx`/`5xx`).
   - No modo detalhado (`-v`), exibe linhas inválidas, distribuição completa por código HTTP, classificação `2xx/3xx/4xx/5xx` com percentuais, requisições por IP, por recurso, por método HTTP e horário da primeira e última requisição.

5. **Módulo 5 — Relatório e histórico de execução (`-o`)**
   - Valida diretório de saída e permissões de escrita antes da execução.
   - Gera arquivo estruturado contendo data/horário, nome do servidor, modo, verificações realizadas, resultados obtidos e lista consolidada de problemas identificados.
   - Se `-o` for utilizado sozinho sem outra opção de módulo, executa uma auditoria padrão (`-i` e `-s`).

---

## Exemplos de Uso

```sh
# Dar permissão de execução
chmod +x netadmin.sh

# Exibir ajuda
./netadmin.sh -h

# Diagnóstico de rede (normal e detalhado)
./netadmin.sh -i
./netadmin.sh -i -v

# Teste de conectividade único e em lote
./netadmin.sh -p 192.168.1.1
./netadmin.sh -p google.com -v
./netadmin.sh -P exemplos/destinos.txt

# Serviços locais e verificação de portas
./netadmin.sh -s
./netadmin.sh -s -v
./netadmin.sh -c 22,80,443

# Análise de log HTTP
./netadmin.sh -l exemplos/acessos_basico.log
./netadmin.sh -l exemplos/acessos_basico.log -v

# Auditoria combinada com geração de relatório
./netadmin.sh -i -s -c 22,80 -l exemplos/acessos_basico.log -o auditoria.txt -v
```

---

## Depuração e Conformidade POSIX

O script foi desenvolvido em conformidade com POSIX `sh` (`#!/bin/sh`), utilizando `getopts`, `OPTIND`/`shift`, `case`, `if`, `test`, laços `while`/`for`, funções modulares, pipes, redirecionamentos e `trap` para remoção de arquivos temporários em `EXIT`, `INT` e `TERM`.

Para validar sintaxe e rastrear execução:

```sh
sh -n netadmin.sh
sh -x ./netadmin.sh -l exemplos/acessos_basico.log
```

---

## Requisitos do Sistema

- Interpretador POSIX `sh` (`dash`, `bash`, `ash`, etc.)
- Utilitários padrão GNU/Linux: `grep`, `cut`, `sort`, `uniq`, `wc`, `awk`, `sed`, `tr`, `hostname`, `date`, `uname`
- Pacote `iproute2` (`ip` e `ss`) e `iputils-ping` (`ping`)
