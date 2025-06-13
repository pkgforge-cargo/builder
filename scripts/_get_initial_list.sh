#!/usr/bin/env bash

#Barebones, will not be improved, meant for one time usage
#slow on purpose to avoid rate limits, 100,000 packages take ~ 5 hrs to process.

#-------------------------------------------------------#
#Get inside a TEMP Dir
pushd "$(mktemp -d)" &>/dev/null
export TEMP_DIR="$(realpath .)"
echo -e "\n[+] Using dir: ${TEMP_DIR}\n"
#Get Most Downloaded (Of All Time)
 echo -e "\n[+] Scraping Crates (most-downloads)\n"
 for i in {1..1000}; do
   echo -e "[+] Page = ${i}/1000"
   T_FILE="${TEMP_DIR}/${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
   (
     for retry in {1..3}; do
       if response=$(curl --retry 2 -qfsSL "https://crates.io/api/v1/crates?sort=downloads&per_page=100&page=${i}") && 
        [[ -n "$response" ]] && 
        echo "$response" | jq -e '.crates[]' &>/dev/null; then
         echo "$response" | jq '
             .crates[] | 
             def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
             {
                 pkg: .name?,
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
   if (( i % 10 == 0 )); then
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
       if response=$(curl --retry 2 -qfsSL "https://crates.io/api/v1/crates?sort=recent-downloads&per_page=100&page=${i}") && 
        [[ -n "$response" ]] && 
        echo "$response" | jq -e '.crates[]' &>/dev/null; then
         echo "$response" | jq '
             .crates[] | 
             def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
             {
                 pkg: .name?,
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
   if (( i % 10 == 0 )); then
       wait &>/dev/null
       sleep "$(shuf -i 500-1500 -n 1)e-3"
   fi
 done
 wait &>/dev/null
#Merge
 echo -e "\n[+] Merging JSON ...\n"
 find "${TEMP_DIR}" -type f -size -3c -delete
 find "${TEMP_DIR}" -type f -iname "*.json" -exec cat "{}" + > "${TEMP_DIR}/RAW.json.tmp"
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "${TEMP_DIR}/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "${TEMP_DIR}/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("pkg"))] 
       | unique_by(.pkg | ascii_downcase) 
       | sort_by(.pkg | ascii_downcase)' "${TEMP_DIR}/RAW.json.raw" > "${TEMP_DIR}/RAW.json"
#Process
 echo -e "\n[+] Processing Crates [$(jq -r '.[] | .pkg' '/tmp/crates/RAW.json' | wc -l)] ...\n"
 rm -rf "/tmp/crates" 2>/dev/null
 mkdir -p "/tmp/crates"
 process_crate() {
     local pkg="$1"
     local retries=0
     local max_retries=2
     local has_bins="false"
     
     while [ $retries -le $max_retries ]; do
         if api_response=$(curl -qfsSL "https://crates.io/api/v1/crates/${pkg}" 2>/dev/null); then
             has_bins=$(echo "$api_response" | jq -r 'any(.. | objects | select(has("bin_names")) | .bin_names | length > 0)')
             break
         fi
         ((retries++))
         [ $retries -le $max_retries ] && sleep 1
     done
     #Add has_bins field
     jq --arg pkg "$pkg" --arg has_bins "$has_bins" \
         '.[] | select(.pkg == $pkg) | . + {has_bins: ($has_bins == "true")}' \
         RAW.json > "/tmp/crates/${pkg}.json"
     
     echo "Processed: $pkg (has_bins: $has_bins)"
 }
 export -f process_crate
 #too many will ratelimit us
 jq -r '.[] | .pkg' "${TEMP_DIR}/RAW.json" | xargs -P 5 -I {} bash -c 'process_crate "{}"'
#Merge Again
 find "/tmp/crates" -type f -size -3c -delete
 find "/tmp/crates" -type f -iname "*.json" -exec cat "{}" + > "/tmp/crates/RAW.json.tmp"
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "/tmp/crates/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "/tmp/crates/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("pkg"))] | unique_by(.pkg | ascii_downcase) | sort_by(.pkg | ascii_downcase) | walk(if type == "object" then with_entries(select(.value != null and .value != "" and .value != "null")) elif type == "boolean" or type == "number" then tostring else . end) | map(to_entries | sort_by(.key) | from_entries)' "/tmp/crates/RAW.json.raw" |\
 jq '
  sort_by([
    -(if .downloads then (.downloads | tonumber) else -1 end),
    .pkg
  ]) |
  to_entries |
  map(.value + { rank: (.key + 1 | tostring) })
' > "/tmp/crates/CRATES_DUMP.json"
#Compute Ranks & Finalize
  jq 'map(select(.has_bins == "true"))' "/tmp/crates/CRATES_DUMP.json" |\
  jq 'walk(if type == "boolean" or type == "number" then tostring else . end)' |\
  jq 'map(select(
     .pkg != null and .pkg != "" and
     .has_bins != null and .has_bins != "" and
     .version != null and .version != ""
  ))' | jq 'unique_by(.pkg) | sort_by(.rank | tonumber) | [range(length)] as $indices | [., $indices] | transpose | map(.[0] + {rank: (.[1] + 1 | tostring)})' > "/tmp/crates/CRATES_BIN_ONLY.json"
#Print stats
 du -bh "/tmp/crates/CRATES_DUMP.json"
 du -bh "/tmp/crates/CRATES_BIN_ONLY.json"
 echo -e "\n[+] Total Packages: $(jq -r '.[] | .pkg' '/tmp/crates/CRATES_DUMP.json' | wc -l)"
 echo -e "[+] Binary Packages: $(jq -r '.[] | .pkg' '/tmp/crates/CRATES_BIN_ONLY.json' | wc -l)\n"
#Cleanup
popd &>/dev/null
#-------------------------------------------------------#