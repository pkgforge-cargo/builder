#!/usr/bin/env bash

#Barebones, will not be improved, meant for one time usage
#slow on purpose to avoid rate limits, 10,000 packages take ~ 2 hrs to process.

#-------------------------------------------------------#
#Setup ENV
pushd "$(mktemp -d)" &>/dev/null
 OUT_DIR="$(realpath "${OUT_DIR:-./output}")"
 TEMP_DIR="${OUT_DIR}/TEMP_BINS"
 WORK_DIR="${OUT_DIR}/WORK"
 PROGRESS_DIR="${OUT_DIR}/PROGRESS"
 mkdir -p "${OUT_DIR}" "${TEMP_DIR}" "${WORK_DIR}" "${PROGRESS_DIR}"
 echo -e "\n[+] Using TEMP dir: ${TEMP_DIR}"
 echo -e "[+] Using OUT dir: ${OUT_DIR}\n"
#Get Data
 echo "[+] Downloading crates data..."
 curl -qfsSL "https://github.com/pkgforge-cargo/builder/raw/refs/heads/main/data/CRATES_BIN_ONLY.json" -o "${OUT_DIR}/CRATES_INPUT.json" || { echo "Failed to download JSON"; exit 1; }
#Create Input
 echo "[+] Preparing crate files..."
 jq -r '.[] | "\(.name)|\(.version)|\(. | tostring | @base64)"' "${OUT_DIR}/CRATES_INPUT.json" > "${WORK_DIR}/crates_to_process.txt"
#Get total count
 TOTAL_CRATES=$(wc -l < "${WORK_DIR}/crates_to_process.txt")
 echo "0" > "${PROGRESS_DIR}/counter"
#Processor func
 process_crate_binary()
 {
   #Var
    local input_line="$1"
    local crate_name="$(echo "$input_line" | cut -d'|' -f1)"
    local crate_version="$(echo "$input_line" | cut -d'|' -f2)"
    local crate_data="$(echo "$input_line" | cut -d'|' -f3-)"
    local retries=0
    local max_retries=4
    
   #Track Progress
    local current_num
    (
        flock -x 200
        current_num=$(cat "${PROGRESS_DIR}/counter")
        current_num=$((current_num + 1))
        echo "$current_num" > "${PROGRESS_DIR}/counter"
    ) 200>"${PROGRESS_DIR}/counter.lock"
    current_num=$(cat "${PROGRESS_DIR}/counter")
   
   #Process  
    echo -e "Processing: $crate_name [$current_num/$TOTAL_CRATES]"
     
   #Download/Extract
    while [ $retries -le $max_retries ]; do
     #Env
      local work_dir="$(mktemp -d)"
      pushd "$work_dir" &>/dev/null || continue
     #Fetch 
      if curl -qfsSL "https://crates.io/api/v1/crates/${crate_name}/${crate_version}/download" -o "./crate" 2>/dev/null; then
       #Extract
         if tar -xzf "./crate" --strip-components=1 2>/dev/null; then
             #Check
             if [[ -f "Cargo.toml" ]]; then
                 #Filter
                 if cargo metadata --format-version 1 --no-deps 2>/dev/null | grep -m 1 -qoiE '"kind"[[:space:]]*:[[:space:]]*\[[^]]*"bin"[^]]*\]'; then
                    #Save
                     echo "$crate_data" | base64 -d > "${TEMP_DIR}/${crate_name}.json"
                     echo "✓ Binary crate: $crate_name ==> ${TEMP_DIR}/${crate_name}.json [$current_num/$TOTAL_CRATES]"
                     popd &>/dev/null
                     rm -rf "$work_dir"
                     return 0
                 else
                    #Skip
                     #echo "⚬ Library crate (skipped): $crate_name [$current_num/$TOTAL_CRATES]"
                     popd &>/dev/null
                     rm -rf "$work_dir"
                     return 0
                 fi
             else
                 echo "✗ No Cargo.toml found: $crate_name [$current_num/$TOTAL_CRATES]"
             fi
         else
             echo "✗ Failed to extract: $crate_name [$current_num/$TOTAL_CRATES]"
         fi
      else
          echo "✗ Download failed: $crate_name (attempt $((retries + 1))) [$current_num/$TOTAL_CRATES]"
      fi
     #Cleanup 
      popd &>/dev/null
      rm -rf "$work_dir"
      ((retries++))
      [[ $retries -le $max_retries ]] && sleep "$(shuf -i 500-1500 -n 1)e-3"
    done

   #Fail if exceeded  
     echo "✗ Failed after $max_retries retries: $crate_name [$current_num/$TOTAL_CRATES]"
     return 1
 }
 export -f process_crate_binary
 export OUT_DIR TEMP_DIR WORK_DIR PROGRESS_DIR TOTAL_CRATES
