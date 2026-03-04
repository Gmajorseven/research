# Lightning Network Channel Breach Simulation

## Step-by-Step Demonstration Guide

> **Prerequisites:** Source the helpers first in your terminal session:
>
> ```bash
> source scripts/helpers.sh
> ```
>
> This gives you shortcuts: `alice`, `bob`, `carol`, `btc`, `mine`

---

## Script Summary

**Goal:** Demonstrate a Lightning Network **channel breach** and the automatic **justice transaction** punishment by the watchtower.

**Network Topology:**

```
Alice (Watchtower Server)
  │
  └── watches Bob's channels
  
Bob ──[channel]──► Carol
  │                   │
  (honest party)     (cheater — broadcasts revoked tx)
```

**Roles:**

| Node | Role |
|------|------|
| **Alice** | Watchtower server — monitors the chain for Bob |
| **Bob** | Honest party — his watchtower (Alice) protects him |
| **Carol** | Cheater — force-closes with an old, revoked commitment tx |

**Scenario:** Carol force-closes the Bob↔Carol channel using an **old, revoked** commitment transaction (cheating). Alice's watchtower detects it on-chain and broadcasts a **justice transaction** — sweeping **all** channel funds to Bob. Carol loses everything.

**Phases:**

| Phase | What Happens |
|-------|-------------|
| 0 | Pre-flight: verify nodes online, find Bob↔Carol channel, confirm watchtower |
| 1 | Force-close channel to capture current commitment tx from mempool (becomes the "old state") |
| 2 | Evict that tx from mempool without confirming it |
| 3 | Reopen the channel, make payments → captured tx is now **revoked** |
| 4 | Broadcast the revoked tx → this is the **breach** (Carol cheating) |
| 5 | Mine blocks → watchtower detects breach → fires **justice tx** → Carol loses everything |

---

## PHASE 0 — Pre-flight Checks

### 0.1 Check all nodes are alive

**Alice:**

```bash
alice getinfo | jq '{alias, identity_pubkey}'
```

**Bob:**

```bash
bob getinfo | jq '{alias, identity_pubkey}'
```

**Carol:**

```bash
carol getinfo | jq '{alias, identity_pubkey}'
```

### 0.2 Verify Alice's watchtower server is running

```bash
alice tower info
```

### 0.3 Verify Bob is registered as watchtower client (watching via Alice)

```bash
bob wtclient towers | jq '[.towers[] | {pubkey, active_session_candidate, num_sessions}]'
```

### 0.4 Save Carol's pubkey

```bash
CAROL_PUBKEY=$(carol getinfo | jq -r '.identity_pubkey')
echo "Carol pubkey: $CAROL_PUBKEY"
```

### 0.5 Find Bob↔Carol channel

```bash
bob listchannels | jq --arg pub "$CAROL_PUBKEY" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0] | {
    channel_point, chan_id, capacity,
    local_balance, remote_balance,
    num_updates, csv_delay
  }'
```

### 0.6 Save the channel point

```bash
# Replace with real values from the output above
CHAN_POINT="<txid>:<vout>"
FUNDING_TXID=$(echo $CHAN_POINT | cut -d: -f1)
FUNDING_VOUT=$(echo $CHAN_POINT | cut -d: -f2)
```

---

## PHASE 1 — Capture the "Old State" Commitment Transaction

> We force-close the channel to get the commitment tx from the mempool.
> This tx reflects the **current** state. After we advance state with payments,
> this captured tx becomes the **revoked old state** — broadcasting it = breach.

### 1.1 Carol force-closes the channel (DO NOT MINE YET)

```bash
carol closechannel --chan_point="$CHAN_POINT" --force
```

### 1.2 Wait, then check mempool

```bash
sleep 3
btc getrawmempool
```

### 1.3 Find the commitment tx that spends the funding output

```bash
# Try each TXID from the mempool until you find the one spending the funding output
TXID="<txid_from_mempool>"
btc getrawtransaction "$TXID" true | \
  jq '.vin[] | select(.txid == "'$FUNDING_TXID'" and .vout == '$FUNDING_VOUT')'
```

