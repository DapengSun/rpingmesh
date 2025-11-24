package controller_client

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/rs/zerolog/log"
	"github.com/yuuki/rpingmesh/internal/rdma"
	"github.com/yuuki/rpingmesh/proto/controller_agent"
	"google.golang.org/grpc"
	"google.golang.org/grpc/connectivity"
	"google.golang.org/grpc/credentials/insecure"
)

// ControllerClient is a client for the controller service
type ControllerClient struct {
	addr   string
	conn   *grpc.ClientConn
	client controller_agent.ControllerServiceClient
	mu     sync.Mutex // [NEW] Protects conn and client during reconnection
}

// NewControllerClient creates a new controller client
func NewControllerClient(addr string) *ControllerClient {
	return &ControllerClient{
		addr: addr,
	}
}

// Connect connects to the controller service
func (c *ControllerClient) Connect() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	// [NEW] If already connected and ready, return (enhanced connection state check)
	if c.conn != nil {
		state := c.conn.GetState()
		if state == connectivity.Ready || state == connectivity.Idle {
			return nil
		}
		// [NEW] Connection exists but not ready, close it and reconnect
		if err := c.conn.Close(); err != nil {
			log.Warn().Err(err).Str("feature", "connection_recovery").Msg("[NEW] Error closing existing connection during reconnect")
		}
		c.conn = nil
		c.client = nil
	}

	// Establish connection without TLS for now
	// In production, should use TLS credentials
	conn, err := grpc.NewClient(
		"dns:///"+c.addr,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		return fmt.Errorf("failed to create client for controller at %s: %w", c.addr, err)
	}

	// Initiate connection with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	// Start connection process
	conn.Connect()

	// Wait for connection to be ready
	for {
		state := conn.GetState()
		if state == connectivity.Ready {
			break
		}
		if !conn.WaitForStateChange(ctx, state) {
			conn.Close()
			return fmt.Errorf("connection to controller at %s failed to become ready within timeout", c.addr)
		}
	}

	c.conn = conn
	c.client = controller_agent.NewControllerServiceClient(conn)
	log.Info().Str("addr", c.addr).Msg("Connected to controller")

	return nil
}

// Close closes the connection to the controller
func (c *ControllerClient) Close() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.conn != nil {
		if err := c.conn.Close(); err != nil {
			return err
		}
		c.conn = nil
		c.client = nil
	}

	return nil
}

// ensureConnected checks if the connection is ready and reconnects if necessary
// [NEW] This is a new method added for automatic connection recovery
func (c *ControllerClient) ensureConnected() error {
	c.mu.Lock()

	// [NEW] If not connected, unlock and connect
	if c.conn == nil || c.client == nil {
		c.mu.Unlock()
		return c.Connect()
	}

	// [NEW] Check connection state
	state := c.conn.GetState()
	if state == connectivity.Ready || state == connectivity.Idle {
		c.mu.Unlock()
		return nil
	}

	// [NEW] Connection is not ready, need to reconnect
	log.Warn().
		Str("feature", "connection_recovery").
		Str("state", state.String()).
		Str("addr", c.addr).
		Msg("[NEW] Controller connection not ready, attempting to reconnect")

	// [NEW] Close existing connection
	if err := c.conn.Close(); err != nil {
		log.Warn().Err(err).Str("feature", "connection_recovery").Msg("[NEW] Error closing connection during reconnect")
	}
	c.conn = nil
	c.client = nil
	c.mu.Unlock()

	// [NEW] Call Connect (which will lock again)
	return c.Connect()
}

// RegisterAgent registers the agent with the controller
func (c *ControllerClient) RegisterAgent(
	agentID string,
	hostName string,
	agentIP string,
	rnics []*rdma.RNIC,
) error {
	// [NEW] Ensure connection is ready before making request (automatic reconnection)
	if err := c.ensureConnected(); err != nil {
		return fmt.Errorf("failed to ensure connection to controller: %w", err)
	}

	// [NEW] Thread-safe client access
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()

	if client == nil {
		return fmt.Errorf("not connected to controller")
	}

	// Create request
	rnicInfos := make([]*controller_agent.RnicInfo, 0, len(rnics))
	for _, rnic := range rnics {
		if rnic.ResponderQueue == nil {
			return fmt.Errorf("no responder queue found for RNIC %s, device %s", rnic.GID, rnic.DeviceName)
		}
		rnicInfos = append(rnicInfos, &controller_agent.RnicInfo{
			Gid: rnic.GID,
			// Use the responder queue for registration not the sender queue
			// because the other agents send probes to this agent via the responder queue
			Qpn:        rnic.ResponderQueue.QPN,
			IpAddress:  rnic.IPAddr,
			HostName:   hostName,
			DeviceName: rnic.DeviceName,
			TorId:      "", // This would need to be set from config
		})
	}

	req := &controller_agent.AgentRegistrationRequest{
		AgentId: agentID,
		AgentIp: agentIP,
		Rnics:   rnicInfos,
	}

	// Send request with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resp, err := client.RegisterAgent(ctx, req)
	if err != nil {
		return fmt.Errorf("failed to register agent: %w", err)
	}

	if !resp.Success {
		return fmt.Errorf("agent registration failed: %s", resp.Message)
	}

	log.Info().
		Str("agentID", agentID).
		Int("rnics", len(rnicInfos)).
		Msg("Successfully registered agent with controller")

	return nil
}

