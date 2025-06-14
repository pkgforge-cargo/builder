#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Generate Metadata Json
## Self: https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/scripts/gen_meta.sh
# PARALLEL_LIMIT="20" bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/scripts/gen_meta.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
##ENV
export TZ="UTC"
SYSTMP="$(dirname $(mktemp -u))" && export SYSTMP="${SYSTMP}"
TMPDIR="$(mktemp -d)" && export TMPDIR="${TMPDIR}" ; echo -e "\n[+] Using TEMP: ${TMPDIR}\n"
mkdir -pv "${TMPDIR}/assets" "${TMPDIR}/data" "${TMPDIR}/src" "${TMPDIR}/tmp"
rm -rvf "${SYSTMP}/AM.json" 2>/dev/null
#-------------------------------------------------------#

#-------------------------------------------------------#
pushd "${TMPDIR}" &>/dev/null
#Get Repo Tags
 META_REPO="pkgforge-cargo/builder"
 CUTOFF_DATE="$(date --utc -d '7 days ago' '+%Y-%m-%d' | tr -d '[:space:]')" ; unset META_TAGS
 export META_REPO CUTOFF_DATE
 for i in {1..5}; do
   #gh api "repos/${META_REPO}/releases" --paginate 2>/dev/null |& cat - > "${TMPDIR}/tmp/RELEASES.json"
   gh api "repos/${META_REPO}/releases" 2>/dev/null |& cat - > "${TMPDIR}/tmp/RELEASES.json"
   if [[ $(stat -c%s "${TMPDIR}/tmp/RELEASES.json" | tr -d '[:space:]') -le 1000 ]]; then
     echo "Retrying... ${i}/5"
     sleep 2
   elif [[ $(stat -c%s "${TMPDIR}/tmp/RELEASES.json" | tr -d '[:space:]') -gt 1000 ]]; then
     readarray -t "META_TAGS" < <(cat "${TMPDIR}/tmp/RELEASES.json" | jq -r --arg cutoff "${CUTOFF_DATE}" \
       '.[] | select(.tag_name | test("METADATA-[0-9]{4}_[0-9]{2}_[0-9]{2}")) | select((.published_at | strptime("%Y-%m-%dT%H:%M:%SZ") | mktime) >= ($cutoff | strptime("%Y-%m-%d") | mktime)) | .tag_name' |\
       grep -i "METADATA-[0-9]\{4\}_[0-9]\{2\}_[0-9]\{2\}" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | sort -u)
     break
   fi
 done
 if [[ -n "${META_TAGS[*]}" && "${#META_TAGS[@]}" -ge 1 ]]; then
   echo -e "\n[+] Total Tags: ${#META_TAGS[@]}"
   echo -e "[+] Tags: ${META_TAGS[*]}"
 else
   echo -e "\n[X] FATAL: Failed to Fetch needed Tags\n"
   echo -e "[+] Tags: ${META_TAGS[*]}"
  exit 1
  fi
#Download Assets
 unset REL_TAG
  for REL_TAG in "${META_TAGS[@]}"; do
   REL_DATE="$(echo "${REL_TAG}" | grep -o '[0-9]\{4\}_[0-9]\{2\}_[0-9]\{2\}' | tr -d '[:space:]')"
   echo -e "[+] Fetching ${REL_TAG} ==> ${TMPDIR}/assets/${REL_DATE}"
   gh release download --repo "${META_REPO}" "${REL_TAG}" --dir "${TMPDIR}/assets/${REL_DATE}" --clobber
   find "${TMPDIR}/assets" -type f -size -3c -delete
   gh release download --repo "${META_REPO}" "${REL_TAG}" --dir "${TMPDIR}/assets/${REL_DATE}" --skip-existing
   find "${TMPDIR}/assets" -type f -size -3c -delete
   gh release download --repo "${META_REPO}" "${REL_TAG}" --dir "${TMPDIR}/assets/${REL_DATE}" --skip-existing
   realpath "${TMPDIR}/assets/${REL_DATE}" && du -sh "${TMPDIR}/assets/${REL_DATE}"
  done
