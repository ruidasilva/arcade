# Isolated Merkle Stage-2 qualification

This note records an isolated qualification of the Stage-2 topology. It does
not enable Merkle in production, does not change the production host, and
does not authorise a later gate.

The first blocked run is kept below, unchanged. A later lifecycle run is
recorded in [Lifecycle run](#lifecycle-run).

The governing design is the Votari Stage-2 architecture and execution plan
dated 2026-10-01. This stack follows that design:

- Arcade is one container, `--mode all`.
- The store is Pebble on a volume used only by that container.
- Merkle Service is a separate container.
- Kafka is a separate container on the same private network.
- The callback URL is `http://votari-arcade:8080/api/v1/merkle-service/callback`.
- That hostname is the Compose service on the private network. It is not the public Arcade name.
- The callback port and the Merkle port are not published to the host.
- Merkle is started with private-IP callback support enabled. The published Merkle image leaves that support off unless it is set.
- Arcade holds two distinct synthetic bearers. One is presented to Merkle. One is required on the callback.
- No production secret, volume, broker, or network is used.

## Topology

```text
votari-arcade (--mode all, Pebble)
    |  private network votari-stage2-isolated
    |  POST /watch  Authorization: Bearer <synthetic merkle auth>
    v
votari-stage2-merkle
    |  callback URL above, Authorization: Bearer <synthetic callback bearer>
    v
votari-arcade /api/v1/merkle-service/callback

votari-stage2-kafka is the only broker. Merkle uses its own Postgres.
Neither Arcade nor Merkle publishes a host port.
```

Compose project: `compose/stage2-isolated/docker-compose.yml`.

Registration remains the current Arcade contract: propagation calls Merkle
`/watch` and only then broadcasts the transactions that registered. A failed
registration is not broadcast. This qualification did not submit a
transaction, so that order was not observed live.

## Image provenance

Arcade is built with `scripts/provenance-build.sh` and is not pushed. The
local image reference is `arcade:provenance`. `local_image_id` is the local
image ID. It is not a registry manifest digest. The registry digest for this
qualification is none.

Observed on the isolated qualification run
`36978016885` (2026-10-02):

```text
SOURCE_SHA=e6aab82f0f3c1cd7cf3f9985e9e06ee39fb5e162
OCI_REVISION=e6aab82f0f3c1cd7cf3f9985e9e06ee39fb5e162
OCI_SOURCE=https://github.com/ruidasilva/arcade
OCI_CREATED=2026-10-02T07:20:54Z
OCI_VERSION=stage2-isolated-qualification
GO_VCS_REVISION=e6aab82f0f3c1cd7cf3f9985e9e06ee39fb5e162
GO_VCS_MODIFIED=false
LOCAL_IMAGE_ID=sha256:9d4a19aa005c239c6af0c171e0bb76dceb13f0525086e4d283bd95f2e571ae1c
REGISTRY_MANIFEST_DIGEST=none
SBOM=sbom.spdx.json SPDX-2.3 name=arcade packages=305
SBOM_SHA256=27eca7d0df554d3fb949b582e50a3b21e1d3c6a8c4a9d733d22bc822cef394ae
RELEASE_MANIFEST=release-manifest.json source_clean=true
```

The Merkle container is the digest already pinned by the Arcade end-to-end
harness:

```text
ghcr.io/bsv-blockchain/merkle-service@sha256:ff4ae409df2680c54267c27887dc1744fb3b64e5ddc5636882185ce82b35ced3
```

That digest is merkle-service v0.2.5. It does not implement the
`expectedSubtreeIndices` producer contract, which requires merkle-service
v0.4.5 or newer.

## Synthetic secrets

| Direction | Config field | Fixture prefix |
| --- | --- | --- |
| Arcade to Merkle | `merkle_service.auth_token` | `synthetic-stage2-merkle-auth-` |
| Merkle to Arcade | `callback_token` | `synthetic-stage2-callback-` |
| Merkle database | Postgres password | `synthetic-stage2-merkle-db` |

The two bearers differ. The probe refuses a callback fixture that does not
use the `synthetic-stage2-` prefix. Logs are scanned for both bearers and
the run fails if either appears. The fixture values live only in the
isolated Compose config. They are not production secrets.

## What this environment can prove

The probe joins the private network. Run `36978016885` recorded:

```text
PRIVATE_CALLBACK_HOST_PORT=unpublished
MERKLE_HOST_PORT=unpublished
ARCADE_HEALTH=200
MERKLE_HEALTH=200
CALLBACK_MISSING_BEARER=401
CALLBACK_WRONG_BEARER=401
CALLBACK_CORRECT_BEARER=200
SECRET_IN_LOGS=absent
RESTART_HEALTH=200
RESTART_CORRECT_BEARER=200
```

Arcade logged `starting arcade` with `mode=all`, `kafka_backend=sarama`,
and `store_backend=pebble`, then listened on `0.0.0.0:8080` inside the
network. Both accepted callbacks were `SEEN_ON_NETWORK` for one unknown
synthetic txid. Arcade logged `dropping callback for unknown txid` and did
not create a lifecycle row. The same drop was logged again after restart.
No `MINED` line was logged.

Restart replayed the Pebble WAL (`replayed 10 keys`). Those keys are the
embedded chaintracks store, not a tracked transaction. No transaction was
pending, so this restart does not prove retention of a tracked row.

The accepted call proves authentication. It does not prove a lifecycle
transition.

## What this environment cannot prove

No synthetic transaction was submitted. There is no regtest chain and no
DataHub in this stack, so Arcade cannot move a transaction through broadcast
and mining. The pinned Merkle image cannot emit `expectedSubtreeIndices`.
There is no fault hook that fails a Pebble write on the first SEEN callback
or fails `SetMinedByTxIDs` once.

`--mode all` also starts embedded chaintracks. With `network: teratestnet`
that process dialed the built-in teratestnet bootstrap peers and logged that
those peers connected. `p2p.datahub_discovery` was off. That dial is not the
production host and it is not a production change. A later isolated run that
must stay off public peers needs an explicit empty bootstrap, which this
qualification did not add.

Observed lifecycle states: none.

| Gate | Result | Why |
| --- | --- | --- |
| Tracked subtree supplies `expectedSubtreeIndices`, and a missing STUMP leaves `processed_at` unset | BLOCKED | Merkle image is v0.2.5 and no tracked block was produced |
| True empty block has no expected set and may finalize | BLOCKED | No empty block was produced |
| SEEN store failure returns HTTP 500, then a retry applies once | BLOCKED | No store-fault injection in the isolated process. The durability tests in this tree cover that contract in process |
| `SetMinedByTxIDs` failure leaves `processed_at` unset and the watchdog later persists MINED | BLOCKED | No mined block and no mine-fault injection |
| Restart keeps a pending tracked transaction, does not regress it, and does not publish a second terminal status | BLOCKED | No tracked transaction existed. The probe only shows the process accepts the same bearer after restart |

`EXPECTED_SUBTREE_INDICES_CONTRACT` is BLOCKED. `MINED_WATCHDOG_RECOVERY` is
BLOCKED. Neither result authorises production Stage-2.

## Remaining production-only gates

From the Stage-2 execution plan, still closed:

- provenance-ready image in the production registry, including a Merkle image at v0.4.5 or newer with an immutable digest;
- production secrets in the secret store, distinct from these fixtures;
- production callback preflight on the production host;
- production read-only preflight;
- enabling Merkle registration;
- a fresh production synthetic transaction;
- rollback readiness.

This qualification does not open those gates.

## Lifecycle run

Run `36983458658` (2026-10-02) is the first isolated run that moved a
synthetic transaction through Merkle to `MINED`. It does not replace the
blocked run above.

The idle Compose stack and the lifecycle process are different. Compose
starts the provenance image, proves the private callback, and then stops.
The lifecycle runs in the end-to-end harness from the same commit: Merkle
v0.4.5 in a container, an in-process libp2p host, and an in-process
synthetic DataHub. The provenance container is not the process that mined.

### Merkle image

`expectedSubtreeIndices` is present in merkle-service v0.4.5
(`internal/callback/delivery.go`, attached from the tracked subtree set in
`emitBlockProcessedCallbacks`). That is the minimum release used here.
v0.4.5 is a single linux/amd64 manifest. The pin is the manifest digest,
not the tag. The end-to-end default pin stays on v0.2.5. Production Merkle
configuration is unchanged.

The v0.4.5 environment surface used by this stack matches the existing
harness: mode, SQL store, Kafka, regtest with DHT off, and explicit
private-IP callback and DataHub flags. No new setting was required.
`BLOB_STORE_URL` stays quoted as `"memory:"`.

```text
MERKLE_VERSION=v0.4.5
MERKLE_IMAGE_DIGEST=sha256:8393a456cac5f5bf24537b519d82a4d96fded0b43005fa0412a7545e43ecf168
EXPECTED_SUBTREE_INDICES_SUPPORTED=YES
```

### Local chain

The chain is the harness synthetic regtest path, not a new node. Regtest
has no built-in public bootstrap peers. The block is fabricated with
`BuildSyntheticBlock` (seven synthetic transactions plus a coinbase, one
subtree) and announced by the harness libp2p host. Merkle fetches the block
and subtree from the harness DataHub. A coinbase-only block is built with
`BuildEmptySyntheticBlock`.

v0.4.5 leaves the coinbase placeholder in the STUMP. The synthetic block
now carries the coinbase left-spine proof so Arcade can fold that
placeholder into the header root. Without it, the compound root stayed the
placeholder tree and Arcade refused to persist `MINED`.

```text
LOCAL_CHAIN_BACKEND=synthetic regtest harness
LOCAL_CHAIN_ISOLATION=regtest, synthetic keys, no public chain
BLOCK_PRODUCTION=harness libp2p announcement of a fabricated block
MERKLE_CHAIN_CONNECTION=P2P regtest, DHT off, harness DataHub
```

### Public peers

Compose sets `network: regtest`, `chaintracks_server.enabled: false`,
`p2p.dht_mode: off`, and an empty bootstrap list. The probe found no
`bsvb.tech` or `dnsaddr` dial in the Compose logs.

```text
EXTERNAL_BOOTSTRAP_CONNECTIONS=0
```

The lifecycle process enables chaintracks and points it only at the harness
loopback peer. Its bootstrap list is empty. One isolated peer does not emit
`SEEN_MULTIPLE_NODES`. That status was not observed.

### Registration

Txid `d740b91e7aa578ef30cdba66d9ace3bf1eaf590522788e4ba1fa23dce6407abe`.

The harness held the DataHub broadcast until Merkle `GET /api/lookup/<txid>`
showed the callback URL. Arcade logged `registered with merkle-service` at
`2026-10-02T08:24:24.854Z` and `transactions accepted by network` at
`2026-10-02T08:24:24.857Z`. The lookup callback path was
`/api/v1/merkle-service/callback`.

```text
MERKLE_REGISTRATION=PASS
```

The lifecycle callback host is the harness proxy (`host.docker.internal`),
not `votari-arcade`. The Compose callback remains
`http://votari-arcade:8080/api/v1/merkle-service/callback`, with both ports
unpublished. Probe authentication on that route:

```text
PRIVATE_CALLBACK_HOST_PORT=unpublished
MERKLE_HOST_PORT=unpublished
CALLBACK_MISSING_BEARER=401
CALLBACK_WRONG_BEARER=401
CALLBACK_CORRECT_BEARER=200
SECRET_IN_LOGS=absent
```

### expectedSubtreeIndices

Block `7051d0e33e52cd291ded10b5d2832f2cc0aea9513c362e930702819743f3ee61`
contained the tracked transactions. Its `BLOCK_PROCESSED` body included
`expectedSubtreeIndices: [0]`. The harness withheld that STUMP. At
`2026-10-02T08:24:28.220Z` the bump builder logged the missing index 0 and
did not finalize. `processedAt` was still empty.

After the STUMP was delivered, at `2026-10-02T08:24:29.794Z` the builder
logged the expected set complete (1 of 1) and skipped the grace window.

The coinbase-only block
`5e0ca2c9477aa18bdf8af7de485a42ea88adb9b834f91952283b3d2294374ae6` did not
carry `expectedSubtreeIndices`. The builder treated it as zero STUMPs. Its
processing status moved from 404 to 200, and `processedAt` was set.

```text
EXPECTED_SUBTREE_INDICES_CONTRACT=PASS
```

### Observed lifecycle

Polled statuses, in order: `RECEIVED`, `ACCEPTED_BY_NETWORK`,
`SEEN_ON_NETWORK`, `MINED`. `SENT_TO_NETWORK` was not seen by the poll.
`SEEN_MULTIPLE_NODES` was not emitted.

```text
2026-10-02T08:24:24.798Z  RECEIVED
2026-10-02T08:24:24.857Z  ACCEPTED_BY_NETWORK
2026-10-02T08:24:27.718Z  SEEN_ON_NETWORK
2026-10-02T08:24:27.720Z  BLOCK_PROCESSED (STUMP withheld, processedAt unset)
2026-10-02T08:24:29.783Z  STUMP stored (subtree 0)
2026-10-02T08:24:29.798Z  MINED (7 transactions, height 1)
```

`MINED` is the durable status of the tracked txid on that block.

### Restart

Arcade was restarted after the withheld-STUMP `BLOCK_PROCESSED` and before
the STUMP was delivered. Chaintracks reopened at height 1. The tracker
reloaded 7 transactions. The Merkle watch for the tracked txid was still
present. `processedAt` was still empty. A replay of the same
`BLOCK_PROCESSED` after `MINED` left the status `MINED` on the same block.
The poll recorded `MINED` once. A second same-block mine write at
`2026-10-02T08:24:30.019Z` did not add a second status observation.

```text
RESTART_RECOVERY=PASS
```

### Fault injection

No runtime fault hook was added. A production binary must not gain a debug
endpoint for this test. The SEEN HTTP 500 retry and the `SetMinedByTxIDs`
`store_failed` path stay covered by the in-process durability tests.

The missing-STUMP case above was recovered by an explicit Merkle
`/reprocess`, which is the call the watchdog would make. The in-process
watchdog timer was not running, and a failed `SetMinedByTxIDs` was not
injected.

```text
RUNTIME_FAULT_INJECTION=NOT_IMPLEMENTED
SEEN_CALLBACK_RETRY=BLOCKED
MINED_WATCHDOG_RECOVERY=BLOCKED
```

### Provenance

The image and the harness that executed this run are the same commit.
`local_image_id` is not a registry digest. The image was not pushed.

```text
ARCADE_IMAGE_SOURCE_SHA=d127b6fd06f9242d350d181a595a438f7973cff7
QUALIFICATION_HARNESS_SHA=d127b6fd06f9242d350d181a595a438f7973cff7
OCI_REVISION=d127b6fd06f9242d350d181a595a438f7973cff7
OCI_SOURCE=https://github.com/ruidasilva/arcade
OCI_CREATED=2026-10-02T08:21:11Z
GO_VCS_REVISION=d127b6fd06f9242d350d181a595a438f7973cff7
GO_VCS_MODIFIED=false
LOCAL_IMAGE_ID=sha256:473db83867b82663d48320676db2443c49c2039b576915312afc924c8dbe9c88
REGISTRY_MANIFEST_DIGEST=none
SBOM=sbom.spdx.json SPDX-2.3 name=arcade packages=305
SBOM_SHA256=0fb09d4ecc82597e6a1bc290c445ba000be552e9465eb586ea19afe6a7a82b1f
MERKLE_VERSION=v0.4.5
MERKLE_IMAGE_DIGEST=sha256:8393a456cac5f5bf24537b519d82a4d96fded0b43005fa0412a7545e43ecf168
```

`go test -count=1 ./...` passed on this tree. That command does not compile
the `e2e` build tag. The lifecycle test passed separately as
`TestStage2_IsolatedLifecycle` in run `36983458658`.

### Verdict

```text
ARCADE MERKLE STAGE2 ISOLATED QUALIFICATION: PASS
```

`PASS` means one tracked synthetic transaction reached `MINED` on the
isolated chain. It does not enable production Merkle. The SEEN retry and
the mined-store watchdog were not injected at runtime. The production gates
from the first run stay closed.