### 1.4 Save the raw tx hex (this is our "old state")

```bash
OLD_COMMIT_RAW=$(btc getrawtransaction "$TXID" false)
OLD_COMMIT_TXID="$TXID"
echo "Captured old commitment tx: $OLD_COMMIT_TXID"
```

---

## PHASE 2 — Evict the Commitment Tx from Mempool

> We need to remove this tx from the mempool **without confirming it**, so the
> channel can be re-established and state can advance.

### 2.1 De-prioritize the tx so it won't be included in the next block

```bash
btc prioritisetransaction "$OLD_COMMIT_TXID" 0 -99999999
```

### 2.2 Mine 1 block (commitment tx should be excluded)

```bash
mine 1
```

### 2.3 Verify eviction

```bash
btc getrawmempool | jq '.'
```

### 2.4 If still in mempool, abandon on Carol's side

```bash
carol abandonchannel --chan_point="$CHAN_POINT"
sleep 2
mine 1
```

### 2.5 Confirm no pending channels

```bash
carol pendingchannels | jq '.'
bob pendingchannels | jq '.'
```

---

## PHASE 3 — Reopen Channel & Advance State

> After this phase, the captured tx from Phase 1 becomes a **revoked** old state.
> Each payment creates a new commitment tx and the old one is revoked.

### 3.1 Reconnect Bob to Carol

```bash
BOB_PUBKEY=$(bob getinfo | jq -r '.identity_pubkey')
bob connect "$CAROL_PUBKEY@lnd-carol:9735"
```

### 3.2 Bob opens a new channel to Carol

```bash
bob openchannel --node_key="$CAROL_PUBKEY" --local_amt=500000 --push_amt=100000
```

### 3.3 Mine 6 blocks to confirm the channel

```bash
mine 6
sleep 5
```

### 3.4 Verify new channel is active

```bash
bob listchannels | jq --arg pub "$CAROL_PUBKEY" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0] | {channel_point, num_updates}'
```

### 3.5 Advance state with 5 payments (Alice → invoice via Bob → Carol route)

> Each payment advances the channel state. Bob's watchtower (Alice) automatically
> stores an encrypted justice tx for each revoked state.

**Payment 1:**

```bash
# Alice creates invoice, Bob pays through the Bob→Carol channel
alice addinvoice --amt 5000 --memo "breach_test_1" | jq -r '.payment_request'

# Carol pays Alice (routes through Bob→Carol channel, advancing its state)
carol sendpayment --pay_req="<pay_req>" --timeout=30 --fee_limit=100
```

**Payment 2:**

```bash
alice addinvoice --amt 5000 --memo "breach_test_2" | jq -r '.payment_request'
carol sendpayment --pay_req="<pay_req>" --timeout=30 --fee_limit=100
```

**Payment 3:**

```bash
alice addinvoice --amt 5000 --memo "breach_test_3" | jq -r '.payment_request'
carol sendpayment --pay_req="<pay_req>" --timeout=30 --fee_limit=100
```

**Payment 4:**

```bash
alice addinvoice --amt 5000 --memo "breach_test_4" | jq -r '.payment_request'
carol sendpayment --pay_req="<pay_req>" --timeout=30 --fee_limit=100
```

**Payment 5:**

```bash
alice addinvoice --amt 5000 --memo "breach_test_5" | jq -r '.payment_request'
carol sendpayment --pay_req="<pay_req>" --timeout=30 --fee_limit=100
```

### 3.6 Mine 1 block after payments

```bash
mine 1
```

### 3.7 Confirm state has advanced (num_updates ≥ 5)

```bash
bob listchannels | jq --arg pub "$CAROL_PUBKEY" \
  '[.channels[] | select(.remote_pubkey == $pub)] | .[0] | {num_updates, local_balance, remote_balance}'
```

---

## PHASE 4 — Broadcast the Revoked Transaction (THE BREACH)

> This simulates **Carol cheating** — broadcasting an old, revoked commitment tx
> that has a more favorable balance for Carol than the current state.

### 4.1 Broadcast the old commitment tx