#Process
 echo -e "\n[+] Processing Crates [$TOTAL_CRATES] ...\n"
 find "${TEMP_DIR}" -type f -exec rm -rf "{}" \;
 cat "${WORK_DIR}/crates_to_process.txt" | xargs -P "${PARALLEL_LIMIT:-$(($(nproc)+1))}" -I {} bash -c 'process_crate_binary "{}"'
#Merge
 echo -e "\n[+] Merging JSON ...\n"
 find "${TEMP_DIR}" -type f -size -3c -delete
 find "${TEMP_DIR}" -type f -iname "*.json" -exec cat "{}" + | jq . > "${TEMP_DIR}/RAW.json.tmp"
 awk '/^\s*{\s*$/{flag=1; buffer="{\n"; next} /^\s*}\s*$/{if(flag){buffer=buffer"}\n"; print buffer}; flag=0; next} flag{buffer=buffer$0"\n"}' "${TEMP_DIR}/RAW.json.tmp" | jq -c '. as $line | (fromjson? | .message) // $line' >> "${TEMP_DIR}/RAW.json.raw"
#Compute Ranks & Finalize
 jq -s '[.[] | select(type == "object" and has("name"))] 
       | unique_by(.name | ascii_downcase) 
       | sort_by(.name | ascii_downcase)' "${TEMP_DIR}/RAW.json.raw" | jq \
 '
  sort_by([
    -(if .downloads then (.downloads | tonumber) else -1 end),
    .name
  ]) |
  to_entries |
  map(.value + { rank: (.key + 1 | tostring) })
 ' > "${OUT_DIR}/RAW.json"
 jq 'map(select(.has_bins == "true"))' "${OUT_DIR}/RAW.json" |\
 jq 'walk(if type == "boolean" or type == "number" then tostring else . end)' |\
 jq 'map(select(
    .name != null and .name != "" and
    .has_bins != null and .has_bins != "" and
    .version != null and .version != ""
 ))' | jq 'unique_by(.name) | sort_by(.rank | tonumber) | [range(length)] as $indices | [., $indices] | transpose | map(.[0] + {rank: (.[1] + 1 | tostring)})' > "${OUT_DIR}/CRATES_PROCESSED.json"
#Print stats
 du -bh "${OUT_DIR}/CRATES_PROCESSED.json"
 echo -e "\n[+] Total Packages: $(jq -r '.[] | .name' "${OUT_DIR}/CRATES_INPUT.json" | wc -l)"
 echo -e "[+] Binary Packages: $(jq -r '.[] | .name' "${OUT_DIR}/CRATES_PROCESSED.json" | wc -l)"
 echo -e "[+] Used TEMP dir: ${TEMP_DIR}"
 echo -e "[+] Used OUT dir: ${OUT_DIR}\n"
#Cleanup
 rm -rf "${TEMP_DIR}" "${WORK_DIR}" "${PROGRESS_DIR}"
popd &>/dev/null
#-------------------------------------------------------#