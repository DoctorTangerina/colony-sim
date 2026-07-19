"""ADR 12: aggregates the dynamic-vs-static allocation sweep's per-run CSVs
(written by experiments/dynamic-vs-static-allocation/metrics_logger.gd, one
run per file) into per-cell summary statistics and plots.

Each CSV is a raw time series only (timestamp, food/wood storage, role
counts, cumulative role changes, cumulative deposits) - this script is where
the three original ADR 12 metrics get derived:

  - storage recovery time: first timestamp where both Food and Wood storage
    are at/above the Nest's static "low" threshold (read from
    configs/nest.json directly, so this can never drift from what the
    simulation itself uses - see ADR 12's explicit rejection of using the
    OM's per-capita copy instead).
  - role churn: cumulative role changes at the run's last sample, normalized
    to changes/agent/minute.
  - throughput: cumulative deposits at the run's last sample, normalized to
    deposits/minute.

A run's swept parameters (population, respawn time, distribution mode, seed)
live only in its filename (metrics_logger.gd's _build_run_tag()) - the CSV
itself carries no metadata columns - so parsing the filename is required,
not incidental.

A run also has a matching <run_tag>_events.jsonl (ADR 12 Amendment), one JSON
object per line - role_changed and action_verified events, timestamped with
the same simulated clock as the CSV. This script derives the transition
latency metric from it: for each agent's role_changed event, the simulated-
time gap to that same agent's next action_verified event (already filtered
to DepositResource/ReportResource/ReportDepletion by metrics_logger.gd - Eat
doesn't count). A role change with no qualifying action before the run ends
is right-censored, same treatment as an unrecovered storage run.

Ticket 07 adds three more qualitative-case sources, all derived here rather
than logged as ready-made conclusions:

  - discovery/death events (same JSONL) are listed with surrounding context
    (role counts from the CSV at/after a discovery; the storage snapshot
    already carried on a death event) into qualitative_events.csv.
  - the oscillation backstop (GoapCycle.gd's _MAX_SYNCHRONOUS_REPLAN_DEPTH
    push_error) isn't logged by the sim at all - run_sweep.sh captures each
    run's stderr to <run_tag>.stderr.log instead, and this script greps it.
    Zero trips across the sweep is itself the expected, citable result.
  - a new pending_role_requests CSV column (Role Request queue length) is
    aggregated per cell; a cell where it's non-empty for a mean of >50% of
    samples across its runs is flagged as evidence of persistent
    under-population (ADR 2's own phrasing), not a single non-empty sample.

Usage:
    .venv/Scripts/python.exe analyze.py [--results-dir DIR] [--output-dir DIR]
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import pandas as pd
import matplotlib

matplotlib.use("Agg")  # headless: no display available when run from CLI
import matplotlib.pyplot as plt

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent

TAG_RE = re.compile(
    r"^pop(?P<population>\d+)_respawn(?P<respawn_time>[\d.]+)_"
    r"(?P<mode>dynamic|static)_seed(?P<seed>-?\d+)$"
)

## GoapCycle.gd's own message for its _MAX_SYNCHRONOUS_REPLAN_DEPTH backstop -
## matched as a substring so a wording tweak to the surrounding sentence
## doesn't silently break detection.
OSCILLATION_BACKSTOP_MESSAGE = "synchronous replans in a row"
QUALITATIVE_EVENT_TYPES = ("discovery", "death")

METRICS = ["recovery_time_s", "churn_rate", "throughput_rate", "latency_mean_s"]
METRIC_LABELS = {
    "recovery_time_s": "Storage recovery time (s)",
    "churn_rate": "Role churn (changes/agent/min)",
    "throughput_rate": "Throughput (deposits/min)",
    "latency_mean_s": "Transition latency (s, role change → next contribution)",
}


def load_nest_low_thresholds(repo_root: Path) -> dict[str, int]:
    """Reads configs/nest.json directly rather than hardcoding {Food: 10,
    Wood: 10} here - the whole point of using this threshold (ADR 12) is
    that it's the simulation's own static value, so this script must read
    the same source of truth the sim does, not a copy that can drift."""
    nest_config = json.loads((repo_root / "configs" / "nest.json").read_text())
    thresholds = nest_config["thresholds"]
    return {res_type: thresholds[res_type]["low"] for res_type in thresholds}


def parse_run_tag(tag: str) -> dict | None:
    match = TAG_RE.match(tag)
    if match is None:
        return None
    return {
        "population": int(match.group("population")),
        "respawn_time": float(match.group("respawn_time")),
        "mode": match.group("mode"),
        "seed": int(match.group("seed")),
    }


def parse_run_filename(path: Path) -> dict | None:
    return parse_run_tag(path.stem)


def load_events(csv_path: Path) -> list[dict]:
    events_path = csv_path.with_name(csv_path.stem + "_events.jsonl")
    if not events_path.exists():
        return []
    events = []
    for line in events_path.read_text().splitlines():
        line = line.strip()
        if line:
            events.append(json.loads(line))
    return events


def compute_latency(events: list[dict], run_end_s: float) -> tuple[float, float]:
    """Per-agent: for each role_changed event, the gap to that same agent's
    next action_verified event (already pre-filtered to the three
    colony-productive actions by metrics_logger.gd). A role change with no
    qualifying action before the run ends is right-censored at run_end_s,
    mirroring compute_run_metrics' treatment of an unrecovered storage run -
    excluded from the mean, but counted toward the censored fraction rather
    than silently dropped.
    """
    by_agent: dict[str, list[dict]] = {}
    for event in events:
        if event["event"] not in ("role_changed", "action_verified"):
            continue  # discovery/death (Ticket 07) carry no agent_id
        by_agent.setdefault(event["agent_id"], []).append(event)

    gaps = []
    total_role_changes = 0
    censored = 0

    for agent_events in by_agent.values():
        agent_events.sort(key=lambda e: e["timestamp"])
        pending_change_ts: float | None = None
        for event in agent_events:
            if event["event"] == "role_changed":
                if pending_change_ts is not None:
                    # A second role change before any qualifying action ended
                    # the first gap - the agent was never productive under
                    # that role at all, which is itself censored, not zero.
                    total_role_changes += 1
                    censored += 1
                pending_change_ts = event["timestamp"]
            elif event["event"] == "action_verified" and pending_change_ts is not None:
                total_role_changes += 1
                gaps.append(event["timestamp"] - pending_change_ts)
                pending_change_ts = None
        if pending_change_ts is not None:
            total_role_changes += 1
            censored += 1

    if total_role_changes == 0:
        return float("nan"), float("nan")

    mean_latency = sum(gaps) / len(gaps) if gaps else float("nan")
    censored_fraction = censored / total_role_changes
    return mean_latency, censored_fraction


def compute_run_metrics(csv_path: Path, meta: dict, low_thresholds: dict[str, int]) -> dict:
    df = pd.read_csv(csv_path)
    if df.empty:
        return {**meta, "recovery_time_s": float("nan"), "recovery_censored": True,
                "churn_rate": float("nan"), "throughput_rate": float("nan"),
                "latency_mean_s": float("nan"), "latency_censored_fraction": float("nan"),
                "queue_nonempty_fraction": float("nan"), "n_samples": 0}

    last = df.iloc[-1]
    duration_minutes = last["timestamp"] / 60.0
    latency_mean_s, latency_censored_fraction = compute_latency(load_events(csv_path), last["timestamp"])

    recovered = df[
        (df["food_storage"] >= low_thresholds["Food"])
        & (df["wood_storage"] >= low_thresholds["Wood"])
    ]
    if recovered.empty:
        # Never recovered within the run - right-censored at run duration,
        # not a missing value. Flagged rather than silently dropped so the
        # summary can report what fraction of runs never stabilized.
        recovery_time_s = float("nan")
        recovery_censored = True
    else:
        recovery_time_s = float(recovered.iloc[0]["timestamp"])
        recovery_censored = False

    churn_rate = (
        (last["cumulative_role_changes"] / meta["population"] / duration_minutes)
        if duration_minutes > 0
        else float("nan")
    )
    throughput_rate = (
        (last["cumulative_deposits"] / duration_minutes)
        if duration_minutes > 0
        else float("nan")
    )
    queue_nonempty_fraction = float((df["pending_role_requests"] > 0).mean())

    return {
        **meta,
        "recovery_time_s": recovery_time_s,
        "recovery_censored": recovery_censored,
        "churn_rate": churn_rate,
        "throughput_rate": throughput_rate,
        "latency_mean_s": latency_mean_s,
        "latency_censored_fraction": latency_censored_fraction,
        "queue_nonempty_fraction": queue_nonempty_fraction,
        "n_samples": len(df),
    }


def load_all_runs(results_dir: Path, low_thresholds: dict[str, int]) -> pd.DataFrame:
    rows = []
    skipped = []
    for csv_path in sorted(results_dir.glob("*.csv")):
        meta = parse_run_filename(csv_path)
        if meta is None:
            skipped.append(csv_path.name)
            continue
        rows.append(compute_run_metrics(csv_path, meta, low_thresholds))

    if skipped:
        print(f"Skipped {len(skipped)} file(s) with unrecognized names: {skipped}")

    if not rows:
        raise SystemExit(f"No run CSVs found in {results_dir}")

    return pd.DataFrame(rows)


def summarize(runs_df: pd.DataFrame) -> pd.DataFrame:
    grouped = runs_df.groupby(["population", "respawn_time", "mode"])
    summary = grouped[METRICS].agg(["mean", "min", "max"])
    summary.columns = ["_".join(col) for col in summary.columns]
    summary["n_runs"] = grouped.size()
    summary["recovery_censored_fraction"] = grouped["recovery_censored"].mean()
    summary["latency_censored_fraction_mean"] = grouped["latency_censored_fraction"].mean()
    summary["queue_nonempty_fraction_mean"] = grouped["queue_nonempty_fraction"].mean()
    # ADR 2's "persistently non-empty" read as "most of the time" (>50% of a
    # cell's samples, averaged across its runs), not "ever non-empty" - a
    # single busy sample is expected noise, not evidence of under-population.
    summary["queue_persistently_nonempty"] = summary["queue_nonempty_fraction_mean"] > 0.5
    return summary.reset_index()


def extract_qualitative_events(results_dir: Path) -> pd.DataFrame:
    """Lists discovery/death events (ADR 12 Amendment) with surrounding
    context: a discovery gets the role counts read from its own run's CSV at
    the first sample at/after the discovery timestamp (the "surge" half of
    the discovery-cascade story); a death already carries its storage
    snapshot on the event itself, logged at the instant it happened."""
    rows = []
    for jsonl_path in sorted(results_dir.glob("*_events.jsonl")):
        tag = jsonl_path.name.removesuffix("_events.jsonl")
        meta = parse_run_tag(tag)
        if meta is None:
            continue

        csv_path = jsonl_path.with_name(f"{tag}.csv")
        df = pd.read_csv(csv_path) if csv_path.exists() else None

        for line in jsonl_path.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            event = json.loads(line)
            if event["event"] not in QUALITATIVE_EVENT_TYPES:
                continue

            row = {**meta, "run_tag": tag, **event}
            if event["event"] == "discovery" and df is not None:
                after = df[df["timestamp"] >= event["timestamp"]]
                if not after.empty:
                    row["role_counts_at_discovery"] = after.iloc[0]["role_counts_json"]
            rows.append(row)

    return pd.DataFrame(rows)


def scan_oscillation_backstop(results_dir: Path) -> pd.DataFrame:
    """Greps each run's captured stderr (run_sweep.sh, Ticket 07) for
    GoapCycle.gd's existing _MAX_SYNCHRONOUS_REPLAN_DEPTH push_error - no new
    signal was added for this case specifically to avoid a second edit to
    that sensitive function. A trip count of 0 everywhere is the expected
    result, confirming the stored_field/high_hunger precondition fix held."""
    rows = []
    for log_path in sorted(results_dir.glob("*.stderr.log")):
        tag = log_path.name.removesuffix(".stderr.log")
        meta = parse_run_tag(tag)
        if meta is None:
            continue
        text = log_path.read_text(errors="replace")
        rows.append({**meta, "run_tag": tag, "oscillation_backstop_trips": text.count(OSCILLATION_BACKSTOP_MESSAGE)})

    return pd.DataFrame(rows)


def plot_metric(summary: pd.DataFrame, metric: str, output_dir: Path) -> None:
    populations = sorted(summary["population"].unique())
    fig, axes = plt.subplots(1, len(populations), figsize=(5 * len(populations), 4), sharey=True)
    if len(populations) == 1:
        axes = [axes]

    for ax, population in zip(axes, populations):
        cell = summary[summary["population"] == population]
        for mode, marker in (("dynamic", "o"), ("static", "s")):
            mode_cell = cell[cell["mode"] == mode].sort_values("respawn_time")
            if mode_cell.empty:
                continue
            mean = mode_cell[f"{metric}_mean"]
            lower = mean - mode_cell[f"{metric}_min"]
            upper = mode_cell[f"{metric}_max"] - mean
            ax.errorbar(
                mode_cell["respawn_time"], mean, yerr=[lower, upper],
                marker=marker, label=mode, capsize=4,
            )
        ax.set_title(f"population = {population}")
        ax.set_xlabel("respawn time (s)")
        ax.grid(alpha=0.3)

    axes[0].set_ylabel(METRIC_LABELS[metric])
    axes[0].legend()
    fig.suptitle(METRIC_LABELS[metric] + ": dynamic vs static")
    fig.tight_layout()

    output_path = output_dir / f"{metric}.png"
    fig.savefig(output_path, dpi=150)
    plt.close(fig)
    print(f"Wrote {output_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results-dir", type=Path, default=SCRIPT_DIR / "results")
    parser.add_argument("--output-dir", type=Path, default=SCRIPT_DIR / "analysis")
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)

    low_thresholds = load_nest_low_thresholds(REPO_ROOT)
    runs_df = load_all_runs(args.results_dir, low_thresholds)
    summary = summarize(runs_df)

    summary_path = args.output_dir / "summary_table.csv"
    summary.to_csv(summary_path, index=False)
    print(f"Wrote {summary_path}")
    print()
    print(summary.to_string(index=False))

    for metric in METRICS:
        plot_metric(summary, metric, args.output_dir)

    persistently_nonempty = summary[summary["queue_persistently_nonempty"]]
    if not persistently_nonempty.empty:
        print()
        print("Cells with a persistently non-empty Role Request queue (>50% of samples):")
        print(persistently_nonempty[["population", "respawn_time", "mode", "queue_nonempty_fraction_mean"]].to_string(index=False))

    qualitative_events = extract_qualitative_events(args.results_dir)
    if not qualitative_events.empty:
        events_path = args.output_dir / "qualitative_events.csv"
        qualitative_events.to_csv(events_path, index=False)
        print()
        print(f"Wrote {events_path} ({len(qualitative_events)} discovery/death events)")
        print(qualitative_events["event"].value_counts().to_string())

    oscillation = scan_oscillation_backstop(args.results_dir)
    if not oscillation.empty:
        oscillation_path = args.output_dir / "oscillation_backstop.csv"
        oscillation.to_csv(oscillation_path, index=False)
        total_trips = int(oscillation["oscillation_backstop_trips"].sum())
        print()
        print(f"Wrote {oscillation_path} - oscillation backstop trips across {len(oscillation)} runs: {total_trips}")


if __name__ == "__main__":
    main()
