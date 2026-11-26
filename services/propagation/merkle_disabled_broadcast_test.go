package propagation

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/bsv-blockchain/arcade/models"
)

// Merkle registration is optional. With no merkle client, broadcast still
// runs, and the only terminal statuses this path may write are the ones
// Teranode actually returned. SEEN_ON_NETWORK and MINED stay untouched.

func assertNotSeenOrMined(t *testing.T, ms *mockStore) {
	t.Helper()
	ms.mu.Lock()
	defer ms.mu.Unlock()
	for _, u := range ms.updates {
		if u.Status == models.StatusSeenOnNetwork || u.Status == models.StatusMined || u.Status == models.StatusSeenMultipleNodes {
			t.Errorf("merkle-disabled broadcast wrote %s for %s", u.Status, u.TxID)
		}
	}
}

func TestMerkleDisabled_BroadcastsWithoutWatch(t *testing.T) {
	log := &eventLog{}
	ms := newMockStore()
	teranodeSrv := newTeranodeServer(log, http.StatusOK)
	defer teranodeSrv.Close()

	p := newPropagator("", teranodeSrv.URL, ms)
	if err := handleAndFlush(t, p, makePropMsg("abc123")); err != nil {
		t.Fatalf("flush: %v", err)
	}

	events := log.all()
	if len(events) != 1 || events[0] != "broadcast" {
		t.Fatalf("expected one broadcast and no /watch, got %v", events)
	}
	got := ms.lastUpdateForTxid("abc123")
	if got == nil || got.Status != models.StatusAcceptedByNetwork {
		t.Fatalf("status = %v, want ACCEPTED_BY_NETWORK", got)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleDisabled_RejectedTransaction(t *testing.T) {
	const txid = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	ms := newMockStore()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte("Failed to process transactions:\n" +
			"TX_INVALID (31): [ProcessTransaction][" + txid + "] tx is invalid\n"))
	}))
	defer srv.Close()

	p := newPropagator("", srv.URL, ms)
	if err := handleAndFlush(t, p, makePropMsg(txid)); err != nil {
		t.Fatalf("flush: %v", err)
	}
	got := ms.lastUpdateForTxid(txid)
	if got == nil || got.Status != models.StatusRejected {
		t.Fatalf("status = %v, want REJECTED", got)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleDisabled_DoesNotReportAcceptanceBeforeNetworkAnswers(t *testing.T) {
	release := make(chan struct{})
	started := make(chan struct{})
	var once sync.Once
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		once.Do(func() { close(started) })
		<-release
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()

	ms := newMockStore()
	p := newPropagator("", srv.URL, ms)
	done := make(chan error, 1)
	go func() {
		done <- handleAndFlush(t, p, makePropMsg("delayed-tx"))
	}()

	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("broadcast did not reach the peer")
	}
	if ms.updateCount() != 0 {
		t.Fatalf("status written before the peer answered: %d", ms.updateCount())
	}
	close(release)

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("flush: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("flush did not finish after the peer answered")
	}
	got := ms.lastUpdateForTxid("delayed-tx")
	if got == nil || got.Status != models.StatusAcceptedByNetwork {
		t.Fatalf("status = %v, want ACCEPTED_BY_NETWORK", got)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleDisabled_UnavailablePeerDoesNotAccept(t *testing.T) {
	ms := newMockStore()
	p := newPropagator("", "http://127.0.0.1:1", ms)
	if err := handleAndFlush(t, p, makePropMsg("unreachable")); err != nil {
		t.Fatalf("flush: %v", err)
	}
	if got := ms.lastUpdateForTxid("unreachable"); got != nil {
		t.Fatalf("unavailable peer wrote %s", got.Status)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleDisabled_DuplicateSubmitStaysAccepted(t *testing.T) {
	log := &eventLog{}
	ms := newMockStore()
	teranodeSrv := newTeranodeServer(log, http.StatusOK)
	defer teranodeSrv.Close()
	p := newPropagator("", teranodeSrv.URL, ms)

	payload := makePropMsg("dup-tx")
	if err := handleAndFlush(t, p, payload); err != nil {
		t.Fatalf("first flush: %v", err)
	}
	if err := handleAndFlush(t, p, payload); err != nil {
		t.Fatalf("second flush: %v", err)
	}
	got := ms.lastUpdateForTxid("dup-tx")
	if got == nil || got.Status != models.StatusAcceptedByNetwork {
		t.Fatalf("status = %v, want ACCEPTED_BY_NETWORK", got)
	}
	assertNotSeenOrMined(t, ms)
	if events := log.all(); len(events) < 2 {
		t.Fatalf("expected both submits to broadcast, got %v", events)
	}
}

func TestMerkleDisabled_MissingParentIsNotRejection(t *testing.T) {
	const (
		child  = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
		parent = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
	)
	ms := newMockStore()
	body := missingParentBody(missingParentLineFor(child, parent))
	srv := missingParentServer(&eventLog{}, body)
	defer srv.Close()

	p := newPropagator("", srv.URL, ms)
	if err := handleAndFlush(t, p, makePropMsg(child)); err != nil {
		t.Fatalf("flush: %v", err)
	}
	if got := ms.lastUpdateForTxid(child); got != nil && (got.Status == models.StatusRejected || got.Status == models.StatusAcceptedByNetwork) {
		t.Fatalf("missing parent became %s", got.Status)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleDisabled_AmbiguousPeerDoesNotAccept(t *testing.T) {
	ms := newMockStore()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	p := newPropagator("", srv.URL, ms)
	if err := handleAndFlush(t, p, makePropMsg("ambiguous")); err != nil {
		t.Fatalf("flush: %v", err)
	}
	if got := ms.lastUpdateForTxid("ambiguous"); got != nil {
		t.Fatalf("ambiguous peer wrote %s", got.Status)
	}
	assertNotSeenOrMined(t, ms)
}

func TestMerkleEnabled_WatchFailureDoesNotBroadcast(t *testing.T) {
	log := &eventLog{}
	ms := newMockStore()
	merkleSrv := newMerkleServer(log, http.StatusServiceUnavailable)
	defer merkleSrv.Close()
	teranodeSrv := newTeranodeServer(log, http.StatusOK)
	defer teranodeSrv.Close()

	p := newPropagator(merkleSrv.URL, teranodeSrv.URL, ms)
	if err := handleAndFlush(t, p, makePropMsg("watched")); err != nil {
		t.Fatalf("flush: %v", err)
	}
	for _, ev := range log.all() {
		if ev == "broadcast" {
			t.Fatal("broadcast ran after /watch failed")
		}
	}
	if got := ms.lastUpdateForTxid("watched"); got != nil && got.Status == models.StatusAcceptedByNetwork {
		t.Fatal("watch failure was stored as network acceptance")
	}
}

func TestMerkleDisabled_RegisterBatchPassesThrough(t *testing.T) {
	p := newPropagator("", "http://127.0.0.1:1", newMockStore())
	batch := []propagationMsg{{TXID: "a"}, {TXID: "b"}}
	registered, failed := p.registerBatch(context.Background(), batch)
	if len(failed) != 0 || len(registered) != 2 {
		t.Fatalf("registered=%d failed=%d", len(registered), len(failed))
	}
}
