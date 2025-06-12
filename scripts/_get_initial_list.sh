#!/usr/bin/env bash

#Barebones, will not be improved, meant for one time usage
#slow on purpose to avoid rate limits, 100,000 packages take ~ 5 hrs to process.

#-------------------------------------------------------#
#Get inside a TEMP Dir
pushd "$(mktemp -d)" &>/dev/null
export TEMP_DIR=" $(realpath .)"
echo -e "\n[+] Using dir: ${TEMP_DIR}\n"
#Get Most Downloaded (Of All Time)
 for i in {1..1000}; do
     echo -e "[+] Page = ${i}/1000"
     T_FILE="${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
     curl -qfsSL "https://crates.io/api/v1/crates?sort=downloads&per_page=100&page=${i}" | jq '
         .crates[] | 
         def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
         {
             pkg: .name?,
             description: .description?,
             version: (.newest_version? // .max_version? // .version?),
             homepage: (.repository? // .homepage? // .documentation?)
         } | clean_strings
     ' > "${T_FILE}"
     sleep "$(shuf -i 50-700 -n 1)e-3"
 done
#Get Most Downloaded (Recently)
 for i in {1..1000}; do
     echo -e "[+] Page = ${i}/1000"
     T_FILE="${i}-$(date --utc "+%y%m%dT%H%M%S$(date +%3N)").json"
     curl -qfsSL "https://crates.io/api/v1/crates?sort=recent-downloads&per_page=100&page=${i}" | jq '
         .crates[] | 
         def clean_strings: walk(if type == "string" then gsub("\\n|\\r|\\t"; " ") | gsub("\\s+"; " ") | gsub("^\\s+|\\s+$"; "") else . end);
         {
             pkg: .name?,
             description: .description?,
             version: (.newest_version? // .max_version? // .version?),
             homepage: (.repository? // .homepage? // .documentation?)
         } | clean_strings
     ' > "${T_FILE}"
     sleep "$(shuf -i 50-700 -n 1)e-3"
 done
#Merge
 find "." -type f -iname "*.json" -exec cat "{}" + > "${TEMP_DIR}/RAW.json.tmp"
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "${TEMP_DIR}/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "${TEMP_DIR}/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("pkg"))] 
       | unique_by(.pkg | ascii_downcase) 
       | sort_by(.pkg | ascii_downcase)' "${TEMP_DIR}/RAW.json.raw" > "${TEMP_DIR}/RAW.json"
#Process
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
#More than 5 will ratelimit us
jq -r '.[] | .pkg' "${TEMP_DIR}/RAW.json" | xargs -P 5 -I {} bash -c 'process_crate "{}"'
#Merge Again
find "/tmp/crates" -type f -iname "*.json" -exec cat "{}" + > "/tmp/crates/RAW.json.tmp"
awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "/tmp/crates/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "/tmp/crates/RAW.json.raw"
 jq -s '[.[] | select(type == "object" and has("pkg"))] 
       | unique_by(.pkg | ascii_downcase) 
       | sort_by(.pkg | ascii_downcase)' "/tmp/crates/RAW.json.raw" > "/tmp/crates/RAW.json"
du -sh "/tmp/crates/RAW.json"       
echo -e "\n[+] Total Packages: $(jq -r '.[] | .pkg' '/tmp/crates/RAW.json' | wc -l)"
echo -e "[+] Binary Packages: $(jq -r '.[] | select(.has_bins == true) | .pkg' '/tmp/crates/RAW.json' | wc -l)\n"
popd &>/dev/null
#-------------------------------------------------------#