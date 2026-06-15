
#!/usr/bin/env bash
# =============================================================================
# nas_cleanup.sh — Gestion d'espace NAS pour pipeline ETL
# =============================================================================
# Usage : sudo bash nas_cleanup.sh [OPTIONS]
#
# Options :
#   -d <répertoire>   Répertoire racine à analyser       (défaut: /mnt/nas)
#   -s <taille>       Taille minimale des fichiers en Mo  (défaut: 100)
#   -t <seuil>        Seuil d'alerte disque en %          (défaut: 80)
#   -l <fichier>      Fichier de log                      (défaut: /var/log/nas_cleanup.log)
#   -n                Dry-run : simulation sans suppression
#   -h                Afficher l'aide
# =============================================================================

set -euo pipefail

# ─── Couleurs ────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Valeurs par défaut ───────────────────────────────────────────────────────
NAS_ROOT="/mnt/nas"
MIN_SIZE_MB=100
DISK_THRESHOLD=80
LOG_FILE="/var/log/nas_cleanup.log"
DRY_RUN=false
TEMP_LIST=""

# ─── Fonctions utilitaires ────────────────────────────────────────────────────

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log() {
    local level="$1"; shift
    local msg="$*"
    local ts
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
}

print_header() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║          NAS CLEANUP — Gestionnaire d'espace ETL         ║${RESET}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_section() {
    echo ""
    echo -e "${BOLD}${YELLOW}▶ $*${RESET}"
    echo -e "${YELLOW}$(printf '%.0s─' {1..60})${RESET}"
}

abort() {
    echo -e "\n${RED}✖ Abandon : $*${RESET}"
    log "ERROR" "$*"
    cleanup_temp
    exit 1
}

cleanup_temp() {
    [[ -n "$TEMP_LIST" && -f "$TEMP_LIST" ]] && rm -f "$TEMP_LIST"
}

trap cleanup_temp EXIT

# Convertit des octets en unité lisible
human_size() {
    local bytes=$1
    if   (( bytes >= 1073741824 )); then printf "%.2f Go" "$(echo "scale=2; $bytes/1073741824" | bc)"
    elif (( bytes >= 1048576 ))   ; then printf "%.2f Mo" "$(echo "scale=2; $bytes/1048576"    | bc)"
    elif (( bytes >= 1024 ))      ; then printf "%.2f Ko" "$(echo "scale=2; $bytes/1024"        | bc)"
    else printf "%d  o" "$bytes"
    fi
}

# Valide le format de date YYYY-MM-DD
validate_date() {
    local d="$1"
    if ! date -d "$d" '+%Y-%m-%d' &>/dev/null 2>&1; then
        # Fallback BSD date (macOS)
        if ! date -j -f '%Y-%m-%d' "$d" '+%Y-%m-%d' &>/dev/null 2>&1; then
            return 1
        fi
    fi
    return 0
}

# ─── Parsing des arguments ────────────────────────────────────────────────────

while getopts ":d:s:t:l:nh" opt; do
    case $opt in
        d) NAS_ROOT="$OPTARG"     ;;
        s) MIN_SIZE_MB="$OPTARG"  ;;
        t) DISK_THRESHOLD="$OPTARG" ;;
        l) LOG_FILE="$OPTARG"     ;;
        n) DRY_RUN=true           ;;
        h) usage                  ;;
        :) abort "Option -$OPTARG requiert un argument." ;;
        \?) abort "Option inconnue : -$OPTARG"           ;;
    esac
done

# ─── Vérifications préalables ─────────────────────────────────────────────────

print_header

# Vérifier que le répertoire existe
[[ -d "$NAS_ROOT" ]] || abort "Répertoire introuvable : $NAS_ROOT"

# Vérifier les commandes requises
for cmd in find du df date bc awk sort; do
    command -v "$cmd" &>/dev/null || abort "Commande manquante : $cmd"
done

# Créer le fichier de log si nécessaire
touch "$LOG_FILE" 2>/dev/null || LOG_FILE="/tmp/nas_cleanup_$(date +%s).log"
log "INFO" "Démarrage du script — répertoire: $NAS_ROOT, taille min: ${MIN_SIZE_MB}Mo"

# ─── ÉTAPE 1 : État du disque ─────────────────────────────────────────────────

print_section "État du disque"

DISK_INFO=$(df -h "$NAS_ROOT" | tail -1)
DISK_USED_PCT=$(df "$NAS_ROOT" | tail -1 | awk '{print $5}' | tr -d '%')
DISK_USED=$(echo "$DISK_INFO" | awk '{print $3}')
DISK_AVAIL=$(echo "$DISK_INFO" | awk '{print $4}')
DISK_TOTAL=$(echo "$DISK_INFO" | awk '{print $2}')

echo -e "  Répertoire  : ${BOLD}$NAS_ROOT${RESET}"
echo -e "  Capacité    : $DISK_TOTAL  |  Utilisé : $DISK_USED  |  Disponible : ${BOLD}$DISK_AVAIL${RESET}"

