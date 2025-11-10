package main

import (
	"context"
	"fmt"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/rs/zerolog"
	"github.com/rs/zerolog/log"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/metric"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

type simulationConfig struct {
	Enabled  bool   `mapstructure:"enabled"`
	Profile  string `mapstructure:"profile"`
	OtelAddr string `mapstructure:"otel-addr"`
	AgentID  string `mapstructure:"agent-id"`
}

type config struct {
	Simulation simulationConfig `mapstructure:"simulation"`
}

type endpoint struct {
	AgentID    string
	Hostname   string
	GID        string
	DeviceName string
}

type sample struct {
	Timeout        bool
	RTT            time.Duration
	ProberDelay    time.Duration
	ResponderDelay time.Duration
	Destination    endpoint
}

const (
	probeTypeTorMesh        = "TOR_MESH"
	probeTypeInterTor       = "INTER_TOR"
	probeTypeServiceTracing = "SERVICE_TRACING"
)

type scenario struct {
	Name      string
	ProbeType string
	Interval  time.Duration
	Samples   []sample
}

func main() {
	zerolog.TimeFieldFormat = time.RFC3339Nano
	logger := log.Output(zerolog.ConsoleWriter{Out: os.Stdout, TimeFormat: time.RFC3339Nano}).With().Str("component", "simulator").Logger()
	log.Logger = logger

	var configPath string
	pflag.StringVar(&configPath, "config", "/app/config/simulator.yaml", "Path to simulator configuration file")
	pflag.Parse()

	cfg, err := loadConfig(configPath)
	if err != nil {
		logger.Fatal().Err(err).Msg("failed to load configuration")
	}

	if !cfg.Simulation.Enabled {
		logger.Info().Msg("simulation disabled; exiting")
		return
	}

	scen := lookupScenario(cfg.Simulation.Profile)
	logger.Info().Str("profile", scen.Name).Dur("interval", scen.Interval).Msg("simulation enabled")

	if scen.ProbeType == "" {
		scen.ProbeType = probeTypeTorMesh
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	metrics, err := newMetrics(context.Background(), cfg.Simulation.AgentID, cfg.Simulation.OtelAddr)
	if err != nil {
		logger.Fatal().Err(err).Str("collector", cfg.Simulation.OtelAddr).Msg("failed to create metrics exporter")
	}
	defer func() {
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := metrics.shutdown(shutdownCtx); err != nil {
			logger.Warn().Err(err).Msg("failed to shutdown metrics provider cleanly")
		}
	}()

	ticker := time.NewTicker(scen.Interval)
	defer ticker.Stop()

	samples := scen.Samples
	srcEndpoint := endpoint{
		AgentID:    cfg.Simulation.AgentID,
		Hostname:   fmt.Sprintf("%s-host", cfg.Simulation.AgentID),
		GID:        fmt.Sprintf("fe80::%s", strings.ReplaceAll(cfg.Simulation.AgentID, "-", "")),
		DeviceName: "sim_mlx5_0",
	}
	if len(samples) == 0 {
		samples = []sample{
			{
				Timeout:        false,
				RTT:            150 * time.Millisecond,
				ProberDelay:    40 * time.Millisecond,
				ResponderDelay: 35 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "sim-peer-1",
					Hostname:   "sim-peer-1",
					GID:        "fe80::3001",
					DeviceName: "sim_mlx5_1",
				},
			},
		}
	}

	baseAttrs := []attribute.KeyValue{
		attribute.String("src_agent_id", srcEndpoint.AgentID),
		attribute.String("src_hostname", srcEndpoint.Hostname),
		attribute.String("src_gid", srcEndpoint.GID),
		attribute.String("src_device_name", srcEndpoint.DeviceName),
	}

	logger.Info().Str("collector", cfg.Simulation.OtelAddr).Str("agent_id", cfg.Simulation.AgentID).Msg("starting simulation loop")

	idx := 0
	for {
		select {
		case <-ctx.Done():
			logger.Info().Msg("received shutdown signal")
			return
		case <-ticker.C:
			sample := samples[idx%len(samples)]
			idx++
			attrs := append([]attribute.KeyValue{}, baseAttrs...)
			if sample.Destination.AgentID != "" {
				attrs = append(attrs,
					attribute.String("dst_agent_id", sample.Destination.AgentID),
					attribute.String("dst_hostname", sample.Destination.Hostname),
					attribute.String("dst_gid", sample.Destination.GID),
					attribute.String("dst_device_name", sample.Destination.DeviceName),
				)
			}
			attrs = append(attrs, attribute.String("probe_type", scen.ProbeType))
			if sample.Timeout {
				metrics.timeout.Add(context.Background(), 1, metric.WithAttributes(attrs...))
				logger.Debug().Str("dst_agent_id", sample.Destination.AgentID).Msg("recorded synthetic timeout")
				continue
			}
			metrics.rtt.Record(context.Background(), sample.RTT.Nanoseconds(), metric.WithAttributes(attrs...))
			metrics.prober.Record(context.Background(), sample.ProberDelay.Nanoseconds(), metric.WithAttributes(attrs...))
			metrics.responder.Record(context.Background(), sample.ResponderDelay.Nanoseconds(), metric.WithAttributes(attrs...))
			logger.Debug().
				Str("dst_agent_id", sample.Destination.AgentID).
				Str("probe_type", scen.ProbeType).
				Dur("rtt", sample.RTT).
				Dur("prober_delay", sample.ProberDelay).
				Dur("responder_delay", sample.ResponderDelay).
				Msg("recorded synthetic observation")
		}
	}
}

func loadConfig(path string) (config, error) {
	v := viper.New()
	v.SetConfigFile(path)
	v.SetConfigType("yaml")
	v.SetDefault("simulation.enabled", false)
	v.SetDefault("simulation.profile", "tor-mesh")
	v.SetDefault("simulation.otel-addr", "grpc://otel-collector:4317")
	v.SetDefault("simulation.agent-id", "sim-agent")

	if err := v.ReadInConfig(); err != nil {
		return config{}, fmt.Errorf("read config: %w", err)
	}

	var cfg config
	if err := v.Unmarshal(&cfg); err != nil {
		return config{}, fmt.Errorf("unmarshal config: %w", err)
	}
	return cfg, nil
}

func lookupScenario(name string) scenario {
	if scen, ok := scenarios[name]; ok {
		return scen
	}
	return scenarios["tor-mesh"]
}

var scenarios = map[string]scenario{
	"tor-mesh": {
		Name:      "tor-mesh",
		ProbeType: probeTypeTorMesh,
		Interval:  2 * time.Second,
		Samples: []sample{
			{
				Timeout:        false,
				RTT:            120 * time.Millisecond,
				ProberDelay:    30 * time.Millisecond,
				ResponderDelay: 25 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "tor-peer",
					Hostname:   "tor-peer",
					GID:        "fe80::2100",
					DeviceName: "mlx5_1",
				},
			},
			{
				Timeout: true,
				Destination: endpoint{
					AgentID:    "tor-peer",
					Hostname:   "tor-peer",
					GID:        "fe80::2100",
					DeviceName: "mlx5_1",
				},
			},
		},
	},
	"inter-tor": {
		Name:      "inter-tor",
		ProbeType: probeTypeInterTor,
		Interval:  3 * time.Second,
		Samples: []sample{
			{
				Timeout:        false,
				RTT:            260 * time.Millisecond,
				ProberDelay:    45 * time.Millisecond,
				ResponderDelay: 40 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "inter-peer",
					Hostname:   "inter-peer",
					GID:        "fe80::3100",
					DeviceName: "mlx5_2",
				},
			},
			{
				Timeout:        false,
				RTT:            320 * time.Millisecond,
				ProberDelay:    48 * time.Millisecond,
				ResponderDelay: 42 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "inter-peer",
					Hostname:   "inter-peer",
					GID:        "fe80::3100",
					DeviceName: "mlx5_2",
				},
			},
			{
				Timeout: true,
				Destination: endpoint{
					AgentID:    "inter-peer",
					Hostname:   "inter-peer",
					GID:        "fe80::3100",
					DeviceName: "mlx5_2",
				},
			},
		},
	},
	"lossy": {
		Name:      "lossy",
		ProbeType: probeTypeServiceTracing,
		Interval:  4 * time.Second,
		Samples: []sample{
			{
				Timeout:        false,
				RTT:            480 * time.Millisecond,
				ProberDelay:    70 * time.Millisecond,
				ResponderDelay: 60 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "service-peer",
					Hostname:   "service-peer",
					GID:        "fe80::4100",
					DeviceName: "mlx5_3",
				},
			},
			{
				Timeout: true,
				Destination: endpoint{
					AgentID:    "service-peer",
					Hostname:   "service-peer",
					GID:        "fe80::4100",
					DeviceName: "mlx5_3",
				},
			},
			{
				Timeout:        false,
				RTT:            520 * time.Millisecond,
				ProberDelay:    75 * time.Millisecond,
				ResponderDelay: 65 * time.Millisecond,
				Destination: endpoint{
					AgentID:    "service-peer",
					Hostname:   "service-peer",
					GID:        "fe80::4100",
					DeviceName: "mlx5_3",
				},
			},
		},
	},
}