// GetPinglist gets the pinglist from the controller
func (c *ControllerClient) GetPinglist(
	requesterRnic *rdma.RNIC,
	hostName string,
	pinglistType controller_agent.PinglistRequest_PinglistType,
) ([]*controller_agent.PingTarget, uint32, uint32, error) {
	// [NEW] Ensure connection is ready before making request (automatic reconnection)
	if err := c.ensureConnected(); err != nil {
		return nil, 0, 0, fmt.Errorf("failed to ensure connection to controller: %w", err)
	}

	// [NEW] Thread-safe client access
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()

	if client == nil {
		return nil, 0, 0, fmt.Errorf("not connected to controller")
	}

	var qpn uint32
	// Use the **responder** queue because the other agents send probes to this agent via the responder queue
	if requesterRnic.ResponderQueue != nil {
		qpn = requesterRnic.ResponderQueue.QPN
	}
	if qpn == 0 { // Return error if no valid QPN is found
		return nil, 0, 0, fmt.Errorf("no valid QPN found for RNIC with GID %s", requesterRnic.GID)
	}

	// Create request
	req := &controller_agent.PinglistRequest{
		RequesterRnic: &controller_agent.RnicInfo{
			Gid:        requesterRnic.GID,
			Qpn:        qpn,
			IpAddress:  requesterRnic.IPAddr,
			HostName:   hostName,
			DeviceName: requesterRnic.DeviceName,
			TorId:      "", // This would need to be set from config
		},
		Type: pinglistType,
	}

	// Send request with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resp, err := client.GetPinglist(ctx, req)
	if err != nil {
		// [NEW] If request failed, connection might be broken, mark for reconnection
		log.Warn().Err(err).Str("feature", "connection_recovery").Msg("[NEW] GetPinglist request failed, connection may be broken")
		// [NEW] Try to reconnect on next call
		c.mu.Lock()
		if c.conn != nil {
			state := c.conn.GetState()
			if state != connectivity.Ready && state != connectivity.Idle {
				log.Warn().Str("feature", "connection_recovery").Str("state", state.String()).Msg("[NEW] Connection state indicates failure, will reconnect on next call")
			}
		}
		c.mu.Unlock()
		return nil, 0, 0, fmt.Errorf("failed to get pinglist: %w", err)
	}

	pinglistTypeStr := "TOR_MESH"
	if pinglistType == controller_agent.PinglistRequest_INTER_TOR {
		pinglistTypeStr = "INTER_TOR"
	}

	log.Info().
		Str("type", pinglistTypeStr).
		Int("targets", len(resp.Targets)).
		Uint32("interval", resp.ProbeIntervalMs).
		Uint32("timeout", resp.TimeoutMs).
		Msg("Received pinglist from controller")

	return resp.Targets, resp.ProbeIntervalMs, resp.TimeoutMs, nil
}

// GetTargetRnicInfo gets the target RNIC info from the controller
func (c *ControllerClient) GetTargetRnicInfo(targetIP string, targetGID string) (*controller_agent.RnicInfo, error) {
	// [NEW] Ensure connection is ready before making request (automatic reconnection)
	if err := c.ensureConnected(); err != nil {
		return nil, fmt.Errorf("failed to ensure connection to controller: %w", err)
	}

	// [NEW] Thread-safe client access
	c.mu.Lock()
	client := c.client
	c.mu.Unlock()

	if client == nil {
		return nil, fmt.Errorf("not connected to controller")
	}

	// Create request
	req := &controller_agent.TargetRnicInfoRequest{
		TargetIp:  targetIP,
		TargetGid: targetGID,
	}

	// Send request with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	resp, err := client.GetTargetRnicInfo(ctx, req)
	if err != nil {
		return nil, fmt.Errorf("failed to get target RNIC info: %w", err)
	}

	if !resp.Success {
		return nil, fmt.Errorf("failed to get target RNIC info: %s", resp.Message)
	}

	log.Info().
		Str("targetIP", targetIP).
		Str("targetGID", targetGID).
		Str("resolvedGID", resp.TargetRnic.Gid).
		Uint32("resolvedQPN", resp.TargetRnic.Qpn).
		Msg("Resolved target RNIC info")

	return resp.TargetRnic, nil
}

