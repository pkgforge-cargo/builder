#!/usr/bin/env bash
## <DO NOT RUN STANDALONE, meant for CI Only>
## Meant to Build Cargo Packages using Cross
## Self: https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/scripts/builder.sh
# bash <(curl -qfsSL "https://raw.githubusercontent.com/pkgforge-cargo/builder/refs/heads/main/scripts/builder.sh")
#-------------------------------------------------------#

#-------------------------------------------------------#
##Version
CB_VERSION="0.0.1" && echo -e "[+] Cargo Builder Version: ${CB_VERSION}" ; unset CB_VERSION
##Enable Debug 
 if [[ "${DEBUG}" = "1" ]] || [[ "${DEBUG}" = "ON" ]]; then
    set -x
 fi
#-------------------------------------------------------#

#-------------------------------------------------------#
##Sanity
 build_fail_gh()
 {
  echo "GHA_BUILD_FAILED=YES" >> "${GITHUB_ENV}"
  echo "BUILD_SUCCESSFUL=NO" >> "${GITHUB_ENV}"
 }
 export -f build_fail_gh
#User 
 if [[ -z "${USER+x}" ]] || [[ -z "${USER##*[[:space:]]}" ]]; then
  USER="$(whoami | tr -d '[:space:]')"
 fi
#Home 
 if [[ -z "${HOME+x}" ]] || [[ -z "${HOME##*[[:space:]]}" ]]; then
  HOME="$(getent passwd "${USER}" | awk -F':' 'NF >= 6 {print $6}' | tr -d '[:space:]')"
 fi
#Tz
 export TZ="UTC"
#GH
 if [[ "${GHA_MODE}" != "MATRIX" ]]; then
   echo -e "[-] FATAL: This Script only Works on Github Actions\n"
   build_fail_gh
  exit 1
 fi
#Input
 if [[ -z "${CRATE_NAME+x}" ]]; then
   echo -e "[-] FATAL: Package Name '\${CRATE_NAME}' is NOT Set\n"
   build_fail_gh
  exit 1
 else
   export CRATE_NAME="${CRATE_NAME}"
 fi
#Target
 if [[ -z "${RUST_TARGET+x}" ]]; then
   echo -e "[-] FATAL: Build Target '\${RUST_TARGET}' is NOT Set\n"
   build_fail_gh
  exit 1
 else
   export RUST_TARGET="${RUST_TARGET}"
 fi
#Host
 if [[ -z "${HOST_TRIPLET+x}" ]]; then
  #HOST_TRIPLET="$(uname -m)-$(uname -s)"
  if echo "${RUST_TARGET}" | grep -qiE "aarch64"; then
   HOST_TRIPLET="aarch64-Linux"
  elif echo "${RUST_TARGET}" | grep -qiE "riscv64"; then
   HOST_TRIPLET="riscv64-Linux"
  elif echo "${RUST_TARGET}" | grep -qiE "x86_64"; then
   HOST_TRIPLET="x86_64-Linux"
  fi
 fi
  HOST_TRIPLET_L="${HOST_TRIPLET,,}"
  export HOST_TRIPLET HOST_TRIPLET_L
#Repo
 export PKG_REPO="builder"
#Tmp
 if [[ ! -d "${SYSTMP}" ]]; then
  SYSTMP="$(dirname $(mktemp -u))" && export SYSTMP
 fi
#User-Agent
 if [[ -z "${USER_AGENT+x}" ]]; then
  USER_AGENT="$(curl -qfsSL 'https://pub.ajam.dev/repos/Azathothas/Wordlists/Misc/User-Agents/ua_chrome_macos_latest.txt')"
 fi
#Install Cargo
 bash <(curl -qfsSL "https://sh.rustup.rs") --no-modify-path -y
 [[ -s "${HOME}/.cargo/env" ]] && source "${HOME}/.cargo/env"
 hash -r &>/dev/null
 if ! command -v cargo &> /dev/null; then
   echo -e "\n[-] cargo (rust) NOT Found\n"
   build_fail_gh
  exit 1
 else
  rustup default stable
  rustc --version && cargo --version
  cargo install cross --git "https://github.com/cross-rs/cross" --jobs="$(($(nproc)+1))"
 fi
#Path
 export PATH="${HOME}/bin:${HOME}/.cargo/bin:${HOME}/.cargo/env:${HOME}/.go/bin:${HOME}/go/bin:${HOME}/.local/bin:${HOME}/miniconda3/bin:${HOME}/miniconda3/condabin:/usr/local/zig:/usr/local/zig/lib:/usr/local/zig/lib/include:/usr/local/musl/bin:/usr/local/musl/lib:/usr/local/musl/include:${PATH}"
 PATH="$(echo "${PATH}" | awk 'BEGIN{RS=":";ORS=":"}{gsub(/\n/,"");if(!a[$0]++)print}' | sed 's/:*$//')" ; export PATH
 hash -r &>/dev/null
 ##Check Needed CMDs
 for DEP_CMD in cross dasel oras ts zstd; do
    case "$(command -v "${DEP_CMD}" 2>/dev/null)" in
        "") echo -e "\n[✗] FATAL: ${DEP_CMD} is NOT INSTALLED\n"
           build_fail_gh
           exit 1 ;;
    esac
 done 
#Cleanup
 docker system prune -a --volumes -f
 unset BUILD_DIR GH_TOKEN GITHUB_TOKEN HF_TOKEN
