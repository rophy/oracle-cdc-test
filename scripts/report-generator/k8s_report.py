#!/usr/bin/env python3
"""
Kubernetes Performance Report Generator

Generates HTML performance reports by querying Prometheus metrics via kubectl.
"""

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from urllib.parse import quote

from jinja2 import Environment, FileSystemLoader


@dataclass
class MetricSeries:
    """A time series of metric values."""
    name: str
    labels: dict
    timestamps: list[float]
    values: list[float]


@dataclass
class ReportConfig:
    """Configuration for report generation."""
    start_time: datetime
    end_time: datetime
    step: int = 30  # seconds
    prometheus_url: str = "http://oracle-cdc-kube-prometheus-prometheus:9090"
    containers: list[str] = field(default_factory=list)
    rate_of_metrics: list[str] = field(default_factory=list)
    total_of_metrics: list[str] = field(default_factory=list)
    title: str = "Performance Test Report"
    namespace: str = "oracle-cdc"
    pod_selector: str = "app=oracle-cdc-hammerdb"


class KubeQueryExecutor:
    """Executes queries via kubectl exec."""

    def __init__(self, config: ReportConfig):
        self.config = config

    def _run_command(self, cmd: list[str]) -> str:
        """Run a command and return stdout."""
        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
            if result.returncode != 0:
                print(f"Command failed: {' '.join(cmd)}", file=sys.stderr)
                print(f"stderr: {result.stderr}", file=sys.stderr)
                return ""
            return result.stdout
        except subprocess.TimeoutExpired:
            print(f"Command timed out: {' '.join(cmd)}", file=sys.stderr)
            return ""
        except Exception as e:
            print(f"Command error: {e}", file=sys.stderr)
            return ""

    def query_prometheus(self, endpoint: str, params: dict) -> dict:
        """Query Prometheus and return JSON response."""
        query_parts = []
        for k, v in params.items():
            query_parts.append(f"{k}={quote(str(v), safe='')}")
        query_string = "&".join(query_parts)
        url = f"{self.config.prometheus_url}{endpoint}?{query_string}"

        curl_cmd = f"curl -s '{url}'"
        cmd = [
            "kubectl", "exec", "-n", self.config.namespace,
            f"deployment/oracle-cdc-hammerdb", "--",
            "sh", "-c", curl_cmd
        ]

        output = self._run_command(cmd)
        if not output:
            return {}

        try:
            return json.loads(output)
        except json.JSONDecodeError as e:
            print(f"JSON decode error: {e}", file=sys.stderr)
            print(f"Raw output: {output[:500]}", file=sys.stderr)
            return {}


class PrometheusClient:
    """Client for querying Prometheus."""

    def __init__(self, executor: KubeQueryExecutor):
        self.executor = executor

    def query_range(self, query: str, start: float, end: float, step: int) -> list[MetricSeries]:
        """Execute a range query and return metric series."""
        params = {
            "query": query,
            "start": start,
            "end": end,
            "step": step,
        }

        data = self.executor.query_prometheus("/api/v1/query_range", params)

        if data.get("status") != "success":
            return []

        series_list = []
        for result in data.get("data", {}).get("result", []):
            metric = result.get("metric", {})
            values = result.get("values", [])

            timestamps = [v[0] for v in values]
            metric_values = [float(v[1]) if v[1] != "NaN" else 0.0 for v in values]

            series = MetricSeries(
                name=metric.get("__name__", "unknown"),
                labels={k: v for k, v in metric.items() if k != "__name__"},
                timestamps=timestamps,
                values=metric_values,
            )
            series_list.append(series)

        return series_list


