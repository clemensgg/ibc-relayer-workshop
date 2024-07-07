#!/bin/bash
NODE=$1

if [ -z $NODE ]; then
  echo "usage: $0 <REST-ENDPOINT>"
  exit 1
fi

echo "Getting channels..."
PAGE_KEY=""
CHANNELS=""

while true; do
  RESPONSE=$(curl -s "${NODE}/ibc/core/channel/v1/channels?pagination.key=${PAGE_KEY}")
  CHANNELS_ARRAY=$(echo "${RESPONSE}" | jq -c '.channels[]')
  for CHANNEL in $CHANNELS_ARRAY; do
    CHANNELS+="${CHANNEL},"
  done
  PAGE_KEY=$(echo "${RESPONSE}" | jq -r '.pagination.next_key')
  echo "Fetched a page of channels, next_key: ${PAGE_KEY}"
  if [ "${PAGE_KEY}" == "null" ]; then
    break
  fi
done
CHANNELS_JSON="[${CHANNELS%,}]"
CHANNELS_JSON=$(echo "${CHANNELS_JSON}" | jq -r 'sort_by(.channel_id | split("-")[1] | tonumber)')

echo "Getting connections..."
PAGE_KEY=""
CONNECTIONS=""

while true; do
  RESPONSE=$(curl -s "${NODE}/ibc/core/connection/v1/connections?pagination.key=${PAGE_KEY}")
  CONNECTIONS_ARRAY=$(echo "${RESPONSE}" | jq -c '.connections[]')
  for CONNECTION in $CONNECTIONS_ARRAY; do
    CONNECTIONS+="${CONNECTION},"
  done
  PAGE_KEY=$(echo "${RESPONSE}" | jq -r '.pagination.next_key')
  echo "Fetched a page of connections, next_key: ${PAGE_KEY}"
  if [ "${PAGE_KEY}" == "null" ]; then
    break
  fi
done
CONNECTIONS_JSON="[${CONNECTIONS%,}]"
CONNECTIONS_JSON=$(echo "${CONNECTIONS_JSON}" | jq -r 'sort_by(.id | split("-")[1] | tonumber)')

NUM_CHANNELS=$(echo "${CHANNELS_JSON}" | jq '. | length')
CHAIN_ID=$(curl -s "${NODE}/cosmos/base/tendermint/v1beta1/blocks/latest" | jq -r .block.header.chain_id)
echo "CHAIN_ID, CLIENT, CONNECTION, CHANNEL, PORT, COUNTERPARTY_CHAIN, COUNTERPARTY_CLIENT, COUNTERPARTY_CONNECTION, COUNTERPARTY_CHANNEL, COUNTERPARTY_PORT"
for (( each_channel=0; each_channel < NUM_CHANNELS; each_channel++ ))
do
    # Just show the open ones
    STATE=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].state")
    if [ "$STATE" != "STATE_OPEN" ]; then
        continue
    fi
    COUNTERPARTY_PORT=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].counterparty.port_id")
    COUNTERPARTY_CHANNEL=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].counterparty.channel_id")
    PORT=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].port_id")
    CHANNEL=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].channel_id")
    CONNECTION=$(echo "${CHANNELS_JSON}" | jq -r ".[${each_channel}].connection_hops[0]")
    CONNECTION_JSON=$(echo "${CONNECTIONS_JSON}" | jq ".[] | select(.id == \"$CONNECTION\")")
    COUNTERPARTY_CONNECTION=$(echo "${CONNECTION_JSON}" | jq -r .counterparty.connection_id)
    COUNTERPARTY_CLIENT=$(echo "${CONNECTION_JSON}" | jq -r .counterparty.client_id)
    CLIENT=$(echo "${CONNECTION_JSON}" | jq -r .client_id)
    CLIENT_JSON=$(curl -s "${NODE}/ibc/core/client/v1/client_states/${CLIENT}")
    CLIENT_STATUS_JSON=$(curl -s "${NODE}/ibc/core/client/v1/client_status/${CLIENT}")
    CLIENT_STATUS=$(echo "${CLIENT_STATUS_JSON}" | jq -r '.status')
    if [[ "$CLIENT_STATUS" != "Active" ]]; then
        continue
    fi
    COUNTERPARTY_CHAIN=$(echo "${CLIENT_JSON}" | jq -r .client_state.chain_id)
    echo "${CHAIN_ID}, ${CLIENT}, ${CONNECTION}, ${CHANNEL}, ${PORT}, ${COUNTERPARTY_CHAIN}, ${COUNTERPARTY_CLIENT}, ${COUNTERPARTY_CONNECTION}, ${COUNTERPARTY_CHANNEL}, ${COUNTERPARTY_PORT}"
done

