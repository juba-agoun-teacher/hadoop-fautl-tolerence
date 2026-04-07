#!/usr/bin/env bash
# =============================================================================
#  tp_hadoop.sh  –  Script principal du TP Hadoop HDFS + MapReduce
# =============================================================================
# Usage :
#   bash scripts/tp_hadoop.sh          # exécute toutes les parties
#   bash scripts/tp_hadoop.sh partie1  # seulement la partie 1
#   bash scripts/tp_hadoop.sh partie2  # seulement la partie 2
# =============================================================================

set -euo pipefail

NAMENODE="namenode"
HDFS_INPUT="/user/tp/ratings"
HDFS_OUTPUT="/user/tp/output_ratings"
LOCAL_DATA="/data"
MR_DIR="/mapreduce"
STREAMING_JAR=$(find /opt/hadoop/share/hadoop/tools/lib/ -name "hadoop-streaming*.jar" | head -1)

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

log()   { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
title() { echo -e "\n${BOLD}${YELLOW}══════════════════════════════════════════${RESET}"; \
          echo -e "${BOLD}${YELLOW}  $*${RESET}"; \
          echo -e "${BOLD}${YELLOW}══════════════════════════════════════════${RESET}\n"; }

# ─────────────────────────────────────────────────────────────────────────────
partie1() {

  # ── Étape 0 : Attendre que le cluster soit prêt ──────────────────────────
  title "Étape 0 – Vérification du cluster"
  log "Attente que le NameNode soit disponible…"
  until hdfs dfsadmin -report &>/dev/null; do
    sleep 3
    echo -n "."
  done
  echo ""
  ok "Cluster Hadoop opérationnel"
  hdfs dfsadmin -report | grep -E "^(Name|Live|Dead|Hostname)"

  # ── Étape 1 : Générer le fichier de ratings en local ─────────────────────
  title "Étape 1 – Génération du fichier ratings.csv"
  log "Génération de 100 000 ratings avec Python…"
  python3 ${LOCAL_DATA}/generate_ratings.py 100000
  wc -l ${LOCAL_DATA}/ratings.csv
  head -5 ${LOCAL_DATA}/ratings.csv
  ok "Fichier ratings.csv créé"

  # ── Étape 2 : Copier le fichier dans HDFS ────────────────────────────────
  title "Étape 2 – Chargement dans HDFS"
  log "Création du répertoire HDFS ${HDFS_INPUT}…"
  hdfs dfs -mkdir -p ${HDFS_INPUT}

  log "Copie de ratings.csv vers HDFS…"
  hdfs dfs -put -f ${LOCAL_DATA}/ratings.csv ${HDFS_INPUT}/ratings.csv
  ok "Fichier présent dans HDFS"

  log "Vérification :"
  hdfs dfs -ls ${HDFS_INPUT}
  hdfs dfs -du -s -h ${HDFS_INPUT}

  log "Localisation des blocs sur les DataNodes :"
  hdfs fsck ${HDFS_INPUT}/ratings.csv -files -blocks -locations

  # ── Étape 3 : Traitement MapReduce – Comptage des ratings ────────────────
  title "Étape 3 – MapReduce : comptage des ratings par note"
  log "Suppression de l'éventuel répertoire de sortie précédent…"
  hdfs dfs -rm -r -f ${HDFS_OUTPUT}

  log "Lancement du job MapReduce (Hadoop Streaming)…"
  hadoop jar ${STREAMING_JAR} \
    -input  ${HDFS_INPUT}/ratings.csv \
    -output ${HDFS_OUTPUT} \
    -mapper  "python3 ${MR_DIR}/mapper_ratings.py" \
    -reducer "python3 ${MR_DIR}/reducer_ratings.py" \
    -file ${MR_DIR}/mapper_ratings.py \
    -file ${MR_DIR}/reducer_ratings.py

  ok "Job MapReduce terminé"
  log "Résultats – Distribution des notes :"
  echo ""
  echo "  Note  | Nombre de ratings"
  echo "  ------|------------------"
  hdfs dfs -cat ${HDFS_OUTPUT}/part-* | sort -t$'\t' -k1 -n | \
    awk -F'\t' '{printf "  %-5s | %s\n", $1, $2}'

  # ── Étape 4 : Tester avec différentes tailles de blocs ──────────────────
  title "Étape 4 – Expérimentation : taille des blocs HDFS"

  for BLOCK_MB in 64 128 256; do
    BLOCK_BYTES=$(( BLOCK_MB * 1024 * 1024 ))
    HDFS_PATH="/user/tp/ratings_block${BLOCK_MB}m"
    OUTPUT_PATH="/user/tp/output_block${BLOCK_MB}m"

    log "--- Test avec blocs de ${BLOCK_MB} Mo ---"
    hdfs dfs -mkdir -p ${HDFS_PATH}
    hdfs dfs -D dfs.blocksize=${BLOCK_BYTES} \
      -put -f ${LOCAL_DATA}/ratings.csv ${HDFS_PATH}/ratings.csv

    log "Nombre de blocs utilisés :"
    hdfs fsck ${HDFS_PATH}/ratings.csv -files -blocks | grep -E "^(Status|Total|Block)"

    log "Lancement du job MapReduce (bloc ${BLOCK_MB} Mo)…"
    START=$(date +%s)
    hdfs dfs -rm -r -f ${OUTPUT_PATH}
    hadoop jar ${STREAMING_JAR} \
      -D dfs.blocksize=${BLOCK_BYTES} \
      -input  ${HDFS_PATH}/ratings.csv \
      -output ${OUTPUT_PATH} \
      -mapper  "python3 ${MR_DIR}/mapper_ratings.py" \
      -reducer "python3 ${MR_DIR}/reducer_ratings.py" \
      -file ${MR_DIR}/mapper_ratings.py \
      -file ${MR_DIR}/reducer_ratings.py \
      2>&1 | grep -E "(map|reduce|Completed)"
    END=$(date +%s)
    ok "Bloc ${BLOCK_MB} Mo – Durée : $(( END - START )) secondes"
  done

  echo ""
  echo -e "${BOLD}Tableau récapitulatif (à compléter avec vos résultats) :${RESET}"
  echo "  ┌────────────┬────────────┬────────────┐"
  echo "  │ Taille bloc│ Nb blocs   │ Durée (s)  │"
  echo "  ├────────────┼────────────┼────────────┤"
  echo "  │   64 Mo    │     ?      │     ?      │"
  echo "  │  128 Mo    │     ?      │     ?      │"
  echo "  │  256 Mo    │     ?      │     ?      │"
  echo "  └────────────┴────────────┴────────────┘"
}

# ─────────────────────────────────────────────────────────────────────────────
partie2() {
  title "PARTIE 2 – Simulation d'une panne de DataNode"

  log "État initial du cluster :"
  hdfs dfsadmin -report | grep -E "^(Live|Dead|Name)"

  # ── 2.1 : Vérifier la réplication AVANT la panne ─────────────────────────
  log "Distribution des blocs avant la panne :"
  hdfs fsck ${HDFS_INPUT}/ratings.csv -files -blocks -locations 2>/dev/null | \
    grep -E "(Block|blk_)" | head -20

  # ── 2.2 : Simuler la panne (arrêt de datanode1) ──────────────────────────
  title "Simulation – Arrêt de datanode1"
  warn "Arrêt du conteneur datanode1…"
  warn "(cette commande doit être lancée depuis l'hôte Docker)"
  echo ""
  echo "  Sur votre terminal HOST (pas dans le conteneur) :"
  echo -e "  ${BOLD}docker stop datanode1${RESET}"
  echo ""
  read -rp "  Appuyez sur [Entrée] une fois datanode1 arrêté…"

  # ── 2.3 : Observer la réaction du cluster ─────────────────────────────────
  title "Observation – Réaction du cluster"
  log "Attente de la détection de la panne (30 s)…"
  sleep 30

  log "État du cluster après la panne :"
  hdfs dfsadmin -report | grep -E "^(Live|Dead|Name)"

  log "Santé du fichier ratings.csv :"
  hdfs fsck ${HDFS_INPUT}/ratings.csv | grep -E "(Status|replicat|corrupt|missing)"

  # ── 2.4 : Vérifier que HDFS reste accessible en lecture ──────────────────
  title "Test de lecture HDFS malgré la panne"
  log "Comptage des lignes via HDFS (doit fonctionner avec 2 DataNodes) :"
  COUNT=$(hdfs dfs -cat ${HDFS_INPUT}/ratings.csv | wc -l)
  ok "Lignes lues : ${COUNT}  →  HDFS toujours accessible ✅"

  # ── 2.5 : Relancer un job MapReduce pendant la panne ─────────────────────
  title "MapReduce pendant la panne"
  log "Lancement d'un job MapReduce avec seulement 2 DataNodes actifs…"
  OUTPUT_PANNE="/user/tp/output_panne"
  hdfs dfs -rm -r -f ${OUTPUT_PANNE}
  hadoop jar ${STREAMING_JAR} \
    -input  ${HDFS_INPUT}/ratings.csv \
    -output ${OUTPUT_PANNE} \
    -mapper  "python3 ${MR_DIR}/mapper_ratings.py" \
    -reducer "python3 ${MR_DIR}/reducer_ratings.py" \
    -file ${MR_DIR}/mapper_ratings.py \
    -file ${MR_DIR}/reducer_ratings.py \
    2>&1 | grep -E "(map|reduce|Completed|Failed)"

  ok "Job MapReduce terminé malgré la panne !"

  # ── 2.6 : Restaurer le DataNode ──────────────────────────────────────────
  title "Restauration – Redémarrage de datanode1"
  echo ""
  echo "  Sur votre terminal HOST :"
  echo -e "  ${BOLD}docker start datanode1${RESET}"
  echo ""
  read -rp "  Appuyez sur [Entrée] une fois datanode1 redémarré…"

  log "Attente de la ré-intégration du nœud (60 s)…"
  sleep 60

  log "État final du cluster :"
  hdfs dfsadmin -report | grep -E "^(Live|Dead|Name)"

  log "Rééquilibrage automatique des blocs (peut prendre quelques minutes) :"
  hdfs fsck ${HDFS_INPUT}/ratings.csv | grep -E "(Status|replicat)"

  ok "PARTIE 2 TERMINÉE – Cluster restauré ✅"
}

# ─────────────────────────────────────────────────────────────────────────────
main() {
  case "${1:-all}" in
    partie1) partie1 ;;
    partie2) partie2 ;;
    all)
      partie1
      echo ""
      warn "Partie 2 disponible : bash scripts/tp_hadoop.sh partie2"
      ;;
    *)
      err "Usage : $0 [partie1|partie2|all]"
      exit 1
      ;;
  esac
}

main "$@"
