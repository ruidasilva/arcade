# Broadcasting without a local Merkle service

Votari's target is to broadcast EF transactions and record network
acceptance without operating a Merkle service. Mining proofs are a later
read. They do not sit on the broadcast path.

This is the existing Arcade toggle, not a second mode. `app` builds a
Merkle client only when `merkle_service.url` is set. With that URL empty,
`registerBatch` does not call `/watch` and does not write a status.
Propagation then broadcasts to Teranode.

## What the network response means

| Teranode result | Stored status |
| --- | --- |
| Peer accepts the transaction | `ACCEPTED_BY_NETWORK` |
| Peer rejects that transaction | `REJECTED` |
| Peer is unreachable, or the body does not identify a verdict | No acceptance and no rejection. The row retries. |
| Parent is not yet visible | Not rejected. The child retries. |

`SEEN_ON_NETWORK`, `MINED`, and `merklePath` are not filled in by this
path. A deployment with an empty Merkle URL cannot turn a skipped
`/watch` into acceptance or into a mining confirmation.

The submit API is unchanged. `POST /tx` still returns the existing
acceptance body with `txStatus` `RECEIVED`. `GET /tx/:txid` later returns
the stored status. GoBA's mempool gate and GoFD's EF submit continue to
use that pair. A duplicate submit still returns the status already stored.

## Merkle-enabled deployments

Other operators keep today's behaviour. When `merkle_service.url` and
`callback_url` are both set, `/watch` still has to succeed before that
transaction is broadcast. A failed registration is retried. It is not
stored as `ACCEPTED_BY_NETWORK`.

## Proofs after acceptance

Votari fetches a transaction-specific Merkle proof only after broadcast,
and only from a provider it does not have to keep alive for submission:

1. Wait until the transaction is in a block. That observation can come
   from the external indexer or, when bump-builder is still running, from
   Arcade seeing the transaction in a processed block. A bump-builder
   `MINED` row means this Arcade saw the transaction in a block. It does
   not attach `merklePath`.
2. Request the Merkle path for that txid from an external indexer
   (WhatsOnChain or the public Merkle service endpoint for the network).
   Arcade does not call that provider during `POST /tx`.
3. Store or present the path beside the transaction. An empty `merklePath`
   on `GET /tx` means the proof has not been fetched. It does not mean the
   broadcast failed, and it does not mean the transaction is mined.

Callback delivery stays available for operators who do run Merkle.
Votari does not point `merkle_service.url` at a local service, so those
callbacks are not part of its broadcast path.
