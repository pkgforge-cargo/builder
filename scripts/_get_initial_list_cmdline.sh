#!/usr/bin/env bash

#Barebones, will not be improved, meant for one time usage
#slow on purpose to avoid rate limits, 10,000 packages take ~ 30 mins to process.

#-------------------------------------------------------#
#Get inside a TEMP Dir
pushd "$(mktemp -d)" &>/dev/null
export TEMP_DIR="$(realpath .)"
export OUT_DIR="/tmp/crates"
export RV_API="https://api.rv.pkgforge.dev"
rm -rf "${OUT_DIR}" 2>/dev/null ; mkdir -p "${OUT_DIR}/TEMP"
echo -e "\n[+] Using TEMP dir: ${TEMP_DIR}"
echo -e "[+] Using OUT dir: ${OUT_DIR}\n"
#Get Most Downloaded (Of All Time)
 echo -e "\n[+] Scraping Crates (most-downloads)\n"
 for i in {1..1000}; do
   echo -e "[+] Page = ${i}/1000"
   T_FILE="${TEMP_DIR}/${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
   (
     for retry in {1..3}; do
       if response=$(curl --retry 2 -qfsSL "${RV_API}/https://crates.io/api/v1/crates?category=command-line-utilities&sort=downloads&per_page=100&page=${i}") &&
        [[ -n "$response" ]] && 
        echo "$response" | jq -e '.crates[]' &>/dev/null; then
         echo "$response" | jq '
             .crates[] | 
             def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
             {
                 name: .name?,
                 description: .description?,
                 version: (.newest_version? // .max_version? // .version?),
                 homepage: (.repository? // .homepage? // .documentation?),
                 downloads: (.recent_downloads? // .downloads?),
                 updated_at: .updated_at?
             } | clean_strings
         ' > "${T_FILE}" && break
       fi
       [[ $retry -lt 3 ]] && sleep 1
     done
   ) &>/dev/null &
   if (( i % 20 == 0 )); then
       wait &>/dev/null
       sleep "$(shuf -i 500-1500 -n 1)e-3"
   fi
 done
 wait &>/dev/null
#Get Most Downloaded (Recently)
 echo -e "\n[+] Scraping Crates (recent-downloads)\n"
 for i in {1..1000}; do
   echo -e "[+] Page = ${i}/1000"
   T_FILE="${TEMP_DIR}/${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
   (
     for retry in {1..3}; do
       if response=$(curl --retry 2 -qfsSL "${RV_API}/https://crates.io/api/v1/crates?category=command-line-utilities&sort=recent-downloads&per_page=100&page=${i}") &&
        [[ -n "$response" ]] && 
        echo "$response" | jq -e '.crates[]' &>/dev/null; then
         echo "$response" | jq '
             .crates[] | 
             def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
             {
                 name: .name?,
                 description: .description?,
                 version: (.newest_version? // .max_version? // .version?),
                 homepage: (.repository? // .homepage? // .documentation?),
                 downloads: (.recent_downloads? // .downloads?),
                 updated_at: .updated_at?
             } | clean_strings
         ' > "${T_FILE}" && break
       fi
       [[ $retry -lt 3 ]] && sleep 1
     done
   ) &>/dev/null &
   if (( i % 20 == 0 )); then
       wait &>/dev/null
       sleep "$(shuf -i 500-1500 -n 1)e-3"
   fi
 done
 wait &>/dev/null
#Get New Crates
 echo -e "\n[+] Scraping Crates (new)\n"
 for i in {1..1000}; do
   echo -e "[+] Page = ${i}/1000"
   T_FILE="${TEMP_DIR}/${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
   (
     for retry in {1..3}; do
       if response=$(curl --retry 2 -qfsSL "${RV_API}/https://crates.io/api/v1/crates?category=command-line-utilities&sort=new&per_page=100&page=${i}") &&
        [[ -n "$response" ]] && 
        echo "$response" | jq -e '.crates[]' &>/dev/null; then
         echo "$response" | jq '
             .crates[] | 
             def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
             {
                 name: .name?,
                 description: .description?,
                 version: (.newest_version? // .max_version? // .version?),
                 homepage: (.repository? // .homepage? // .documentation?),
                 downloads: (.recent_downloads? // .downloads?),
                 updated_at: .updated_at?
             } | clean_strings
         ' > "${T_FILE}" && break
       fi
       [[ $retry -lt 3 ]] && sleep 1
     done
   ) &>/dev/null &
   if (( i % 20 == 0 )); then
       wait &>/dev/null
       sleep "$(shuf -i 500-1500 -n 1)e-3"
   fi
 done
 wait &>/dev/null
#Merge
 echo -e "\n[+] Merging JSON ...\n"
 CUTOFF_DATE="$(date -d 'last year' '+%Y-01-01' | tr -d '[:space:]')"
 find "${TEMP_DIR}" -type f -size -3c -delete
 find "${TEMP_DIR}" -type f -iname "*.json" -exec cat "{}" + > "${TEMP_DIR}/RAW.json.tmp"
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "${TEMP_DIR}/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "${TEMP_DIR}/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("name"))] 
       | unique_by(.name | ascii_downcase) 
       | sort_by(.name | ascii_downcase)' "${TEMP_DIR}/RAW.json.raw" |\
 jq --arg cutoff_date "${CUTOFF_DATE}" '[.[] | select((.updated_at | split("T")[0] | strptime("%Y-%m-%d") | mktime) >= ($cutoff_date | strptime("%Y-%m-%d") | mktime))]' > "${OUT_DIR}/RAW.json"
#Process
 echo -e "\n[+] Processing Crates [$(jq -r '.[] | .name' "${OUT_DIR}/RAW.json" | wc -l)] ...\n"
 process_crate() {
     local pkg="$1"
     local retries=0
     local max_retries=2
     local has_bins="false"
     local bin_names=""
     local version=""
     
     while [ $retries -le $max_retries ]; do
         if api_response=$(curl -qfsSL "https://crates.io/api/v1/crates/${pkg}" 2>/dev/null); then
             has_bins="$(echo "$api_response" | jq -r 'any(.. | objects | select(has("bin_names")) | .bin_names | select(. != null and . != [] and . != "" and . != "null") | map(select(. != null and . != "" and . != "null")) | length > 0)')"
             bin_names="$(echo "$api_response" | jq -r \
              '
                [.. | objects | select(has("bin_names")) | .bin_names | 
                 if type == "array" then .[] else . end] | 
                map(select(. != null and . != "" and type == "string")) | 
                unique | sort | join(",")
              ' | sed 's/^,\+//; s/,\+$//; s/,\+/,/g; s/,/, /g')"
             #bin_names="$(echo "$api_response" | jq -r '.. | objects | select(has("bin_names")) | .bin_names' | \
             #  jq -r 'if type == "array" then .[] else . end' | tr -d '[]' |\
             #  sort -u | grep -v '^null$' | grep -v '^$' | sort -u | paste -sd, - |\
             #  tr -d '[:space:]' | sed 's/^,\+//; s/,\+$//; s/,\+/,/g; s/,/, /g')"
             version="$(echo "$api_response" | jq -r '.. | objects | (.newest_version // .max_version // .version) | select(. != null) | tostring' | grep -iv 'null' | head -1)"
             break
         fi
         ((retries++))
         [ $retries -le $max_retries ] && sleep 1
     done
     
     #Add new fields
     jq --arg pkg "$pkg" --arg has_bins "$has_bins" --arg bin_names "$bin_names" --arg version "$version" \
       '.[] | select(.name == $pkg) | . + {has_bins: ($has_bins == "true"), version: $version, bin_names: ($bin_names | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | unique | sort)}' \
       "${OUT_DIR}/RAW.json" > "${OUT_DIR}/TEMP/${pkg}.json"
     
     echo "Processed: $pkg (has_bins: $has_bins) (bin_names: $bin_names) (version: $version) [${OUT_DIR}/TEMP/${pkg}.json]"
 }
 export -f process_crate
 #too many will ratelimit us
 jq -r '.[] | .name' "${OUT_DIR}/RAW.json" | xargs -P "${PARALLEL_LIMIT:-$(($(nproc)+1))}" -I "{}" timeout -k 10s 300s bash -c 'process_crate "{}"'
#Merge Again
 find "${OUT_DIR}/TEMP" -type f -size -3c -delete
 find "${OUT_DIR}/TEMP" -type f -iname "*.json" -exec cat "{}" + > "${OUT_DIR}/RAW.json.tmp"
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
 echo -e "\n[+] Total Packages: $(jq -r '.[] | .name' "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" | wc -l)"
 echo -e "[+] Binary Packages: $(jq -r '.[] | .name' "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" | wc -l)"
 echo -e "[+] Used TEMP dir: ${TEMP_DIR}"
 echo -e "[+] Used OUT dir: ${OUT_DIR}\n"
#Cleanup
popd &>/dev/null
#Copy
PKG_COUNT="$(jq -r '.[] | .name' "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" | grep -iv 'null' | sort -u | wc -l | tr -d '[:space:]')"
if [[ "${PKG_COUNT}" -ge 1000 ]]; then
  if [[ ! -d "${SYSTMP}" ]]; then
    SYSTMP="$(dirname $(mktemp -u))"
  fi
  cp -fv "${OUT_DIR}/CRATES_CMDLINE_ONLY.json" "${SYSTMP}/CRATES_CMDLINE_ONLY.json"
fi
#-------------------------------------------------------#