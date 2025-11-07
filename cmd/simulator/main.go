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

type sample struct {
	Timeout        bool
	RTT            time.Duration
	ProberDelay    time.Duration
	ResponderDelay time.Duration
}

type scenario struct {
	Name     string
	Interval time.Duration
	Samples  []sample
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
	if len(samples) == 0 {
		samples = []sample{{Timeout: false, RTT: 150 * time.Millisecond, ProberDelay: 40 * time.Millisecond, ResponderDelay: 35 * time.Millisecond}}
	}

	commonAttrs := []attribute.KeyValue{
		attribute.String("source", "simulation"),
		attribute.String("profile", scen.Name),
		attribute.String("agent_id", cfg.Simulation.AgentID),
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
			if sample.Timeout {
				metrics.timeout.Add(context.Background(), 1, metric.WithAttributes(commonAttrs...))
				logger.Debug().Msg("recorded synthetic timeout")
				continue
			}
			metrics.rtt.Record(context.Background(), sample.RTT.Nanoseconds(), metric.WithAttributes(commonAttrs...))
			metrics.prober.Record(context.Background(), sample.ProberDelay.Nanoseconds(), metric.WithAttributes(commonAttrs...))
			metrics.responder.Record(context.Background(), sample.ResponderDelay.Nanoseconds(), metric.WithAttributes(commonAttrs...))
			logger.Debug().Dur("rtt", sample.RTT).Dur("prober_delay", sample.ProberDelay).Dur("responder_delay", sample.ResponderDelay).Msg("recorded synthetic observation")
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
		Name:     "tor-mesh",
		Interval: 2 * time.Second,
		Samples: []sample{
			{Timeout: false, RTT: 120 * time.Millisecond, ProberDelay: 30 * time.Millisecond, ResponderDelay: 25 * time.Millisecond},
			{Timeout: false, RTT: 140 * time.Millisecond, ProberDelay: 32 * time.Millisecond, ResponderDelay: 28 * time.Millisecond},
			{Timeout: true},
		},
	},
	"inter-tor": {
		Name:     "inter-tor",
		Interval: 3 * time.Second,
		Samples: []sample{
			{Timeout: false, RTT: 260 * time.Millisecond, ProberDelay: 45 * time.Millisecond, ResponderDelay: 40 * time.Millisecond},
			{Timeout: false, RTT: 320 * time.Millisecond, ProberDelay: 48 * time.Millisecond, ResponderDelay: 42 * time.Millisecond},
			{Timeout: true},
		},
	},
	"lossy": {
		Name:     "lossy",
		Interval: 4 * time.Second,
		Samples: []sample{
			{Timeout: false, RTT: 480 * time.Millisecond, ProberDelay: 70 * time.Millisecond, ResponderDelay: 60 * time.Millisecond},
			{Timeout: true},
			{Timeout: false, RTT: 520 * time.Millisecond, ProberDelay: 75 * time.Millisecond, ResponderDelay: 65 * time.Millisecond},
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

	rtt, err := meter.Int64Histogram("rpingmesh.simulated_rtt", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create rtt histogram: %w", err)
	}
	prober, err := meter.Int64Histogram("rpingmesh.simulated_prober_delay", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create prober histogram: %w", err)
	}
	responder, err := meter.Int64Histogram("rpingmesh.simulated_responder_delay", metric.WithUnit("ns"))
	if err != nil {
		return nil, fmt.Errorf("create responder histogram: %w", err)
	}
	timeout, err := meter.Int64Counter("rpingmesh.simulated_timeout", metric.WithUnit("{count}"))
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
