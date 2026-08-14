# oracle-a1-hunter

Oracle Cloud'un **Always Free** ARM sunucusu (`VM.Standard.A1.Flex`) icin kapasite bekleyen
kucuk bir GitHub Actions isi. Frankfurt bolgesinde bu shape surekli "Out of host capacity"
dondugu icin, kapasite acilana kadar belirli araliklarla deniyor.

## Nasil calisiyor

- 15 dakikada bir tetiklenir (`.github/workflows/hunt.yml`).
- Her calismada ~4 dakika boyunca, buyukten kucuge **4 OCPU/24 GB → 2/12 → 1/6**
  boyutlarini tenancy'deki tum availability domain'lerde dener. Ilk kabul edilen alinir.
- Rate limit (429) yerse aralik kendini buyutur.
- Tenancy'de calisan bir sunucu varsa hicbir sey denemeden cikar; boylede ayni anda
  calisan baska bir avci (ornegin yerel makinedeki) ile catismaz.
- Sunucu olustugunda repo'da IP ve baglanti bilgisini iceren bir issue acilir.

## Gerekli secret'lar

| Secret | Icerik |
| --- | --- |
| `OCI_CLI_USER` | Kullanici OCID |
| `OCI_CLI_TENANCY` | Tenancy OCID |
| `OCI_CLI_FINGERPRINT` | API anahtari parmak izi |
| `OCI_CLI_KEY_CONTENT` | API ozel anahtari (PEM) |
| `OCI_CLI_REGION` | Bolge, ornegin `eu-frankfurt-1` |
| `OCI_SUBNET_ID` | Sunucunun baglanacagi public subnet OCID |
| `OCI_SSH_PUBKEY` | Sunucuya yazilacak SSH acik anahtari |

Workflow yalnizca `schedule` ve `workflow_dispatch` ile tetiklenir; pull request
tetikleyicisi bulunmadigi icin fork'lardan gelen kod secret'lara erisemez.