#Dirs
 BUILD_DIR="$(mktemp -d --tmpdir=${SYSTMP} XXXXXXXXXXXXXXXXXX)"
 mkdir -p "${BUILD_DIR}"
 if [[ ! -d "${BUILD_DIR}" ]]; then
    echo -e "\n[✗] FATAL: \${BUILD_DIR} couldn't be created\n"
    build_fail_gh
   exit 1
 else
    export BUILD_DIR
    export C_ARTIFACT_DIR="${BUILD_DIR}/BUILD_ARTIFACTS/${HOST_TRIPLET}" ; mkdir -p "${C_ARTIFACT_DIR}"
    if [[ ! -d "${C_ARTIFACT_DIR}" ]]; then
      echo -e "\n[✗] FATAL: \${C_ARTIFACT_DIR} couldn't be created\n"
      build_fail_gh
     exit 1 
    fi
    mkdir -p "${BUILD_DIR}/BUILD_CRATE" 
    mkdir -p "${BUILD_DIR}/BUILD_TMP"
 fi
 [[ "${GHA_MODE}" == "MATRIX" ]] && echo "BUILD_DIR=${BUILD_DIR}" >> "${GITHUB_ENV}"
 [[ "${GHA_MODE}" == "MATRIX" ]] && echo "C_ARTIFACT_DIR=${C_ARTIFACT_DIR}" >> "${GITHUB_ENV}"
#-------------------------------------------------------#

#-------------------------------------------------------#
##Functions
 #Fix/Patch
  fixup_cargo()
  {
   rm -rvf "./.cargo" rust-toolchain* 2>/dev/null
   sed "/^\[profile\.release\]/,/^$/d" -i "./Cargo.toml" ; echo -e "\n[profile.release]\nstrip = true\nopt-level = 3\nlto = true" >> "./Cargo.toml"
   dasel --file "./Cargo.toml" ".dependencies.openssl" 2>/dev/null
   dasel delete --file "./Cargo.toml" ".dependencies.openssl" 2>/dev/null
   sed "/\[dependencies\]/a openssl = { version = \"*\", features = ['vendored'] }" -i "./Cargo.toml"
  }
  export -f fixup_cargo
 #Set Build Env
  set_rustflags()
  {
   if [[ -z "${RUST_TARGET:-}" ]]; then
     echo "Error: RUST_TARGET is not set or is empty" >&2
     return 1
   fi
   RUST_FLAGS=()
   RUST_FLAGS+=("-C target-feature=+crt-static")
   RUST_FLAGS+=("-C default-linker-libraries=yes")
   if echo "${RUST_TARGET}" | grep -Eqiv "alpine|gnu"; then
     RUST_FLAGS+=("-C link-self-contained=yes")
   fi
   RUST_FLAGS+=("-C prefer-dynamic=no")
   RUST_FLAGS+=("-C embed-bitcode=yes")
   RUST_FLAGS+=("-C lto=yes")
   RUST_FLAGS+=("-C opt-level=3")
   RUST_FLAGS+=("-C debuginfo=none")
   RUST_FLAGS+=("-C strip=symbols")
   RUST_FLAGS+=("-C link-arg=-Wl,-S")
   RUST_FLAGS+=("-C link-arg=-Wl,--build-id=none")
   RUST_FLAGS+=("-C link-arg=-Wl,--discard-all")
   RUST_FLAGS+=("-C link-arg=-Wl,--strip-all")
   export OPENSSL_STATIC="1"
   export RUSTFLAGS="${RUST_FLAGS[*]}"
  }
  export -f set_rustflags
 #Set Build Flags
  cross_build()
  {
   #Env  
    echo -e "\n[+] Target: ${RUST_TARGET}"
    echo -e "[+] Flags: ${RUSTFLAGS}\n"
    mkdir -p "${C_ARTIFACT_DIR}"
    #https://github.com/cross-rs/cross/issues/1688
    export CACHE_DIR="${C_ARTIFACT_DIR}/" ; mkdir -p "${CACHE_DIR}"
    echo '[build.env]' > "./Cross.toml"
    echo 'volumes = ["CACHE_DIR"]' >> "./Cross.toml"
   #Build
    cargo clean &>/dev/null
    cross clean &>/dev/null
    cross +nightly build --target "${RUST_TARGET}" -Z unstable-options \
     --all-features \
     --artifact-dir="${C_ARTIFACT_DIR}" \
     --jobs="$(($(nproc)+1))" \
     --release \
     --keep-going \
     --verbose
   #License
    ( askalono --format "json" crawl --follow "$(realpath .)" | jq -r ".. | objects | .path? // empty" | head -n 1 | xargs -I "{}" cp -fv "{}" "${C_ARTIFACT_DIR}/LICENSE" ) 2>/dev/null
   #List
    find "${C_ARTIFACT_DIR}/" -type f -exec bash -c "echo && realpath {} && readelf --section-headers {} 2>/dev/null" \;
    file "${C_ARTIFACT_DIR}/"* && stat -c "%n:         %s Bytes" "${C_ARTIFACT_DIR}/"* && \
    du "${C_ARTIFACT_DIR}/"* --bytes --human-readable --time --time-style="full-iso" --summarize
   #Pretty Print
    echo -e "\n" ; tree "${BUILD_DIR}" 2>/dev/null
    find "${C_ARTIFACT_DIR}" -type f -exec touch "{}" \;
    find "${C_ARTIFACT_DIR}" -maxdepth 1 -type f -print | sort -u | xargs -I "{}" sh -c 'printf "\nFile: $(basename {})\n  Type: $(file -b {})\n  B3sum: $(b3sum {} | cut -d" " -f1)\n  SHA256sum: $(sha256sum {} | cut -d" " -f1)\n  Size: $(du -bh {} | cut -f1)\n"'
   #Checksums
    echo -e "\n[+] Generating (b3sum) Checksums ==> [${C_ARTIFACT_DIR}/CHECKSUM]"
    find "${C_ARTIFACT_DIR}" -maxdepth 1 -type f ! -iname "*CHECKSUM*" -exec b3sum "{}" + | awk '{gsub(".*/", "", $2); print $2 ":" $1}' | tee "${C_ARTIFACT_DIR}/CHECKSUM"
   #Cleanup   
    docker system prune -a --volumes -f &>/dev/null
  }
  export -f cross_build
