#!/bin/bash

set -e

if (($# < 2)); then
    echo >&2 "This script deploys a testnet with mainnet NNS state and upgrades the replica and all NNS canisters via proposals."
    echo "Usage: <TESTNET> <REPLICA_VERSION>"
    echo ""
    echo "NOTE: To use this script, your public key should be present on pyr07 backup pod! (ask for help on #backup-ops Slack channel)"
    echo ""
    echo "REPLICA_VERSION    A build id of a downloadable image."
    echo "TESTNET            A testnet which supports unassigned nodes. (hosts_unassigned.ini should be present!)"
    exit 1
fi

TESTNET=$1
CUSTOM_GIT_SHA=$2
NNS_DAPP_RELEASE="proposal-123301"

get_latest_nns_proposal() {
    dfx canister \
        --network "${NNS_URL}" \
        call "${GOVERNANCE}" \
        --candid ../../../rs/nns/governance/canister/governance.did \
        list_proposals '(record {include_reward_status = vec {}; before_proposal = null; limit = 1; exclude_topic = vec {}; include_status = vec {};})'
}

export REPLICA_SHA_HEX="$(
    curl -s "https://download.dfinity.systems/ic/${CUSTOM_GIT_SHA}/guest-os/update-img/SHA256SUMS" \
        | grep update-img.tar.zst \
        | sed -e 's/\s.*$//'
)"
echo "REPLICA_SHA_HEX = ${REPLICA_SHA_HEX}"

export GOVERNANCE=rrkah-fqaaa-aaaaa-aaaaq-cai
export REGISTRY=rwlgt-iiaaa-aaaaa-aaaaa-cai
export LEDGER=ryjl3-tyaaa-aaaaa-aaaba-cai
export ROOT=r7inp-6aaaa-aaaaa-aaabq-cai
export CMC=rkp4c-7iaaa-aaaaa-aaaca-cai
export LIFELINE=rno2w-sqaaa-aaaaa-aaacq-cai
export GTC=renrk-eyaaa-aaaaa-aaada-cai
export NNS_DAPP=qoctq-giaaa-aaaaa-aaaea-cai
export ICP_ARCHIVE=qjdve-lqaaa-aaaaa-aaaeq-cai
export SNS_W=qaa6y-5yaaa-aaaaa-aaafa-cai

TIMESTAMP=$(date +%s)
export DIR="${HOME}/testnet-${TIMESTAMP}/${TESTNET}"
rm -fr "${DIR}"
mkdir -p "${DIR}"
echo "DIR = ${DIR}"

# Don't deploy BNs
STEPS="1" ./nns_dev_testnet.sh "${TESTNET}" || true

source "${DIR}/output_vars_nns_dev_testnet.sh"
"${DIR}/ic-admin" \
    -r "${NNS_URL}" \
    -s "${PEM}" \
    propose-to-update-elected-replica-versions \
    --replica-version-to-elect "${CUSTOM_GIT_SHA}" \
    --release-package-urls https://download.dfinity.systems/ic/"${CUSTOM_GIT_SHA}"/guest-os/update-img/update-img.tar.zst \
    --release-package-sha256-hex "${REPLICA_SHA_HEX}" \
    --proposer "${NEURON_ID}" \
    --summary "Blessing replica with old metering_type"

sleep 3
get_latest_nns_proposal

"${DIR}/ic-admin" \
    -r "${NNS_URL}" \
    -s "${PEM}" \
    propose-to-update-subnet-replica-version tdb26-jop6k-aogll-7ltgs-eruif-6kk7m-qpktf-gdiqx-mxtrf-vb5e6-eqe \
    "${CUSTOM_GIT_SHA}" \
    --proposer "${NEURON_ID}" \
    --summary "Update root subnet to replica with old metering_type"

sleep 3
get_latest_nns_proposal

# wait till replica is up again
while ! ssh -n \
    -o Batchmode=yes \
    -o UserKnownHostsFile=/dev/null \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "admin@${NNS_IP}" \
    2>&1 \
    | grep -q -m 1 'password'; do
    echo "Waiting for the replica to restart after upgrade ..."
    sleep 3
done

echo "==== Replica upgraded SUCCESSFULLY! ===="

./test-canister-upgrade.sh governance "${CUSTOM_GIT_SHA}"
./test-canister-upgrade.sh registry "${CUSTOM_GIT_SHA}"
./test-canister-upgrade.sh root "${CUSTOM_GIT_SHA}"
./test-canister-upgrade.sh lifeline "${CUSTOM_GIT_SHA}"
./test-canister-upgrade.sh genesis-token "${CUSTOM_GIT_SHA}"
./test-canister-upgrade.sh sns-wasm "${CUSTOM_GIT_SHA}"

# Upgrade NNS dapp
curl \
    -L "https://github.com/dfinity/nns-dapp/releases/download/${NNS_DAPP_RELEASE}/nns-dapp.wasm.gz" \
    -o "${DIR}/nns-dapp.wasm.gz"
"${DIR}/ic-admin" \
    -r "${NNS_URL}" \
    -s "${PEM}" \
    propose-to-change-nns-canister \
    --canister-id "${NNS_DAPP}" \
    --wasm-module-path "${DIR}/nns-dapp.wasm.gz" \
    --wasm-module-sha256 "$(sha256sum "${DIR}/nns-dapp.wasm.gz" | sed 's/ .*$//')" \
    --mode upgrade \
    --proposer "${NEURON_ID}" \
    --summary "Propose to upgrade NNS dapp to ${NNS_DAPP_RELEASE}"

sleep 3
get_latest_nns_proposal

echo "All done!"

sleep 10

curl \
    --max-time 180 \
    "http://[${NNS_IP}]:19531/entries?follow" >"${DIR}/${CUSTOM_GIT_SHA}.log" \
    || true

echo "Canister,Function,Instructions,Duration(ms)" \
    >"${DIR}/${CUSTOM_GIT_SHA}.csv"
cat "${DIR}/${CUSTOM_GIT_SHA}.log" \
    | grep "instructions = " \
    | grep "]: Executed " \
    | sed -e 's/^.*Executed //' \
    | sed -e "s/${GOVERNANCE}/GOVERNANCE/" \
    | sed -e "s/${REGISTRY}/REGISTRY/" \
    | sed -e "s/${LEDGER}/LEDGER/" \
    | sed -e "s/${ROOT}/ROOT/" \
    | sed -e "s/${CMC}/CMC/" \
    | sed -e "s/${LIFELINE}/LIFELINE/" \
    | sed -e "s/${GTC}/GTC/" \
    | sed -e "s/${NNS_DAPP}/NNS_DAPP/" \
    | sed -e "s/${ICP_ARCHIVE}/ICP_ARCHIVE/" \
    | sed -e "s/${SNS_W}/SNS_W/" \
    | sed -e 's/::/,/' \
    | sed -e 's/: instructions = /,/' \
    | sed -e 's/: instructions = /,/' \
    | sed -e 's/, duration = /,/' \
    | sed -e 's/ms\..*//' \
        >>"${DIR}/${CUSTOM_GIT_SHA}.csv"

sort \
    -k3 \
    -n \
    -r \
    -t, \
    "${DIR}/${CUSTOM_GIT_SHA}.csv" \
    >"${DIR}/${CUSTOM_GIT_SHA}--sorted.csv"

echo "Statistics were written to ${DIR}/${CUSTOM_GIT_SHA}--sorted.csv"