if (( DISK_USED_PCT >= DISK_THRESHOLD )); then
    echo -e "  Utilisation : ${RED}${BOLD}${DISK_USED_PCT}%${RESET} ${RED}⚠ Seuil dépassé (${DISK_THRESHOLD}%)${RESET}"
    log "WARN" "Seuil disque dépassé : ${DISK_USED_PCT}% >= ${DISK_THRESHOLD}%"
else
    echo -e "  Utilisation : ${GREEN}${DISK_USED_PCT}%${RESET} (seuil: ${DISK_THRESHOLD}%)"
fi

# ─── ÉTAPE 2 : Scan des fichiers volumineux ───────────────────────────────────

print_section "Scan des fichiers ≥ ${MIN_SIZE_MB} Mo"

TEMP_LIST=$(mktemp /tmp/nas_filelist_XXXXXX.tsv)

echo -e "  ${CYAN}Analyse en cours...${RESET}"

# find : taille, date de modification, chemin
# Format TSV : <taille_octets>\t<date_modif YYYY-MM-DD>\t<chemin>
find "$NAS_ROOT" -type f -size +"${MIN_SIZE_MB}M" \
    -printf '%s\t%TY-%Tm-%Td\t%p\n' 2>/dev/null \
    | sort -t$'\t' -k2,2 \
    > "$TEMP_LIST"

FILE_COUNT=$(wc -l < "$TEMP_LIST")

if [[ "$FILE_COUNT" -eq 0 ]]; then
    echo -e "  ${GREEN}✔ Aucun fichier ≥ ${MIN_SIZE_MB} Mo trouvé. Espace NAS correct.${RESET}"
    log "INFO" "Aucun fichier volumineux détecté."
    exit 0
fi

TOTAL_BYTES=$(awk -F'\t' '{sum+=$1} END {print sum+0}' "$TEMP_LIST")
TOTAL_HUMAN=$(human_size "$TOTAL_BYTES")

echo -e "  ${BOLD}${FILE_COUNT}${RESET} fichier(s) trouvé(s) — Volume total : ${BOLD}${TOTAL_HUMAN}${RESET}"
echo ""

# Afficher un aperçu (top 15 par taille décroissante)
echo -e "  ${BOLD}Aperçu des 15 fichiers les plus volumineux :${RESET}"
echo -e "  $(printf '%-12s %-12s %s' 'TAILLE' 'DATE' 'CHEMIN')"
echo -e "  $(printf '%.0s─' {1..70})"

sort -t$'\t' -k1,1rn "$TEMP_LIST" | head -15 | while IFS=$'\t' read -r size date path; do
    h=$(human_size "$size")
    printf "  %-12s %-12s %s\n" "$h" "$date" "$path"
done

# ─── ÉTAPE 3 : Plage de dates ─────────────────────────────────────────────────

print_section "Définition de la plage de suppression"

# Bornes disponibles dans la liste
DATE_MIN=$(awk -F'\t' '{print $2}' "$TEMP_LIST" | sort | head -1)
DATE_MAX=$(awk -F'\t' '{print $2}' "$TEMP_LIST" | sort | tail -1)

echo -e "  Plage disponible : ${BOLD}$DATE_MIN${RESET}  →  ${BOLD}$DATE_MAX${RESET}"
echo ""

while true; do
    read -rp "  Date de début (YYYY-MM-DD) [défaut: $DATE_MIN] : " DATE_FROM
    DATE_FROM="${DATE_FROM:-$DATE_MIN}"
    validate_date "$DATE_FROM" && break
    echo -e "  ${RED}Format invalide. Utilisez YYYY-MM-DD.${RESET}"
done

while true; do
    read -rp "  Date de fin   (YYYY-MM-DD) [défaut: $DATE_MAX] : " DATE_TO
    DATE_TO="${DATE_TO:-$DATE_MAX}"
    validate_date "$DATE_TO" && break
    echo -e "  ${RED}Format invalide. Utilisez YYYY-MM-DD.${RESET}"
done

if [[ "$DATE_FROM" > "$DATE_TO" ]]; then
    abort "La date de début ($DATE_FROM) est postérieure à la date de fin ($DATE_TO)."
fi

echo -e "\n  Plage retenue : ${BOLD}${DATE_FROM}${RESET}  →  ${BOLD}${DATE_TO}${RESET}"

# ─── ÉTAPE 4 : Filtrage et récapitulatif ─────────────────────────────────────

print_section "Récapitulatif des fichiers à supprimer"

TEMP_SELECTED=$(mktemp /tmp/nas_selected_XXXXXX.tsv)

awk -F'\t' -v from="$DATE_FROM" -v to="$DATE_TO" \
    '$2 >= from && $2 <= to {print}' "$TEMP_LIST" \
    | sort -t$'\t' -k2,2 \
    > "$TEMP_SELECTED"

SEL_COUNT=$(wc -l < "$TEMP_SELECTED")

