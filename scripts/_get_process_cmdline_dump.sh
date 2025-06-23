#!/usr/bin/env bash

#-------------------------------------------------------#
#Get inside a TEMP Dir
pushd "$(mktemp -d)" &>/dev/null
export TEMP_DIR="$(realpath .)"
export OUT_DIR="/tmp/crates"
rm -rf "${OUT_DIR}" 2>/dev/null ; mkdir -p "${OUT_DIR}/TEMP"
echo -e "\n[+] Using TEMP dir: ${TEMP_DIR}"
echo -e "[+] Using OUT dir: ${OUT_DIR}\n"
if [[ ! -d "${SYSTMP}" ]]; then
  SYSTMP="$(dirname $(mktemp -u))"
fi
export SYSTMP
##Cmd
sudo curl -qfsSL "https://bin.pkgforge.dev/$(uname -m)-$(uname -s)/crates-dumper" -o "/usr/local/bin/crates-dumper"
sudo chmod 'a+x' "/usr/local/bin/crates-dumper" ; hash -r &>/dev/null
if ! command -v crates-dumper &> /dev/null; then
   echo -e "\n[-] crates-dumper NOT Found"
  exit 1
fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Generate Dump: https://rust-lang.github.io/rfcs/3463-crates-io-policy-update.html#data-access
 #https://static.crates.io/db-dump.tar.gz
 crates-dumper --verbose download --dump-file "${TEMP_DIR}/db-dump.tar.gz" --output "${TEMP_DIR}/CRATES_RAW.json"
 echo -e "\n[+] Processing RAW Crates\n"
##Process 
 jq \
 '
    .[] | 
    select(.yanked == false and ((.categories[]? == "command-line-utilities") or .has_bins == true)) |
    def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
    {
        bin_names: .bin_names? // [],
        description: (.description? | tostring),
        downloads: (.total_downloads? | tostring),
        has_bins: (.has_bins? | tostring),
        homepage: ((.repository? // .homepage? // .documentation?) | tostring),
        name: (.name? | tostring),
        updated_at: (.updated_at? | tostring),
        version: (.version? | tostring)
    } | clean_strings
 ' "${TEMP_DIR}/CRATES_RAW.json" > "${OUT_DIR}/RAW.json.tmp"
##Merge Again
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "${OUT_DIR}/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "${OUT_DIR}/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("name"))] | unique_by(.name | ascii_downcase) | sort_by(.name | ascii_downcase) | walk(if type == "object" then with_entries(select(.value != null and .value != "" and .value != "null")) elif type == "boolean" or type == "number" then tostring else . end) | map(to_entries | sort_by(.key) | from_entries)' \
 "${OUT_DIR}/RAW.json.raw" | jq \
 '
  sort_by([
    -(if .downloads then (.downloads | tonumber) else -1 end),
    .name
  ]) |
  to_entries |
  map(.value + { rank: (.key + 1 | tostring) })
 ' > "${OUT_DIR}/CRATES_CMDLINE_ONLY.json.tmp"
#Compute Ranks & Finalize
 cat "${OUT_DIR}/CRATES_CMDLINE_ONLY.json.tmp" |\
 jq 'walk(if type == "boolean" or type == "number" then tostring else . end)' |\
 jq 'map(select(
    .name != null and .name != "" and
    .has_bins != null and .has_bins != "" and
    .version != null and .version != ""
 ))' | jq 'unique_by(.name) | sort_by(.rank | tonumber) | [range(length)] as $indices | [., $indices] | transpose | map(.[0] + {rank: (.[1] + 1 | tostring)})' > "${OUT_DIR}/CRATES_CMDLINE_ONLY.json"
#Print stats
 du -bh "${OUT_DIR}/CRATES_CMDLINE_ONLY.json.tmp"
 du -bh "${OUT_DIR}/CRATES_CMDLINE_ONLY.json"
 echo -e "\n[+] Total Packages: $(jq -r '.[] | .name' "${TEMP_DIR}/CRATES_RAW.json" | wc -l)"
 echo -e "[+] Binary Packages: $(jq -r '.[] | .name' "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" | wc -l)"
 echo -e "[+] Used TEMP dir: ${TEMP_DIR}"
 echo -e "[+] Used OUT dir: ${OUT_DIR}\n"
#Cleanup
popd &>/dev/null
#Copy
PKG_COUNT="$(jq -r '.[] | .name' "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" | grep -Eiv '^null$' | sort -u | wc -l | tr -d '[:space:]')"
if [[ "${PKG_COUNT}" -ge 1000 ]]; then
  cp -fv "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" "${SYSTMP}/CRATES_CMDLINE_ONLY.json"
  #Filter
  unset PKG_COUNT 
  echo "[+] Filtering Crates..."
  CUTOFF_DATE="$(date -d 'last year' '+%Y-01-01' | tr -d '[:space:]')"
  jq --arg cutoff_date "${CUTOFF_DATE}" '[.[] | select((.updated_at | split("T")[0] | strptime("%Y-%m-%d") | mktime) > ($cutoff_date | strptime("%Y-%m-%d") | mktime))]' "${SYSTMP}/CRATES_CMDLINE_ONLY.json" | jq . > "${OUT_DIR}/CRATES_PROCESSED.json"
  PKG_COUNT="$(jq -r '.[] | .name' "${OUT_DIR}/CRATES_PROCESSED.json" | grep -Eiv '^null$' | sort -u | wc -l | tr -d '[:space:]')"
  if [[ "${PKG_COUNT}" -ge 1000 ]]; then
     cp -fv "${OUT_DIR}/CRATES_PROCESSED.json" "${SYSTMP}/CRATES_PROCESSED.json"
  fi
fi
#-------------------------------------------------------#
