package errorlog

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
)

// TimeoutEntry represents a probe timeout event (Prober waiting for ACKs).
type TimeoutEntry struct {
	Type        string  `json:"type"`         // "timeout"
	Timestamp   string  `json:"ts"`           // ISO8601
	SrcGID      string  `json:"src_gid"`
	DstGID      string  `json:"dst_gid"`
	SrcDev      string  `json:"src_dev"`
	DstDev      string  `json:"dst_dev"`
	SrcHost     string  `json:"src_host"`
	DstHost     string  `json:"dst_host"`
	SrcIP       string  `json:"src_ip"`
	DstIP       string  `json:"dst_ip"`
	ProbeType   string  `json:"probe_type"`
	Seq         uint64  `json:"seq"`
	RttUs       float64 `json:"rtt_us"`       // -1 if unknown (timeout)
	AckReceived int     `json:"ack_received"` // 0, 1, or 2
	AckTotal    int     `json:"ack_total"`    // always 2
}

// UnmatchedSendWCEntry represents a send completion whose WR-ID was not found in pendingSendChans.
type UnmatchedSendWCEntry struct {
	Type      string `json:"type"`  // "unmatched_send_wc"
	Timestamp string `json:"ts"`    // ISO8601
	Dev       string `json:"dev"`   // device name
	GID       string `json:"gid"`
	IP        string `json:"ip"`
	QPN       uint32 `json:"qpn"`
	WRID      uint64 `json:"wr_id"`
	Host      string `json:"host"`
}

// AckSendTimeoutEntry represents an ACK send timeout (Responder failing to send ACK).
type AckSendTimeoutEntry struct {
	Type      string `json:"type"`       // "ack_send_timeout"
	Timestamp string `json:"ts"`         // ISO8601
	AckType   int    `json:"ack_type"`   // 1=first ACK, 2=second ACK
	SrcGID    string `json:"src_gid"`    // responder (local)
	DstGID    string `json:"dst_gid"`    // prober (remote)
	SrcDev    string `json:"src_dev"`
	DstDev    string `json:"dst_dev"`   // may be empty
	SrcHost   string `json:"src_host"`
	DstHost   string `json:"dst_host"`  // may be empty
	SrcIP     string `json:"src_ip"`
	DstIP     string `json:"dst_ip"`
	Seq       uint64 `json:"seq"`
}

// Logger writes error events (e.g. timeouts) to a dedicated file with rotation.
type Logger struct {
	path       string
	maxSizeMB  int
	maxBackups int
	file       *os.File
	size       int64
	mu         sync.Mutex
	enabled    bool
}

// New creates an error logger. If path is empty or enabled is false, returns nil (no-op).
func New(path string, enabled bool, maxSizeMB, maxBackups int) (*Logger, error) {
	if !enabled || path == "" {
		return nil, nil
	}
	absPath, err := filepath.Abs(path)
	if err != nil {
		return nil, err
	}
	dir := filepath.Dir(absPath)
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, err
	}
	f, err := os.OpenFile(absPath, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0644)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	l := &Logger{
		path:       absPath,
		maxSizeMB:  maxSizeMB,
		maxBackups: maxBackups,
		file:       f,
		size:       info.Size(),
		enabled:    true,
	}
	log.Info().
		Str("path", absPath).
		Int("max_size_mb", maxSizeMB).
		Int("max_backups", maxBackups).
		Msg("Error log (timeouts) enabled")
	return l, nil
}

// WriteTimeout writes a timeout entry as a JSON line.
func (l *Logger) WriteTimeout(e *TimeoutEntry) {
	if l == nil || !l.enabled {
		return
	}
	e.Type = "timeout"
	e.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	data, err := json.Marshal(e)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to marshal timeout entry")
		return
	}
	line := append(data, '\n')
	l.mu.Lock()
	defer l.mu.Unlock()
	n, err := l.file.Write(line)
	if err != nil {
		log.Warn().Err(err).Str("path", l.path).Msg("Failed to write error log")
		return
	}
	l.size += int64(n)
	if l.maxSizeMB > 0 && l.size >= int64(l.maxSizeMB)*1024*1024 {
		l.rotate()
	}
}

// WriteAckSendTimeout writes an ACK send timeout entry (Responder side).
func (l *Logger) WriteAckSendTimeout(e *AckSendTimeoutEntry) {
	if l == nil || !l.enabled {
		return
	}
	e.Type = "ack_send_timeout"
	e.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	data, err := json.Marshal(e)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to marshal ack_send_timeout entry")
		return
	}
	line := append(data, '\n')
	l.mu.Lock()
	defer l.mu.Unlock()
	n, err := l.file.Write(line)
	if err != nil {
		log.Warn().Err(err).Str("path", l.path).Msg("Failed to write error log")
		return
	}
	l.size += int64(n)
	if l.maxSizeMB > 0 && l.size >= int64(l.maxSizeMB)*1024*1024 {
		l.rotate()
	}
}

// WriteUnmatchedSendWC writes an unmatched send WC entry (agent_errors).
func (l *Logger) WriteUnmatchedSendWC(e *UnmatchedSendWCEntry) {
	if l == nil || !l.enabled {
		return
	}
	e.Type = "unmatched_send_wc"
	e.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	data, err := json.Marshal(e)
	if err != nil {
		log.Warn().Err(err).Msg("Failed to marshal unmatched_send_wc entry")
		return
	}
	line := append(data, '\n')
	l.mu.Lock()
	defer l.mu.Unlock()
	n, err := l.file.Write(line)
	if err != nil {
		log.Warn().Err(err).Str("path", l.path).Msg("Failed to write error log")
		return
	}
	l.size += int64(n)
	if l.maxSizeMB > 0 && l.size >= int64(l.maxSizeMB)*1024*1024 {
		l.rotate()
	}
}

func (l *Logger) rotate() {
	l.file.Close()
	// Rotate: remove path.N, then path.(N-1) -> path.N, ..., path.1 -> path.2, path -> path.1
	for i := l.maxBackups; i >= 1; i-- {
		oldPath := l.path
		if i > 1 {
			oldPath = l.path + "." + strconv.Itoa(i-1)
		}
		newPath := l.path + "." + strconv.Itoa(i)
		if i == l.maxBackups {
			os.Remove(newPath)
		}
		os.Rename(oldPath, newPath)
	}
	f, err := os.OpenFile(l.path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0644)
	if err != nil {
		log.Error().Err(err).Str("path", l.path).Msg("Failed to recreate error log after rotate")
		return
	}
	l.file = f
	l.size = 0
}

// Close closes the error log file.
func (l *Logger) Close() error {
	if l == nil || l.file == nil {
		return nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	return l.file.Close()
}