type metricSet struct {
	provider  *sdkmetric.MeterProvider
	rtt       metric.Int64Histogram
	prober    metric.Int64Histogram
	responder metric.Int64Histogram
	timeout   metric.Int64Counter
}

func newMetrics(ctx context.Context, agentID, collectorAddr string) (*metricSet, error) {
	if collectorAddr == "" {
		collectorAddr = "grpc://otel-collector:4317"
	}
	parsed, err := url.Parse(collectorAddr)
	if err != nil {
		return nil, fmt.Errorf("parse collector address: %w", err)
	}
	if parsed.Scheme == "" {
		parsed.Scheme = "grpc"
	}
	endpoint := parsed.Host
	if endpoint == "" {
		endpoint = strings.TrimPrefix(parsed.Path, "//")
	}
	if endpoint == "" {
		return nil, fmt.Errorf("collector address %q missing host", collectorAddr)
	}

	var exporter sdkmetric.Exporter
	switch strings.ToLower(parsed.Scheme) {
	case "grpc":
		exporter, err = otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithEndpoint(endpoint), otlpmetricgrpc.WithInsecure())
	case "grpcs":
		exporter, err = otlpmetricgrpc.New(ctx, otlpmetricgrpc.WithEndpoint(endpoint))
	case "http":
		exporter, err = otlpmetrichttp.New(ctx, otlpmetrichttp.WithEndpoint(endpoint), otlpmetrichttp.WithInsecure())
	case "https":
		exporter, err = otlpmetrichttp.New(ctx, otlpmetrichttp.WithEndpoint(endpoint))
	default:
		return nil, fmt.Errorf("unsupported collector scheme %q", parsed.Scheme)
	}
	if err != nil {
		return nil, fmt.Errorf("create exporter: %w", err)
	}

	res, err := resource.Merge(
		resource.Default(),
		resource.NewWithAttributes(
			semconv.SchemaURL,
			semconv.ServiceName("rpingmesh-agent-simulator"),
			semconv.ServiceInstanceID(agentID),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("create resource: %w", err)
	}

	provider := sdkmetric.NewMeterProvider(
		sdkmetric.WithResource(res),
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(exporter, sdkmetric.WithInterval(10*time.Second))),
	)
	otel.SetMeterProvider(provider)

	meter := provider.Meter("github.com/yuuki/rpingmesh/cmd/simulator")

	rtt, err := meter.Int64Histogram("rpingmesh.nwrtt", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create rtt histogram: %w", err)
	}
	prober, err := meter.Int64Histogram("rpingmesh.prober_delay", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create prober histogram: %w", err)
	}
	responder, err := meter.Int64Histogram("rpingmesh.responder_delay", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create responder histogram: %w", err)
	}
	timeout, err := meter.Int64Counter("rpingmesh.timeout", metric.WithUnit("{count}"))
	if err != nil {
		return nil, fmt.Errorf("create timeout counter: %w", err)
	}

	return &metricSet{
		provider:  provider,
		rtt:       rtt,
		prober:    prober,
		responder: responder,
		timeout:   timeout,
	}, nil
}

func (m *metricSet) shutdown(ctx context.Context) error {
	return m.provider.Shutdown(ctx)
}
