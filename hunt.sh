#!/bin/bash
# Oracle Cloud Always Free A1.Flex kapasite avi — GitHub Actions tarafi.
# Her calismada, sure butcesi dolana kadar boyut/AD kombinasyonlarini dener.
set -u

export SUPPRESS_LABEL_WARNING=True

SURE=${SURE:-240}            # bu calismada denemeye ayrilan saniye
BEKLE=${BEKLE:-15}           # denemeler arasi aralik
SHAPES=("4 24" "2 12" "1 6") # buyukten kucuge; ilk tutan alinir
TENANCY="$OCI_CLI_TENANCY"
# Secret'tan gelen anahtarda satir sonu kalmis olabilir; metadata JSON'unu bozar.
SSH_PUBKEY=$(printf '%s' "$SSH_PUBKEY" | tr -d '\n\r')

log() { echo "[$(date -u '+%H:%M:%S')] $*"; }

# --- Zaten bir sunucu var mi? (Mac'teki avci kapmis olabilir) ---------------
liste=$(oci compute instance list -c "$TENANCY" --output json 2>/dev/null)
canli=$(printf '%s' "$liste" | grep -o '"lifecycle-state": "[A-Z]*"' | grep -vc 'TERMINAT')
if [ "$canli" -gt 0 ]; then
  log "Tenancy'de zaten $canli calisan sunucu var — bu calisma atlaniyor."
  exit 0
fi

# --- Availability domain'ler ve guncel imaj --------------------------------
ADS=($(oci iam availability-domain list --query 'data[].name' --raw-output 2>/dev/null | tr -d '[],"' | tr -s ' \n' '\n' | grep -v '^$'))
if [ "${#ADS[@]}" -eq 0 ]; then
  log "HATA: availability domain listesi alinamadi (kimlik bilgileri hatali olabilir)."
  exit 1
fi

IMAGE=$(oci compute image list -c "$TENANCY" \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --shape VM.Standard.A1.Flex --sort-by TIMECREATED \
  --query 'data[0].id' --raw-output 2>/dev/null)
if [ -z "${IMAGE:-}" ]; then
  log "HATA: Ubuntu imaji bulunamadi."
  exit 1
fi

log "Av basliyor — ${#ADS[@]} AD, ${#SHAPES[@]} boyut, ${SURE}s butce"
BITIS=$(( $(date +%s) + SURE ))
deneme=0

while [ "$(date +%s)" -lt "$BITIS" ]; do
  for SHAPE in "${SHAPES[@]}"; do
    OCPUS=${SHAPE% *}
    MEM=${SHAPE#* }

    for AD in "${ADS[@]}"; do
      [ "$(date +%s)" -ge "$BITIS" ] && break 3
      deneme=$((deneme + 1))
      etiket="${AD##*-1-} ${OCPUS}/${MEM}"

      resp=$(oci --no-retry compute instance launch \
        --availability-domain "$AD" \
        --compartment-id "$TENANCY" \
        --shape VM.Standard.A1.Flex \
        --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEM}" \
        --image-id "$IMAGE" \
        --subnet-id "$SUBNET_ID" \
        --assign-public-ip true \
        --display-name trendoptik \
        --metadata "{\"ssh_authorized_keys\":\"$SSH_PUBKEY\"}" 2>&1)

      if [ $? -eq 0 ]; then
        iid=$(printf '%s' "$resp" | sed -n 's/.*"id": "\(ocid1\.instance[^"]*\)".*/\1/p' | head -1)
        log "### SUNUCU OLUSTU — ${OCPUS} OCPU / ${MEM} GB, $AD"
        log "### $iid"

        ip=""
        for _ in $(seq 1 24); do
          sleep 10
          ip=$(oci compute instance list-vnics --instance-id "$iid" \
            --query 'data[0]."public-ip"' --raw-output 2>/dev/null)
          [ -n "${ip:-}" ] && [ "$ip" != "null" ] && break
        done
        log "### PUBLIC IP: ${ip:-henuz atanmadi}"

        {
          echo "ocpus=$OCPUS"
          echo "memory=$MEM"
          echo "ad=$AD"
          echo "instance_id=$iid"
          echo "public_ip=${ip:-}"
        } >>"${GITHUB_OUTPUT:-/dev/null}"
        exit 0
      fi

      case "$resp" in
        *OutOfHostCapacity* | *"Out of host capacity"*)
          log "#$deneme $etiket — kapasite yok" ;;
        *TooManyRequests* | *"Too many requests"* | *"429"*)
          BEKLE=$((BEKLE * 2)); [ "$BEKLE" -gt 90 ] && BEKLE=90
          log "#$deneme $etiket — rate limit; aralik ${BEKLE}s"
          sleep 60 ;;
        *LimitExceeded* | *QuotaExceeded*)
          log "#$deneme $etiket — LIMIT/KOTA ASILDI: $(printf '%s' "$resp" | tr '\n' ' ' | cut -c1-200)"
          exit 0 ;;
        *NotAuthenticated* | *"401"*)
          log "#$deneme $etiket — KIMLIK DOGRULAMA HATASI: $(printf '%s' "$resp" | tr '\n' ' ' | cut -c1-200)"
          exit 1 ;;
        *)
          log "#$deneme $etiket — hata: $(printf '%s' "$resp" | tr '\n' ' ' | cut -c1-200)" ;;
      esac

      sleep "$BEKLE"
    done
  done
done

log "Butce doldu — $deneme deneme yapildi, kapasite cikmadi."