#Rename Assets
 find "${TMPDIR}/assets/" -mindepth 1 -type f -exec bash -c \
  '
   for file; do
    dir=$(dirname "$file")
    base=$(basename "$dir")
    mv -fv "$file" "${file%.*}_${base}.${file##*.}"
   done
  ' _ {} +
#Copy Valid Assets
 find "${TMPDIR}/assets/" -type f -iregex '.*\.json$' -exec bash -c 'jq empty "{}" 2>/dev/null && cp -f "{}" ${TMPDIR}/src/' \;
#Copy Newer Assets 
 find "${TMPDIR}/src" -type f -iregex '.*\.json$' | sort -u | awk -F'[_-]' '{base=""; for(i=1;i<=NF-1;i++) base=base (i>1?"_":"") $i; date=$(NF); file[base]=(file[base]==""||date>file[base])?date:file[base]; path[base,date]=$0} END {for(b in file) print path[b,file[b]]}' | xargs -I "{}" cp -fv "{}" "${TMPDIR}/data"
#-------------------------------------------------------#

#-------------------------------------------------------#
##Merge
 HOST_TRIPLETS=("aarch64-Linux" "loongarch64-Linux" "riscv64-Linux" "x86_64-Linux")
 for HOST_TRIPLET in "${HOST_TRIPLETS[@]}"; do
    echo -e "\n[+] Processing ${HOST_TRIPLET}..."
    #Gen Raw
     find "${TMPDIR}/data" -type f -iregex ".*-${HOST_TRIPLET}.*\.json$" -exec \
      bash -c 'jq empty "{}" 2>/dev/null && cat "{}"' \; | \
         jq --arg host "${HOST_TRIPLET}" 'select(.host | ascii_downcase == ($host | ascii_downcase))' | \
         jq -s 'sort_by(.pkg) | unique_by(.ghcr_pkg)' > "${TMPDIR}/${HOST_TRIPLET}.json.tmp"
    #Fixup
     sed -E 's~\bhttps?:/{1,2}\b~https://~g' -i "${TMPDIR}/${HOST_TRIPLET}.json.tmp"
    #Calc Rank & Merge
     jq \
      '
       sort_by([
         -(if .downloads then (.downloads | tonumber) else -1 end),
         .name
       ]) |
       to_entries |
       map(.value + { rank: (.key + 1 | tostring) })
      ' "${TMPDIR}/${HOST_TRIPLET}.json.tmp" | jq '.[] | .download_count |= tostring' | jq \
      'walk(if type == "boolean" or type == "number" then tostring else . end)' | jq -s \
      'if type == "array" then . else [.] end' | jq 'map(to_entries | sort_by(.key) | from_entries)
       ' | jq \
       '
         map(select(
        .pkg != null and .pkg != "" and
        .pkg_id != null and .pkg_id != "" and
        .pkg_name != null and .pkg_name != "" and
        .description != null and .description != "" and
        .ghcr_pkg != null and .ghcr_pkg != "" and
        .version != null and .version != ""
        ))
       ' | jq 'unique_by(.ghcr_pkg) | sort_by(.pkg)' > "${TMPDIR}/${HOST_TRIPLET}.json"
    #Sanity Check
     PKG_COUNT="$(jq -r '.[] | .pkg_id' "${TMPDIR}/${HOST_TRIPLET}.json" | grep -iv 'null' | wc -l | tr -d '[:space:]')"
     if [[ "${PKG_COUNT}" -le 5 ]]; then
        echo -e "\n[-] FATAL: Failed to Generate AM MetaData\n"
        echo "[-] Count: ${PKG_COUNT}"
        continue
     else
        echo -e "\n[+] Packages: ${PKG_COUNT}"
        cp -fv "${TMPDIR}/${HOST_TRIPLET}.json" "${SYSTMP}/${HOST_TRIPLET}.json"
     fi
 done
#-------------------------------------------------------#