class ReportGenerator:
    """Generates performance reports from Prometheus metrics."""

    def __init__(self, config: ReportConfig):
        self.config = config
        executor = KubeQueryExecutor(config)
        self.client = PrometheusClient(executor)
        self.start_ts = config.start_time.timestamp()
        self.end_ts = config.end_time.timestamp()

    def _format_time_labels(self, timestamps: list[float]) -> list[str]:
        """Convert timestamps to readable time labels."""
        if not timestamps:
            return []
        return [datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%M:%S") for ts in timestamps]

    def get_pod_cpu(self, pod_pattern: str) -> Optional[MetricSeries]:
        """Get CPU usage percentage for pods matching pattern."""
        query = f'sum(rate(container_cpu_usage_seconds_total{{namespace="{self.config.namespace}", pod=~"{pod_pattern}.*", container!=""}}[30s]))*100'
        series_list = self.client.query_range(query, self.start_ts, self.end_ts, self.config.step)

        if series_list:
            series = series_list[0]
            series.name = pod_pattern.replace("oracle-cdc-", "")
            return series
        return None

    def get_pod_memory(self, pod_pattern: str) -> Optional[MetricSeries]:
        """Get memory usage in MB for pods matching pattern."""
        query = f'sum(container_memory_usage_bytes{{namespace="{self.config.namespace}", pod=~"{pod_pattern}.*", container!=""}})/1024/1024'
        series_list = self.client.query_range(query, self.start_ts, self.end_ts, self.config.step)

        if series_list:
            series = series_list[0]
            series.name = pod_pattern.replace("oracle-cdc-", "")
            return series
        return None

    def get_metric_rate(self, metric_expr: str) -> Optional[MetricSeries]:
        """Get rate of a metric expression."""
        query = f'sum(rate({metric_expr}[30s]))'
        series_list = self.client.query_range(query, self.start_ts, self.end_ts, self.config.step)

        if series_list:
            series = series_list[0]
            series.name = metric_expr
            return series
        return None

    def get_metric_total(self, metric_expr: str) -> Optional[MetricSeries]:
        """Get total (raw sum) of a metric expression."""
        query = f'sum({metric_expr})'
        series_list = self.client.query_range(query, self.start_ts, self.end_ts, self.config.step)

        if series_list:
            series = series_list[0]
            series.name = metric_expr
            return series
        return None

    def _format_number(self, value: float, unit: str = "") -> str:
        """Format a number with appropriate precision and unit."""
        if value >= 1_000_000:
            return f"{value/1_000_000:,.1f}M{unit}"
        elif value >= 1_000:
            return f"{value/1_000:,.1f}K{unit}"
        elif value >= 100:
            return f"{value:,.0f}{unit}"
        elif value >= 1:
            return f"{value:,.1f}{unit}"
        else:
            return f"{value:,.2f}{unit}"

    def generate(self) -> dict:
        """Generate all report data."""
        data = {
            "title": self.config.title,
            "start_time": self.config.start_time.strftime("%Y-%m-%d %H:%M:%S UTC"),
            "end_time": self.config.end_time.strftime("%Y-%m-%d %H:%M:%S UTC"),
            "duration_minutes": int((self.end_ts - self.start_ts) / 60),
            "time_labels": [],
            "cpu_series": [],
            "memory_series": [],
            "network_rx_series": [],
            "network_tx_series": [],
            "fs_read_series": [],
            "fs_write_series": [],
            "rate_series": [],
            "total_series": [],
            "metrics_table": [],
        }

        # Get pod metrics (using pod name patterns)
        for container in self.config.containers:
            pod_pattern = f"oracle-cdc-{container}"

            # CPU
            cpu_series = self.get_pod_cpu(pod_pattern)
            if cpu_series:
                data["cpu_series"].append({
                    "name": cpu_series.name,
                    "values": [round(v, 2) for v in cpu_series.values],
                })
                if not data["time_labels"]:
                    data["time_labels"] = self._format_time_labels(cpu_series.timestamps)

            # Memory
            mem_series = self.get_pod_memory(pod_pattern)
            if mem_series:
                data["memory_series"].append({
                    "name": mem_series.name,
                    "values": [round(v, 1) for v in mem_series.values],
                })

        # Get rate metrics
        for metric_expr in self.config.rate_of_metrics:
            rate_series = self.get_metric_rate(metric_expr)
            if rate_series:
                data["rate_series"].append({
                    "name": metric_expr,
                    "values": [round(v, 1) for v in rate_series.values],
                })

        # Get total metrics
        for metric_expr in self.config.total_of_metrics:
            total_series = self.get_metric_total(metric_expr)
            if total_series:
                data["total_series"].append({
                    "name": metric_expr,
                    "values": [round(v, 1) for v in total_series.values],
                })

        # Build metrics table
        for series in data["cpu_series"]:
            values = [v for v in series["values"] if v > 0]
            if values:
                data["metrics_table"].append({
                    "name": f"{series['name']} CPU",
                    "min": self._format_number(min(values), "%"),
                    "avg": self._format_number(sum(values) / len(values), "%"),
                    "max": self._format_number(max(values), "%"),
                    "total": "-",
                })

        for series in data["memory_series"]:
            values = series["values"]
            if values:
                data["metrics_table"].append({
                    "name": f"{series['name']} Memory",
                    "min": self._format_number(min(values), " MB"),
                    "avg": self._format_number(sum(values) / len(values), " MB"),
                    "max": self._format_number(max(values), " MB"),
                    "total": "-",
                })

        for series in data["rate_series"]:
            values = [v for v in series["values"] if v > 0]
            if values:
                duration_sec = self.end_ts - self.start_ts
                estimated_total = (sum(values) / len(values)) * duration_sec
                data["metrics_table"].append({
                    "name": series["name"],
                    "min": self._format_number(min(values), "/s"),
                    "avg": self._format_number(sum(values) / len(values), "/s"),
                    "max": self._format_number(max(values), "/s"),
                    "total": f"~{self._format_number(estimated_total)}",
                })

        for series in data["total_series"]:
            values = series["values"]
            if values:
                delta = max(values) - min(values)
                data["metrics_table"].append({
                    "name": series["name"],
                    "min": self._format_number(min(values)),
                    "avg": self._format_number(sum(values) / len(values)),
                    "max": self._format_number(max(values)),
                    "total": f"+{self._format_number(delta)}",
                })

        return data


def render_report(data: dict, template_dir: Path, output_path: Path):
    """Render the report using Jinja2 template."""
    env = Environment(loader=FileSystemLoader(template_dir))
    template = env.get_template("charts.html.j2")

    html = template.render(**data)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(html)
    print(f"Report generated: {output_path}")


def parse_args():
    parser = argparse.ArgumentParser(description="Generate performance report from Prometheus metrics via kubectl")
    parser.add_argument("--start", required=True, help="Start time (ISO format)")
    parser.add_argument("--end", required=True, help="End time (ISO format)")
    parser.add_argument("--containers", required=True, help="Comma-separated list of container names")
    parser.add_argument("--rate-of", action="append", dest="rate_of_metrics", default=[],
                        help="Metric expression for rate chart")
    parser.add_argument("--total-of", action="append", dest="total_of_metrics", default=[],
                        help="Metric expression for total chart")
    parser.add_argument("--output", required=True, help="Output HTML file path")
    parser.add_argument("--title", default="Performance Test Report", help="Report title")
    parser.add_argument("--step", type=int, default=30, help="Query step in seconds")
    parser.add_argument("--namespace", default="oracle-cdc", help="Kubernetes namespace")

    return parser.parse_args()


def main():
    args = parse_args()

    start_time = datetime.fromisoformat(args.start.replace("Z", "+00:00"))
    end_time = datetime.fromisoformat(args.end.replace("Z", "+00:00"))

    config = ReportConfig(
        start_time=start_time,
        end_time=end_time,
        step=args.step,
        containers=[c.strip() for c in args.containers.split(",")],
        rate_of_metrics=args.rate_of_metrics,
        total_of_metrics=args.total_of_metrics,
        title=args.title,
        namespace=args.namespace,
    )

    generator = ReportGenerator(config)
    data = generator.generate()

    script_dir = Path(__file__).parent
    output_path = Path(args.output)

    render_report(data, script_dir, output_path)


if __name__ == "__main__":
    main()
