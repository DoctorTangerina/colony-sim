"""ADR 12: aggregates the dynamic-vs-static allocation sweep's per-run CSVs
(written by experiments/dynamic-vs-static-allocation/metrics_logger.gd, one
run per file) into per-cell summary statistics and plots.

Each CSV is a raw time series only (timestamp, food/wood storage, role
counts, cumulative role changes, cumulative deposits) - this script is where
the three metrics ADR 12 actually cares about get derived:

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

FILENAME_RE = re.compile(
    r"^pop(?P<population>\d+)_respawn(?P<respawn_time>[\d.]+)_"
    r"(?P<mode>dynamic|static)_seed(?P<seed>-?\d+)\.csv$"
)

METRICS = ["recovery_time_s", "churn_rate", "throughput_rate"]
METRIC_LABELS = {
    "recovery_time_s": "Storage recovery time (s)",
    "churn_rate": "Role churn (changes/agent/min)",
    "throughput_rate": "Throughput (deposits/min)",
}


def load_nest_low_thresholds(repo_root: Path) -> dict[str, int]:
    """Reads configs/nest.json directly rather than hardcoding {Food: 10,
    Wood: 10} here - the whole point of using this threshold (ADR 12) is
    that it's the simulation's own static value, so this script must read
    the same source of truth the sim does, not a copy that can drift."""
    nest_config = json.loads((repo_root / "configs" / "nest.json").read_text())
    thresholds = nest_config["thresholds"]
    return {res_type: thresholds[res_type]["low"] for res_type in thresholds}


def parse_run_filename(path: Path) -> dict | None:
    match = FILENAME_RE.match(path.name)
    if match is None:
        return None
    return {
        "population": int(match.group("population")),
        "respawn_time": float(match.group("respawn_time")),
        "mode": match.group("mode"),
        "seed": int(match.group("seed")),
    }


def compute_run_metrics(csv_path: Path, meta: dict, low_thresholds: dict[str, int]) -> dict:
    df = pd.read_csv(csv_path)
    if df.empty:
        return {**meta, "recovery_time_s": float("nan"), "recovery_censored": True,
                "churn_rate": float("nan"), "throughput_rate": float("nan"), "n_samples": 0}

    last = df.iloc[-1]
    duration_minutes = last["timestamp"] / 60.0

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

    return {
        **meta,
        "recovery_time_s": recovery_time_s,
        "recovery_censored": recovery_censored,
        "churn_rate": churn_rate,
        "throughput_rate": throughput_rate,
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
    return summary.reset_index()


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


if __name__ == "__main__":
    main()