```bash
btc sendrawtransaction "$OLD_COMMIT_RAW" true
```

### 4.2 Confirm it's in mempool

```bash
btc getrawmempool | jq '.'
```

> **At this point the breach has begun.** Carol has broadcast a revoked state on-chain.

---

## PHASE 5 — Mine Blocks & Observe Watchtower Justice Response

> Alice's watchtower detects the revoked tx on-chain and broadcasts the justice
> transaction within the CSV delay window — sweeping ALL funds to Bob.

### 5.1 Mine 1 block to confirm the breach tx

```bash
mine 1
```

### 5.2 Check Alice's watchtower logs (breach detection)

```bash
docker logs lnd-alice --since=60s 2>&1 | grep -iE "breach|justice|revok|sweep|fraud"
```

### 5.3 Check Bob's logs

```bash
docker logs lnd-bob --since=60s 2>&1 | grep -iE "breach|justice|revok|sweep"
```

### 5.4 Check Carol's logs (the cheater)

```bash
docker logs lnd-carol --since=60s 2>&1 | grep -iE "breach|justice|revok|sweep"
```

### 5.5 Mine full CSV delay window

```bash
# Replace 144 with actual csv_delay value from Phase 0
CSV_DELAY=144
mine $CSV_DELAY
```

### 5.6 Compare final wallet balances

**Bob (honest party — should have MORE, recovered his balance + Carol's penalty):**

```bash
bob walletbalance | jq '{confirmed_balance, unconfirmed_balance}'
```

**Carol (cheater — should have LESS, lost everything in the channel):**

```bash
carol walletbalance | jq '{confirmed_balance, unconfirmed_balance}'
```

**Alice (watchtower only — unaffected):**

```bash
alice walletbalance | jq '{confirmed_balance, unconfirmed_balance}'
```

### 5.7 Check Bob's closed channels for BREACH_CLOSE

```bash
bob closedchannels | jq '[.channels[] | select(.close_type == "BREACH_CLOSE") | {
  close_type, channel_point, settled_balance
}]'
```

### 5.8 Check Bob's pending channels (limbo/recovered balance during CSV window)

```bash
bob pendingchannels | jq '.pending_force_closing_channels[] | {
  channel: .channel.channel_point,
  limbo_balance,
  recovered_balance
}'
```

---

## Key Points for Research Presentation

| Concept | What to Show | Phase |
|---------|-------------|-------|
| **Watchtower setup** | Alice runs tower server, Bob registered as client | Phase 0 |
| **Commitment transaction** | Raw hex captured from mempool | Phase 1 |
| **State revocation** | `num_updates` increments with each payment | Phase 3 |
| **The breach attempt** | Carol broadcasts old tx with `sendrawtransaction` | Phase 4 |
| **Watchtower detection** | `grep "breach\|justice"` in Alice's logs | Phase 5 |
| **Economic penalty** | Bob balance ↑, Carol balance → 0 | Phase 5 |

---

## How the Penalty Mechanism Works

1. Each payment transitions the Bob↔Carol channel from **State N → State N+1**
2. Both parties exchange **revocation secrets**, permanently invalidating State N
3. Bob's watchtower (Alice) stores an encrypted **justice transaction** for each revoked state
4. The encryption key is derived from the revoked tx's txid — the watchtower **cannot spy** on normal channel activity
5. When Carol broadcasts a revoked tx, Alice's watchtower detects the matching txid within **1 block**
6. The justice tx sweeps **ALL** channel outputs to Bob — Carol loses **100%** of her channel funds
7. This makes cheating **economically irrational**: expected loss (100% of funds) far exceeds any possible gain

---

## Monitoring Commands (use anytime after Phase 5)

```bash
# Check pending force-close balances on Bob's side
bob pendingchannels | jq '.pending_force_closing_channels'

# Watch Alice's watchtower for justice tx activity
docker logs lnd-alice --follow | grep -iE "breach|justice|sweep"

# List all breach-closed channels on Bob's side
bob closedchannels | jq '[.channels[] | select(.close_type == "BREACH_CLOSE")]'

# Check watchtower session stats on Alice
alice tower info
```