#-------------------------------------------------------#

#-------------------------------------------------------#
##Main
  pushd "${BUILD_DIR}" &>/dev/null
  #Download & Extract Crate
   cd "${BUILD_DIR}/BUILD_CRATE" &&\
   curl -w "(DL) <== %{url}\n" -qfsSL "https://crates.io/api/v1/crates/${CRATE_NAME}/${CRATE_VERSION}/download" -o "${BUILD_DIR}/BUILD_TMP/${CRATE_NAME}.crate"
   tar -vxz --strip-components="1" -f "${BUILD_DIR}/BUILD_TMP/${CRATE_NAME}.crate"
  #Check
   if [[ "$(du -s "${BUILD_DIR}/BUILD_CRATE" | cut -f1)" -lt 10 ]]; then
      echo -e "\n[✗] FATAL: Crate Download/Extraction probably Failed\n"
      du -bh "${BUILD_DIR}/BUILD_TMP/${CRATE_NAME}.crate"
      du -bh "${BUILD_DIR}/BUILD_CRATE"
      ls -lah "${BUILD_DIR}/BUILD_CRATE"
      build_fail_gh
     exit 1
   else
     #Meta (Raw)
      if [[ -s "${CRATE_META_RAW}" ]]; then
        cp -fv "${CRATE_META_RAW}" "${BUILD_DIR}/CRATE_META_RAW.json"
      else
        build_fail_gh
       exit 1
      fi
     #Meta (Cleaned)
      if [[ -s "${CRATE_META}" ]]; then
        cp -fv "${CRATE_META}" "${BUILD_DIR}/CRATE_META.json"
      else
        build_fail_gh
       exit 1
      fi
   fi
  #Fixup
   fixup_cargo ; echo -e "\n[+] Cargo TOML:\n" && cat "./Cargo.toml" ; echo -e "\n"
  #Build
   echo "[+] Artifacts: ${C_ARTIFACT_DIR}\n"
   {
     echo '\\\\============================ Package Forge ============================////'
     echo '|--- Repository: https://github.com/pkgforge-cargo/builder                 ---|'
     echo '|--- Contact: https://docs.pkgforge.dev/contact/chat                       ---|'
     echo '|--- Discord: https://discord.gg/djJUs48Zbu                                ---|'  
     echo '|--- Docs: https://docs.pkgforge.dev/repositories/external/pkgforge-cargo  ---|'
     echo '|--- Bugs/Issues: https://github.com/pkgforge-cargo/builder/issues         ---|'
     echo '|-----------------------------------------------------------------------------|'
     echo -e "\n==> [+] Started Building at :: $(TZ='UTC' date +'%A, %Y-%m-%d (%I:%M:%S %p)') UTC\n"
     set_rustflags && cross_build
     echo -e "\n==> [+] Finished Building at :: $(TZ='UTC' date +'%A, %Y-%m-%d (%I:%M:%S %p)') UTC\n"
   } |& ts -s '[%H:%M:%S]➜ ' | tee "${C_ARTIFACT_DIR}/BUILD.log"
  #Check Dir
   if [[ "$(du -s --exclude='*.log' "${C_ARTIFACT_DIR}" | cut -f1)" -lt 10 ]]; then
      echo -e "\n[✗] FATAL: ${C_ARTIFACT_DIR} seems broken\n"
      du -bh "${C_ARTIFACT_DIR}"
      ls -lah "${C_ARTIFACT_DIR}"
      build_fail_gh
     exit 1
   else
      PROGS=()
      mapfile -t PROGS < <(find "${C_ARTIFACT_DIR}" -maxdepth 1 -type f -exec file -i "{}" \; | \
                     grep -Ei "application/.*executable" | \
                     cut -d":" -f1 | \
                     xargs realpath --no-symlinks | \
                     xargs -I "{}" basename "{}")
      if [[ ${#PROGS[@]} -le 0 ]]; then
         echo -e "\n[✗] FATAL: Failed to find any Executables\n"
         build_fail_gh
        exit 1
      fi
   fi
  #Gen Metadata
   cd "${C_ARTIFACT_DIR}"
   for PROG in "${PROGS[@]}"; do
    #clean
     unset BUILD_GHACTIONS BUILD_ID BUILD_LOG DOWNLOAD_URL GHCRPKG_TAG GHCRPKG_URL ghcr_push_cmd PKG_BSUM PKG_CATEGORY PKG_DATE PKG_DATETMP PKG_DESCRIPTION PKG_DOWNLOAD_COUNT PKG_FAMILY PKG_HOMEPAGE PKG_JSON PKG_ID PKG_LICENSE PKG_NAME PKG_PROVIDES PKG_SHASUM PKG_SIZE PKG_SIZE_RAW PKG_SRC_URL PKG_TAGS PKG_TYPE PKG_VERSION PKG_WEBPAGE SNAPSHOT_JSON SNAPSHOT_TAGS TAG_URL
    #Check
     if [[ ! -s "./${PROG}" ]]; then
        echo -e "\n[-] Skipping ${PROG} - file does not exist or is empty\n"
        continue
     else
        echo -e "\n[+] Processing ${PROG} [${CRATE_NAME}]\n"
     fi
    #Name
     PKG_NAME="$(basename "${PROG}" | tr -d '[:space:]')"
     PKG_FAMILY="${CRATE_NAME##*[[:space:]]}"
     echo "[+] Name: ${PKG_NAME}"
     echo "[+] Crate: ${PKG_FAMILY}"
     export PKG_NAME PKG_FAMILY
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_NAME=${PKG_NAME}" >> "${GITHUB_ENV}"
    #Version
     PKG_VERSION="${CRATE_VERSION##*[[:space:]]}"
     echo "[+] Version: ${PKG_VERSION}"
     export PKG_VERSION
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_VERSION=${PKG_VERSION}" >> "${GITHUB_ENV}"
    #Checksums
     PKG_BSUM="$(b3sum "${PROG}" | grep -oE '^[a-f0-9]{64}' | tr -d '[:space:]')"
     PKG_SHASUM="$(sha256sum "${PROG}" | grep -oE '^[a-f0-9]{64}' | tr -d '[:space:]')"
     echo "[+] blake3sum: ${PKG_BSUM}"
     echo "[+] sha256sum: ${PKG_SHASUM}"
     export PKG_BSUM PKG_SHASUM
    #Date
     PKG_DATETMP="$(date --utc +%Y-%m-%dT%H:%M:%S)Z"
     PKG_DATE="$(echo "${PKG_DATETMP}" | sed 's/ZZ\+/Z/Ig')"
     echo "[+] Build Date: ${PKG_DATE}"
     export PKG_DATETMP PKG_DATE
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_DATE=${PKG_DATE}" >> "${GITHUB_ENV}"
    #Description 
     PKG_DESCRIPTION="$(jq -r '.description' "${CRATE_META}" 2>/dev/null | grep -iv 'null' | sed 's/`//g' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed ':a;N;$!ba;s/\r\n//g; s/\n//g' | sed 's/["'\'']//g' | sed 's/|//g' | sed 's/`//g')"
      if [[ "$(echo "${PKG_DESCRIPTION}" | tr -d '[:space:]' | wc -c)" -ge 5 ]]; then
        echo "[+] Description: ${PKG_DESCRIPTION}"
      else
        PKG_DESCRIPTION="No Description Provided"
      fi
     export PKG_DESCRIPTION
    #Download Count
     PKG_DOWNLOAD_COUNT="$(jq -r '.. | objects | select(has("recent_downloads")) | .recent_downloads' "${CRATE_META_RAW}" | grep -iv 'null' | head -n 1 | tr -cd '[:digit:]')"
      if [[ "$(echo "${PKG_DOWNLOAD_COUNT}" | tr -d '[:space:]')" -ge 5 ]]; then
        echo "[+] Download Count: ${PKG_DOWNLOAD_COUNT}"
      else
        PKG_DOWNLOAD_COUNT="-1"
      fi
     export PKG_DOWNLOAD_COUNT
    #GHCR
     GHCRPKG_TAG="${PKG_VERSION}-${HOST_TRIPLET}"
     GHCRPKG_URL="$(echo "ghcr.io/pkgforge-cargo/${CRATE_NAME}/stable/${PROG}" | sed ':a; s|^\(https://\)\([^/]\)/\(/\)|\1\2/\3|; ta' | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
     echo "[+] GHCR (TAG): ${GHCRPKG_TAG}"
     echo "[+] GHCR (URL): ${GHCRPKG_URL}"
     export GHCRPKG_TAG GHCRPKG_URL
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "GHCRPKG_URL=${GHCRPKG_URL}" >> "${GITHUB_ENV}"
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "GHCRPKG_TAG=${GHCRPKG_TAG}" >> "${GITHUB_ENV}"
    #Download URL
     DOWNLOAD_URL="$(echo "${GHCRPKG_URL}" | sed 's|^ghcr.io|https://api.ghcr.pkgforge.dev|' | sed ':a; s|^\(https://\)\([^/]\)/\(/\)|\1\2/\3|; ta')?tag=${GHCRPKG_TAG}&download=${PROG}"
     BUILD_LOG="$(echo "${DOWNLOAD_URL}" | sed 's/download=[^&]*/download='"${PROG}"'.log/')"
     echo "[+] Build Log: ${DOWNLOAD_URL}"
     echo "[+] Download URL: ${DOWNLOAD_URL}"
     export BUILD_LOG DOWNLOAD_URL
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "DOWNLOAD_URL=${DOWNLOAD_URL}" >> "${GITHUB_ENV}"
    #HomePage  
     PKG_HOMEPAGE="$(jq -r '.homepage' "${CRATE_META}" 2>/dev/null | grep -iv 'null' | grep -i 'http' | tr -d '[:space:]')"
      if [[ "$(echo "${PKG_HOMEPAGE}" | tr -d '[:space:]' | wc -c)" -ge 5 ]]; then
        echo "[+] Homepage: ${PKG_HOMEPAGE}"
      else
        PKG_HOMEPAGE="https://crates.io/crates/${CRATE_NAME}"
      fi
     export PKG_HOMEPAGE
    #ID
     BUILD_ID="${GITHUB_RUN_ID}"
     BUILD_GHACTIONS="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
     PKG_ID="pkgforge-cargo.${CRATE_NAME}.stable"
     export BUILD_ID BUILD_GHACTIONS PKG_ID
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "BUILD_GHACTIONS=${BUILD_GHACTIONS}" >> "${GITHUB_ENV}"
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "BUILD_ID=${BUILD_ID}" >> "${GITHUB_ENV}"
    #License
     PKG_LICENSE="$(jq -r '.. | objects | select(has("license")) | .license' "${CRATE_META_RAW}" | grep -iv 'null' | head -n 1 | sed 's/"//g' | sed 's/^[ \t]*//;s/[ \t]*$//' | sed 's/["'\'']//g' | sed 's/|//g' | sed 's/`//g' | sed 's/^, //; s/, $//')"
     if [[ "$(echo "${PKG_LICENSE}" | tr -d '[:space:]' | wc -c)" -ge 2 ]]; then
       echo "[+] License: ${PKG_LICENSE}"
     else
       PKG_LICENSE="Blessing"
     fi
     export PKG_LICENSE
    #Provides
     #PKG_PROVIDES="$(jq -r '.. | objects | select(has("bin_names")) | .bin_names' "${CRATE_META_RAW}" | tr -d '[]' | sort -u | grep -iv 'null' | paste -sd, - | tr -d '[:space:]' | sed 's/, /, /g' | sed 's/,/, /g' | sed 's/|//g' | sed 's/"//g' | sed 's/^, //; s/, $//')"
     PKG_PROVIDES="$(printf '%s\n' "${PROGS[@]}" | paste -sd, - | tr -d '[:space:]' | sed 's/, /, /g' | sed 's/,/, /g' | sed 's/|//g' | sed 's/"//g' | sed 's/^, //; s/, $//')"
     if [[ "$(echo "${PKG_PROVIDES}" | tr -d '[:space:]' | wc -c)" -ge 2 ]]; then
       echo "[+] Provides: ${PKG_PROVIDES}"
     else
       PKG_PROVIDES="${PKG_NAME}"
     fi
     export PKG_PROVIDES
    #Size
     PKG_SIZE="$(du -bh "${PROG}" | awk '{unit=substr($1,length($1)); sub(/[BKMGT]$/,"",$1); print $1 " " unit "B"}' | tr -d '[:space:]')"
     PKG_SIZE_RAW="$(stat --format="%s" "${PROG}" | tr -d '[:space:]')"
     echo "[+] Size: ${PKG_SIZE}"
     echo "[+] Size (RAW): ${PKG_SIZE_RAW}"
     export PKG_SIZE PKG_SIZE_RAW
    #Src
     PKG_WEBPAGE="https://crates.io/crates/${CRATE_NAME}"
     PKG_SRC_URL="https://crates.io/api/v1/crates/${CRATE_NAME}/${CRATE_VERSION}/download"
     echo "[+] Src URL: ${PKG_SRC_URL}"
     export PKG_SRC_URL PKG_WEBPAGE
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_SRC_URL=${PKG_SRC_URL}" >> "${GITHUB_ENV}"
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_WEBPAGE=${PKG_WEBPAGE}" >> "${GITHUB_ENV}"
    #Tags
     PKG_TAGS="$(jq -r '.. | objects | select(has("keyword")) | .keyword' "${CRATE_META_RAW}" | tr -d '[]' | sort -u | grep -iv 'null' | paste -sd, - | tr -d '[:space:]' | sed 's/, /, /g' | sed 's/,/, /g' | sed 's/|//g' | sed 's/"//g' | sed 's/^, //; s/, $//')" 
     if [[ "$(echo "${PKG_TAGS}" | tr -d '[:space:]' | wc -c)" -ge 3 ]]; then
       echo "[+] Tags: ${PKG_TAGS}"
     else
       PKG_TAGS="Utility"
     fi
     PKG_CATEGORY="Utility"
     export PKG_CATEGORY PKG_TAGS
    #Type
     PKG_TYPE="static"
     export PKG_TYPE
     [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_TYPE=${PKG_TYPE}" >> "${GITHUB_ENV}"
    #Generate Snapshots
     if [[ -n "${GHCRPKG_URL+x}" ]] && [[ "${GHCRPKG_URL}" =~ ^[^[:space:]]+$ ]]; then
      #Generate Manifest
       unset PKG_GHCR PKG_MANIFEST METADATA_URL
       PKG_MANIFEST="$(echo "${DOWNLOAD_URL}" | sed 's/download=[^&]*/manifest/')"
       METADATA_URL="$(echo "${DOWNLOAD_URL}" | sed 's/download=[^&]*/download='"${PROG}"'.json/')"
       PKG_GHCR="${GHCRPKG_URL}:${GHCRPKG_TAG}"
       export PKG_GHCR PKG_MANIFEST
      #Generate Tags
       TAG_URL="https://api.ghcr.pkgforge.dev/$(echo "${GHCRPKG}" | sed ':a; s|^\(https://\)\([^/]\)/\(/\)|\1\2/\3|; ta' | sed -E 's|^ghcr\.io/||; s|^/+||; s|/+?$||' | sed ':a; s|^\(https://\)\([^/]\)/\(/\)|\1\2/\3|; ta')/${PROG}?tags"
       echo -e "[+] Fetching Snapshot Tags <== ${TAG_URL} [\$GHCRPKG]"
       readarray -t "SNAPSHOT_TAGS" < <(oras repo tags "${GHCRPKG_URL}" | grep -viE '^\s*(latest|srcbuild)[.-][0-9]{6}T[0-9]{6}[.-]' | grep -i "${HOST_TRIPLET%%-*}" | uniq)
     else
       TAG_URL="https://api.ghcr.pkgforge.dev/pkgforge/$(echo "${PKG_REPO}/${PKG_FAMILY:-${PKG_NAME}}/${PKG_NAME:-${PKG_FAMILY:-${PKG_ID}}}" | sed ':a; s|^\(https://\)\([^/]\)/\(/\)|\1\2/\3|; ta')/${PROG}?tags"
       echo -e "[+] Fetching Snapshot Tags <== ${TAG_URL} [NO \$GHCRPKG]"
       readarray -t "SNAPSHOT_TAGS" < <(oras repo tags "${GHCRPKG_URL}" | grep -viE '^\s*(latest|srcbuild)[.-][0-9]{6}T[0-9]{6}[.-]' | grep -i "${HOST_TRIPLET%%-*}" | uniq)
     fi
     if [[ -n "${SNAPSHOT_TAGS[*]}" && "${#SNAPSHOT_TAGS[@]}" -gt 0 ]]; then
       echo -e "[+] Snapshots: ${SNAPSHOT_TAGS[*]}"
       unset S_TAG S_TAGS S_TAG_VALUE SNAPSHOT_JSON ; S_TAGS=()
       for S_TAG in "${SNAPSHOT_TAGS[@]}"; do
        S_TAG_VALUE="$(oras manifest fetch "${GHCRPKG_URL}:${S_TAG}" | jq -r '.annotations["dev.pkgforge.soar.version_upstream"]' | tr -d '[:space:]')"
        [[ "${S_TAG_VALUE}" == "null" ]] && unset S_TAG_VALUE
         if [[ -n "${S_TAG_VALUE+x}" ]] && [[ "${S_TAG_VALUE}" =~ ^[^[:space:]]+$ ]]; then
           S_TAGS+=("${S_TAG}[${S_TAG_VALUE}]")
         else
           S_TAGS+=("${S_TAG}")
         fi
       done
       if [[ -n "${S_TAGS[*]}" && "${#S_TAGS[@]}" -gt 0 ]]; then
         SNAPSHOT_JSON=$(printf '%s\n' "${S_TAGS[@]}" | jq -R . | jq -s 'if type == "array" then . else [] end')
         export SNAPSHOT_JSON
       else
         export SNAPSHOT_JSON="[]"
       fi
       unset S_TAG S_TAGS S_TAG_VALUE
     else
       echo -e "[-] INFO: Snapshots is empty (No Previous Build Exists?)"
       export SNAPSHOT_JSON="[]"
     fi
    #Generate Json
     jq -rn --argjson "snapshots" "${SNAPSHOT_JSON:-[]}" \
      '{
       "_disabled": "false",
       "host": (env.HOST_TRIPLET // ""),
       "rank": (env.RANK // ""),
       "pkg": (env.PKG_NAME // .pkg // ""),
       "pkg_family": (env.PKG_FAMILY // ""),
       "pkg_id": (env.PKG_ID // ""),
       "pkg_name": (env.PKG_NAME // .pkg // ""),
       "pkg_type": (env.PKG_TYPE // .pkg_type // ""),
       "pkg_webpage": (env.PKG_WEBPAGE // ""),
       "bundle": "false",
       "category": (if env.PKG_CATEGORY then (env.PKG_CATEGORY | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique | sort) else [] end),
       "description": (env.PKG_DESCRIPTION // (if type == "object" and has("description") and (.description | type == "object") then (if env.PROG != null and (.description[env.PROG] != null) then .description[env.PROG] else .description["_default"] end) else .description end // "")),
       "homepage": (if env.PKG_HOMEPAGE then (env.PKG_HOMEPAGE | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique | sort) else [] end),
       "license": (if env.PKG_LICENSE then (env.PKG_LICENSE | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique | sort) else [] end),
       "maintainer": ["pkgforge-cargo (https://github.com/pkgforge-cargo/builder)"],
       "provides": (if env.PKG_PROVIDES then (env.PKG_PROVIDES | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique | sort) else [] end),
       "note": [
         "[EXTERNAL] (This is an Official but externally maintained repository)",
         "This package was automatically built from crates.io using cargo-cross",
         "Provided by: https://github.com/pkgforge-cargo/builder",
         "Learn More: https://docs.pkgforge.dev/repositories/external/pkgforge-cargo"
       ],
       "src_url": (env.PKG_SRC_URL // ""),
       "tag": (if env.PKG_TAGS then (env.PKG_TAGS | split(",") | map(gsub("^\\s+|\\s+$"; "")) | unique | sort) else [] end),
       "version": (env.PKG_VERSION // ""),
       "version_upstream": (env.PKG_VERSION // ""),
       "bsum": (env.PKG_BSUM // ""),
       "build_date": (env.PKG_DATE // ""),
       "build_gha": (env.BUILD_GHACTIONS // ""),
       "build_id": (env.BUILD_ID // ""),
       "build_log": (env.BUILD_LOG // ""),
       "deprecated": (env.PKG_DEPRECATED // "false"),
       "desktop_integration": "false",
       "download_url": (env.DOWNLOAD_URL // ""),
       "external": "true", 
       "ghcr_pkg": (env.PKG_GHCR // ""),
       "ghcr_url": (if (env.GHCRPKG_URL // "") | startswith("https://") then (env.GHCRPKG_URL // "") else "https://" + (env.GHCRPKG_URL // "") end),
       "installable": "true",
       "manifest_url": (env.PKG_MANIFEST // ""),
       "portable": "true",
       "recurse_provides": "true",
       "shasum": (env.PKG_SHASUM // ""),
       "size": (env.PKG_SIZE // ""),
       "size_raw": (env.PKG_SIZE_RAW // ""),
       "soar_syms": "false",
       "snapshots": $snapshots,
       "trusted": "true"
     }' | jq . > "${BUILD_DIR}/BUILD_TMP/${PROG}.json"
     #Copy
       if jq -r '.pkg' "${BUILD_DIR}/BUILD_TMP/${PROG}.json" | grep -iv 'null' | tr -d '[:space:]' | grep -Eiq "^${PKG_NAME}$"; then
         mv -fv "${BUILD_DIR}/BUILD_TMP/${PROG}.json" "${C_ARTIFACT_DIR}/${PROG}.json"
         cp -fv "${C_ARTIFACT_DIR}/BUILD.log" "${C_ARTIFACT_DIR}/${PROG}.log"
         echo "${PKG_VERSION}" | tr -d '[:space:]' > "${C_ARTIFACT_DIR}/${PROG}.version"
         PKG_JSON="${C_ARTIFACT_DIR}/${PROG}.json"
         METADATA_FILE="${METADATA_DIR}/$(echo "${GHCRPKG_URL}" | sed 's/[^a-zA-Z0-9]/_/g' | tr -d '"'\''[:space:]')-${HOST_TRIPLET}.json"
         cp -fv "${PKG_JSON}" "${METADATA_FILE}"
         export PKG_JSON
         echo -e "\n[+] Metadata: \n" && jq . "${PKG_JSON}" ; echo -e "\n"
       else
          echo -e "\n[✗] FATAL: Failed to generate Metadata\n"
          build_fail_gh
         exit 1
       fi
    #Upload to ghcr
     #Construct Upload CMD
      ghcr_push_cmd()
      {
       for i in {1..10}; do
         unset ghcr_push ; ghcr_push=(oras push --disable-path-validation)
         ghcr_push+=(--config "/dev/null:application/vnd.oci.empty.v1+json")
         ghcr_push+=(--annotation "com.github.package.type=container")
         ghcr_push+=(--annotation "dev.pkgforge.discord=https://discord.gg/djJUs48Zbu")
         ghcr_push+=(--annotation "dev.pkgforge.soar.build_date=${PKG_DATE}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.build_gha=${BUILD_GHACTIONS}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.build_id=${BUILD_ID}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.build_log=${BUILD_LOG}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.bsum=${PKG_BSUM}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.category=${PKG_CATEGORY}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.description=${PKG_DESCRIPTION}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.download_url=${DOWNLOAD_URL}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.ghcr_pkg=${GHCRPKG_URL}:${GHCRPKG_TAG}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.homepage=${PKG_HOMEPAGE:-${PKG_SRC_URL}}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.json=$(jq . ${PKG_JSON})")
         ghcr_push+=(--annotation "dev.pkgforge.soar.manifest_url=${PKG_MANIFEST}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.metadata_url=${METADATA_URL}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.pkg=${PKG_NAME}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.pkg_family=${PKG_FAMILY}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.pkg_name=${PKG_NAME}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.pkg_webpage=${PKG_WEBPAGE}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.shasum=${PKG_SHASUM}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.size=${PKG_SIZE}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.size_raw=${PKG_SIZE_RAW}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.src_url=${PKG_SRC_URL:-${PKG_HOMEPAGE}}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.version=${PKG_VERSION}")
         ghcr_push+=(--annotation "dev.pkgforge.soar.version_upstream=${PKG_VERSION_UPSTREAM}")
         ghcr_push+=(--annotation "org.opencontainers.image.authors=https://docs.pkgforge.dev/contact/chat")
         ghcr_push+=(--annotation "org.opencontainers.image.created=${PKG_DATE}")
         ghcr_push+=(--annotation "org.opencontainers.image.description=${PKG_DESCRIPTION}")
         ghcr_push+=(--annotation "org.opencontainers.image.documentation=${PKG_WEBPAGE}")
         ghcr_push+=(--annotation "org.opencontainers.image.licenses=blessing")
         ghcr_push+=(--annotation "org.opencontainers.image.ref.name=${PKG_VERSION}")
         ghcr_push+=(--annotation "org.opencontainers.image.revision=${PKG_SHASUM:-${PKG_VERSION}}")
         ghcr_push+=(--annotation "org.opencontainers.image.source=https://github.com/pkgforge-cargo/${PKG_REPO}")
         ghcr_push+=(--annotation "org.opencontainers.image.title=${PKG_NAME}")
         ghcr_push+=(--annotation "org.opencontainers.image.url=${PKG_SRC_URL}")
         ghcr_push+=(--annotation "org.opencontainers.image.vendor=pkgforge-cargo")
         ghcr_push+=(--annotation "org.opencontainers.image.version=${PKG_VERSION}")
         ghcr_push+=("${GHCRPKG_URL}:${GHCRPKG_TAG}" "./${PROG}")
         [[ -f "./${PROG}.sig" && -s "./${PROG}.sig" ]] && ghcr_push+=("./${PROG}.sig")
         [[ -f "./CHECKSUM" && -s "./CHECKSUM" ]] && ghcr_push+=("./CHECKSUM")
         [[ -f "./CHECKSUM.sig" && -s "./CHECKSUM.sig" ]] && ghcr_push+=("./CHECKSUM.sig")
         [[ -f "./LICENSE" && -s "./LICENSE" ]] && ghcr_push+=("./LICENSE")
         [[ -f "./LICENSE.sig" && -s "./LICENSE.sig" ]] && ghcr_push+=("./LICENSE.sig")
         [[ -f "./${PROG}.json" && -s "./${PROG}.json" ]] && ghcr_push+=("./${PROG}.json")
         [[ -f "./${PROG}.json.sig" && -s "./${PROG}.json.sig" ]] && ghcr_push+=("./${PROG}.json.sig")
         [[ -f "./${PROG}.log" && -s "./${PROG}.log" ]] && ghcr_push+=("./${PROG}.log")
         [[ -f "./${PROG}.log.sig" && -s "./${PROG}.log.sig" ]] && ghcr_push+=("./${PROG}.log.sig")
         [[ -f "./${PROG}.version" && -s "./${PROG}.version" ]] && ghcr_push+=("./${PROG}.version")
         [[ -f "./${PROG}.version.sig" && -s "./${PROG}.version.sig" ]] && ghcr_push+=("./${PROG}.version.sig")
         "${ghcr_push[@]}" ; sleep 5
        #Check 
         if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge.soar.build_date"]' | tr -d '[:space:]')" == "${PKG_DATE}" ]]; then
           echo -e "\n[+] Registry --> https://${GHCRPKG_URL}"
           echo -e "[+] ==> ${MANIFEST_URL:-${DOWNLOAD_URL}} \n"
           export PUSH_SUCCESSFUL="YES"
           #rm -rf "${GHCR_PKG}" "${PKG_JSON}" 2>/dev/null
           [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PKG_VERSION_UPSTREAM=${PKG_VERSION_UPSTREAM}" >> "${GITHUB_ENV}"
           [[ "${GHA_MODE}" == "MATRIX" ]] && echo "GHCRPKG_URL=${GHCRPKG_URL}" >> "${GITHUB_ENV}"
           [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PUSH_SUCCESSFUL=${PUSH_SUCCESSFUL}" >> "${GITHUB_ENV}"
           break
         else
           echo -e "\n[-] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG} (Retrying ${i}/10)\n"
         fi
         sleep "$(shuf -i 500-4500 -n 1)e-3"
       done
      }
      export -f ghcr_push_cmd
      #First Set of tries
       ghcr_push_cmd
      #Check if Failed  
       if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge.soar.build_date"]' | tr -d '[:space:]')" != "${PKG_DATE}" ]]; then
         echo -e "\n[✗] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG}\n"
         #Second set of Tries
          echo -e "\n[-] Retrying ...\n"
          ghcr_push_cmd
           if [[ "$(oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq -r '.annotations["dev.pkgforge.soar.build_date"]' | tr -d '[:space:]')" != "${PKG_DATE}" ]]; then
             oras manifest fetch "${GHCRPKG_URL}:${GHCRPKG_TAG}" | jq .
             echo -e "\n[✗] Failed to Push Artifact to ${GHCRPKG_URL}:${GHCRPKG_TAG}\n"
             export PUSH_SUCCESSFUL="NO"
             [[ "${GHA_MODE}" == "MATRIX" ]] && echo "PUSH_SUCCESSFUL=${PUSH_SUCCESSFUL}" >> "${GITHUB_ENV}"
             return 1 || exit 1
           fi
       fi
  done
  popd &>/dev/null
#-------------------------------------------------------#

#-------------------------------------------------------#
##Upload SRCBUILD
 if [[ -n "${GITHUB_TEST_BUILD+x}" || "${GHA_MODE}" == "MATRIX" ]]; then
  pushd "$(mktemp -d)" &>/dev/null &&\
   tar --directory="${BUILD_DIR}" --preserve-permissions --create --file="BUILD_ARTIFACTS.tar" "."
   zstd --force "./BUILD_ARTIFACTS.tar" --verbose -o "/tmp/BUILD_ARTIFACTS.zstd"
   rm -rvf "./BUILD_ARTIFACTS.tar" 2>/dev/null &&\
  popd &>/dev/null
 elif [[ "${KEEP_LOGS}" != "YES" ]]; then
  echo -e "\n[-] Removing ALL Logs & Files\n"
  rm -rvf "${BUILD_DIR}" 2>/dev/null
 fi
##Disable Debug 
 if [[ "${DEBUG}" = "1" ]] || [[ "${DEBUG}" = "ON" ]]; then
    set -x
 fi
#-------------------------------------------------------#