-- Probe 9c — EXPECTED TO FAIL: ZORDER on a liquid-clustered table.
OPTIMIZE dev.probes.lc_toy ZORDER BY (id);
