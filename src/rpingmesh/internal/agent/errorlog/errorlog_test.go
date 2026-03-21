package errorlog

import (
	"bufio"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTimeoutEntryJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "agent_errors.log")
	l, err := New(path, true, 20, 3)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer l.Close()

	e := &TimeoutEntry{
		SrcGID:      "::ffff:10.106.1.1",
		DstGID:      "::ffff:10.106.9.6",
		SrcDev:      "mlx5_0",
		DstDev:      "mlx5_0",
		SrcHost:     "node001",
		DstHost:     "node009",
		SrcIP:       "10.106.1.1",
		DstIP:       "10.106.9.6",
		ProbeType:   "TOR_MESH",
		Seq:         2010877,
		RttUs:       -1,
		AckReceived: 0,
		AckTotal:    2,
	}
	l.WriteTimeout(e)

	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if !sc.Scan() {
		t.Fatal("Expected one line")
	}
	line := sc.Text()
	if !strings.Contains(line, `"type":"timeout"`) {
		t.Errorf("Expected type=timeout, got %s", line)
	}
	if !strings.Contains(line, `"src_gid":"::ffff:10.106.1.1"`) {
		t.Errorf("Expected src_gid, got %s", line)
	}
	if !strings.Contains(line, `"dst_gid":"::ffff:10.106.9.6"`) {
		t.Errorf("Expected dst_gid, got %s", line)
	}
	if !strings.Contains(line, `"rtt_us":-1`) {
		t.Errorf("Expected rtt_us=-1, got %s", line)
	}
}

func TestAckSendTimeoutEntryJSON(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "agent_errors.log")
	l, err := New(path, true, 20, 3)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer l.Close()

	// ack_type=1: first ACK send timeout (responder -> prober)
	e1 := &AckSendTimeoutEntry{
		AckType: 1,
		SrcGID:  "::ffff:10.106.22.8",
		DstGID:  "::ffff:10.106.30.5",
		SrcDev:  "mlx5_5",
		SrcHost: "node024",
		SrcIP:   "10.106.22.8",
		DstIP:   "10.106.30.5",
		Seq:     2007295,
	}
	l.WriteAckSendTimeout(e1)

	// ack_type=2: second ACK send timeout
	e2 := &AckSendTimeoutEntry{
		AckType: 2,
		SrcGID:  "::ffff:10.106.22.8",
		DstGID:  "::ffff:10.106.30.5",
		SrcDev:  "mlx5_5",
		SrcHost: "node024",
		SrcIP:   "10.106.22.8",
		DstIP:   "10.106.30.5",
		Seq:     2007296,
	}
	l.WriteAckSendTimeout(e2)

	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)

	// Line 1: ack_type=1
	if !sc.Scan() {
		t.Fatal("Expected line 1")
	}
	line1 := sc.Text()
	if !strings.Contains(line1, `"type":"ack_send_timeout"`) {
		t.Errorf("line1: expected type=ack_send_timeout, got %s", line1)
	}
	if !strings.Contains(line1, `"ack_type":1`) {
		t.Errorf("line1: expected ack_type=1, got %s", line1)
	}
	if !strings.Contains(line1, `"src_gid":"::ffff:10.106.22.8"`) {
		t.Errorf("line1: expected src_gid, got %s", line1)
	}
	if !strings.Contains(line1, `"dst_gid":"::ffff:10.106.30.5"`) {
		t.Errorf("line1: expected dst_gid, got %s", line1)
	}
	if !strings.Contains(line1, `"src_dev":"mlx5_5"`) {
		t.Errorf("line1: expected src_dev, got %s", line1)
	}
	if !strings.Contains(line1, `"src_host":"node024"`) {
		t.Errorf("line1: expected src_host, got %s", line1)
	}
	if !strings.Contains(line1, `"seq":2007295`) {
		t.Errorf("line1: expected seq=2007295, got %s", line1)
	}

	// Line 2: ack_type=2
	if !sc.Scan() {
		t.Fatal("Expected line 2")
	}
	line2 := sc.Text()
	if !strings.Contains(line2, `"ack_type":2`) {
		t.Errorf("line2: expected ack_type=2, got %s", line2)
	}
	if !strings.Contains(line2, `"seq":2007296`) {
		t.Errorf("line2: expected seq=2007296, got %s", line2)
	}
}

// TestMixedTypesInSameLog 验证 timeout 和 ack_send_timeout 可以共存于同一日志文件
func TestMixedTypesInSameLog(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "agent_errors.log")
	l, err := New(path, true, 20, 3)
	if err != nil {
		t.Fatalf("New: %v", err)
	}
	defer l.Close()

	l.WriteTimeout(&TimeoutEntry{
		SrcGID: "::ffff:10.106.1.1", DstGID: "::ffff:10.106.9.6",
		SrcDev: "mlx5_0", DstDev: "mlx5_0",
		SrcHost: "node001", DstHost: "node009",
		SrcIP: "10.106.1.1", DstIP: "10.106.9.6",
		ProbeType: "TOR_MESH", Seq: 1000, RttUs: -1, AckReceived: 0, AckTotal: 2,
	})
	l.WriteAckSendTimeout(&AckSendTimeoutEntry{
		AckType: 1,
		SrcGID:  "::ffff:10.106.22.8", DstGID: "::ffff:10.106.30.5",
		SrcDev: "mlx5_5", SrcHost: "node024",
		SrcIP: "10.106.22.8", DstIP: "10.106.30.5",
		Seq: 2000,
	})

	f, err := os.Open(path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	var lines []string
	for sc.Scan() {
		lines = append(lines, sc.Text())
	}
	if len(lines) != 2 {
		t.Fatalf("Expected 2 lines, got %d", len(lines))
	}
	if !strings.Contains(lines[0], `"type":"timeout"`) {
		t.Errorf("line0: expected type=timeout, got %s", lines[0])
	}
	if !strings.Contains(lines[1], `"type":"ack_send_timeout"`) {
		t.Errorf("line1: expected type=ack_send_timeout, got %s", lines[1])
	}
}