if [[ "$SEL_COUNT" -eq 0 ]]; then
    echo -e "  ${YELLOW}⚠ Aucun fichier dans cette plage de dates.${RESET}"
    log "INFO" "Aucun fichier sélectionné pour la plage $DATE_FROM → $DATE_TO"
    rm -f "$TEMP_SELECTED"
    exit 0
fi

SEL_BYTES=$(awk -F'\t' '{sum+=$1} END {print sum+0}' "$TEMP_SELECTED")
SEL_HUMAN=$(human_size "$SEL_BYTES")

echo -e "  Fichiers sélectionnés : ${BOLD}${SEL_COUNT}${RESET}"
echo -e "  Volume à libérer      : ${BOLD}${RED}${SEL_HUMAN}${RESET}"
echo ""

# Distribution par sous-répertoire
echo -e "  ${BOLD}Répartition par répertoire parent :${RESET}"
awk -F'\t' '{
    n=split($3, parts, "/")
    dir=""
    for(i=1; i<n; i++) dir=dir"/"parts[i]
    sizes[dir]+=$1; counts[dir]++
} END {
    for(d in sizes) printf "  %-10s  %-5d fichier(s)  %s\n", sizes[d], counts[d], d
}' "$TEMP_SELECTED" | sort -rn | head -20 | while read -r bytes rest; do
    echo -e "  $(human_size "$bytes")  $rest"
done

echo ""
echo -e "  ${BOLD}Liste complète des fichiers ciblés :${RESET}"
echo -e "  $(printf '%-12s %-12s %s' 'TAILLE' 'DATE' 'CHEMIN')"
echo -e "  $(printf '%.0s─' {1..70})"
while IFS=$'\t' read -r size date path; do
    h=$(human_size "$size")
    printf "  %-12s %-12s %s\n" "$h" "$date" "$path"
done < "$TEMP_SELECTED"

# ─── ÉTAPE 5 : Confirmation et suppression ────────────────────────────────────

print_section "Confirmation de suppression"

if $DRY_RUN; then
    echo -e "  ${YELLOW}Mode DRY-RUN actif — aucune suppression ne sera effectuée.${RESET}"
fi

echo -e "  ${RED}${BOLD}⚠  ATTENTION${RESET} : Cette opération est ${BOLD}irréversible${RESET}."
echo -e "  ${SEL_COUNT} fichier(s) représentant ${BOLD}${SEL_HUMAN}${RESET} seront supprimés."
echo ""
read -rp "  Confirmez-vous la suppression ? Tapez exactement ${BOLD}OUI${RESET} pour valider : " CONFIRM

if [[ "$CONFIRM" != "OUI" ]]; then
    echo -e "\n  ${YELLOW}✖ Suppression annulée par l'administrateur.${RESET}"
    log "INFO" "Suppression annulée par l'administrateur."
    rm -f "$TEMP_SELECTED"
    exit 0
fi

print_section "Suppression en cours"

SUCCESS=0
FAIL=0
FREED_BYTES=0

while IFS=$'\t' read -r size date path; do
    if $DRY_RUN; then
        echo -e "  [DRY-RUN] Suppression simulée : $path"
        (( SUCCESS++ )) || true
        (( FREED_BYTES += size )) || true
        log "DRY-RUN" "Simulé : $path ($size octets)"
    else
        if rm -f "$path" 2>/dev/null; then
            echo -e "  ${GREEN}✔${RESET} Supprimé : $path"
            (( SUCCESS++ )) || true
            (( FREED_BYTES += size )) || true
            log "INFO" "Supprimé : $path ($size octets)"
        else
            echo -e "  ${RED}✖${RESET} Échec    : $path"
            (( FAIL++ )) || true
            log "ERROR" "Échec suppression : $path"
        fi
    fi
done < "$TEMP_SELECTED"

rm -f "$TEMP_SELECTED"

# ─── ÉTAPE 6 : Rapport final ──────────────────────────────────────────────────

print_section "Rapport final"

FREED_HUMAN=$(human_size "$FREED_BYTES")

echo -e "  Fichiers supprimés : ${GREEN}${BOLD}${SUCCESS}${RESET}"
[[ $FAIL -gt 0 ]] && echo -e "  Échecs             : ${RED}${BOLD}${FAIL}${RESET}"
echo -e "  Espace libéré      : ${GREEN}${BOLD}${FREED_HUMAN}${RESET}"
echo ""

if ! $DRY_RUN; then
    NEW_AVAIL=$(df -h "$NAS_ROOT" | tail -1 | awk '{print $4}')
    NEW_PCT=$(df "$NAS_ROOT" | tail -1 | awk '{print $5}')
    echo -e "  Nouvel espace disponible : ${BOLD}${NEW_AVAIL}${RESET} (utilisation : ${NEW_PCT})"
fi

echo -e "\n  Log complet : ${CYAN}${LOG_FILE}${RESET}"
log "INFO" "Terminé — supprimés: $SUCCESS, échecs: $FAIL, libéré: $FREED_BYTES octets"

echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${GREEN}║                    Opération terminée                    ║${RESET}"
echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo ""
